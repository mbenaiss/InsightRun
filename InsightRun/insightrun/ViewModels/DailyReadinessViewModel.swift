//
//  DailyReadinessViewModel.swift
//  InsightRun
//
//  ViewModel for daily readiness scoring and recommendations
//

import SwiftUI
import Combine

@MainActor
class DailyReadinessViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var readinessScore: Int?
    @Published var status: ReadinessStatus = .unknown
    @Published var recommendation: String = ""
    @Published var suggestedWorkoutType: SuggestedWorkoutType = .rest
    @Published var insights: [ReadinessInsight] = []

    private let backendClient = BackendAPIClient.shared
    private let healthKitManager = HealthKitManager.shared

    // MARK: - Fetch Daily Readiness

    /// Fetch today's readiness score from backend
    func fetchDailyReadiness() async {
        isLoading = true
        errorMessage = nil

        do {
            // Fetch current recovery metrics
            let recoveryMetrics = try await healthKitManager.fetchRecoveryMetrics(for: Date())

            // Load personal baseline
            let baseline = PersonalBaselineStorage.shared.load()

            // Build request
            let request = DailyReadinessRequest(
                recovery: buildRecoveryPayload(from: recoveryMetrics),
                baseline: baseline.map { buildBaselinePayload(from: $0) },
                language: Locale.current.language.languageCode?.identifier ?? "en"
            )

            // Call backend
            let response = try await backendClient.fetchDailyReadiness(request: request)

            // Update state
            readinessScore = response.score
            status = ReadinessStatus(from: response.status)
            recommendation = response.recommendation
            suggestedWorkoutType = SuggestedWorkoutType(from: response.suggestedWorkoutType)
            insights = response.insights.map { ReadinessInsight(from: $0) }

        } catch {
            print("❌ DailyReadinessViewModel: Failed to fetch readiness: \(error)")
            errorMessage = String(
                localized: "Unable to calculate readiness score. Please try again.",
                comment: "Error message when readiness calculation fails"
            )
        }

        isLoading = false
    }

    // MARK: - Payload Builders

    private func buildRecoveryPayload(from metrics: RecoveryMetrics) -> RecoveryData {
        RecoveryData(
            restingHeartRate: metrics.restingHeartRate.map { Int($0) },
            hrv: metrics.hrvAverage.map { Int($0) },
            walkingHeartRate: metrics.walkingHeartRate.map { Int($0) },
            respiratoryRate: metrics.respiratoryRate.map { Int($0) },
            sleepData: metrics.sleepData.map { sleep in
                SleepDataPayload(
                    totalDuration: sleep.totalSleepDuration,
                    efficiency: Int(sleep.sleepEfficiency),
                    deepDuration: sleep.deepSleepDuration,
                    remDuration: sleep.remSleepDuration
                )
            }
        )
    }

    private func buildBaselinePayload(from baseline: PersonalBaseline) -> PersonalBaselineData {
        PersonalBaselineData(
            restingHeartRateAverage: baseline.restingHeartRateAverage,
            restingHeartRateStdDev: baseline.restingHeartRateStdDev,
            hrvAverage: baseline.hrvAverage,
            hrvStdDev: baseline.hrvStdDev,
            sleepDurationAverage: baseline.sleepDurationAverage,
            sleepEfficiencyAverage: baseline.sleepEfficiencyAverage,
            respiratoryRateAverage: baseline.respiratoryRateAverage,
            respiratoryRateStdDev: baseline.respiratoryRateStdDev,
            dataPointCount: baseline.dataPointCount,
            isReliable: baseline.isReliable
        )
    }
}

// MARK: - Request/Response Models

struct DailyReadinessRequest: Encodable {
    let recovery: RecoveryData
    let baseline: PersonalBaselineData?
    let language: String
}

struct DailyReadinessResponse: Decodable {
    let score: Int
    let status: String
    let recommendation: String
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
