#if DEBUG
import Combine
import Foundation
import HealthKit
import SwiftData
import SwiftUI

@MainActor
final class WorkoutAnalysisUITestScenario {
    static var isEnabled: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-DEMO_MODE") && arguments.contains("-WORKOUT_ANALYSIS_UI_TEST")
    }

    let workout: WorkoutModel
    let metrics: WorkoutMetrics
    let analysisViewModel: WorkoutAnalysisViewModel

    static func makeModelContainer() throws -> ModelContainer {
        let schema = Schema([
            WorkoutAnalysis.self,
            CachedStravaActivity.self,
            CachedUnifiedWorkout.self,
            CachedRaceGoal.self,
            MonthlyStatsAnalysis.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    init(modelContext: ModelContext) {
        precondition(Self.isEnabled)
        ConsentService.shared.resetConsentState()

        let startDate = Date(timeIntervalSince1970: 1_788_854_400)
        let workout = WorkoutModel(
            id: UUID(),
            workoutType: .running,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(1_800),
            duration: 1_800,
            distance: 5_000,
            totalEnergyBurned: 320,
            sourceName: "UI Test",
            sourceVersion: nil,
            metadata: ["display_name": "Course du matin", "is_sample": false],
            averageHeartRate: 145,
            maxHeartRate: 160,
            elevationGain: 12,
            hasRoute: false,
            effortScore: ProcessInfo.processInfo.arguments.contains("-TRAINING_INSIGHTS_UI_TEST") ? 7 : nil,
            effortIsEstimated: true
        )
        var metrics = WorkoutMetrics(workout: workout)
        metrics.averageHeartRate = 145
        metrics.minHeartRate = 115
        metrics.maxHeartRate = 160
        metrics.averagePace = 6
        metrics.averageSpeed = 10
        metrics.totalSteps = 5_100
        metrics.averageCadence = 170
        metrics.totalElevationAscent = 12
        metrics.movingTime = 1_800
        metrics.pausedTime = 0
        if ProcessInfo.processInfo.arguments.contains("-TRAINING_INSIGHTS_UI_TEST") {
            metrics.splits = (1...5).map { kilometer in
                Split(kilometer: kilometer, distance: 1000, time: 360, pace: 6,
                      averageHeartRate: 145, averagePower: 200, elevationGain: 2, elevationLoss: 1)
            }
            metrics.groundContactTime = 260
            metrics.temperature = 19.5
            metrics.humidity = 62
            metrics.evidence = WorkoutEvidence(
                measuredAt: Date().ISO8601Format(), source: "com.apple.health", device: "Watch", softwareVersion: "27",
                zones: RecordedHeartRateZones(source: "system", zones: [
                    .init(index: 0, minimum: nil, maximum: 130, seconds: 60),
                    .init(index: 1, minimum: 130, maximum: 142, seconds: 300),
                    .init(index: 2, minimum: 142, maximum: 155, seconds: 1000),
                    .init(index: 3, minimum: 155, maximum: 168, seconds: 440),
                    .init(index: 4, minimum: 168, maximum: nil, seconds: 0)
                ]),
                signals: [.init(metric: "heartRate", sampleCount: 360, coverage: 0.99, longestGapSeconds: 5, sourceCount: 1)],
                phases: []
            )
        }

        self.workout = workout
        self.metrics = metrics
        self.analysisViewModel = WorkoutAnalysisViewModel(
            workout: workout,
            metrics: metrics,
            modelContext: modelContext,
            aiService: WorkoutAnalysisUITestClient(
                failsFirstRequest: ProcessInfo.processInfo.arguments.contains("-WORKOUT_ANALYSIS_UI_ERROR")
            ),
            // Demo mode bypasses the consent boolean; the real sheet still persists its acceptance date.
            hasAIConsent: { ConsentService.shared.consentDate != nil },
            requiresIndexation: { false },
            isDemo: false
        )
    }
}

@MainActor
private final class WorkoutAnalysisUITestClient: WorkoutAnalysisClient {
    @Published private(set) var streamedResponse = ""
    private(set) var error: String?
    private let failsFirstRequest: Bool
    private var requestCount = 0

    var responsePublisher: AnyPublisher<String, Never> {
        $streamedResponse.eraseToAnyPublisher()
    }

    init(failsFirstRequest: Bool) {
        self.failsFirstRequest = failsFirstRequest
    }

    func askQuestion(question: String, mode: AIAssistantMode) async {
        requestCount += 1
        streamedResponse = ""
        error = nil

        if failsFirstRequest && requestCount == 1 {
            error = "Connexion indisponible. Réessayez pour analyser cette séance."
            return
        }

        streamedResponse = """
            Cette séance de 5 kilomètres en 30 minutes présente une allure régulière, ce qui décrit une bonne continuité de l'effort sans suffire à en déduire son intensité. La fréquence cardiaque moyenne de 145 battements par minute complète cette observation, mais son interprétation dépend de ton objectif et de ton ressenti. Pour ta prochaine séance, commence par 10 minutes à une allure confortable afin de prendre tes repères avant d'augmenter l'effort.
            """
    }
}
struct WorkoutRaceUITestView: View {
    let scenario: WorkoutAnalysisUITestScenario

    private var plan: TrainingPlan {
        TrainingPlan(
            name: "Test plan", goal: "10K", level: .beginner,
            weeks: [TrainingWeek(weekNumber: 1, phase: .base, days: [TrainingDay(dayOfWeek: .monday)])],
            startDate: Calendar.current.startOfDay(for: scenario.workout.startDate)
        )
    }

    var body: some View {
        NavigationStack {
            WorkoutDetailView(
                workout: scenario.workout,
                analysisViewModel: scenario.analysisViewModel,
                initialMetrics: scenario.metrics
            )
            .toolbar {
                NavigationLink {
                    ScrollView {
                        OfficialRacesInPlanView(plan: plan, weekIndex: 0)
                            .padding()
                    }
                    .navigationTitle("Test plan")
                } label: {
                    Image(systemName: "calendar")
                }
                .accessibilityIdentifier("test-official-race-plan")
            }
        }
    }
}
#endif
