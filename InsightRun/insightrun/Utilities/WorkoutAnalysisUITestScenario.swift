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
            hasRoute: false
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
            ## Synthèse
            Cette séance de 5 kilomètres présente une allure régulière et un effort maîtrisé.

            ## Prochaine action
            Commencez votre prochaine séance par dix minutes à allure facile.
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
