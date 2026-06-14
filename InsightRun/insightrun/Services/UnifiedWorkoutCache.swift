//
//  UnifiedWorkoutCache.swift
//  InsightRun
//
//  Cache manager for unified workouts
//  Strategy: Keep all workouts, clear only on Strava disconnect
//

import Foundation
import SwiftData

@MainActor
class UnifiedWorkoutCache {
    static let shared = UnifiedWorkoutCache()

    private var modelContext: ModelContext?

    private init() {
        print("⚠️ UnifiedWorkoutCache: Initialized without context (will be set from environment)")
    }

    // Set the shared ModelContext from the app's unified container
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        print("✅ UnifiedWorkoutCache: Using shared ModelContext from unified container")
    }

    // Helper to get context (throws if not initialized)
    private func getContext() throws -> ModelContext {
        guard let context = modelContext else {
            throw NSError(domain: "UnifiedWorkoutCache", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "ModelContext not initialized. Call setModelContext() first."
            ])
        }
        return context
    }

    // MARK: - Save

    /// Save unified workouts to cache (upsert + delete stale entries)
    func saveWorkouts(_ workouts: [UnifiedWorkout]) throws {
        // Guardrail: an empty set almost always means a transient source failure
        // (locked phone, HealthKit error), not a genuine "user has no workouts".
        // Treat it as a no-op so the delete-stale pass never wipes the cache.
        // Use clearAll() for an intentional reset.
        guard !workouts.isEmpty else {
            print("⚠️ saveWorkouts called with empty set — skipping to avoid cache wipe")
            return
        }

        let context = try getContext()

        // Get all cached workouts once
        let descriptor = FetchDescriptor<CachedUnifiedWorkout>()
        let allCachedWorkouts = try context.fetch(descriptor)

        // Build set of new workout IDs for quick lookup
        let newWorkoutIDs = Set(workouts.map { $0.id })

        // Delete stale entries (not in new list)
        for cached in allCachedWorkouts {
            if !newWorkoutIDs.contains(cached.id) {
                context.delete(cached)
                print("🗑️ Deleted stale cached workout: \(cached.name)")
            }
        }

        // Upsert workouts
        for workout in workouts {
            let existing = allCachedWorkouts.first { $0.id == workout.id }

            if let existing = existing {
                // Update existing (in case data changed)
                existing.source = workout.source.rawValue
                existing.startDate = workout.startDate
                existing.endDate = workout.endDate
                existing.duration = workout.duration
                existing.distance = workout.distance
                existing.totalEnergyBurned = workout.totalEnergyBurned
                existing.averageSpeed = workout.averageSpeed
                existing.averagePace = workout.averagePace
                existing.averageHeartRate = workout.averageHeartRate
                existing.maxHeartRate = workout.maxHeartRate
                existing.totalElevationGain = workout.totalElevationGain
                existing.hasRoute = workout.hasRoute
                existing.routePolyline = workout.routePolyline
                existing.name = workout.name
                existing.notes = workout.notes
                existing.cachedAt = Date()
                existing.originalSourceName = workout.sourceName

                print("🔄 Updated cached unified workout: \(workout.name)")
            } else {
                // Insert new
                let cached = CachedUnifiedWorkout(from: workout)
                context.insert(cached)

                print("💾 Cached new unified workout: \(workout.name)")
            }
        }

        try context.save()
        print("✅ Saved \(workouts.count) unified workouts to cache")
    }

    // MARK: - Fetch

    /// Fetch all cached workouts (sorted by date)
    func fetchAllWorkouts() throws -> [UnifiedWorkout] {
        let context = try getContext()
        let descriptor = FetchDescriptor<CachedUnifiedWorkout>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )

        let cached = try context.fetch(descriptor)
        return cached.map { $0.toUnifiedWorkout() }
    }

    /// Get total count of cached workouts
    func getWorkoutCount() throws -> Int {
        let context = try getContext()
        let descriptor = FetchDescriptor<CachedUnifiedWorkout>()
        return try context.fetchCount(descriptor)
    }

    // MARK: - Clear

    /// Clear ALL cached unified workouts (called when user disconnects Strava)
    func clearAll() throws {
        let context = try getContext()
        try context.delete(model: CachedUnifiedWorkout.self)
        try context.save()
        print("🗑️  Cleared all cached unified workouts")
    }

    /// Clear only Strava-related workouts (Strava-only + merged)
    func clearStravaWorkouts() throws {
        let context = try getContext()

        // Fetch all workouts
        let descriptor = FetchDescriptor<CachedUnifiedWorkout>()
        let allWorkouts = try context.fetch(descriptor)

        // Filter Strava-related workouts manually
        let stravaRelated = allWorkouts.filter { workout in
            workout.source == WorkoutSource.strava.rawValue || workout.source == WorkoutSource.merged.rawValue
        }

        // Delete
        for workout in stravaRelated {
            context.delete(workout)
        }

        try context.save()
        print("🗑️  Cleared \(stravaRelated.count) Strava-related cached workouts")
    }

    // MARK: - Statistics

    func getCacheStats() throws -> UnifiedCacheStats {
        let context = try getContext()

        // Fetch all workouts and count by source (manual filtering)
        let allDescriptor = FetchDescriptor<CachedUnifiedWorkout>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let allWorkouts = try context.fetch(allDescriptor)

        let healthKitCount = allWorkouts.filter { $0.source == WorkoutSource.healthKit.rawValue }.count
        let stravaCount = allWorkouts.filter { $0.source == WorkoutSource.strava.rawValue }.count
        let mergedCount = allWorkouts.filter { $0.source == WorkoutSource.merged.rawValue }.count
        let total = allWorkouts.count

        // Get date range
        let lastDate = allWorkouts.first?.startDate
        let firstDate = allWorkouts.last?.startDate

        return UnifiedCacheStats(
            totalWorkouts: total,
            healthKitOnly: healthKitCount,
            stravaOnly: stravaCount,
            merged: mergedCount,
            lastWorkoutDate: lastDate,
            oldestWorkoutDate: firstDate
        )
    }
}

// MARK: - Cache Statistics

struct UnifiedCacheStats {
    let totalWorkouts: Int
    let healthKitOnly: Int
    let stravaOnly: Int
    let merged: Int
    let lastWorkoutDate: Date?
    let oldestWorkoutDate: Date?

    var dateRange: String? {
        guard let oldest = oldestWorkoutDate, let latest = lastWorkoutDate else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale.current

        return "\(formatter.string(from: oldest)) → \(formatter.string(from: latest))"
    }

    var summary: String {
        """
        Total: \(totalWorkouts) workouts
        - HealthKit only: \(healthKitOnly)
        - Strava only: \(stravaOnly)
        - Merged: \(merged)
        Range: \(dateRange ?? "N/A")
        """
    }
}
