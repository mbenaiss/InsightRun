//
//  StravaViewModel.swift
//  InsightRun
//
//  ViewModel for Strava activities with Lazy Loading strategy
//  Strategy: Load page 1 (30 activities) on launch, infinite scroll for more
//

import SwiftUI
import Combine

@MainActor
class StravaViewModel: ObservableObject {
    @Published var activities: [StravaActivity] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var hasMoreActivities = true
    @Published var errorMessage: String?
    @Published var rateLimits: StravaRateLimits?
    @Published var cacheStats: CacheStats?

    private let apiClient = StravaAPIClient.shared
    private let authService = StravaAuthService.shared
    private let backendClient = StravaBackendClient.shared
    private let cache = StravaCache.shared

    private var currentPage = 1
    private let initialPageSize = 30 // Fast initial load
    private let backfillPageSize = 200 // For backfill operations

    // MARK: - Initial Load (Lazy Loading with Cache)

    /// Load activities from iOS local cache first, then sync from backend if needed
    /// Strategy: Cache-first for instant loading, sync in background
    func loadRecentActivities() async {
        guard authService.isAuthenticated else {
            errorMessage = String(localized: "Not authenticated with Strava")
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            // STEP 1: Try to load from LOCAL iOS cache first (INSTANT)
            print("💾 Loading Strava activities from LOCAL iOS cache...")
            do {
                let cachedActivities = try cache.fetchAllActivities()

                if !cachedActivities.isEmpty {
                    activities = cachedActivities
                    print("⚡ Loaded \(activities.count) activities from iOS cache (instant)")
                    isLoading = false

                    // STEP 2: Sync from backend in background (non-blocking)
                    Task {
                        await syncFromBackend()
                    }
                    return
                }

                print("📭 No iOS cache found, loading from backend...")
            } catch {
                // Cache failed (e.g., corrupted database) - continue to backend loading
                print("⚠️ iOS cache failed: \(error.localizedDescription), loading from backend...")
            }

            // STEP 3: No cache - load from backend D1
            let userId = UserIdentityService.shared.userID
            let response = try await backendClient.fetchActivities(
                userId: userId,
                limit: 100,
                offset: 0
            )

            // Convert and save to iOS cache (cache save is non-blocking)
            activities = response.activities.map { $0.toStravaActivity() }
            do {
                try cache.saveActivities(activities)
                print("✅ Loaded \(activities.count) activities from backend and cached")
            } catch {
                print("⚠️ Cache save failed (will work without cache): \(error.localizedDescription)")
                print("✅ Loaded \(activities.count) activities from backend (cache unavailable)")
            }
            print("📊 Total Strava activities: \(response.total)")
        } catch {
            errorMessage = String(localized: "Failed to load activities: \(error.localizedDescription)")
            print("❌ Error: \(error)")
        }

        isLoading = false
    }

    /// Sync activities from backend (background, non-blocking)
    private func syncFromBackend() async {
        do {
            print("🔄 Syncing Strava from backend...")

            let userId = UserIdentityService.shared.userID
            let response = try await backendClient.fetchActivities(
                userId: userId,
                limit: 100,
                offset: 0
            )

            let newActivities = response.activities.map { $0.toStravaActivity() }

            // Upsert into the cache rather than replacing the visible list: the
            // backend page is capped at `limit`, so overwriting `activities` would
            // drop older entries when the user has more than `limit` activities.
            // The cache merges by id, then we reload the visible window from it.
            try? cache.saveActivities(newActivities)
            let merged = (try? cache.fetchActivities(limit: 100, offset: 0)) ?? newActivities

            if Self.activitiesDiffer(merged, activities) {
                activities = merged
                print("✅ Background sync: \(activities.count) activities (updated)")
            } else {
                print("✅ Background sync: no changes")
            }
        } catch {
            print("⚠️ Background sync failed: \(error)")
        }
    }

    /// Incremental sync: Only fetch NEW activities since last cached activity
    /// This is THE KEY to scaling - avoids re-downloading old activities
    private func syncNewActivities() async {
        do {
            // Get last activity date from cache
            let lastActivityDate = try cache.getLastActivityDate()

            if let lastDate = lastActivityDate {
                print("🔄 Syncing activities after \(lastDate)...")

                // Fetch only NEW activities (after last cached date)
                let newActivities = try await apiClient.fetchActivitiesSince(
                    after: Int(lastDate.timeIntervalSince1970)
                )

                if !newActivities.isEmpty {
                    print("✨ Found \(newActivities.count) new activities")

                    // Save to cache
                    try cache.saveActivities(newActivities)

                    // Reload from cache to get sorted list
                    activities = try cache.fetchActivities(limit: 100, offset: 0)

                    // Update stats
                    cacheStats = try cache.getCacheStats()
                } else {
                    print("✅ No new activities - cache up to date")
                }
            } else {
                // No cache - do initial sync
                print("🆕 No cache found - doing initial sync...")

                let newActivities = try await apiClient.fetchActivities(page: 1, perPage: initialPageSize)

                // Save to cache
                try cache.saveActivities(newActivities)

                // Reload from cache
                activities = try cache.fetchActivities(limit: 100, offset: 0)

                // If we got a full page, there's likely more
                hasMoreActivities = newActivities.count == initialPageSize

                // Update stats
                cacheStats = try cache.getCacheStats()
            }

            rateLimits = apiClient.currentRateLimits

            print("✅ Synced \(activities.count) activities")
        } catch {
            errorMessage = String(localized: "Failed to sync activities: \(error.localizedDescription)")
            print("❌ Error: \(error)")
        }
    }

    /// True when the two activity lists differ in a way the user should see.
    /// Compares by id plus the fields the backend can change (name, distance,
    /// moving time, start date) — count equality alone misses renames and swaps.
    private static func activitiesDiffer(_ lhs: [StravaActivity], _ rhs: [StravaActivity]) -> Bool {
        guard lhs.count == rhs.count else { return true }
        func fingerprint(_ list: [StravaActivity]) -> [String] {
            list
                .sorted { $0.id < $1.id }
                .map { "\($0.id)|\($0.name)|\($0.distance)|\($0.movingTime)|\($0.startDate)" }
        }
        return fingerprint(lhs) != fingerprint(rhs)
    }

    // MARK: - Infinite Scroll (Load More)

    /// Load next page of activities when user scrolls to bottom
    /// This implements the "Scroll Infini" strategy
    func loadMoreActivities() async {
        // Don't load if already loading or no more activities
        guard !isLoadingMore && hasMoreActivities else {
            return
        }

        isLoadingMore = true
        currentPage += 1

        do {
            print("📄 Loading more activities (page \(currentPage))...")

            let newActivities = try await apiClient.fetchActivities(
                page: currentPage,
                perPage: initialPageSize
            )

            // Dedup: the visible list may have come from cache, so a fresh page can
            // overlap with what's already shown — appending blindly duplicates rows.
            let existingIds = Set(activities.map { $0.id })
            let uniqueNew = newActivities.filter { !existingIds.contains($0.id) }
            activities.append(contentsOf: uniqueNew)

            // Check if there are more pages (based on the raw page size, not the
            // deduped count, so a fully-overlapping page doesn't stop pagination early).
            hasMoreActivities = newActivities.count == initialPageSize

            rateLimits = apiClient.currentRateLimits

            print("✅ Loaded \(uniqueNew.count) new activities (total: \(activities.count))")
        } catch {
            errorMessage = String(localized: "Failed to load more: \(error.localizedDescription)")
            currentPage -= 1 // Reset page on error
            print("❌ Error loading more: \(error)")
        }

        isLoadingMore = false
    }

    // MARK: - Backfill (For Statistics)

    /// Background backfill for global statistics
    /// Uses larger page size (200) to minimize API calls
    /// This should run in the background, NOT on UI load
    func backfillActivities(progressCallback: @escaping (Int, Int) -> Void) async {
        guard authService.isAuthenticated else { return }

        var page = 1
        var totalLoaded = 0
        var shouldContinue = true

        print("🔄 Starting backfill with per_page=200 (optimized for quota)")

        // Rate limiting is enforced server-side; the client just reacts to 429s
        // surfaced as errors below (the old client-side 15-min wait was dead code).
        while shouldContinue {
            do {
                let newActivities = try await apiClient.fetchActivities(
                    page: page,
                    perPage: backfillPageSize
                )

                totalLoaded += newActivities.count
                progressCallback(totalLoaded, newActivities.count)

                // Stop if we got less than a full page
                shouldContinue = newActivities.count == backfillPageSize

                page += 1

                print("📊 Backfill progress: \(totalLoaded) activities loaded")

                // Small delay between requests to be respectful
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            } catch {
                print("❌ Backfill error: \(error)")
                shouldContinue = false
            }
        }

        print("✅ Backfill complete: \(totalLoaded) total activities")
    }

    // MARK: - Refresh

    func refresh() async {
        await loadRecentActivities()
    }

    // MARK: - Filtering

    var runningActivities: [StravaActivity] {
        activities.filter { $0.type == "Run" }
    }

    var cyclingActivities: [StravaActivity] {
        activities.filter { $0.type == "Ride" }
    }

    // MARK: - Statistics (from loaded activities only)

    var totalDistance: Double {
        activities.reduce(0) { $0 + $1.distance }
    }

    var totalDistanceKm: Double {
        totalDistance / 1000.0
    }

    var totalMovingTime: Int {
        activities.reduce(0) { $0 + $1.movingTime }
    }

    /// Canonical average pace = total moving time / total distance (min/km),
    /// not the arithmetic mean of per-activity paces.
    var averagePace: Double? {
        let totalSeconds = activities.reduce(0.0) { $0 + Double($1.movingTime) }
        let totalKm = activities.reduce(0.0) { $0 + $1.distanceKm }
        return Formatters.averagePaceValue(totalDurationSeconds: totalSeconds, totalDistanceKm: totalKm)
            .map { $0 / 60.0 }
    }

    var activityCount: Int {
        activities.count
    }

    // MARK: - Grouping (by month)

    var groupedActivities: [(String, [StravaActivity])] {
        let grouped = Dictionary(grouping: activities) { activity -> String in
            guard let date = activity.startDateParsed else { return "Unknown" }
            return DateFormatter.monthYear.string(from: date).capitalized
        }

        return grouped.sorted { first, second in
            guard let date1 = first.value.first?.startDateParsed,
                  let date2 = second.value.first?.startDateParsed else {
                return false
            }
            return date1 > date2
        }
    }
}
