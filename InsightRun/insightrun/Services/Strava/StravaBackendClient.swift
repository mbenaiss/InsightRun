//
//  StravaBackendClient.swift
//  InsightRun
//

import Foundation

class StravaBackendClient {
    static let shared = StravaBackendClient()

    private let baseURL = "https://api.insightrun.altcode.studio"
    private let appKey = "healthapp-LEtZ5vhVA5RBpw8u-F0Rxvk1mHagGeINJEI9GOPUFs4"

    private init() {}

    func exchangeCodeForTokens(code: String, userId: String) async throws -> TokenResponse {
        let url = URL(string: "\(baseURL)/api/strava/exchange-token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(appKey, forHTTPHeaderField: "X-App-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: String] = [
            "code": code,
            "userId": userId
        ]

        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StravaBackendError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw StravaBackendError.httpError(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    func refreshToken(refreshToken: String, userId: String) async throws -> TokenResponse {
        let url = URL(string: "\(baseURL)/api/strava/refresh-token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(appKey, forHTTPHeaderField: "X-App-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: String] = [
            "refreshToken": refreshToken,
            "userId": userId
        ]

        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StravaBackendError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw StravaBackendError.httpError(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    func syncActivities(userId: String, force: Bool = false) async throws -> SyncResponse {
        let url = URL(string: "\(baseURL)/api/strava/sync")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(appKey, forHTTPHeaderField: "X-App-Key")
        request.setValue(userId, forHTTPHeaderField: "X-User-ID")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "force": force
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        print("🔄 Syncing activities via backend for user \(userId)...")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StravaBackendError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorString = String(data: data, encoding: .utf8) {
                print("❌ Backend sync error: \(errorString)")
            }
            throw StravaBackendError.httpError(httpResponse.statusCode)
        }

        let syncResponse = try JSONDecoder().decode(SyncResponse.self, from: data)
        print("✅ Sync complete: \(syncResponse.newActivities) new, \(syncResponse.totalActivities) total")
        return syncResponse
    }

    func fetchActivities(userId: String, limit: Int = 100, offset: Int = 0, since: Date? = nil) async throws -> ActivitiesResponse {
        var urlComponents = URLComponents(string: "\(baseURL)/api/strava/activities")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]

        if let since = since {
            let timestamp = Int(since.timeIntervalSince1970)
            queryItems.append(URLQueryItem(name: "since", value: String(timestamp)))
        }

        urlComponents.queryItems = queryItems

        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = "GET"
        request.setValue(appKey, forHTTPHeaderField: "X-App-Key")
        request.setValue(userId, forHTTPHeaderField: "X-User-ID")
        request.timeoutInterval = 30

        print("📥 Fetching activities from backend (limit: \(limit), offset: \(offset))...")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StravaBackendError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorString = String(data: data, encoding: .utf8) {
                print("❌ Backend fetch error: \(errorString)")
            }
            throw StravaBackendError.httpError(httpResponse.statusCode)
        }

        let activitiesResponse = try JSONDecoder().decode(ActivitiesResponse.self, from: data)
        print("✅ Fetched \(activitiesResponse.activities.count) activities from backend")
        return activitiesResponse
    }

    func disconnect(userId: String) async throws {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/strava/disconnect")!)
        request.httpMethod = "DELETE"
        request.setValue(appKey, forHTTPHeaderField: "X-App-Key")
        request.setValue(userId, forHTTPHeaderField: "X-User-ID")
        request.timeoutInterval = 30

        print("🗑️  Calling backend cleanup endpoint...")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StravaBackendError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorString = String(data: data, encoding: .utf8) {
                print("❌ Backend cleanup error: \(errorString)")
            }
            throw StravaBackendError.httpError(httpResponse.statusCode)
        }

        print("✅ Backend cleanup successful")
    }

}

struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Int
    let athlete: Athlete?

    struct Athlete: Codable {
        let id: Int64
        let username: String?
        let firstname: String?
        let lastname: String?
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
        case athlete
    }
}

struct SyncResponse: Codable {
    let newActivities: Int
    let totalActivities: Int

    enum CodingKeys: String, CodingKey {
        case newActivities = "new_activities"
        case totalActivities = "total_activities"
    }
}

struct ActivitiesResponse: Codable {
    let activities: [BackendActivity]
    let total: Int
    let limit: Int
    let offset: Int
    let cached: Bool
}

struct BackendActivity: Codable {
    let id: Int64
    let userId: String
    let activityId: Int64
    let name: String
    let type: String
    let distance: Double
    let movingTime: Int
    let elapsedTime: Int
    let totalElevationGain: Double
    let startDate: String
    let startDateLocal: String
    let averageSpeed: Double?
    let maxSpeed: Double?
    let averageHeartrate: Double?
    let maxHeartrate: Double?
    let calories: Double?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case activityId = "activity_id"
        case name, type, distance
        case movingTime = "moving_time"
        case elapsedTime = "elapsed_time"
        case totalElevationGain = "total_elevation_gain"
        case startDate = "start_date"
        case startDateLocal = "start_date_local"
        case averageSpeed = "average_speed"
        case maxSpeed = "max_speed"
        case averageHeartrate = "average_heartrate"
        case maxHeartrate = "max_heartrate"
        case calories
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func toStravaActivity() -> StravaActivity {
        return StravaActivity(
            id: activityId,
            name: name,
            distance: distance,
            movingTime: movingTime,
            elapsedTime: elapsedTime,
            totalElevationGain: totalElevationGain,
            type: type,
            startDate: startDate,
            startDateLocal: startDateLocal,
            averageSpeed: averageSpeed,
            maxSpeed: maxSpeed,
            averageHeartrate: averageHeartrate,
            maxHeartrate: maxHeartrate,
            calories: calories
        )
    }
}

enum StravaBackendError: LocalizedError {
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Strava backend"
        case .httpError(let code):
            return "Strava backend error (HTTP \(code))"
        }
    }
}
