//
//  UnifiedAIContextProvider.swift
//  InsightRun
//
//  Service that provides unified AI context across all app screens.
//  Loads workouts, recovery, profile, and baseline data for comprehensive AI coaching.
//

import Foundation
import Combine

/// Represents the current page/context for contextual suggestions
enum AIContextPage: String, CaseIterable {
    case workouts
    case statistics
    case plan
    case recovery
    case profile
    case workoutDetail
}

@MainActor
class UnifiedAIContextProvider: ObservableObject {
    static let shared = UnifiedAIContextProvider()

    // Current context page (for contextual suggestions)
    @Published var currentPage: AIContextPage = .workouts

    // Loaded data
    @Published var recentWorkouts: [WorkoutModel] = [] {
        didSet { workoutsMetrics = [:] }
    }
    @Published var workoutsMetrics: [UUID: WorkoutMetrics] = [:]
    @Published var recoveryMetrics: RecoveryMetrics?
    @Published var healthProfile: HealthProfile?
    @Published var personalBaseline: PersonalBaseline?
    @Published var selectedWorkout: WorkoutModel?
    @Published var selectedWorkoutMetrics: WorkoutMetrics?

    // Loading states
    @Published var isLoadingWorkouts = false
    @Published var isLoadingRecovery = false
    @Published var isLoadingProfile = false

    private var contextRefreshedAt: Date?

    var needsRefresh: Bool {
        guard let contextRefreshedAt else { return true }
        return Date().timeIntervalSince(contextRefreshedAt) > 300
    }

    private let healthKitManager = HealthKitManager.shared

    private init() {}

    // MARK: - Data Loading

    /// Load all data needed for unified AI context
    func loadAllData(includeWorkoutMetrics: Bool = true) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadRecentWorkouts(includeMetrics: includeWorkoutMetrics) }
            group.addTask { await self.loadRecoveryMetrics() }
            group.addTask { await self.loadHealthProfile() }
            group.addTask { await self.loadPersonalBaseline() }
        }
        contextRefreshedAt = Date()
    }

    /// The currently-active goal with a training plan, if any.
    /// Reads directly from `GoalStorage` — goals data is light and changes outside this provider.
    var activeGoalWithPlan: RaceGoal? {
        GoalStorage.shared.load().first { $0.isActive && !$0.isPast && $0.hasTrainingPlan }
    }

    /// Load recent workouts with metrics
    func loadRecentWorkouts(includeMetrics: Bool = true) async {
        isLoadingWorkouts = true
        defer { isLoadingWorkouts = false }

        do {
            let calendar = Calendar.current
            let now = Date()
            guard let start = calendar.date(byAdding: .year, value: -1, to: now) else { return }
            let workouts = try await healthKitManager.fetchRunningWorkouts(from: start, to: now, limit: 10)
            let healthRuns = workouts.map { UnifiedWorkout(from: $0) }
            let cached = (try? UnifiedWorkoutCache.shared.fetchAllWorkouts()) ?? []
            let imported = cached.filter { candidate in
                (candidate.source == .suunto || (candidate.source == .strava && StravaAuthService.shared.isAuthenticated)) &&
                candidate.endDate <= now && candidate.startDate >= start &&
                !healthRuns.contains { $0.isDuplicateOf(candidate) }
            }.map { $0.toWorkoutModel() }
            let recent = Array((workouts + imported).sorted { $0.startDate > $1.startDate }.prefix(10))
            self.recentWorkouts = recent
            guard includeMetrics else { return }

            // Load metrics in parallel
            var metricsDict: [UUID: WorkoutMetrics] = [:]
            await withTaskGroup(of: (UUID, WorkoutMetrics?).self) { group in
                for workout in recent {
                    group.addTask {
                        let metrics = try? await self.healthKitManager.fetchWorkoutMetrics(for: workout)
                        return (workout.id, metrics)
                    }
                }

                for await (id, metrics) in group {
                    if let metrics = metrics {
                        metricsDict[id] = metrics
                    }
                }
            }

            guard recent.map(\.id) == recentWorkouts.map(\.id) else { return }
            self.workoutsMetrics = metricsDict
        } catch {
            print("⚠️ UnifiedAIContextProvider: Failed to load workouts: \(error)")
        }
    }

    /// Load today's recovery metrics
    func loadRecoveryMetrics() async {
        isLoadingRecovery = true

        do {
            let metrics = try await healthKitManager.fetchRecoveryMetrics(for: Date())
            self.recoveryMetrics = metrics
        } catch {
            print("⚠️ UnifiedAIContextProvider: Failed to load recovery: \(error)")
        }

        isLoadingRecovery = false
    }

    /// Load health profile
    func loadHealthProfile() async {
        isLoadingProfile = true

        do {
            let profile = try await healthKitManager.fetchHealthProfile()
            self.healthProfile = profile
        } catch {
            print("⚠️ UnifiedAIContextProvider: Failed to load profile: \(error)")
        }

        isLoadingProfile = false
    }

    /// Load personal baseline from storage
    func loadPersonalBaseline() async {
        personalBaseline = PersonalBaselineStorage.shared.load()
    }

    /// Set current selected workout (from detail view)
    func setSelectedWorkout(_ workout: WorkoutModel, metrics: WorkoutMetrics?) {
        selectedWorkout = workout
        selectedWorkoutMetrics = metrics
    }

    /// Clear selected workout
    func clearSelectedWorkout() {
        selectedWorkout = nil
        selectedWorkoutMetrics = nil
    }

    // MARK: - Contextual Suggestions

    /// Get sample questions based on current page
    func getSampleQuestions() -> [String] {
        switch currentPage {
        case .workouts:
            return [
                String(localized: "How have my performances evolved?", comment: "AI suggestion for workouts page"),
                String(localized: "What is my best workout?", comment: "AI suggestion for workouts page"),
                String(localized: "Am I overtraining?", comment: "AI suggestion for workouts page"),
                String(localized: "Analyze my consistency", comment: "AI suggestion for workouts page")
            ]
        case .statistics:
            return [
                String(localized: "Analyze my pace trends", comment: "AI suggestion for statistics page"),
                String(localized: "How is my VO2max evolving?", comment: "AI suggestion for statistics page"),
                String(localized: "What's my weekly volume trend?", comment: "AI suggestion for statistics page"),
                String(localized: "Compare my performance by month", comment: "AI suggestion for statistics page")
            ]
        case .plan:
            return [
                String(localized: "Create a 5K training plan", comment: "AI suggestion for plan page"),
                String(localized: "What workout should I do today?", comment: "AI suggestion for plan page"),
                String(localized: "Generate interval training", comment: "AI suggestion for plan page"),
                String(localized: "Plan my next long run", comment: "AI suggestion for plan page")
            ]
        case .recovery:
            return [
                String(localized: "Can I train today?", comment: "AI suggestion for recovery page"),
                String(localized: "How to improve my recovery?", comment: "AI suggestion for recovery page"),
                String(localized: "Why is my HRV low?", comment: "AI suggestion for recovery page"),
                String(localized: "What type of training is suitable?", comment: "AI suggestion for recovery page")
            ]
        case .profile:
            return [
                String(localized: "Analyze my body composition", comment: "AI suggestion for profile page"),
                String(localized: "How does my age affect training?", comment: "AI suggestion for profile page"),
                String(localized: "Recommend training based on my profile", comment: "AI suggestion for profile page"),
                String(localized: "What's my ideal training volume?", comment: "AI suggestion for profile page")
            ]
        case .workoutDetail:
            return [
                String(localized: "How was my performance?", comment: "AI suggestion for workout detail"),
                String(localized: "Analyze my heart rate", comment: "AI suggestion for workout detail"),
                String(localized: "What was my best pace?", comment: "AI suggestion for workout detail"),
                String(localized: "Give me improvement tips", comment: "AI suggestion for workout detail")
            ]
        }
    }

    /// Get the page-specific title for the AI assistant
    func getContextTitle() -> String {
        switch currentPage {
        case .workouts:
            return String(localized: "Training Coach", comment: "AI context title for workouts")
        case .statistics:
            return String(localized: "Performance Analyst", comment: "AI context title for statistics")
        case .plan:
            return String(localized: "Workout Planner", comment: "AI context title for plan")
        case .recovery:
            return String(localized: "Recovery Coach", comment: "AI context title for recovery")
        case .profile:
            return String(localized: "Health Advisor", comment: "AI context title for profile")
        case .workoutDetail:
            return String(localized: "Workout Analyst", comment: "AI context title for workout detail")
        }
    }

    /// Check if we have enough data for AI
    var hasData: Bool {
        !recentWorkouts.isEmpty || recoveryMetrics != nil || healthProfile != nil
    }

    var hasWorkoutMetrics: Bool {
        recentWorkouts.allSatisfy { workoutsMetrics[$0.id] != nil }
    }

    var isLoading: Bool {
        isLoadingWorkouts || isLoadingRecovery || isLoadingProfile
    }
}
