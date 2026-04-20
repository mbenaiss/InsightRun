//
//  StravaAuthService.swift
//  InsightRun
//
//  Strava OAuth 2.0 Authentication Service
//  Handles token management with automatic refresh
//

import Foundation
import AuthenticationServices
import Security
import Combine
import UIKit

/// Secure storage for Strava tokens using Keychain
class StravaTokenStorage {
    static let shared = StravaTokenStorage()

    private let service = "com.insightrun.strava"
    private let accessTokenKey = "strava_access_token"
    private let refreshTokenKey = "strava_refresh_token"
    private let expiresAtKey = "strava_expires_at"
    private let athleteIdKey = "strava_athlete_id"

    // MARK: - Token Management

    func saveTokens(accessToken: String, refreshToken: String, expiresAt: Date, athleteId: Int64) {
        // Save to Keychain (secure)
        saveToKeychain(key: accessTokenKey, value: accessToken)
        saveToKeychain(key: refreshTokenKey, value: refreshToken)

        // Save expiration date and athlete ID to UserDefaults (not sensitive)
        UserDefaults.standard.set(expiresAt.timeIntervalSince1970, forKey: expiresAtKey)
        UserDefaults.standard.set(athleteId, forKey: athleteIdKey)

        print("🔐 Tokens saved securely (expires: \(expiresAt))")
    }

    func getAccessToken() -> String? {
        return getFromKeychain(key: accessTokenKey)
    }

    func getRefreshToken() -> String? {
        return getFromKeychain(key: refreshTokenKey)
    }

    func getExpiresAt() -> Date? {
        let timestamp = UserDefaults.standard.double(forKey: expiresAtKey)
        return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }

    func getAthleteId() -> Int64? {
        let id = UserDefaults.standard.object(forKey: athleteIdKey) as? Int64
        return id != 0 ? id : nil
    }

    func isTokenExpired() -> Bool {
        guard let expiresAt = getExpiresAt() else { return true }
        // Consider expired if less than 5 minutes remaining
        return Date().addingTimeInterval(300) > expiresAt
    }

    func clearTokens() {
        deleteFromKeychain(key: accessTokenKey)
        deleteFromKeychain(key: refreshTokenKey)
        UserDefaults.standard.removeObject(forKey: expiresAtKey)
        UserDefaults.standard.removeObject(forKey: athleteIdKey)

        print("🗑️ Strava tokens cleared")
    }

    // MARK: - Keychain Helpers

    private func saveToKeychain(key: String, value: String) {
        let data = value.data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        // Delete old value first
        SecItemDelete(query as CFDictionary)

        // Add new value
        SecItemAdd(query as CFDictionary, nil)
    }

    private func getFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Presentation Context Provider

class WebAuthenticationPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Use modern API to get the key window
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            return windowScene.windows.first { $0.isKeyWindow } ?? windowScene.windows.first ?? ASPresentationAnchor()
        }
        return ASPresentationAnchor()
    }
}

// MARK: - Strava Auth Service

@MainActor
class StravaAuthService: ObservableObject {
    static let shared = StravaAuthService()

    @Published var isAuthenticated = false
    @Published var athleteId: Int64?

    private let tokenStorage = StravaTokenStorage.shared
    private let backendClient = StravaBackendClient.shared
    private let presentationContextProvider = WebAuthenticationPresentationContextProvider()
    private var currentAuthSession: ASWebAuthenticationSession?

    private let clientId = "147744"
    private let redirectUri = "insightrun://insightrun.altcode.studio"
    private let authBaseURL = "https://www.strava.com/oauth"

    private init() {
        // Check if we have valid tokens on init
        checkAuthentication()
    }

    // MARK: - Authentication Status

    func checkAuthentication() {
        isAuthenticated = tokenStorage.getAccessToken() != nil
        athleteId = tokenStorage.getAthleteId()

        if isAuthenticated {
            print("✅ Strava: Already authenticated (athlete: \(athleteId ?? 0))")
        }
    }

    // MARK: - OAuth 2.0 Flow

    /// Start OAuth flow using ASWebAuthenticationSession
    func authenticate() async throws {
        // Step 1: Build authorization URL
        let scope = "read,activity:read_all" // Request permissions
        let authURL = "\(authBaseURL)/authorize?client_id=\(clientId)&response_type=code&redirect_uri=\(redirectUri)&scope=\(scope)&approval_prompt=force"

        guard let url = URL(string: authURL) else {
            throw StravaAuthError.invalidURL
        }

        print("🔐 Starting Strava OAuth flow...")

        // Step 2: Open web authentication session
        let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            self.currentAuthSession = ASWebAuthenticationSession(url: url, callbackURLScheme: "insightrun") { callbackURL, error in
                if let error = error {
                    // User closed the OAuth popup. Treat as a skip, not a technical failure.
                    if let asError = error as? ASWebAuthenticationSessionError, asError.code == .canceledLogin {
                        continuation.resume(throwing: StravaAuthError.userCancelled)
                        return
                    }
                    continuation.resume(throwing: StravaAuthError.authenticationFailed(error.localizedDescription))
                    return
                }

                guard let callbackURL = callbackURL else {
                    continuation.resume(throwing: StravaAuthError.noCallbackURL)
                    return
                }

                continuation.resume(returning: callbackURL)
            }

            self.currentAuthSession?.presentationContextProvider = self.presentationContextProvider
            self.currentAuthSession?.start()
        }

        // Clear auth session reference
        self.currentAuthSession = nil

        // Step 3: Extract authorization code from callback URL
        guard let code = extractCode(from: callbackURL) else {
            throw StravaAuthError.invalidCode
        }

        print("✅ Authorization code received")

        // Step 4: Exchange code for tokens
        try await exchangeCodeForToken(code: code)

        isAuthenticated = true
        print("🎉 Strava authentication successful!")
    }

    private func exchangeCodeForToken(code: String) async throws {
        let userId = UserIdentityService.shared.userID
        let tokenResponse = try await backendClient.exchangeCodeForTokens(code: code, userId: userId)

        let expiresAt = Date(timeIntervalSince1970: TimeInterval(tokenResponse.expiresAt))
        tokenStorage.saveTokens(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            expiresAt: expiresAt,
            athleteId: tokenResponse.athlete?.id ?? 0
        )

        athleteId = tokenResponse.athlete?.id ?? 0
    }

    // MARK: - Token Refresh (THE CRITICAL PART!)

    /// Get valid access token (automatically refreshes if expired)
    func getValidAccessToken() async throws -> String {
        // Check if token is expired
        if tokenStorage.isTokenExpired() {
            print("⚠️ Access token expired, refreshing...")
            try await refreshAccessToken()
        }

        guard let accessToken = tokenStorage.getAccessToken() else {
            throw StravaAuthError.notAuthenticated
        }

        return accessToken
    }

    private func refreshAccessToken() async throws {
        guard let refreshToken = tokenStorage.getRefreshToken() else {
            throw StravaAuthError.noRefreshToken
        }

        do {
            let userId = UserIdentityService.shared.userID
            let tokenResponse = try await backendClient.refreshToken(refreshToken: refreshToken, userId: userId)

            let expiresAt = Date(timeIntervalSince1970: TimeInterval(tokenResponse.expiresAt))
            tokenStorage.saveTokens(
                accessToken: tokenResponse.accessToken,
                refreshToken: tokenResponse.refreshToken,
                expiresAt: expiresAt,
                athleteId: tokenResponse.athlete?.id ?? 0
            )
        } catch {
            tokenStorage.clearTokens()
            isAuthenticated = false
            throw StravaAuthError.refreshFailed
        }
    }

    // MARK: - Logout

    func logout() async {
        // Call backend cleanup endpoint to delete KV tokens + D1 data
        do {
            try await StravaBackendClient.shared.disconnect(
                userId: UserIdentityService.shared.userID
            )
            print("✅ Backend cleanup completed")
        } catch {
            print("⚠️ Backend cleanup failed (continuing with local cleanup): \(error)")
        }

        // Clear local tokens
        tokenStorage.clearTokens()
        isAuthenticated = false
        athleteId = nil

        print("👋 Logged out from Strava")
    }

    // MARK: - Helpers

    private func extractCode(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              let code = queryItems.first(where: { $0.name == "code" })?.value else {
            return nil
        }
        return code
    }
}

// MARK: - Errors

enum StravaAuthError: LocalizedError {
    case invalidURL
    case authenticationFailed(String)
    case userCancelled
    case noCallbackURL
    case invalidCode
    case tokenExchangeFailed
    case notAuthenticated
    case noRefreshToken
    case refreshFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Strava URL"
        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"
        case .userCancelled:
            return "Strava authentication was cancelled"
        case .noCallbackURL:
            return "No callback URL received"
        case .invalidCode:
            return "Invalid authorization code"
        case .tokenExchangeFailed:
            return "Failed to exchange code for token"
        case .notAuthenticated:
            return "Not authenticated with Strava"
        case .noRefreshToken:
            return "No refresh token available"
        case .refreshFailed:
            return "Failed to refresh token. Please re-authenticate."
        }
    }
}

// MARK: - Presentation Context Provider

class ASWebAuthenticationPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return ASPresentationAnchor()
    }
}
