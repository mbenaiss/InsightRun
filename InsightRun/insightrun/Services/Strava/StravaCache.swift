//
//  StravaCache.swift
//  InsightRun
//
//  Local cache for Strava activities using SwiftData
//  Prevents downloading the same activity twice - CRITICAL for scaling
//

import Foundation
import SwiftData

// MARK: - SwiftData Model

@Model
final class CachedStravaActivity {
    @Attribute(.unique) var id: Int64
    var name: String
    var distance: Double
    var movingTime: Int
    var elapsedTime: Int
    var totalElevationGain: Double
    var type: String
    var startDate: Date
    var startDateLocal: String
    var averageSpeed: Double?
    var maxSpeed: Double?
    var averageHeartrate: Double?
    var maxHeartrate: Double?
    var calories: Double?
    var trainer: Bool?

    // Metadata
    var cachedAt: Date
    var lastSyncedAt: Date?

    init(from activity: StravaActivity) {
        self.id = activity.id
        self.name = activity.name
        self.distance = activity.distance
        self.movingTime = activity.movingTime
        self.elapsedTime = activity.elapsedTime
        self.totalElevationGain = activity.totalElevationGain
        self.type = activity.type
        self.startDate = activity.startDateParsed ?? Date()
        self.startDateLocal = activity.startDateLocal
        self.averageSpeed = activity.averageSpeed
        self.maxSpeed = activity.maxSpeed
        self.averageHeartrate = activity.averageHeartrate
        self.maxHeartrate = activity.maxHeartrate
        self.calories = activity.calories
        self.trainer = activity.trainer
        self.cachedAt = Date()
        self.lastSyncedAt = nil
    }

    // Convert back to StravaActivity
    func toStravaActivity() -> StravaActivity {
        return StravaActivity(
            id: id,
            name: name,
            distance: distance,
            movingTime: movingTime,
            elapsedTime: elapsedTime,
            totalElevationGain: totalElevationGain,
            type: type,
            startDate: ISO8601DateFormatter().string(from: startDate),
            startDateLocal: startDateLocal,
            averageSpeed: averageSpeed,
            maxSpeed: maxSpeed,
            averageHeartrate: averageHeartrate,
            maxHeartrate: maxHeartrate,
            calories: calories,
            trainer: trainer
        )
    }
}

// MARK: - Cache Manager

@MainActor
class StravaCache {
    static let shared = StravaCache()

    private var modelContext: ModelContext?

    private init() {
        // Context will be injected via setModelContext() from ContentView
        print("⚠️ StravaCache: Initialized without context (will be set from environment)")
    }

    // Set the shared ModelContext from the app's unified container
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        print("✅ StravaCache: Using shared ModelContext from unified container")
    }

    // Helper to get context (throws if not initialized)
    private func getContext() throws -> ModelContext {
        guard let context = modelContext else {
            throw NSError(domain: "StravaCache", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "ModelContext not initialized. Call setModelContext() first."
            ])
        }
        return context
    }

    // MARK: - Save Activities

    /// Save activities to cache (upsert - update if exists, insert if new)
    func saveActivities(_ activities: [StravaActivity]) throws {
        let context = try getContext()

        for activity in activities {
            // Check if activity already exists
            let descriptor = FetchDescriptor<CachedStravaActivity>(
                predicate: #Predicate { $0.id == activity.id }
            )

            let existing = try context.fetch(descriptor).first

            if let existing = existing {
                // Update ALL fields (not just some) to capture renames, metric corrections, etc.
                existing.name = activity.name
                existing.distance = activity.distance
                existing.movingTime = activity.movingTime
                existing.elapsedTime = activity.elapsedTime
                existing.totalElevationGain = activity.totalElevationGain
                existing.type = activity.type
                existing.startDate = activity.startDateParsed ?? existing.startDate
                existing.startDateLocal = activity.startDateLocal
                existing.averageSpeed = activity.averageSpeed
                existing.maxSpeed = activity.maxSpeed
                existing.averageHeartrate = activity.averageHeartrate
                existing.maxHeartrate = activity.maxHeartrate
                existing.calories = activity.calories
                existing.lastSyncedAt = Date()

                print("🔄 Updated cached activity: \(activity.name)")
            } else {
                // Insert new
                let cachedActivity = CachedStravaActivity(from: activity)
                context.insert(cachedActivity)

                print("💾 Cached new activity: \(activity.name)")
            }
        }

        try context.save()
    }

    // MARK: - Fetch from Cache

    /// Fetch all cached activities (sorted by date)
    func fetchAllActivities() throws -> [StravaActivity] {
        let context = try getContext()
        let descriptor = FetchDescriptor<CachedStravaActivity>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )

        let cachedActivities = try context.fetch(descriptor)
        return cachedActivities.map { $0.toStravaActivity() }
    }

    /// Fetch activities with pagination (for infinite scroll from cache)
    func fetchActivities(limit: Int, offset: Int) throws -> [StravaActivity] {
        let context = try getContext()
        var descriptor = FetchDescriptor<CachedStravaActivity>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        descriptor.fetchOffset = offset

        let cachedActivities = try context.fetch(descriptor)
        return cachedActivities.map { $0.toStravaActivity() }
    }

    /// Get last synced activity date (for incremental sync)
    func getLastActivityDate() throws -> Date? {
        let context = try getContext()
        let descriptor = FetchDescriptor<CachedStravaActivity>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )

        let lastActivity = try context.fetch(descriptor).first
        return lastActivity?.startDate
    }

    /// Check if activity exists in cache
    func hasActivity(id: Int64) throws -> Bool {
        let context = try getContext()
        let descriptor = FetchDescriptor<CachedStravaActivity>(
            predicate: #Predicate { $0.id == id }
        )

        return try !context.fetch(descriptor).isEmpty
    }

    /// Get total count of cached activities
    func getActivityCount() throws -> Int {
        let context = try getContext()
        let descriptor = FetchDescriptor<CachedStravaActivity>()
        return try context.fetchCount(descriptor)
    }

    // MARK: - Delete

    /// Delete specific activity
    func deleteActivity(id: Int64) throws {
        let context = try getContext()
        let descriptor = FetchDescriptor<CachedStravaActivity>(
            predicate: #Predicate { $0.id == id }
        )

        if let activity = try context.fetch(descriptor).first {
            context.delete(activity)
            try context.save()
            print("🗑️  Deleted cached activity: \(id)")
        }
    }

    /// Clear all cache (use with caution)
    func clearAll() throws {
        let context = try getContext()
        try context.delete(model: CachedStravaActivity.self)
        try context.save()
        print("🗑️  Cleared all cached activities")
    }

    // MARK: - Statistics

    func getCacheStats() throws -> CacheStats {
        let count = try getActivityCount()
        let lastActivity = try getLastActivityDate()
        let oldestActivity = try getOldestActivityDate()

        return CacheStats(
            totalActivities: count,
            lastActivityDate: lastActivity,
            oldestActivityDate: oldestActivity,
            cacheSize: getCacheSizeInMB()
        )
    }

    private func getOldestActivityDate() throws -> Date? {
        let context = try getContext()
        let descriptor = FetchDescriptor<CachedStravaActivity>(
            sortBy: [SortDescriptor(\.startDate, order: .forward)]
        )

        let oldestActivity = try context.fetch(descriptor).first
        return oldestActivity?.startDate
    }

    private func getCacheSizeInMB() -> Double {
        // Estimate cache size based on activity count
        // Average activity ~2KB, so 1000 activities ≈ 2MB
        do {
            let count = try getActivityCount()
            return Double(count) * 0.002 // ~2KB per activity
        } catch {
            return 0
        }
    }
}

struct CacheStats {
    let totalActivities: Int
    let lastActivityDate: Date?
    let oldestActivityDate: Date?
    let cacheSize: Double // in MB

    var formattedSize: String {
        return String(format: "%.1f MB", cacheSize)
    }

    var dateRange: String? {
        guard let oldest = oldestActivityDate, let latest = lastActivityDate else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale(identifier: "fr_FR")

        return "\(formatter.string(from: oldest)) → \(formatter.string(from: latest))"
    }
}
