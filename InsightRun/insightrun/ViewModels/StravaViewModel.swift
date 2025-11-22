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

    private let apiClient = StravaAPIClient.shared
    private let authService = StravaAuthService.shared

    private var currentPage = 1
    private let initialPageSize = 30 // Fast initial load
    private let backfillPageSize = 200 // For backfill operations

    // MARK: - Initial Load (Lazy Loading - Page 1 only)

    /// Load first page of activities (30 activities - very fast)
    /// This is called on app launch
    func loadRecentActivities() async {
        guard authService.isAuthenticated else {
            errorMessage = "Not authenticated with Strava"
            return
        }

        isLoading = true
        errorMessage = nil
        currentPage = 1

        do {
            print("🏃 Loading recent Strava activities (page 1)...")

            // LAZY LOADING: Only fetch page 1 (30 activities)
            // Much faster than loading ALL history!
            activities = try await apiClient.fetchActivities(page: 1, perPage: initialPageSize)

            // If we got a full page, there's likely more
            hasMoreActivities = activities.count == initialPageSize

            rateLimits = apiClient.currentRateLimits

            print("✅ Loaded \(activities.count) activities")
        } catch {
            errorMessage = "Failed to load activities: \(error.localizedDescription)"
            print("❌ Error: \(error)")
        }

        isLoading = false
    }

    // MARK: - Infinite Scroll (Load More)

    /// Load next page of activities when user scrolls to bottom
    /// This implements the "Scroll Infini" strategy
    func loadMoreActivities() async {
        // Don't load if already loading or no more activities
        guard !isLoadingMore && hasMoreActivities else {
            return
        }

        // Safety: Check rate limits before making request
        guard apiClient.canMakeRequest() else {
            errorMessage = "Rate limit reached. Please wait a few minutes."
            print("⚠️ Rate limit safety check failed")
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

            // Append to existing list
            activities.append(contentsOf: newActivities)

            // Check if there are more pages
            hasMoreActivities = newActivities.count == initialPageSize

            rateLimits = apiClient.currentRateLimits

            print("✅ Loaded \(newActivities.count) more activities (total: \(activities.count))")
        } catch {
            errorMessage = "Failed to load more: \(error.localizedDescription)"
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

        while shouldContinue {
            // Safety: Check rate limits
            guard apiClient.canMakeRequest() else {
                print("⚠️ Backfill paused due to rate limits")
                // Wait 15 minutes before retrying
                try? await Task.sleep(nanoseconds: 15 * 60 * 1_000_000_000)
                continue
            }

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

    var averagePace: Double? {
        let paces = activities.compactMap { $0.averagePace }
        guard !paces.isEmpty else { return nil }
        return paces.reduce(0, +) / Double(paces.count)
    }

    var activityCount: Int {
        activities.count
    }

    // MARK: - Grouping (by month)

    var groupedActivities: [(String, [StravaActivity])] {
        let grouped = Dictionary(grouping: activities) { activity -> String in
            guard let date = activity.startDateParsed else { return "Unknown" }
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            formatter.locale = Locale(identifier: "fr_FR")
            return formatter.string(from: date).capitalized
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
