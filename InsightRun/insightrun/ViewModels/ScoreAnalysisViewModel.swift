//
//  ScoreAnalysisViewModel.swift
//  InsightRun
//
//  ViewModel for AI analysis specific to each dashboard score type
//

import Foundation
import Combine

@MainActor
class ScoreAnalysisViewModel: ObservableObject {
    private enum PendingAnalysis {
        case score(ScoreType, Int, RecoveryMetrics, [TrendDataPoint]?)
        case metric(MetricType, Double, String, RecoveryMetrics)
    }

    @Published var analysisText: String?
    @Published var isLoading = false
    @Published var error: String?
    @Published var needsConsent = false
    @Published var needsIndexation = false

    private let aiService = WorkoutAIService()
    private var cancellables = Set<AnyCancellable>()
    private var pendingAnalysis: PendingAnalysis?

    private static let cachePrefix = "ai_analysis_"
    #if DEBUG
    static var defaults: UserDefaults = .standard
    #else
    static let defaults: UserDefaults = .standard
    #endif

    init() {
        aiService.$streamedResponse
            .receive(on: DispatchQueue.main)
            .sink { [weak self] response in
                let isSystemMessage = response.isEmpty

                if !isSystemMessage {
                    self?.analysisText = response
                }
            }
            .store(in: &cancellables)

        aiService.$error
            .receive(on: DispatchQueue.main)
            .sink { [weak self] errorMsg in
                self?.error = errorMsg
            }
            .store(in: &cancellables)

        aiService.$needsConsent
            .receive(on: DispatchQueue.main)
            .sink { [weak self] needsConsent in
                self?.needsConsent = needsConsent
            }
            .store(in: &cancellables)

        aiService.$needsIndexation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] needsIndexation in
                self?.needsIndexation = needsIndexation
            }
            .store(in: &cancellables)
    }

    // MARK: - Cache

    // Cache key includes the value so that a changing score/metric invalidates
    // the cached analysis instead of returning a stale explanation.
    private static func cacheKey(for identifier: String, value: String) -> String {
        let dateString = DateFormatter.cacheDateFormatter.string(from: Date())
        let lang = AppLanguage.current
        return "\(cachePrefix)\(identifier)_\(lang)_\(dateString)_v\(value)"
    }

    private static func cachedAnalysis(for identifier: String, value: String) -> String? {
        let key = cacheKey(for: identifier, value: value)
        guard let cached = Self.defaults.string(forKey: key) else { return nil }
        // Defensive: discard caches written by older builds that may have stored a
        // truncated chunk (e.g. interrupted streaming). Re-fetch a fresh analysis instead.
        if !AIResponseValidator.isComplete(cached) {
            Self.defaults.removeObject(forKey: key)
            return nil
        }
        return cached
    }

    private static func saveAnalysis(_ text: String, for identifier: String, value: String) {
        guard AIResponseValidator.isComplete(text) else { return }
        let key = cacheKey(for: identifier, value: value)
        Self.defaults.set(text, forKey: key)
        cleanOldCache(currentKey: key, identifier: identifier)
    }

    private static func cleanOldCache(currentKey: String, identifier: String) {
        let prefix = "\(cachePrefix)\(identifier)_"
        for key in Self.defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) && key != currentKey {
            Self.defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Score Analysis

    func analyze(scoreType: ScoreType, score: Int, recoveryMetrics: RecoveryMetrics, trendData: [TrendDataPoint]? = nil) async {
        guard !isLoading else { return }
        pendingAnalysis = .score(scoreType, score, recoveryMetrics, trendData)

        if DemoMode.isEnabled {
            analysisText = MockData.sampleScoreAnalysis(for: scoreType)
            pendingAnalysis = nil
            return
        }

        let identifier = "score_\(scoreType.id)"
        let valueKey = String(score)

        if let cached = Self.cachedAnalysis(for: identifier, value: valueKey) {
            analysisText = cached
            pendingAnalysis = nil
            return
        }

        guard ConsentService.shared.hasConsentedToAIDataSharing else {
            needsConsent = true
            return
        }

        if await HistoricalSummaryStorage.shared.requiresIndexation() {
            AnalyticsService.shared.trackIndexationGateTriggered(source: "score_analysis")
            needsIndexation = true
            return
        }

        isLoading = true
        error = nil
        analysisText = nil
        pendingAnalysis = nil

        let prompt = buildPrompt(scoreType: scoreType, score: score, trendData: trendData)
        let userLanguage = AppLanguage.current

        // askQuestion only returns once the stream is fully consumed, so the final
        // text is available synchronously on aiService.streamedResponse afterwards.
        await aiService.askQuestion(
            question: prompt,
            mode: .recoveryCoaching(recoveryMetrics),
            language: userLanguage
        )

        isLoading = false

        // Read the service flags directly: they are set synchronously inside askQuestion,
        // whereas the @Published mirrors arrive through an async Combine sink a tick later.
        if aiService.needsConsent || aiService.needsIndexation {
            return
        }

        let text = aiService.streamedResponse
        if aiService.error == nil, AIResponseValidator.isComplete(text) {
            analysisText = text
            Self.saveAnalysis(text, for: identifier, value: valueKey)
        } else if aiService.error == nil {
            // Stream finished without throwing but produced a truncated/empty payload —
            // surface as an error and clear the partial text so the sheet doesn't display
            // a half-sentence to the user.
            analysisText = nil
            error = String(localized: "Unable to generate analysis", comment: "Score analysis error")
        }
    }

    // MARK: - Metric Analysis

    func analyzeMetric(metricType: MetricType, value: Double, unit: String, recoveryMetrics: RecoveryMetrics, activityData: DailyActivityData? = nil) async {
        guard !isLoading else { return }
        pendingAnalysis = .metric(metricType, value, unit, recoveryMetrics)

        if DemoMode.isEnabled {
            analysisText = MockData.sampleMetricAnalysis(for: metricType)
            pendingAnalysis = nil
            return
        }

        let identifier = "metric_\(metricType)"
        let valueKey = String(format: "%.1f", value)

        if let cached = Self.cachedAnalysis(for: identifier, value: valueKey) {
            analysisText = cached
            pendingAnalysis = nil
            return
        }

        guard ConsentService.shared.hasConsentedToAIDataSharing else {
            needsConsent = true
            return
        }

        if await HistoricalSummaryStorage.shared.requiresIndexation() {
            AnalyticsService.shared.trackIndexationGateTriggered(source: "metric_analysis")
            needsIndexation = true
            return
        }

        isLoading = true
        error = nil
        analysisText = nil
        pendingAnalysis = nil

        let prompt = buildMetricPrompt(metricType: metricType, value: value, unit: unit, activityData: activityData)
        let userLanguage = AppLanguage.current

        // askQuestion only returns once the stream is fully consumed, so the final
        // text is available synchronously on aiService.streamedResponse afterwards.
        await aiService.askQuestion(
            question: prompt,
            mode: .recoveryCoaching(recoveryMetrics),
            language: userLanguage
        )

        isLoading = false

        // Read the service flags directly: they are set synchronously inside askQuestion,
        // whereas the @Published mirrors arrive through an async Combine sink a tick later.
        if aiService.needsConsent || aiService.needsIndexation {
            return
        }

        let text = aiService.streamedResponse
        if aiService.error == nil, AIResponseValidator.isComplete(text) {
            analysisText = text
            Self.saveAnalysis(text, for: identifier, value: valueKey)
        } else if aiService.error == nil {
            analysisText = nil
            error = String(localized: "Unable to generate analysis", comment: "Score analysis error")
        }
    }

    func resumePendingAnalysis() async {
        guard let pendingAnalysis else { return }

        switch pendingAnalysis {
        case .score(let scoreType, let score, let recoveryMetrics, let trendData):
            await analyze(scoreType: scoreType, score: score, recoveryMetrics: recoveryMetrics, trendData: trendData)
        case .metric(let metricType, let value, let unit, let recoveryMetrics):
            await analyzeMetric(metricType: metricType, value: value, unit: unit, recoveryMetrics: recoveryMetrics)
        }
    }

    // MARK: - Prompts

    private var userLanguageName: String {
        Locale.current.englishLanguageName
    }

    private func buildMetricPrompt(metricType: MetricType, value: Double, unit: String, activityData: DailyActivityData? = nil) -> String {
        let formattedValue = String(format: "%.1f", value)
        let lang = userLanguageName

        switch metricType {
        case .hrv:
            return "My HRV is \(formattedValue) ms. Briefly analyze my heart rate variability and what it means for my recovery. Give me 1 actionable tip. Reply in 2-3 sentences max, no markdown. You MUST reply in \(lang)."

        case .restingHeartRate:
            return "My resting heart rate is \(formattedValue) bpm. Briefly analyze what this means for my cardiovascular health. Give me 1 actionable tip. Reply in 2-3 sentences max, no markdown. You MUST reply in \(lang)."

        case .respiratoryRate:
            return "My respiratory rate is \(formattedValue) rpm. Briefly analyze what this means for my recovery state. Give me 1 tip. Reply in 2-3 sentences max, no markdown. You MUST reply in \(lang)."

        case .oxygenSaturation:
            return "My oxygen saturation is \(formattedValue)%. Briefly analyze my blood oxygenation level. Give me 1 tip. Reply in 2-3 sentences max, no markdown. You MUST reply in \(lang)."

        case .totalCalories:
            let totalKcal = String(format: "%.0f", value)
            if let activity = activityData {
                let basal = String(format: "%.0f", activity.basalCalories)
                let active = String(format: "%.0f", activity.activeCalories)
                return "My total calories burned today is \(totalKcal) kcal: \(basal) kcal basal (resting metabolism) + \(active) kcal active (movement & exercise). Briefly analyze what this energy expenditure says about my activity level today, and whether the active vs basal split looks healthy. Give me 1 actionable tip. Reply in 2-3 sentences max, no markdown. You MUST reply in \(lang)."
            }
            return "My total calories burned today is \(totalKcal) kcal (basal metabolism + active calories combined). Briefly analyze my daily energy expenditure. Give me 1 actionable tip. Reply in 2-3 sentences max, no markdown. You MUST reply in \(lang)."

        default:
            return "Analyze this health metric: \(formattedValue) \(unit). Reply in 2-3 sentences max, no markdown. You MUST reply in \(lang)."
        }
    }

    private func buildPrompt(scoreType: ScoreType, score: Int, trendData: [TrendDataPoint]? = nil) -> String {
        let lang = userLanguageName

        switch scoreType {
        case .effort:
            return "My daily effort score is \(score)% (composite: steps 30%, active calories 35%, exercise minutes 35%, each vs personal Apple Ring goals, capped at 100%). Briefly analyze my daily activity level and what this score means. Give me 1 actionable tip. Reply in 2-3 sentences max, no markdown. You MUST reply in \(lang)."

        case .sleep:
            return "My sleep score is \(score)%. Briefly analyze my sleep quality (duration and efficiency). Give me 1 tip to improve my sleep. Reply in 2-3 sentences max, no markdown. You MUST reply in \(lang)."

        case .readiness:
            return "My readiness score is \(score)%. Briefly analyze my overall recovery and training preparedness. Give me 1 tip for today. Reply in 2-3 sentences max, no markdown. You MUST reply in \(lang)."

        case .cardiacLoad:
            if let trendSummary = formatTrendSummary(trendData) {
                return "My cardiac load is \(score)/20 (ACWR-based, 10/20 = maintaining). Here is my 14-day trend: [\(trendSummary)]. Analyze the trend evolution and current load. Is my training load progressing well? Give me 1 actionable tip on load management. Reply in 3-4 sentences max, no markdown. You MUST reply in \(lang)."
            }
            return "My cardiac load is \(score)/20 (ACWR-based, 10/20 = maintaining). Briefly analyze this cardiovascular load. Give me 1 tip on load management. Reply in 2-3 sentences max, no markdown. You MUST reply in \(lang)."

        case .freshness:
            if let trendSummary = formatTrendSummary(trendData) {
                return "My freshness score is \(score)/100, derived from Training Stress Balance (TSB = CTL − ATL). Higher = more rested for hard training, lower = accumulated fatigue. I don't track sleep, so this is my main recovery signal. Here is my 14-day trend: [\(trendSummary)]. Analyze whether I'm fresh enough for intensity today. Do NOT mention sleep. Give me 1 actionable tip. Reply in 3-4 sentences max, no markdown. You MUST reply in \(lang)."
            }
            return "My freshness score is \(score)/100, derived from Training Stress Balance. Higher = rested, lower = fatigued. I don't track sleep. Briefly tell me if I'm fresh enough for intensity today and give 1 tip. Do NOT mention sleep. Reply in 2-3 sentences max, no markdown. You MUST reply in \(lang)."
        }
    }

    private func formatTrendSummary(_ trendData: [TrendDataPoint]?) -> String? {
        guard let data = trendData, !data.isEmpty else { return nil }

        let sorted = data.sorted { $0.date < $1.date }
        let today = Calendar.current.startOfDay(for: Date())

        let entries: [String] = sorted.map { point in
            let pointDay = Calendar.current.startOfDay(for: point.date)
            let dayOffset = Calendar.current.dateComponents([.day], from: pointDay, to: today).day ?? 0
            let label = dayOffset == 0 ? "Day 0" : "Day -\(dayOffset)"
            return "\(label): \(Int(point.value))"
        }

        return entries.joined(separator: ", ")
    }

    // MARK: - Test Helpers

    #if DEBUG
    func testCacheKey(for identifier: String, value: String) -> String {
        Self.cacheKey(for: identifier, value: value)
    }

    func testCachedAnalysis(for identifier: String, value: String) -> String? {
        Self.cachedAnalysis(for: identifier, value: value)
    }

    func testSaveAnalysis(_ text: String, for identifier: String, value: String) {
        Self.saveAnalysis(text, for: identifier, value: value)
    }

    func testBuildPrompt(scoreType: ScoreType, score: Int, trendData: [TrendDataPoint]? = nil) -> String {
        buildPrompt(scoreType: scoreType, score: score, trendData: trendData)
    }

    func testBuildMetricPrompt(metricType: MetricType, value: Double, unit: String) -> String {
        buildMetricPrompt(metricType: metricType, value: value, unit: unit)
    }

    func testFormatTrendSummary(_ trendData: [TrendDataPoint]?) -> String? {
        formatTrendSummary(trendData)
    }
    #endif
}

// MARK: - DateFormatter Extension

private extension DateFormatter {
    static let cacheDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

// MARK: - Locale Extension

extension Locale {
    /// Returns the English name of the user's language (e.g. "French", "Spanish")
    var englishLanguageName: String {
        let code = language.languageCode?.identifier ?? "en"
        return Locale(identifier: "en").localizedString(forLanguageCode: code) ?? "English"
    }
}
