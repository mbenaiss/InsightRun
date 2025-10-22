//
//  BackendAPIClient.swift
//  HealthApp
//
//  Secure API client for backend communication
//  Replaces direct OpenRouter API calls
//

import Foundation

class BackendAPIClient {
    static let shared = BackendAPIClient()

    // Backend API endpoint
    private let baseURL = "https://healthapp-backend.mbenaissa.workers.dev"

    // App identifier key
    // Note: This is safe to hardcode as it's just an app identifier (like a User-Agent).
    // Real security is server-side with rate limiting, IP tracking, and secret rotation.
    // iOS apps can always be decompiled, so no true secrets should ever be in client code.
    private let appKey = "insightrun-LEtZ5vhVA5RBpw8u-F0Rxvk1mHagGeINJEI9GOPUFs4"

    private init() {}

    // MARK: - Chat (Non-streaming)

    func chat(prompt: String, systemPrompt: String, model: String) async throws -> String {
        let url = URL(string: "\(baseURL)/api/chat")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(appKey, forHTTPHeaderField: "X-App-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "prompt": prompt,
            "systemPrompt": systemPrompt,
            "model": model
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        // Vérifier le status code
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            // Success
            break
        case 401:
            throw BackendError.unauthorized
        case 429:
            throw BackendError.rateLimitExceeded
        case 500...599:
            throw BackendError.serverError
        default:
            throw BackendError.unknownError(httpResponse.statusCode)
        }

        // Parser la réponse
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseText = json["response"] as? String else {
            throw BackendError.invalidResponse
        }

        return responseText
    }

    // MARK: - Chat (Streaming)

    func chatStream(prompt: String, systemPrompt: String, model: String) async throws -> AsyncStream<String> {
        let url = URL(string: "\(baseURL)/api/chat")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(appKey, forHTTPHeaderField: "X-App-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "prompt": prompt,
            "systemPrompt": systemPrompt,
            "model": model
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return AsyncStream { continuation in
            Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                          (200...299).contains(httpResponse.statusCode) else {
                        continuation.finish()
                        return
                    }

                    for try await line in bytes.lines {
                        // Parse SSE format: data: {...}
                        if line.hasPrefix("data: ") {
                            let jsonString = String(line.dropFirst(6))

                            if jsonString == "[DONE]" {
                                continuation.finish()
                                return
                            }

                            // Parse simplified format: {"content": "..."}
                            if let jsonData = jsonString.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                               let content = json["content"] as? String {
                                continuation.yield(content)
                            }
                        }
                    }

                    continuation.finish()

                } catch {
                    print("❌ BackendAPIClient streaming error: \(error)")
                    continuation.finish()
                }
            }
        }
    }

    // MARK: - Stats

    func getStats() async throws -> RateLimitStats {
        let url = URL(string: "\(baseURL)/api/stats")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(appKey, forHTTPHeaderField: "X-App-Key")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw BackendError.serverError
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let remaining = json["requestsRemaining"] as? Int,
              let limit = json["limit"] as? Int,
              let resetIn = json["resetIn"] as? Int else {
            throw BackendError.invalidResponse
        }

        return RateLimitStats(
            requestsRemaining: remaining,
            limit: limit,
            resetIn: resetIn
        )
    }

    // MARK: - Configuration

    func setBaseURL(_ url: String) {
        // Pour changer l'URL après déploiement
        // BackendAPIClient.shared.setBaseURL("https://healthapp-backend.YOUR_SUBDOMAIN.workers.dev")
    }
}

// MARK: - Models

struct RateLimitStats {
    let requestsRemaining: Int
    let limit: Int
    let resetIn: Int // seconds

    var percentageUsed: Double {
        return Double(limit - requestsRemaining) / Double(limit) * 100
    }

    var formattedResetTime: String {
        let minutes = resetIn / 60
        return "\(minutes) minutes"
    }
}

// MARK: - Errors

enum BackendError: LocalizedError {
    case unauthorized
    case rateLimitExceeded
    case serverError
    case invalidResponse
    case unknownError(Int)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Unauthorized - Invalid app key"
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please try again later."
        case .serverError:
            return "Server error. Please try again."
        case .invalidResponse:
            return "Invalid response from server"
        case .unknownError(let code):
            return "Unknown error (HTTP \(code))"
        }
    }
}
