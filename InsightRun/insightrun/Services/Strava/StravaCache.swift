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
            calories: calories
        )
    }
}

// MARK: - Cache Manager

@MainActor
class StravaCache {
    static let shared = StravaCache()

    private var modelContainer: ModelContainer
    private var modelContext: ModelContext

    private init() {
        let schema = Schema([CachedStravaActivity.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            modelContext = ModelContext(modelContainer)
            print("✅ StravaCache: SwiftData initialized")
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    // MARK: - Save Activities

    /// Save activities to cache (upsert - update if exists, insert if new)
    func saveActivities(_ activities: [StravaActivity]) throws {
        for activity in activities {
            // Check if activity already exists
            let descriptor = FetchDescriptor<CachedStravaActivity>(
                predicate: #Predicate { $0.id == activity.id }
            )

            let existing = try modelContext.fetch(descriptor).first

            if let existing = existing {
                // Update existing
                existing.name = activity.name
                existing.distance = activity.distance
                existing.movingTime = activity.movingTime
                existing.elapsedTime = activity.elapsedTime
                existing.totalElevationGain = activity.totalElevationGain
                existing.type = activity.type
                existing.lastSyncedAt = Date()

                print("🔄 Updated cached activity: \(activity.name)")
            } else {
                // Insert new
                let cachedActivity = CachedStravaActivity(from: activity)
                modelContext.insert(cachedActivity)

                print("💾 Cached new activity: \(activity.name)")
            }
        }

        try modelContext.save()
    }

    // MARK: - Fetch from Cache

    /// Fetch all cached activities (sorted by date)
    func fetchAllActivities() throws -> [StravaActivity] {
        let descriptor = FetchDescriptor<CachedStravaActivity>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )

        let cachedActivities = try modelContext.fetch(descriptor)
        return cachedActivities.map { $0.toStravaActivity() }
    }

    /// Fetch activities with pagination (for infinite scroll from cache)
    func fetchActivities(limit: Int, offset: Int) throws -> [StravaActivity] {
        var descriptor = FetchDescriptor<CachedStravaActivity>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        descriptor.fetchOffset = offset

        let cachedActivities = try modelContext.fetch(descriptor)
        return cachedActivities.map { $0.toStravaActivity() }
    }

    /// Get last synced activity date (for incremental sync)
    func getLastActivityDate() throws -> Date? {
        let descriptor = FetchDescriptor<CachedStravaActivity>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )

        let lastActivity = try modelContext.fetch(descriptor).first
        return lastActivity?.startDate
    }

    /// Check if activity exists in cache
    func hasActivity(id: Int64) throws -> Bool {
        let descriptor = FetchDescriptor<CachedStravaActivity>(
            predicate: #Predicate { $0.id == id }
        )

        return try !modelContext.fetch(descriptor).isEmpty
    }

    /// Get total count of cached activities
    func getActivityCount() throws -> Int {
        let descriptor = FetchDescriptor<CachedStravaActivity>()
        return try modelContext.fetchCount(descriptor)
    }

    // MARK: - Delete

    /// Delete specific activity
    func deleteActivity(id: Int64) throws {
        let descriptor = FetchDescriptor<CachedStravaActivity>(
            predicate: #Predicate { $0.id == id }
        )

        if let activity = try modelContext.fetch(descriptor).first {
            modelContext.delete(activity)
            try modelContext.save()
            print("🗑️  Deleted cached activity: \(id)")
        }
    }

    /// Clear all cache (use with caution)
    func clearAll() throws {
        try modelContext.delete(model: CachedStravaActivity.self)
        try modelContext.save()
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
        let descriptor = FetchDescriptor<CachedStravaActivity>(
            sortBy: [SortDescriptor(\.startDate, order: .forward)]
        )

        let oldestActivity = try modelContext.fetch(descriptor).first
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
