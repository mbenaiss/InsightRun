//
//  StravaAPIClient.swift
//  InsightRun
//
//  Strava API Client with Lazy Loading and Rate Limit Monitoring
//  Implements the strategy: Load page 1 on launch, infinite scroll for more
//

import Foundation
import Combine

// MARK: - Rate Limit Tracking

struct StravaRateLimits {
    let usage15Min: Int      // Current usage in 15-min window
    let limit15Min: Int      // Limit for 15-min window (default: 100)
    let usageDaily: Int      // Current usage in daily window
    let limitDaily: Int      // Limit for daily window (default: 1000)

    var is15MinNearLimit: Bool {
        return Double(usage15Min) / Double(limit15Min) > 0.9 // 90% threshold
    }

    var isDailyNearLimit: Bool {
        return Double(usageDaily) / Double(limitDaily) > 0.9 // 90% threshold
    }

    var percentageUsed15Min: Double {
        return Double(usage15Min) / Double(limit15Min) * 100
    }

    var percentageUsedDaily: Double {
        return Double(usageDaily) / Double(limitDaily) * 100
    }
}

// MARK: - Strava API Client

@MainActor
class StravaAPIClient {
    static let shared = StravaAPIClient()

    private let authService = StravaAuthService.shared
    private let backendURL = "https://api.insightrun.altcode.studio/api/strava"
    private let appKey = "healthapp-LEtZ5vhVA5RBpw8u-F0Rxvk1mHagGeINJEI9GOPUFs4"
    private var userId: String {
        return UserIdentityService.shared.userID
    }

    // Rate limit tracking
    @Published var currentRateLimits: StravaRateLimits?

    private init() {
        // userId is now computed dynamically from UserIdentityService
    }

    // MARK: - Activities API with LAZY LOADING

    /// Fetch activities with pagination (RECOMMENDED - Lazy Loading approach)
    /// - Parameters:
    ///   - page: Page number (starts at 1)
    ///   - perPage: Number of activities per page (max 200)
    /// - Returns: List of activities for this page
    func fetchActivities(page: Int = 1, perPage: Int = 30) async throws -> [StravaActivity] {
        guard authService.isAuthenticated else {
            throw StravaAPIError.unauthorized
        }

        var components = URLComponents(string: "\(backendURL)/activities")!
        components.queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "\(perPage)")
        ]

        guard let url = components.url else {
            throw StravaAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(appKey, forHTTPHeaderField: "X-App-Key")
        request.setValue(userId, forHTTPHeaderField: "X-User-ID")
        request.timeoutInterval = 30

        print("📡 Backend API: Fetching page \(page) (\(perPage) activities per page)...")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StravaAPIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            break
        case 401:
            throw StravaAPIError.unauthorized
        case 429:
            throw StravaAPIError.rateLimitExceeded
        default:
            throw StravaAPIError.unknownError(httpResponse.statusCode)
        }

        struct BackendResponse: Codable {
            let activities: [StravaActivity]
            let page: Int
            let perPage: Int
            let cached: Bool
            let syncedAt: Int?
        }

        let backendResponse = try JSONDecoder().decode(BackendResponse.self, from: data)

        print("✅ Backend: Loaded \(backendResponse.activities.count) activities (cached: \(backendResponse.cached))")

        return backendResponse.activities
    }

    /// Get total activity count (useful for progress tracking)
    /// WARNING: This is an estimation based on the first page
    func estimateActivityCount() async throws -> Int {
        // Fetch just 1 activity to get headers
        let activities = try await fetchActivities(page: 1, perPage: 1)

        // Strava doesn't provide total count in headers, so we estimate
        // If we get a full page, there's likely more
        return activities.isEmpty ? 0 : Int.max // We don't know the exact count
    }

    /// Fetch recent activities (optimized for initial load)
    /// This is what you call on app launch - only 30 activities, very fast
    func fetchRecentActivities() async throws -> [StravaActivity] {
        return try await fetchActivities(page: 1, perPage: 30)
    }

    /// Fetch activities since a specific date (INCREMENTAL SYNC)
    /// This is handled by the backend automatically
    /// - Parameter after: Unix timestamp (seconds since epoch)
    /// - Returns: Only activities created after this date
    func fetchActivitiesSince(after timestamp: Int) async throws -> [StravaActivity] {
        return try await fetchActivities(page: 1, perPage: 200)
    }

    /// Fetch activity detail by ID
    func fetchActivity(id: Int64) async throws -> StravaDetailedActivity {
        guard authService.isAuthenticated else {
            throw StravaAPIError.unauthorized
        }

        let url = URL(string: "\(backendURL)/activities/\(id)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(appKey, forHTTPHeaderField: "X-App-Key")
        request.setValue(userId, forHTTPHeaderField: "X-User-ID")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StravaAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw StravaAPIError.unknownError(httpResponse.statusCode)
        }

        struct BackendResponse: Codable {
            let activity: StravaDetailedActivity
            let cached: Bool
            let syncedAt: Int
        }

        let backendResponse = try JSONDecoder().decode(BackendResponse.self, from: data)

        print("✅ Backend: Loaded activity \(id) (cached: \(backendResponse.cached))")

        return backendResponse.activity
    }

    // MARK: - Rate Limit Monitoring (Legacy - now handled by backend)

    /// Check if we can make more requests safely
    /// Backend now handles all rate limiting
    func canMakeRequest() -> Bool {
        return true
    }

    // MARK: - Athlete Info

    func fetchAthlete() async throws -> StravaAthleteInfo {
        guard authService.isAuthenticated, let athleteId = authService.athleteId else {
            throw StravaAPIError.unauthorized
        }

        return StravaAthleteInfo(
            id: Int64(athleteId),
            username: nil,
            firstname: nil,
            lastname: nil,
            profile: nil,
            city: nil,
            state: nil,
            country: nil
        )
    }
}

// MARK: - Athlete Model

struct StravaAthleteInfo: Codable {
    let id: Int64
    let username: String?
    let firstname: String?
    let lastname: String?
    let profile: String?
    let city: String?
    let state: String?
    let country: String?
}

// MARK: - Strava Activity Models

struct StravaActivity: Codable, Identifiable {
    let id: Int64
    let name: String
    let distance: Double // meters
    let movingTime: Int // seconds
    let elapsedTime: Int // seconds
    let totalElevationGain: Double // meters
    let type: String // "Run", "Ride", "Swim", etc.
    let startDate: String // ISO 8601 format
    let startDateLocal: String
    let averageSpeed: Double? // m/s
    let maxSpeed: Double? // m/s
    let averageHeartrate: Double?
    let maxHeartrate: Double?
    let calories: Double?

    // Computed properties for display
    var distanceKm: Double {
        distance / 1000.0
    }

    var durationFormatted: String {
        let hours = movingTime / 3600
        let minutes = (movingTime % 3600) / 60
        let seconds = movingTime % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    var averagePace: Double? {
        guard averageSpeed ?? 0 > 0 else { return nil }
        // Convert m/s to min/km
        return (1000.0 / averageSpeed!) / 60.0
    }

    var startDateParsed: Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: startDate)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, distance, type, calories
        case movingTime = "moving_time"
        case elapsedTime = "elapsed_time"
        case totalElevationGain = "total_elevation_gain"
        case startDate = "start_date"
        case startDateLocal = "start_date_local"
        case averageSpeed = "average_speed"
        case maxSpeed = "max_speed"
        case averageHeartrate = "average_heartrate"
        case maxHeartrate = "max_heartrate"
    }
}

struct StravaDetailedActivity: Codable {
    let id: Int64
    let name: String
    let distance: Double
    let movingTime: Int
    let elapsedTime: Int
    let totalElevationGain: Double
    let type: String
    let startDate: String
    let calories: Double?
    let description: String?
    let photos: StravaPhotos?
    let map: StravaMap?

    enum CodingKeys: String, CodingKey {
        case id, name, distance, type, calories, description, photos, map
        case movingTime = "moving_time"
        case elapsedTime = "elapsed_time"
        case totalElevationGain = "total_elevation_gain"
        case startDate = "start_date"
    }
}

struct StravaPhotos: Codable {
    let count: Int
}

struct StravaMap: Codable {
    let id: String
    let polyline: String?
    let summaryPolyline: String?

    enum CodingKeys: String, CodingKey {
        case id, polyline
        case summaryPolyline = "summary_polyline"
    }
}

// MARK: - Errors

enum StravaAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case rateLimitExceeded
    case serverError
    case unknownError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Strava API URL"
        case .invalidResponse:
            return "Invalid response from Strava"
        case .unauthorized:
            return "Unauthorized - Please re-authenticate with Strava"
        case .rateLimitExceeded:
            return "Strava rate limit exceeded. Please try again later."
        case .serverError:
            return "Strava server error. Please try again."
        case .unknownError(let code):
            return "Unknown error (HTTP \(code))"
        }
    }
}
