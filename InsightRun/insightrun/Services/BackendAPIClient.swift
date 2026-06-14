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

    // MARK: - HTTP Status Handling

    /// Centralized HTTP status mapping so every endpoint maps 401/403/429/5xx consistently.
    /// `data` is optional (unavailable for streaming responses) and only used for the unknown-error preview.
    private func validate(_ response: URLResponse, data: Data?) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401:
            throw BackendError.unauthorized
        case 403:
            throw BackendError.blocked
        case 429:
            throw BackendError.rateLimitExceeded(retryAfter: Self.retryAfter(from: httpResponse))
        case 500...599:
            throw BackendError.serverError
        default:
            throw BackendError.unknownError(code: httpResponse.statusCode,
                                            body: data.flatMap { BackendError.bodyPreview(from: $0) })
        }
    }

    /// Extract a retry delay (seconds) from a 429 response. Supports `Retry-After`
    /// (seconds or HTTP-date) and the backend's `X-RateLimit-Reset` epoch header.
    private static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        if let raw = response.value(forHTTPHeaderField: "Retry-After") {
            if let seconds = TimeInterval(raw.trimmingCharacters(in: .whitespaces)) {
                return seconds
            }
            let httpDate = DateFormatter()
            httpDate.locale = Locale(identifier: "en_US_POSIX")
            httpDate.timeZone = TimeZone(identifier: "GMT")
            httpDate.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            if let date = httpDate.date(from: raw) {
                return max(0, date.timeIntervalSinceNow)
            }
        }
        if let resetRaw = response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
           let resetEpoch = TimeInterval(resetRaw.trimmingCharacters(in: .whitespaces)) {
            return max(0, Date(timeIntervalSince1970: resetEpoch).timeIntervalSinceNow)
        }
        return nil
    }

    // MARK: - Chat (Non-streaming)

    /// Simple classification using RequestType (no hardcoded model)
    func classify(prompt: String, systemPrompt: String, requestType: RequestType = .classification) async throws -> String {
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
            "requestType": requestType.rawValue,
            "stream": false // Non-streaming for quick classification
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)

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
                    try self.validate(response, data: nil)

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

    // MARK: - Agent Chat (Streaming with function calling)

    enum AgentStreamEvent {
        case content(String)
        case functionResult(AgentFunctionResult)
    }

    struct AgentFunctionResult {
        let functionName: String
        let result: Data
        let message: String
    }

    func agentChatStream(payload: AgentChatRequest) async throws -> AsyncThrowingStream<AgentStreamEvent, Error> {
        let url = URL(string: "\(baseURL)/api/agent/chat")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(appKey, forHTTPHeaderField: "X-App-Key")
        request.setValue(UserIdentityService.shared.userID, forHTTPHeaderField: "X-User-ID")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(payload)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    try self.validate(response, data: nil)

                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let jsonString = String(line.dropFirst(6))

                            if jsonString == "[DONE]" {
                                continuation.finish()
                                return
                            }

                            guard let jsonData = jsonString.data(using: .utf8),
                                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                                  let type = json["type"] as? String else {
                                continue
                            }

                            switch type {
                            case "content":
                                if let content = json["content"] as? String {
                                    continuation.yield(.content(content))
                                }
                            case "function_result":
                                if let functionName = json["function"] as? String,
                                   let message = json["message"] as? String,
                                   let result = json["result"] {
                                    let resultData = try JSONSerialization.data(withJSONObject: result)
                                    continuation.yield(.functionResult(AgentFunctionResult(
                                        functionName: functionName,
                                        result: resultData,
                                        message: message
                                    )))
                                }
                            default:
                                break
                            }
                        }
                    }

                    continuation.finish()

                } catch {
                    print("❌ BackendAPIClient agent streaming error: \(error)")
                    continuation.finish(throwing: error)
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
        request.timeoutInterval = 300

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
        try validate(response, data: data)

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
        try validate(response, data: data)

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
        try validate(response, data: data)

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
        request.timeoutInterval = 90 // Backend runs up to 2 generation attempts with no per-attempt timeout

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
        try validate(response, data: data)

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
            baseline: nil,
            recentWorkouts: recentWorkoutsData,
            historicalSummary: historicalSummary,
            trainingPlan: nil
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
        try validate(response, data: data)

        let decoder = JSONDecoder()
        let suggestionResponse = try decoder.decode(SmartSuggestionResponse.self, from: data)

        print("✅ BackendAPIClient: Smart suggestion generated: \"\(suggestionResponse.suggestion)\"")

        return suggestionResponse
    }

    // MARK: - Training Plan Generation

    /// Generate a multi-week training plan for a race goal
    func generateTrainingPlan(request: TrainingPlanGenerationRequest) async throws -> TrainingPlanGenerationResponse {
        // Anti-double-submission: a long, premium-quota generation must not run twice concurrently.
        let key = "generate-plan:\(request.raceType):\(request.targetDate)"
        guard await InFlightGuard.shared.begin(key) else { throw RequestInProgressError() }
        defer { Task { await InFlightGuard.shared.end(key) } }

        let url = URL(string: "\(baseURL)/api/generate-training-plan")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(appKey, forHTTPHeaderField: "X-App-Key")
        urlRequest.setValue(UserIdentityService.shared.userID, forHTTPHeaderField: "X-User-ID")
        urlRequest.setValue(key, forHTTPHeaderField: "Idempotency-Key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = 185 // Backend may run 2x90s attempts; client must outlast it

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        try validate(response, data: data)

        let decoder = JSONDecoder()
        return try decoder.decode(TrainingPlanGenerationResponse.self, from: data)
    }

    // MARK: - Training Plan Adaptation

    func adaptTrainingPlan(request: AdaptTrainingPlanRequest) async throws -> AdaptTrainingPlanResponse {
        let key = "adapt-plan:\(request.originalPlanName):\(request.currentWeekNumber)"
        guard await InFlightGuard.shared.begin(key) else { throw RequestInProgressError() }
        defer { Task { await InFlightGuard.shared.end(key) } }

        let url = URL(string: "\(baseURL)/api/adapt-training-plan")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(appKey, forHTTPHeaderField: "X-App-Key")
        urlRequest.setValue(UserIdentityService.shared.userID, forHTTPHeaderField: "X-User-ID")
        urlRequest.setValue(key, forHTTPHeaderField: "Idempotency-Key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = 185 // Backend may run 2x90s attempts; client must outlast it

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        try validate(response, data: data)

        let decoder = JSONDecoder()
        return try decoder.decode(AdaptTrainingPlanResponse.self, from: data)
    }

    // MARK: - Remote Configuration

    /// Fetch remote configuration (feature flags, version info, maintenance mode)
    /// Used by RemoteConfigService for offline-first feature management
    func getConfig() async throws -> RemoteConfig {
        let url = URL(string: "\(baseURL)/api/config")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(appKey, forHTTPHeaderField: "X-App-Key")
        request.setValue(UserIdentityService.shared.userID, forHTTPHeaderField: "X-User-ID")
        request.timeoutInterval = 10 // Short timeout for config fetch

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)

        let decoder = JSONDecoder()
        let config = try decoder.decode(RemoteConfig.self, from: data)

        print("✅ BackendAPIClient: Fetched remote config")

        return config
    }

    // MARK: - Daily Readiness

    /// Fetch daily readiness score from backend
    func fetchDailyReadiness(request: DailyReadinessRequest) async throws -> DailyReadinessResponse {
        let url = URL(string: "\(baseURL)/api/daily-readiness")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(appKey, forHTTPHeaderField: "X-App-Key")
        urlRequest.setValue(UserIdentityService.shared.userID, forHTTPHeaderField: "X-User-ID")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = 30

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        print("📊 BackendAPIClient: Fetching daily readiness...")

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        try validate(response, data: data)

        let decoder = JSONDecoder()
        let readinessResponse = try decoder.decode(DailyReadinessResponse.self, from: data)

        print("✅ BackendAPIClient: Daily readiness fetched - Score: \(readinessResponse.score)")

        return readinessResponse
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
    case blocked
    case rateLimitExceeded(retryAfter: TimeInterval?)
    case serverError
    case invalidResponse
    case unknownError(code: Int, body: String?)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return String(localized: "Unauthorized - Invalid app key", comment: "Backend error: unauthorized")
        case .blocked:
            return String(localized: "Your account has been blocked. Please contact support.", comment: "Backend error: account blocked")
        case .rateLimitExceeded(let retryAfter):
            if let retryAfter, retryAfter > 0 {
                let minutes = max(1, Int((retryAfter / 60).rounded(.up)))
                return String(localized: "backend.error.rateLimit.retryAfter",
                              defaultValue: "Rate limit exceeded. Try again in \(minutes) min.",
                              comment: "Backend error: rate limit with retry delay in minutes")
            }
            return String(localized: "Rate limit exceeded. Please try again later.", comment: "Backend error: rate limit")
        case .serverError:
            return String(localized: "Server error. Please try again.", comment: "Backend error: server error")
        case .invalidResponse:
            return String(localized: "Invalid response from server", comment: "Backend error: invalid response")
        case .unknownError(let code, _):
            return String(localized: "Unknown error (HTTP \(code))", comment: "Backend error: unknown HTTP error")
        }
    }

    /// Seconds to wait before retrying, if the server provided a hint (429 only).
    var retryAfterSeconds: TimeInterval? {
        if case .rateLimitExceeded(let retryAfter) = self { return retryAfter }
        return nil
    }

    /// Truncate a response body to a preview suitable for analytics.
    static func bodyPreview(from data: Data, maxBytes: Int = 500) -> String? {
        guard !data.isEmpty else { return nil }
        return String(data: data.prefix(maxBytes), encoding: .utf8)
    }
}

// MARK: - In-Flight Guard

/// Thrown when a long generation is already running for the same key (anti-double-submission).
struct RequestInProgressError: LocalizedError {
    var errorDescription: String? {
        String(localized: "backend.error.alreadyInProgress",
               defaultValue: "This request is already in progress. Please wait.",
               comment: "Error: a long generation is already running")
    }
}

/// Serializes long, quota-consuming requests by key: rejects a second call while one with the
/// same key is still running, so a double-tap or retry doesn't double-charge the premium quota.
actor InFlightGuard {
    static let shared = InFlightGuard()

    private var keys: Set<String> = []

    func begin(_ key: String) -> Bool {
        keys.insert(key).inserted
    }

    func end(_ key: String) {
        keys.remove(key)
    }
}
