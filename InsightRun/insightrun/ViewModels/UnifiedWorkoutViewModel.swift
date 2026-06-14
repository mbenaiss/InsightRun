//
//  UnifiedWorkoutViewModel.swift
//  InsightRun
//
//  ViewModel that merges workouts from HealthKit and Strava
//  Strategy:
//  1. Load workouts from HealthKit (source of truth on iOS)
//  2. Load activities from Strava
//  3. Detect duplicates (same workout in both sources)
//  4. Merge duplicates to create enhanced workouts
//  5. Present unified list sorted by date
//

import SwiftUI
import Combine

@MainActor
class UnifiedWorkoutViewModel: ObservableObject {
    @Published var unifiedWorkouts: [UnifiedWorkout] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var syncStatus: SyncStatus = .idle

    // Stats
    @Published var totalWorkouts: Int = 0
    @Published var healthKitOnly: Int = 0
    @Published var stravaOnly: Int = 0
    @Published var mergedCount: Int = 0

    private let healthKitManager = HealthKitManager.shared
    private let stravaViewModel = StravaViewModel()
    private let stravaAuthService = StravaAuthService.shared
    private let unifiedCache = UnifiedWorkoutCache.shared
    private let suuntoService = SuuntoImportService.shared

    enum SyncStatus {
        case idle
        case loadingHealthKit
        case loadingStrava
        case merging
        case completed
    }

    // MARK: - Public Methods

    /// Load and merge workouts from both sources
    /// Strategy: Load from cache first (instant), then sync in background
    func loadUnifiedWorkouts() async {
        // In demo mode, never overwrite the curated MockData seeded by
        // WorkoutListViewModel — fetching from HealthKit/Strava in the
        // simulator would either return [] (silent fallback) or real data
        // that breaks the controlled screenshots / app preview.
        if DemoMode.isEnabled {
            isLoading = false
            syncStatus = .completed
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            // STEP 1: Try to load from cache first (INSTANT)
            print("💾 Loading from cache...")
            if let cachedWorkouts = try? unifiedCache.fetchAllWorkouts(), !cachedWorkouts.isEmpty {
                // Filter cache based on auth status
                let filteredWorkouts: [UnifiedWorkout]
                if stravaAuthService.isAuthenticated {
                    // Show all workouts when authenticated
                    filteredWorkouts = cachedWorkouts
                    print("✅ Strava authenticated - showing all \(cachedWorkouts.count) cached workouts")
                } else {
                    // Only show HealthKit workouts when not authenticated
                    filteredWorkouts = cachedWorkouts.filter { $0.source == .healthKit }
                    print("⚠️ Strava not authenticated - filtering to \(filteredWorkouts.count) HealthKit workouts (was \(cachedWorkouts.count))")
                }

                if !filteredWorkouts.isEmpty {
                    unifiedWorkouts = filteredWorkouts
                    updateStats()
                    print("⚡ Loaded \(filteredWorkouts.count) workouts from cache (instant)")

                    // Display cached data immediately
                    isLoading = false
                    syncStatus = .completed

                    // Then sync in background (non-blocking)
                    Task {
                        await syncWorkoutsInBackground()
                    }
                    return
                }

                print("📭 Cache filtered to 0 workouts, loading from sources...")
            }

            print("📭 No cache found, loading from sources...")

            // STEP 2: Load HealthKit workouts (non-fatal - continue if fails)
            syncStatus = .loadingHealthKit
            print("📱 Loading HealthKit workouts...")
            var healthKitWorkouts: [WorkoutModel] = []
            var healthKitFailed = false
            do {
                healthKitWorkouts = try await loadHealthKitWorkouts()
                print("✅ Loaded \(healthKitWorkouts.count) HealthKit workouts")
            } catch {
                healthKitFailed = true
                print("⚠️ HealthKit loading failed (continuing with Strava only): \(error.localizedDescription)")
            }

            // STEP 3: Load Strava activities (if authenticated)
            syncStatus = .loadingStrava
            var stravaActivities: [StravaActivity] = []

            if stravaAuthService.isAuthenticated {
                print("🏃 Loading Strava activities...")
                stravaActivities = try await loadStravaActivities()
                print("✅ Loaded \(stravaActivities.count) Strava activities")
            } else {
                print("⚠️ Not authenticated with Strava, skipping")
            }

            // STEP 4: Merge and deduplicate
            syncStatus = .merging
            print("🔄 Merging workouts...")
            let merged = mergeWorkouts(healthKit: healthKitWorkouts, strava: stravaActivities)
            let sortedMerged = merged.sorted { $0.startDate > $1.startDate }

            // Never wipe the UI/cache on a transient HealthKit failure: if the
            // only source failed and produced nothing, keep whatever we have.
            if healthKitFailed, sortedMerged.isEmpty {
                print("⚠️ HealthKit failed and no workouts available — not overwriting cache/UI")
                syncStatus = .completed
                isLoading = false
                return
            }

            // STEP 5: Update UI
            unifiedWorkouts = sortedMerged
            updateStats()
            syncStatus = .completed

            // STEP 6: Save to cache for next launch
            try? unifiedCache.saveWorkouts(unifiedWorkouts)
            print("💾 Saved \(unifiedWorkouts.count) workouts to cache")

            print("""
            ✅ Merge complete:
               - Total: \(totalWorkouts)
               - HealthKit only: \(healthKitOnly)
               - Strava only: \(stravaOnly)
               - Merged: \(mergedCount)
            """)

            // DEBUG: Print source for each workout
            print("\n📊 DEBUG - Workout sources:")
            for workout in unifiedWorkouts.prefix(20) {
                let sourceEmoji: String
                let sourceText: String
                switch workout.source {
                case .healthKit:
                    sourceEmoji = "📱"
                    sourceText = "HealthKit"
                case .strava:
                    sourceEmoji = "🏃"
                    sourceText = "Strava"
                case .suunto:
                    sourceEmoji = "⌚"
                    sourceText = "Suunto"
                case .merged:
                    sourceEmoji = "🔗"
                    sourceText = "Merged"
                }

                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
                let dateStr = dateFormatter.string(from: workout.startDate)

                let distance = workout.distance.map { String(format: "%.1f km", $0 / 1000) } ?? "N/A"

                print("\(sourceEmoji) [\(sourceText)] \(dateStr) - \(distance) - \(workout.name)")
            }
            if unifiedWorkouts.count > 20 {
                print("... (\(unifiedWorkouts.count - 20) more workouts)")
            }
            print("")

        } catch {
            errorMessage = String(localized: "Failed to load workouts: \(error.localizedDescription)")
            print("❌ Error loading workouts: \(error)")
        }

        isLoading = false
    }

    /// Refresh unified workouts
    func refresh() async {
        await loadUnifiedWorkouts()
    }

    /// Sync workouts in background after displaying cache
    /// This ensures cache is always up-to-date without blocking UI
    private func syncWorkoutsInBackground() async {
        print("🔄 Background sync started...")

        // Load fresh data from sources (non-fatal for HealthKit)
        var healthKitWorkouts: [WorkoutModel] = []
        var healthKitFailed = false
        do {
            healthKitWorkouts = try await loadHealthKitWorkouts()
        } catch {
            healthKitFailed = true
            print("⚠️ Background HealthKit sync failed: \(error.localizedDescription)")
        }

        var stravaActivities: [StravaActivity] = []
        if stravaAuthService.isAuthenticated {
            do {
                stravaActivities = try await loadStravaActivities()
            } catch {
                print("⚠️ Background Strava sync failed: \(error.localizedDescription)")
            }
        }

        // Merge
        let merged = mergeWorkouts(healthKit: healthKitWorkouts, strava: stravaActivities)
        let sortedMerged = merged.sorted { $0.startDate > $1.startDate }

        // Guard against a transient source failure (e.g. locked phone) producing
        // an empty or shrunk result: never overwrite the displayed list or the
        // cache when HealthKit errored and the fresh result is empty/smaller.
        if healthKitFailed, sortedMerged.count < unifiedWorkouts.count {
            print("⚠️ Background sync aborted: HealthKit failed, keeping \(unifiedWorkouts.count) cached workouts")
            return
        }

        // Check if the content changed (not only the count): a renamed run or a
        // simultaneous add+remove keeps the count identical.
        if hasContentChanged(from: unifiedWorkouts, to: sortedMerged) {
            // Update UI
            unifiedWorkouts = sortedMerged
            updateStats()

            // Update cache
            try? unifiedCache.saveWorkouts(unifiedWorkouts)
            print("✅ Background sync complete: \(unifiedWorkouts.count) workouts (updated)")
        } else {
            // Just update cache timestamps
            try? unifiedCache.saveWorkouts(sortedMerged)
            print("✅ Background sync complete: no changes")
        }
    }

    /// Content-level comparison used by the background sync. Detects added,
    /// removed and mutated workouts — not only a difference in count.
    private func hasContentChanged(from old: [UnifiedWorkout], to new: [UnifiedWorkout]) -> Bool {
        guard old.count == new.count else { return true }

        func signature(_ workout: UnifiedWorkout) -> String {
            [
                workout.id,
                workout.name,
                String(workout.duration),
                String(workout.distance ?? -1),
                workout.source.rawValue
            ].joined(separator: "|")
        }

        let oldSignatures = Set(old.map(signature))
        let newSignatures = Set(new.map(signature))
        return oldSignatures != newSignatures
    }

    // MARK: - Private Methods

    private func loadHealthKitWorkouts() async throws -> [WorkoutModel] {
        // Eager load: fetch all running workouts so the year filter and full
        // history are available without pagination.
        try await healthKitManager.fetchRunningWorkouts()
    }

    private func loadStravaActivities() async throws -> [StravaActivity] {
        // Load from Strava cache + sync
        await stravaViewModel.loadRecentActivities()
        return stravaViewModel.activities
    }

    /// Core merge logic: Detect duplicates and combine data
    private func mergeWorkouts(
        healthKit: [WorkoutModel],
        strava: [StravaActivity]
    ) -> [UnifiedWorkout] {
        var result: [UnifiedWorkout] = []
        var matchedStravaIDs = Set<Int64>()

        // Load cached Suunto workouts
        let suuntoWorkouts = loadCachedSuuntoWorkouts()

        print("🔍 DEBUG - Starting merge:")
        print("   HealthKit workouts: \(healthKit.count)")
        print("   Strava activities: \(strava.count)")
        print("   Suunto workouts: \(suuntoWorkouts.count)")

        // STEP 1: Process HealthKit workouts and find Strava/Suunto matches
        for hkWorkout in healthKit {
            // Try to find matching Strava activity
            if let matchingStrava = findMatchingStravaActivity(
                for: hkWorkout,
                in: strava,
                excluding: matchedStravaIDs
            ) {
                // Found a match - create merged workout
                let merged = UnifiedWorkout(merging: hkWorkout, with: matchingStrava)
                result.append(merged)
                matchedStravaIDs.insert(matchingStrava.id)

                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "MMM dd HH:mm"
                print("🔗 Merged: \(dateFormatter.string(from: hkWorkout.startDate)) - HK: \(hkWorkout.sourceName) + Strava: \(matchingStrava.name)")
            } else if let matchingSuunto = findMatchingSuuntoWorkout(for: hkWorkout, in: suuntoWorkouts) {
                // Found Suunto match - create merged workout with Suunto data
                let merged = UnifiedWorkout(merging: hkWorkout, with: matchingSuunto)
                result.append(merged)

                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "MMM dd HH:mm"
                print("⌚ Merged with Suunto: \(dateFormatter.string(from: hkWorkout.startDate)) - \(matchingSuunto.activityType)")
            } else {
                // No match - HealthKit only
                let healthKitOnly = UnifiedWorkout(from: hkWorkout)
                result.append(healthKitOnly)
            }
        }

        // STEP 2: Add unmatched Strava activities
        for stravaActivity in strava {
            if !matchedStravaIDs.contains(stravaActivity.id) {
                let stravaOnly = UnifiedWorkout(from: stravaActivity)
                result.append(stravaOnly)

                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "MMM dd HH:mm"
                let dateStr = stravaActivity.startDateParsed.map { dateFormatter.string(from: $0) } ?? "Unknown"
                print("🏃 Strava only: \(dateStr) - \(stravaActivity.name)")
            }
        }

        // STEP 3: Add unmatched Suunto workouts (imported FIT files without HealthKit match)
        // Check against ALL workouts in result (not just merged/suunto) to avoid duplicates
        // when a Suunto workout was saved to HealthKit
        for suunto in suuntoWorkouts {
            let isMatched = result.contains { workout in
                let timeDiff = abs(workout.startDate.timeIntervalSince(suunto.startDate))
                guard timeDiff < 5 * 60 else { return false }
                if let dist = workout.distance, dist > 0, suunto.distance > 0 {
                    let distanceDiff = abs(dist - suunto.distance) / max(dist, suunto.distance)
                    return distanceDiff < 0.05
                }
                let durationDiff = abs(workout.duration - suunto.duration) / max(workout.duration, suunto.duration)
                return durationDiff < 0.05
            }

            if !isMatched {
                let suuntoOnly = UnifiedWorkout(from: suunto)
                result.append(suuntoOnly)

                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "MMM dd HH:mm"
                print("⌚ Suunto only (imported): \(dateFormatter.string(from: suunto.startDate)) - \(suunto.activityType)")
            }
        }

        print("✅ Merge result: \(result.count) unified workouts (\(matchedStravaIDs.count) merged)")

        return result
    }

    /// Find a Suunto workout that matches the HealthKit workout
    private func findMatchingSuuntoWorkout(
        for healthKitWorkout: WorkoutModel,
        in suuntoWorkouts: [SuuntoActivity]
    ) -> SuuntoActivity? {
        let tolerance: TimeInterval = 5 * 60 // 5 minutes

        for suunto in suuntoWorkouts {
            let timeDiff = abs(healthKitWorkout.startDate.timeIntervalSince(suunto.startDate))
            guard timeDiff < tolerance else { continue }

            // Prefer distance similarity (stable across sources); fall back to
            // duration only when distance is unavailable.
            if let dist = healthKitWorkout.distance, dist > 0, suunto.distance > 0 {
                let distanceDiff = abs(dist - suunto.distance) / max(dist, suunto.distance)
                if distanceDiff < 0.05 { return suunto }
            } else {
                let durationDiff = abs(healthKitWorkout.duration - suunto.duration) / max(healthKitWorkout.duration, suunto.duration)
                if durationDiff < 0.05 { return suunto }
            }
        }
        return nil
    }

    /// Load cached Suunto workouts
    private func loadCachedSuuntoWorkouts() -> [SuuntoActivity] {
        do {
            let cached = try suuntoService.fetchAllCachedWorkouts()
            let activities = cached.map { SuuntoActivity(from: $0) }
            print("⌚ Suunto cache: \(activities.count) workouts loaded")
            for activity in activities {
                print("   - \(activity.startDate): \(activity.activityType) - \(activity.distance)m")
            }
            return activities
        } catch {
            print("⚠️ Could not load Suunto cache: \(error.localizedDescription)")
            return []
        }
    }

    /// Find a Strava activity that matches the HealthKit workout
    private func findMatchingStravaActivity(
        for healthKitWorkout: WorkoutModel,
        in stravaActivities: [StravaActivity],
        excluding excludedIDs: Set<Int64>
    ) -> StravaActivity? {
        // Create a temporary UnifiedWorkout for comparison
        let hkUnified = UnifiedWorkout(from: healthKitWorkout)

        // Search for matching Strava activity
        for stravaActivity in stravaActivities {
            // Skip already matched
            if excludedIDs.contains(stravaActivity.id) {
                continue
            }

            let stravaUnified = UnifiedWorkout(from: stravaActivity)

            // Check if duplicate
            if hkUnified.isDuplicateOf(stravaUnified) {
                return stravaActivity
            }
        }

        return nil
    }

    /// Update statistics
    private func updateStats() {
        totalWorkouts = unifiedWorkouts.count
        healthKitOnly = unifiedWorkouts.filter { $0.source == .healthKit }.count
        stravaOnly = unifiedWorkouts.filter { $0.source == .strava }.count
        mergedCount = unifiedWorkouts.filter { $0.source == .merged }.count
    }

    // MARK: - Computed Properties

    var groupedWorkouts: [(String, [UnifiedWorkout])] {
        let grouped = Dictionary(grouping: unifiedWorkouts) { workout -> String in
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            formatter.locale = Locale.current
            return formatter.string(from: workout.startDate).capitalized
        }

        return grouped.sorted { first, second in
            guard let date1 = first.value.first?.startDate,
                  let date2 = second.value.first?.startDate else {
                return false
            }
            return date1 > date2
        }
    }

    var totalDistance: Double {
        unifiedWorkouts.compactMap { $0.distance }.reduce(0, +)
    }

    var totalDistanceKm: Double {
        totalDistance / 1000.0
    }

    var totalDuration: TimeInterval {
        unifiedWorkouts.map { $0.duration }.reduce(0, +)
    }

    var totalCalories: Double {
        unifiedWorkouts.compactMap { $0.totalEnergyBurned }.reduce(0, +)
    }

    /// Canonical average pace (min/km): sum(durations) / sum(distances).
    var averagePace: Double? {
        var totalDurationSeconds = 0.0
        var totalDistanceMeters = 0.0
        for workout in unifiedWorkouts {
            guard let distance = workout.distance, distance > 0, workout.duration > 0 else { continue }
            totalDurationSeconds += workout.duration
            totalDistanceMeters += distance
        }
        guard totalDistanceMeters > 0, totalDurationSeconds > 0 else { return nil }
        return (totalDurationSeconds / 60.0) / (totalDistanceMeters / 1000.0)
    }

    var averageDistance: Double {
        guard !unifiedWorkouts.isEmpty else { return 0 }
        return totalDistance / Double(unifiedWorkouts.count)
    }

    var averageHeartRate: Double? {
        let hrs = unifiedWorkouts.compactMap { $0.averageHeartRate }
        guard !hrs.isEmpty else { return nil }
        return hrs.reduce(0, +) / Double(hrs.count)
    }

    var longestRun: UnifiedWorkout? {
        unifiedWorkouts.max(by: { ($0.distance ?? 0) < ($1.distance ?? 0) })
    }

    var fastestRun: UnifiedWorkout? {
        unifiedWorkouts.min(by: { ($0.averagePace ?? Double.infinity) < ($1.averagePace ?? Double.infinity) })
    }

    /// Workouts with enhanced data (merged from both sources)
    var enhancedWorkouts: [UnifiedWorkout] {
        unifiedWorkouts.filter { $0.isMerged }
    }

    /// Data quality distribution
    var qualityDistribution: [Int: Int] {
        var distribution: [Int: Int] = [:]
        for workout in unifiedWorkouts {
            let bucket = (workout.dataQualityScore / 20) * 20 // 0, 20, 40, 60, 80, 100
            distribution[bucket, default: 0] += 1
        }
        return distribution
    }

    // MARK: - Formatting Helpers

    func formatDistance(_ distance: Double) -> String {
        Formatters.distance(km: distance / 1000.0, fractionDigits: 1)
    }

    func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60

        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        } else {
            return String(format: "%dm", minutes)
        }
    }

    func formatPace(_ pace: Double?) -> String {
        guard let pace = pace else { return String(localized: "common.value.notAvailable") }
        return Formatters.paceFromMinutesPerKm(pace)
    }

    func formatHeartRate(_ hr: Double?) -> String {
        guard let hr = hr else { return String(localized: "common.value.notAvailable") }
        return Formatters.heartRate(hr)
    }
}

// MARK: - Merge Statistics

extension UnifiedWorkoutViewModel {
    struct MergeStats {
        let totalWorkouts: Int
        let healthKitOnly: Int
        let stravaOnly: Int
        let merged: Int
        let mergeRate: Double

        var mergeRatePercentage: Int {
            Int(mergeRate * 100)
        }

        var description: String {
            """
            Total: \(totalWorkouts) workouts
            - HealthKit only: \(healthKitOnly)
            - Strava only: \(stravaOnly)
            - Merged: \(merged) (\(mergeRatePercentage)%)
            """
        }
    }

    var mergeStatistics: MergeStats {
        let total = totalWorkouts
        let rate = total > 0 ? Double(mergedCount) / Double(total) : 0

        return MergeStats(
            totalWorkouts: total,
            healthKitOnly: healthKitOnly,
            stravaOnly: stravaOnly,
            merged: mergedCount,
            mergeRate: rate
        )
    }
}
