//
//  WorkoutListViewModel.swift
//  InsightRun
//
//  ViewModel for the workout list screen
//

import SwiftUI
import Combine
import HealthKit

@MainActor
class WorkoutListViewModel: ObservableObject {
    @Published var workouts: [WorkoutModel] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var authorizationStatus: AuthStatus = .notDetermined

    // Pagination state
    @Published var hasMoreWorkouts = false
    @Published var isLoadingMore = false

    private let healthKitManager = HealthKitManager.shared
    private let pageSize = 100 // Similar to Strava's per_page=200, but conservative for HealthKit

    enum AuthStatus {
        case notDetermined
        case denied
        case authorized
    }

    init() {
        // Check data access on initialization
        Task {
            await checkAuthorizationStatus()
        }
    }

    // MARK: - Actions

    func requestAuthorization() async {
        isLoading = true
        errorMessage = nil

        do {
            try await healthKitManager.requestAuthorization()
            // After requesting authorization, check if we actually have access
            await checkAuthorizationStatus()
            if authorizationStatus == .authorized {
                await loadWorkouts()
            }
        } catch {
            errorMessage = "Erreur lors de la demande d'autorisation: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// Check authorization by attempting to access data
    private func checkAuthorizationStatus() async {
        let hasAccess = await healthKitManager.checkDataAccess()
        authorizationStatus = hasAccess ? .authorized : .notDetermined
    }

    /// Load first page of workouts (Lazy Loading - only recent workouts)
    /// This is called on app launch and loads only the first 100 workouts
    func loadWorkouts() async {
        guard authorizationStatus == .authorized else {
            return
        }

        isLoading = true
        errorMessage = nil

        // Check if this is the first workout sync
        let isFirstSync = !UserDefaults.standard.bool(forKey: "hasCompletedFirstWorkoutSync")

        do {
            // LAZY LOADING: Only fetch first page (100 workouts)
            // This is much faster than loading ALL workouts (which could be 1000+)
            let result = try await healthKitManager.fetchRunningWorkouts(limit: pageSize)
            workouts = result.workouts
            hasMoreWorkouts = result.hasMore

            // Update widget data
            WidgetDataProvider.shared.updateWeeklyStats(workouts: workouts)
            if let latestWorkout = workouts.first {
                WidgetDataProvider.shared.updateLastWorkout(from: latestWorkout)
            }

            if workouts.isEmpty {
                errorMessage = "Aucun workout de course trouvé."
            } else if isFirstSync {
                // Track first workout sync only once
                AnalyticsService.shared.trackFirstWorkoutSynced(
                    workoutsCount: workouts.count,
                    syncSuccess: true
                )
                UserDefaults.standard.set(true, forKey: "hasCompletedFirstWorkoutSync")

                print("✅ Lazy Loading: Loaded \(workouts.count) workouts (hasMore: \(hasMoreWorkouts))")
            }
        } catch {
            errorMessage = "Impossible de charger les workouts: \(error.localizedDescription)"

            // Track first sync failure if it's the first time
            if isFirstSync {
                AnalyticsService.shared.trackFirstWorkoutSynced(
                    workoutsCount: 0,
                    syncSuccess: false
                )
            }
        }

        isLoading = false
    }

    /// Load next page of workouts (Infinite Scroll)
    /// This is called when the user scrolls to the bottom of the list
    func loadMoreWorkouts() async {
        // Don't load more if already loading or no more workouts
        guard !isLoadingMore && hasMoreWorkouts else {
            return
        }

        isLoadingMore = true

        do {
            // Get the oldest workout's start date as anchor for pagination
            guard let oldestWorkout = workouts.last else {
                isLoadingMore = false
                return
            }

            // Fetch next page starting before the oldest workout
            let result = try await healthKitManager.fetchRunningWorkouts(
                limit: pageSize,
                startingBefore: oldestWorkout.startDate
            )

            // Append new workouts
            workouts.append(contentsOf: result.workouts)
            hasMoreWorkouts = result.hasMore

            print("📄 Loaded page: +\(result.workouts.count) workouts (total: \(workouts.count), hasMore: \(hasMoreWorkouts))")
        } catch {
            errorMessage = "Impossible de charger plus de workouts: \(error.localizedDescription)"
        }

        isLoadingMore = false
    }

    func refresh() async {
        await loadWorkouts()
    }

    func refreshAuthorizationStatus() {
        Task {
            await checkAuthorizationStatus()
            if authorizationStatus == .authorized {
                await loadWorkouts()
            }
        }
    }

    // MARK: - Computed Properties

    var groupedWorkouts: [(String, [WorkoutModel])] {
        let grouped = Dictionary(grouping: workouts) { workout -> String in
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            formatter.locale = Locale(identifier: "fr_FR")
            return formatter.string(from: workout.startDate).capitalized
        }
        return grouped.sorted { $0.value.first!.startDate > $1.value.first!.startDate }
    }

    var totalDistance: Double {
        workouts.compactMap { $0.distance }.reduce(0, +)
    }

    var totalDuration: TimeInterval {
        workouts.map { $0.duration }.reduce(0, +)
    }

    var totalCalories: Double {
        workouts.compactMap { $0.totalEnergyBurned }.reduce(0, +)
    }

    var workoutCount: Int {
        workouts.count
    }

    var averagePace: Double? {
        let paces = workouts.compactMap { $0.averagePace }
        guard !paces.isEmpty else { return nil }
        return paces.reduce(0, +) / Double(paces.count)
    }

    var averageDistance: Double {
        guard !workouts.isEmpty else { return 0 }
        return totalDistance / Double(workouts.count)
    }

    var averageDuration: TimeInterval {
        guard !workouts.isEmpty else { return 0 }
        return totalDuration / Double(workouts.count)
    }

    var averageSpeed: Double? {
        let speeds = workouts.compactMap { $0.averageSpeed }
        guard !speeds.isEmpty else { return nil }
        return speeds.reduce(0, +) / Double(speeds.count)
    }

    var longestRun: WorkoutModel? {
        workouts.max(by: { ($0.distance ?? 0) < ($1.distance ?? 0) })
    }

    var fastestRun: WorkoutModel? {
        workouts.min(by: { ($0.averagePace ?? Double.infinity) < ($1.averagePace ?? Double.infinity) })
    }

    // Stats for a specific group of workouts
    func stats(for workouts: [WorkoutModel]) -> GroupStats {
        let distance = workouts.compactMap { $0.distance }.reduce(0, +)
        let duration = workouts.map { $0.duration }.reduce(0, +)
        let calories = workouts.compactMap { $0.totalEnergyBurned }.reduce(0, +)
        let paces = workouts.compactMap { $0.averagePace }
        let avgPace = !paces.isEmpty ? paces.reduce(0, +) / Double(paces.count) : nil

        return GroupStats(
            count: workouts.count,
            totalDistance: distance,
            totalDuration: duration,
            totalCalories: calories,
            averagePace: avgPace
        )
    }

    struct GroupStats {
        let count: Int
        let totalDistance: Double
        let totalDuration: TimeInterval
        let totalCalories: Double
        let averagePace: Double?
    }

    // MARK: - Formatting

    func formatTotalDistance() -> String {
        let km = totalDistance / 1000.0
        return String(format: "%.1f km", km)
    }

    func formatTotalDuration() -> String {
        let hours = Int(totalDuration) / 3600
        let minutes = Int(totalDuration) % 3600 / 60
        return String(format: "%dh %02dmin", hours, minutes)
    }

    func formatAveragePace() -> String {
        guard let pace = averagePace else { return "N/A" }
        let minutes = Int(pace)
        let seconds = Int((pace - Double(minutes)) * 60)
        return String(format: "%d:%02d min/km", minutes, seconds)
    }

    func formatAverageDistance() -> String {
        let km = averageDistance / 1000.0
        return String(format: "%.1f km", km)
    }

    func formatAverageDuration() -> String {
        let minutes = Int(averageDuration) / 60
        return String(format: "%d min", minutes)
    }

    func formatDistance(_ distance: Double) -> String {
        let km = distance / 1000.0
        return String(format: "%.1f km", km)
    }

    func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        if hours > 0 {
            return String(format: "%dh %02dmin", hours, minutes)
        } else {
            return String(format: "%d min", minutes)
        }
    }

    func formatPace(_ pace: Double?) -> String {
        guard let pace = pace else { return "N/A" }
        let minutes = Int(pace)
        let seconds = Int((pace - Double(minutes)) * 60)
        return String(format: "%d:%02d", minutes, seconds)
    }
}
