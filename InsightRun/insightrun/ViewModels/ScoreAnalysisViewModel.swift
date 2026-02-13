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
    @Published var analysisText: String?
    @Published var isLoading = false
    @Published var error: String?

    private let aiService = WorkoutAIService()
    private var cancellables = Set<AnyCancellable>()

    private static let cachePrefix = "ai_analysis_"

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
    }

    // MARK: - Cache

    private static func cacheKey(for identifier: String) -> String {
        let dateString = DateFormatter.cacheDateFormatter.string(from: Date())
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        return "\(cachePrefix)\(identifier)_\(lang)_\(dateString)"
    }

    private static func cachedAnalysis(for identifier: String) -> String? {
        UserDefaults.standard.string(forKey: cacheKey(for: identifier))
    }

    private static func saveAnalysis(_ text: String, for identifier: String) {
        let key = cacheKey(for: identifier)
        UserDefaults.standard.set(text, forKey: key)
        cleanOldCache(currentKey: key, identifier: identifier)
    }

    private static func cleanOldCache(currentKey: String, identifier: String) {
        let prefix = "\(cachePrefix)\(identifier)_"
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix(prefix) && key != currentKey {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - Score Analysis

    func analyze(scoreType: ScoreType, score: Int, recoveryMetrics: RecoveryMetrics, trendData: [TrendDataPoint]? = nil) async {
        guard !isLoading else { return }

        let identifier = "score_\(scoreType.id)"

        if let cached = Self.cachedAnalysis(for: identifier) {
            analysisText = cached
            return
        }

        isLoading = true
        error = nil
        analysisText = nil

        let prompt = buildPrompt(scoreType: scoreType, score: score, trendData: trendData)

        await aiService.askQuestion(
            question: prompt,
            mode: .recoveryCoaching(recoveryMetrics)
        )

        var attempts = 0
        while aiService.isStreaming && attempts < 60 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            attempts += 1
        }

        isLoading = false

        if let text = analysisText, !text.isEmpty {
            Self.saveAnalysis(text, for: identifier)
        } else if error == nil {
            error = String(localized: "Unable to generate analysis", comment: "Score analysis error")
        }
    }

    // MARK: - Metric Analysis

    func analyzeMetric(metricType: MetricType, value: Double, unit: String, recoveryMetrics: RecoveryMetrics) async {
        guard !isLoading else { return }

        let identifier = "metric_\(metricType)"

        if let cached = Self.cachedAnalysis(for: identifier) {
            analysisText = cached
            return
        }

        isLoading = true
        error = nil
        analysisText = nil

        let prompt = buildMetricPrompt(metricType: metricType, value: value, unit: unit)

        await aiService.askQuestion(
            question: prompt,
            mode: .recoveryCoaching(recoveryMetrics)
        )

        var attempts = 0
        while aiService.isStreaming && attempts < 60 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            attempts += 1
        }

        isLoading = false

        if let text = analysisText, !text.isEmpty {
            Self.saveAnalysis(text, for: identifier)
        } else if error == nil {
            error = String(localized: "Unable to generate analysis", comment: "Score analysis error")
        }
    }

    // MARK: - Prompts

    private var userLanguageName: String {
        Locale.current.englishLanguageName
    }

    private func buildMetricPrompt(metricType: MetricType, value: Double, unit: String) -> String {
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
        switch code {
        case "fr": return "French"
        case "es": return "Spanish"
        case "de": return "German"
        case "it": return "Italian"
        case "pt": return "Portuguese"
        case "nl": return "Dutch"
        case "ja": return "Japanese"
        case "zh": return "Chinese"
        case "ko": return "Korean"
        case "ar": return "Arabic"
        default: return "English"
        }
    }
}
