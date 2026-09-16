//
//  DailyReadinessViewModel.swift
//  InsightRun
//
//  ViewModel for daily readiness scoring and recommendations
//

import SwiftUI
import Combine
import CryptoKit

@MainActor
class DailyReadinessViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var readinessScore: Int?
    @Published var status: ReadinessStatus = .unknown
    @Published var recommendation: String = ""
    /// Short TL;DR shown collapsed in the dashboard coach card.
    /// Falls back to `recommendation` when the backend doesn't provide a separate summary.
    @Published var recommendationSummary: String = ""
    @Published var suggestedWorkoutType: SuggestedWorkoutType = .rest
    @Published var insights: [ReadinessInsight] = []
    @Published var needsConsent = false
    @Published var needsIndexation = false
    /// True when fewer than 3 nights of sleep are tracked over the last 14 days.
    /// The dashboard swaps sleep-based cards for freshness (TSB) cards and the
    /// backend omits sleep from the AI coaching prompt.
    @Published var isNoSleepMode: Bool = false
    @Published var updatedAt: Date?
    private var requestID = UUID()
    private var hasPromptedConsent = false

    private let backendClient = BackendAPIClient.shared
    private let healthKitManager = HealthKitManager.shared
    private let dailyCache: DailyMetricsCache

    init(dailyCache: DailyMetricsCache? = nil) {
        self.dailyCache = dailyCache ?? .shared
    }

    // MARK: - Fetch Daily Readiness

    /// Fetch today's readiness score from backend
    /// - Parameters:
    ///   - activityData: Daily steps/calories/exercise from HealthKit
    ///   - effortScore: Computed daily effort score (0-100)
    ///   - cardiacLoadScore: Current cardiac load score (0-20)
    ///   - cardiacLoadStatus: Current cardiac load trend status
    ///   - forceRefresh: Skip cache and fetch fresh analysis from backend
    func fetchDailyReadiness(
        for date: Date = Date(),
        recoveryMetrics suppliedRecovery: RecoveryMetrics? = nil,
        activityData: DailyActivityData? = nil,
        effortScore: Int = 0,
        cardiacLoadScore: Int? = nil,
        cardiacLoadStatus: CardiacLoadStatus = .detraining,
        freshnessAvailable: Bool = false,
        forceRefresh: Bool = false
    ) async {
        let id = UUID()
        requestID = id
        isLoading = true
        errorMessage = nil
        defer { if requestID == id { isLoading = false } }
        if !Calendar.current.isDateInToday(date) {
            let cached = dailyCache.getReadiness(for: date)
            readinessScore = cached?.score ?? dailyCache.getHistoricalReadinessScore(for: date)
            status = cached.map { ReadinessStatus(from: $0.status) } ?? .unknown
            recommendation = cached?.recommendation ?? ""
            recommendationSummary = cached?.summary ?? recommendation
            insights = []
            updatedAt = cached?.cacheDate
            return
        }
        isNoSleepMode = await SleepDataAvailabilityService.shared.isNoSleepMode()
        guard requestID == id, !Task.isCancelled else { return }
        if DemoMode.isEnabled {
            readinessScore = 82
            status = .good
            recommendation = String(localized: "Good recovery. You can do a moderate to intense workout.", comment: "Demo readiness recommendation")
            recommendationSummary = recommendation
            suggestedWorkoutType = .moderate
            insights = []
            isLoading = false
            errorMessage = nil
            return
        }

        // Check AI consent before sending health data
        guard ConsentService.shared.hasConsentedToAIDataSharing else {
            if !hasPromptedConsent {
                needsConsent = true
                hasPromptedConsent = true
            }
            isLoading = false
            return
        }

        // Check historical indexation
        if await HistoricalSummaryStorage.shared.requiresIndexation() {
            AnalyticsService.shared.trackIndexationGateTriggered(source: "daily_readiness")
            needsIndexation = true
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let recoveryMetrics = try await recoveryMetrics(for: date, supplied: suppliedRecovery)
            let baseline = recoveryMetrics.baseline
            guard requestID == id, !Task.isCancelled else { return }
            let noSleepMode = isNoSleepMode
            guard recoveryMetrics.hasRecoveryMeasurements(includeSleep: !noSleepMode) else {
                readinessScore = nil
                status = .unknown
                recommendation = ""
                recommendationSummary = ""
                insights = []
                updatedAt = nil
                errorMessage = String(localized: "recovery.insufficient_data", defaultValue: "Not enough health data to assess your recovery yet.")
                return
            }

            let recentWorkouts = try? await healthKitManager.fetchRunningWorkouts(from: Date().addingTimeInterval(-8 * 86_400), to: Date())
            guard requestID == id, !Task.isCancelled else { return }
            let workoutPayloads = buildRecentWorkoutPayloads(from: recentWorkouts ?? [])

            let activityPayload: DailyActivityPayload? = activityData.map {
                DailyActivityPayload(
                    steps: $0.steps,
                    activeCalories: $0.activeCalories,
                    exerciseMinutes: $0.exerciseMinutes,
                    effortScore: effortScore
                )
            }

            let cardiacPayload: CardiacLoadPayload? = cardiacLoadScore.map {
                CardiacLoadPayload(score: $0, status: cardiacLoadStatus.rawValue)
            }

            // Pull the morning score for today (if any) so the backend keeps it stable
            // when only effort/cardiac context has shifted.
            let recoverySignature = Self.signature([
                "recovery-v2",
                Self.signature(buildRecoveryPayload(from: recoveryMetrics)),
                Self.signature(baseline.map { buildBaselinePayload(from: $0) }),
                String(noSleepMode)
            ])
            let inputSignature = Self.signature([
                recoverySignature, String(describing: activityData),
                String(effortScore), String(describing: cardiacLoadScore), cardiacLoadStatus.rawValue,
                workoutPayloads.map { "\($0.date):\($0.distanceMeters):\($0.durationSeconds):\(String(describing: $0.avgHeartRate)):\(String(describing: $0.maxHeartRate)):\(String(describing: $0.pace))" }.joined(separator: ";")
            ])
            if !forceRefresh, let cached = dailyCache.getCachedReadiness(
                effortScore: effortScore, cardiacLoadScore: cardiacLoadScore, inputSignature: inputSignature
            ) {
                readinessScore = cached.score
                status = ReadinessStatus(from: cached.status)
                recommendation = cached.recommendation
                recommendationSummary = cached.summary?.nilIfEmpty ?? cached.recommendation
                suggestedWorkoutType = SuggestedWorkoutType(from: cached.suggestedWorkoutType)
                updatedAt = cached.cacheDate
                return
            }
            let frozenScore = dailyCache.getCachedScoreForToday(recoverySignature: recoverySignature)

            let request = DailyReadinessRequest(
                recovery: buildRecoveryPayload(from: recoveryMetrics),
                baseline: baseline.map { buildBaselinePayload(from: $0) },
                dailyActivity: activityPayload,
                cardiacLoad: cardiacPayload,
                recentWorkouts: workoutPayloads.isEmpty ? nil : workoutPayloads,
                language: AppLanguage.current,
                cachedScore: frozenScore?.score,
                cachedStatus: frozenScore?.status,
                noSleepMode: noSleepMode ? true : nil
            )

            let response = try await backendClient.fetchDailyReadiness(request: request)

            guard requestID == id, !Task.isCancelled else { return }

            // Defensive freeze: if the user already has a morning score for today,
            // keep it regardless of what the backend returned. Covers older backends
            // that don't honor `cachedScore`, and rollback scenarios.
            let displayScore = frozenScore?.score ?? response.score
            let displayStatus = frozenScore?.status ?? response.status

            readinessScore = displayScore
            status = ReadinessStatus(from: displayStatus)
            // Long form goes to the legacy `recommendation` (so older readers keep working);
            // collapsed dashboard view reads `recommendationSummary` and falls back gracefully.
            let detailText = response.detail?.nilIfEmpty ?? response.recommendation
            recommendation = detailText
            recommendationSummary = response.summary?.nilIfEmpty ?? detailText
            suggestedWorkoutType = SuggestedWorkoutType(from: response.suggestedWorkoutType)
            insights = response.insights.map { ReadinessInsight(from: $0) }

            dailyCache.cacheReadiness(
                score: displayScore,
                status: displayStatus,
                recommendation: detailText,
                summary: response.summary,
                workoutType: response.suggestedWorkoutType,
                effortScore: effortScore,
                cardiacLoadScore: cardiacLoadScore,
                inputSignature: inputSignature,
                recoverySignature: recoverySignature,
                date: date
            )

            updatedAt = Date()

            // Tracked here (not on cache hits) so the metric reflects real backend
            // computations and stays cheap. `freshness_available` lets us split the
            // no-sleep cohort into "TSB ready" vs. "still building baseline".
            AnalyticsService.shared.trackDailyReadinessComputed(
                noSleepMode: noSleepMode,
                freshnessAvailable: freshnessAvailable
            )

        } catch {
            guard requestID == id, !Task.isCancelled else { return }
            print("❌ DailyReadinessViewModel: Failed to fetch readiness: \(error)")
            // Surface specific backend errors (rate limit + retry delay, blocked, …)
            // instead of masking a 429 behind a generic "try again" message.
            if let backendError = error as? BackendError {
                errorMessage = backendError.errorDescription
            } else {
                errorMessage = String(
                    localized: "Unable to calculate readiness score. Please try again.",
                    comment: "Error message when readiness calculation fails"
                )
            }
        }

    }

    private func recoveryMetrics(for date: Date, supplied: RecoveryMetrics?) async throws -> RecoveryMetrics {
        if let supplied { return supplied }
        return try await healthKitManager.fetchRecoveryMetrics(for: date)
    }

    private static func signature<Value: Encodable>(_ value: Value) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(value)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Payload Builders

    private func buildRecoveryPayload(from metrics: RecoveryMetrics) -> RecoveryData {
        RecoveryData(metrics: metrics)
    }

    // ISO 8601: the backend parses this via `new Date(w.date)`. A locale-formatted
    // string ("14 juin 2026 à 09:30") would fail that parse on non-English locales.
    private static let workoutDateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func buildRecentWorkoutPayloads(from workouts: [WorkoutModel]) -> [ReadinessWorkoutData] {
        let now = Date()
        return workouts.map { workout in
            let hoursAgo = now.timeIntervalSince(workout.endDate) / 3600
            return ReadinessWorkoutData(
                date: Self.workoutDateFormatter.string(from: workout.startDate),
                distanceMeters: workout.distance ?? 0,
                durationSeconds: workout.duration,
                avgHeartRate: workout.averageHeartRate.map { Int($0) },
                maxHeartRate: workout.maxHeartRate.map { Int($0) },
                pace: workout.averagePace,
                hoursAgo: (hoursAgo * 10).rounded() / 10
            )
        }
    }

    private func buildBaselinePayload(from baseline: PersonalBaseline) -> PersonalBaselineData {
        PersonalBaselineData(baseline: baseline)
    }
}

// MARK: - Request/Response Models

struct DailyReadinessRequest: Encodable {
    let recovery: RecoveryData
    let baseline: PersonalBaselineData?
    let dailyActivity: DailyActivityPayload?
    let cardiacLoad: CardiacLoadPayload?
    let recentWorkouts: [ReadinessWorkoutData]?
    let language: String
    /// Morning score already computed today. When set, the backend honors it as the
    /// response score instead of recomputing — keeps the displayed score stable for the day.
    let cachedScore: Int?
    /// Status paired with `cachedScore`. Used by the backend to keep the AI prompt and
    /// suggested workout type coherent with the frozen score.
    let cachedStatus: String?
    /// Set to true when the client detects fewer than 3 nights tracked over 14 days.
    /// The backend uses it to omit sleep from the AI coaching prompt and tag the
    /// response with `mode: "noSleep"`. Omitted (nil) for users who track sleep.
    let noSleepMode: Bool?
}

struct ReadinessWorkoutData: Encodable {
    let date: String
    let distanceMeters: Double
    let durationSeconds: Double
    let avgHeartRate: Int?
    let maxHeartRate: Int?
    let pace: Double? // min/km
    let hoursAgo: Double
}

struct DailyReadinessResponse: Decodable {
    let score: Int
    let status: String
    /// Legacy field — older backends only populate this. New backends keep it filled with the full coaching text.
    let recommendation: String
    /// One-sentence TL;DR (new backend only). Falls back to `recommendation` for old backends.
    let summary: String?
    /// Full coaching explanation (new backend only). Falls back to `recommendation` for old backends.
    let detail: String?
    let suggestedWorkoutType: String
    let insights: [DailyReadinessInsightResponse]
}

struct DailyReadinessInsightResponse: Decodable {
    let metric: String
    let value: Double
    let comparison: String
    let deviation: Double?
    let message: String
}

// MARK: - View Models

enum ReadinessStatus {
    case excellent
    case good
    case fair
    case poor
    case unknown

    init(from string: String) {
        switch string.lowercased() {
        case "excellent":
            self = .excellent
        case "good":
            self = .good
        case "fair":
            self = .fair
        case "poor":
            self = .poor
        default:
            self = .unknown
        }
    }

    var emoji: String {
        switch self {
        case .excellent: return "🟢"
        case .good: return "🟡"
        case .fair: return "🟠"
        case .poor: return "🔴"
        case .unknown: return "⚪"
        }
    }

    var title: String {
        switch self {
        case .excellent:
            return String(localized: "Excellent", comment: "Readiness status - excellent")
        case .good:
            return String(localized: "Good", comment: "Readiness status - good")
        case .fair:
            return String(localized: "Fair", comment: "Readiness status - fair")
        case .poor:
            return String(localized: "Rest", comment: "Readiness status - poor")
        case .unknown:
            return String(localized: "Unknown", comment: "Readiness status - unknown")
        }
    }

    var color: Color {
        switch self {
        case .excellent: return .green
        case .good: return .yellow
        case .fair: return .orange
        case .poor: return .red
        case .unknown: return .gray
        }
    }
}

enum SuggestedWorkoutType {
    case intense
    case moderate
    case easy
    case rest

    init(from string: String) {
        switch string.lowercased() {
        case "intense":
            self = .intense
        case "moderate":
            self = .moderate
        case "easy":
            self = .easy
        default:
            self = .rest
        }
    }

    var icon: String {
        switch self {
        case .intense: return "flame.fill"
        case .moderate: return "figure.run"
        case .easy: return "figure.walk"
        case .rest: return "bed.double.fill"
        }
    }

    var title: String {
        switch self {
        case .intense:
            return String(localized: "Intense Training", comment: "Workout type - intense")
        case .moderate:
            return String(localized: "Moderate Run", comment: "Workout type - moderate")
        case .easy:
            return String(localized: "Easy Run", comment: "Workout type - easy")
        case .rest:
            return String(localized: "Rest Day", comment: "Workout type - rest")
        }
    }
}

struct ReadinessInsight: Identifiable {
    let id = UUID()
    let metric: String
    let value: Double
    let comparison: InsightComparison
    let deviation: Double?
    let message: String

    init(from response: DailyReadinessInsightResponse) {
        self.metric = response.metric
        self.value = response.value
        self.comparison = InsightComparison(from: response.comparison)
        self.deviation = response.deviation
        self.message = response.message
    }
}

enum InsightComparison {
    case above
    case at
    case below

    init(from string: String) {
        switch string.lowercased() {
        case "above":
            self = .above
        case "below":
            self = .below
        default:
            self = .at
        }
    }

    var icon: String {
        switch self {
        case .above: return "arrow.up"
        case .at: return "equal"
        case .below: return "arrow.down"
        }
    }

    var color: Color {
        switch self {
        case .above: return .green
        case .at: return .blue
        case .below: return .orange
        }
    }
}
