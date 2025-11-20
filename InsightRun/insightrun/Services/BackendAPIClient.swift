//
//  BackendAPIClient.swift
//  InsightRun
//
//  Secure API client for backend communication
//  Replaces direct OpenRouter API calls
//

import Foundation

class BackendAPIClient {
    static let shared = BackendAPIClient()

    // Backend API endpoint
    private let baseURL = "https://api.insightrun.altcode.studio"

    // App identifier key
    // Note: This is safe to hardcode as it's just an app identifier (like a User-Agent).
    // Real security is server-side with rate limiting, IP tracking, and secret rotation.
    // iOS apps can always be decompiled, so no true secrets should ever be in client code.
    private let appKey = "healthapp-LEtZ5vhVA5RBpw8u-F0Rxvk1mHagGeINJEI9GOPUFs4"

    private init() {}

    // MARK: - Chat (Non-streaming)

    /// Simple classification using RequestType (no hardcoded model)
    func classify(prompt: String, systemPrompt: String) async throws -> String {
        let url = URL(string: "\(baseURL)/api/chat")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(appKey, forHTTPHeaderField: "X-App-Key")
        request.setValue(UserIdentityService.shared.userID, forHTTPHeaderField: "X-User-ID")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "prompt": prompt,
            "systemPrompt": systemPrompt,
            "requestType": RequestType.classification.rawValue
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
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

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseText = json["response"] as? String else {
            throw BackendError.invalidResponse
        }

        return responseText
    }

    // MARK: - Chat V2 (Streaming with JSON data)

    func chatStreamV2(payload: ChatRequestV2) async throws -> AsyncStream<String> {
        let url = URL(string: "\(baseURL)/api/chat/v2")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(appKey, forHTTPHeaderField: "X-App-Key")
        request.setValue(UserIdentityService.shared.userID, forHTTPHeaderField: "X-User-ID")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let encoder = JSONEncoder()
        // Keep camelCase for backend compatibility
        request.httpBody = try encoder.encode(payload)

        return AsyncStream { continuation in
            Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish()
                        return
                    }

                    // Check for errors
                    switch httpResponse.statusCode {
                    case 200...299:
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
                    print("❌ BackendAPIClient V2 streaming error: \(error)")
                    continuation.finish()
                }
            }
        }
    }

    // MARK: - Historical Analysis (Batch Processing)

    /// Analyze a batch of workouts (up to 50)
    func analyzeBatch(workouts: [WorkoutData], batchIndex: Int, requestType: String?, model: String?, language: String) async throws -> BatchAnalysisResponse {
        let url = URL(string: "\(baseURL)/api/analyze-history/batch")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(appKey, forHTTPHeaderField: "X-App-Key")
        request.setValue(UserIdentityService.shared.userID, forHTTPHeaderField: "X-User-ID")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let requestBody = BatchAnalysisRequest(
            workouts: workouts,
            batchIndex: batchIndex,
            requestType: requestType,
            model: model,
            language: language
        )

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(requestBody)

        print("📊 BackendAPIClient: Analyzing batch \(batchIndex) (\(workouts.count) workouts)...")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
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

        let decoder = JSONDecoder()
        let batchResponse = try decoder.decode(BatchAnalysisResponse.self, from: data)

        print("✅ BackendAPIClient: Batch \(batchIndex) analyzed (\(batchResponse.workoutCount) workouts, \(batchResponse.tokenCount) tokens)")

        return batchResponse
    }

    /// Consolidate all batch summaries into a final summary
    func consolidateBatches(batchSummaries: [String], totalWorkouts: Int, profile: HealthProfileData?, requestType: String?, model: String?, language: String) async throws -> ConsolidationResponse {
        let url = URL(string: "\(baseURL)/api/analyze-history/consolidate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(appKey, forHTTPHeaderField: "X-App-Key")
        request.setValue(UserIdentityService.shared.userID, forHTTPHeaderField: "X-User-ID")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let requestBody = ConsolidationRequest(
            batchSummaries: batchSummaries,
            totalWorkouts: totalWorkouts,
            profile: profile,
            requestType: requestType,
            model: model,
            language: language
        )

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(requestBody)

        print("📊 BackendAPIClient: Consolidating \(batchSummaries.count) batch summaries...")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
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

        let decoder = JSONDecoder()
        let consolidationResponse = try decoder.decode(ConsolidationResponse.self, from: data)

        print("✅ BackendAPIClient: Consolidation completed (\(consolidationResponse.workoutCount) workouts, \(consolidationResponse.tokenCount) tokens)")

        return consolidationResponse
    }

    // MARK: - Stats

    func getStats() async throws -> RateLimitStats {
        let url = URL(string: "\(baseURL)/api/stats")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(appKey, forHTTPHeaderField: "X-App-Key")
        request.setValue(UserIdentityService.shared.userID, forHTTPHeaderField: "X-User-ID")

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

    // MARK: - Workout Generation

    /// Generate a custom workout using AI
    func generateWorkout(userQuestion: String, language: String, userContext: WorkoutGenerationRequest.UserContext?, requestType: String? = nil, model: String? = nil) async throws -> WorkoutGenerationResponse {
        let url = URL(string: "\(baseURL)/api/generate-workout")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(appKey, forHTTPHeaderField: "X-App-Key")
        request.setValue(UserIdentityService.shared.userID, forHTTPHeaderField: "X-User-ID")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60 // Increased timeout for AI generation (parsing + generation)

        let requestBody = WorkoutGenerationRequest(
            userQuestion: userQuestion,
            language: language,
            userContext: userContext,
            requestType: requestType,
            model: model
        )

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
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

        let decoder = JSONDecoder()
        do {
            let workoutResponse = try decoder.decode(WorkoutGenerationResponse.self, from: data)
            return workoutResponse
        } catch {
            throw BackendError.invalidResponse
        }
    }

    /// Generate a smart workout suggestion based on recent workout history
    /// Uses ChatRequestV2 payload like /api/chat/v2
    func generateSmartWorkoutSuggestion(recentWorkoutsData: RecentWorkoutsData, historicalSummary: String?, language: String) async throws -> SmartSuggestionResponse {
        let url = URL(string: "\(baseURL)/api/workout/smart-suggestion")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(appKey, forHTTPHeaderField: "X-App-Key")
        request.setValue(UserIdentityService.shared.userID, forHTTPHeaderField: "X-User-ID")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        // Build ChatRequestV2 payload (same structure as WorkoutAIService)
        let chatData = ChatDataPayload(
            workout: nil,
            recovery: nil,
            profile: nil,
            recentWorkouts: recentWorkoutsData,
            historicalSummary: historicalSummary
        )

        let requestBody = ChatRequestV2(
            promptType: "workout_suggestion",
            requestType: RequestType.smartSuggestion.rawValue,
            model: nil, // Backend will select appropriate model
            userQuestion: "Suggest a detailed workout based on my recent training",
            language: language,
            data: chatData
        )

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(requestBody)

        print("✨ BackendAPIClient: Generating smart workout suggestion...")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
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

        let decoder = JSONDecoder()
        let suggestionResponse = try decoder.decode(SmartSuggestionResponse.self, from: data)

        print("✅ BackendAPIClient: Smart suggestion generated: \"\(suggestionResponse.suggestion)\"")

        return suggestionResponse
    }

    // MARK: - Configuration

    func setBaseURL(_ url: String) {
        // Pour changer l'URL après déploiement
        // BackendAPIClient.shared.setBaseURL("https://insightrun-backend.YOUR_SUBDOMAIN.workers.dev")
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
