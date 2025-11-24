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
