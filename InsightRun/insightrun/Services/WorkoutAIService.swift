//
//  WorkoutAIService.swift
//  InsightRun
//
//  AI Service for workout analysis using OpenRouter API
//

import Foundation
import Combine
import FoundationModels
import NaturalLanguage

enum AIModel: String, CaseIterable, Sendable {
    case foundationModels = "local/apple-foundation-model"
    case claudeHaiku = "anthropic/claude-haiku-4.5"
    case claudeSonnet = "anthropic/claude-sonnet-4.5"
    case gpt5 = "openai/gpt-5"
    case grok4 = "x-ai/grok-4-fast"

    nonisolated var displayName: String {
        switch self {
        case .foundationModels:
            return "Apple Intelligence (Local)"
        case .claudeHaiku:
            return "Claude Haiku 4.5"
        case .claudeSonnet:
            return "Claude Sonnet 4.5"
        case .gpt5:
            return "GPT-5"
        case .grok4:
            return "Grok 4 Fast"
        }
    }

    nonisolated var modelId: String {
        return self.rawValue
    }

    nonisolated var isLocal: Bool {
        return self == .foundationModels
    }
}

class WorkoutAIService: NSObject, ObservableObject, URLSessionDataDelegate {
    @Published var isStreaming = false
    @Published var streamedResponse = ""
    @Published var error: String?
    @Published var suggestedQuestions: [String] = []
    @Published var showRetryIndexation = false

    // Backend API client (sécurisé)
    private let backendClient = BackendAPIClient.shared

    private var lastResponse = ""

    // Language detection cache (question -> language code)
    private var languageCache: [String: String] = [:]
    private let languageCacheMaxSize = 10

    // Store the last question for retry
    private var lastQuestion: String?
    private var lastMode: AIAssistantMode?
    private var lastModel: AIModel?

    @MainActor
    private var foundationModelsService: FoundationModelsService? {
        if #available(iOS 26.0, *) {
            return FoundationModelsService.shared
        }
        return nil
    }

    override init() {
        super.init()
    }

    // MARK: - Language Detection

    /// Detect the language of the question and return language code (fr, en, es, etc.)
    /// Uses cache to avoid repeated detections for similar questions
    private func detectLanguage(from text: String) -> String {
        // Check cache first (use first 50 chars as key to allow variations)
        let cacheKey = String(text.prefix(50))
        if let cached = languageCache[cacheKey] {
            print("✅ WorkoutAIService: Using cached language: \(cached)")
            return cached
        }

        let recognizer = NLLanguageRecognizer()

        // Add language hints to improve detection for short phrases
        recognizer.languageHints = [
            .french: 0.3,
            .english: 0.3,
            .spanish: 0.1,
            .german: 0.1,
            .italian: 0.1,
            .portuguese: 0.1
        ]

        recognizer.processString(text)

        guard let dominantLanguage = recognizer.dominantLanguage else {
            print("⚠️ WorkoutAIService: Language detection failed, using device language")
            let fallback = getUserLanguage()
            cacheLanguage(cacheKey, language: fallback)
            return fallback
        }

        // Map NLLanguage to language code
        let languageCode: String
        switch dominantLanguage {
        case .french:
            languageCode = "fr"
        case .english:
            languageCode = "en"
        case .spanish:
            languageCode = "es"
        case .german:
            languageCode = "de"
        case .italian:
            languageCode = "it"
        case .portuguese:
            languageCode = "pt"
        case .dutch:
            languageCode = "nl"
        case .japanese:
            languageCode = "ja"
        case .simplifiedChinese, .traditionalChinese:
            languageCode = "zh"
        case .korean:
            languageCode = "ko"
        case .arabic:
            languageCode = "ar"
        default:
            print("⚠️ WorkoutAIService: Unsupported language '\(dominantLanguage.rawValue)', using device language")
            let fallback = getUserLanguage()
            cacheLanguage(cacheKey, language: fallback)
            return fallback
        }

        print("✅ WorkoutAIService: Detected language: \(dominantLanguage.rawValue) -> \(languageCode)")
        cacheLanguage(cacheKey, language: languageCode)
        return languageCode
    }

    /// Cache the detected language with LRU eviction
    private func cacheLanguage(_ key: String, language: String) {
        languageCache[key] = language

        // Simple LRU: if cache is too large, remove oldest entries
        if languageCache.count > languageCacheMaxSize {
            let keysToRemove = languageCache.keys.prefix(languageCache.count - languageCacheMaxSize)
            keysToRemove.forEach { languageCache.removeValue(forKey: $0) }
        }
    }

    /// Detect the language of the question and return appropriate Locale (for local models)
    private func detectLocale(from text: String) -> Locale {
        let languageCode = detectLanguage(from: text)
        return Locale(identifier: languageCode)
    }

    func askQuestion(question: String, mode: AIAssistantMode, model: AIModel? = nil) async {
        // Store for retry
        lastQuestion = question
        lastMode = mode
        lastModel = model

        await MainActor.run {
            self.isStreaming = true
            self.streamedResponse = ""
            self.error = nil
            self.suggestedQuestions = []
            self.showRetryIndexation = false
        }

        // Check if summary needs refresh or generation (automatic after 3 months)
        let storage = await HistoricalSummaryStorage.shared
        let needsUpdate = await storage.needsGeneration()

        if needsUpdate {
            let existingSummary = await storage.load()
            let isRefresh = existingSummary != nil

            print(isRefresh ? "🔄 WorkoutAIService: Summary needs refresh (>3 months old)" : "📊 WorkoutAIService: No historical summary found")

            await MainActor.run {
                if isRefresh {
                    self.streamedResponse = String(localized: "🔄 Updating your athletic profile...\nYour data is being refreshed with recent workouts.", comment: "Message during profile refresh")
                } else {
                    self.streamedResponse = String(localized: "🔍 Analyzing your training history...\nThis takes 10-20 seconds.", comment: "Message during first-time historical analysis")
                }
            }

            // Generate/refresh historical summary in background
            let success = await generateHistoricalSummaryIfNeeded()

            if !success {
                // If generation failed, show error with retry button
                await MainActor.run {
                    self.streamedResponse = String(localized: "❌ Failed to analyze your training history.\nYou can still ask questions, or retry the analysis.", comment: "Error message when indexation fails")
                    self.showRetryIndexation = true
                    self.isStreaming = false
                }
                print("❌ WorkoutAIService: Historical summary generation failed, showing retry button")
                return
            } else {
                print(isRefresh ? "✅ WorkoutAIService: Historical summary refreshed successfully" : "✅ WorkoutAIService: Historical summary generated successfully")
                await MainActor.run {
                    self.streamedResponse = ""
                }
            }
        }

        // If model not provided, use intelligent routing
        let selectedModel: AIModel
        if let model = model {
            selectedModel = model
        } else {
            selectedModel = await ModelRouter.shared.selectOptimalModel(for: question, mode: mode)
        }

        print("🎯 WorkoutAIService: Using model: \(selectedModel.displayName)")

        // Route to appropriate service based on model type
        if selectedModel.isLocal {
            // For local models, use simplified prompt
            // Note: Local models don't have access to structured data context like remote models
            let localSystemPrompt = """
            You are an expert AI running coach specializing in data-driven performance optimization, injury prevention, and personalized training.

            Analyze the user's question and provide actionable insights.
            Be data-driven, concise, actionable, and use markdown formatting.
            Respond in the user's language.
            """

            // Detect locale once and cache it
            let questionLocale = detectLocale(from: question)
            await handleLocalModelInference(systemPrompt: localSystemPrompt, question: question, locale: questionLocale)
        } else {
            // For remote models, backend builds the full prompt from structured data
            await handleRemoteModelInference(question: question, model: selectedModel, mode: mode)
        }
    }

    // MARK: - Historical Summary Generation

    /// Retry indexation after failure (called from UI button)
    func retryHistoricalIndexation() async {
        print("🔄 WorkoutAIService: Retry indexation requested")

        await MainActor.run {
            self.streamedResponse = String(localized: "🔍 Retrying analysis...", comment: "Message when retrying indexation")
            self.showRetryIndexation = false
        }

        // Reset manager state
        let manager = await HistoricalIndexationManager.shared
        await MainActor.run {
            manager.resetState()
        }

        // Try again
        let success = await generateHistoricalSummaryIfNeeded()

        if !success {
            await MainActor.run {
                self.streamedResponse = String(localized: "❌ Failed to analyze your training history.\nYou can still ask questions, or retry the analysis.", comment: "Error message when indexation fails")
                self.showRetryIndexation = true
                self.isStreaming = false
            }
            print("❌ WorkoutAIService: Retry failed, showing button again")
        } else {
            print("✅ WorkoutAIService: Retry succeeded")
            await MainActor.run {
                self.streamedResponse = ""
            }

            // Continue with the original question if available
            if let question = lastQuestion, let mode = lastMode {
                await askQuestion(question: question, mode: mode, model: lastModel)
            }
        }
    }

    /// Force refresh of historical summary (for manual refresh from Settings)
    func forceRefreshHistoricalSummary() async -> Bool {
        print("🔄 WorkoutAIService: Force refresh requested")
        return await generateHistoricalSummaryIfNeeded()
    }

    /// Generate historical summary automatically (called on first message)
    private func generateHistoricalSummaryIfNeeded() async -> Bool {
        do {
            // Fetch all workouts
            let workouts = try await HealthKitManager.shared.fetchRunningWorkouts()

            guard !workouts.isEmpty else {
                print("⚠️ WorkoutAIService: No workouts found, skipping historical analysis")
                return false
            }

            print("📊 WorkoutAIService: Found \(workouts.count) workouts for analysis")

            // Convert workouts to API format (limit to 365)
            var workoutDataList: [WorkoutData] = []
            let maxWorkouts = min(workouts.count, 365)

            for workout in workouts.prefix(maxWorkouts) {
                let workoutData = convertToWorkoutDataSimple(workout: workout)
                workoutDataList.append(workoutData)
            }

            // Generate summary via backend
            let language = getUserLanguage()
            let model = "x-ai/grok-4-fast" // Fast model for historical analysis

            let response = try await backendClient.generateHistoricalSummary(
                workouts: workoutDataList,
                profile: nil, // Profile not available in this context
                model: model,
                language: language
            )

            // Save to local storage
            let summary = await MainActor.run {
                HistoricalSummary(
                    summary: response.summary,
                    workoutCount: response.workoutCount,
                    dateRangeStart: workouts.last?.startDate ?? Date(),
                    dateRangeEnd: workouts.first?.startDate ?? Date()
                )
            }

            await HistoricalSummaryStorage.shared.save(summary)
            print("✅ WorkoutAIService: Historical summary generated and saved")

            return true

        } catch {
            print("❌ WorkoutAIService: Failed to generate historical summary: \(error)")
            return false
        }
    }

    /// Convert workout to simplified API format (without metrics for bulk analysis)
    private func convertToWorkoutDataSimple(workout: WorkoutModel) -> WorkoutData {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        return WorkoutData(
            date: formatter.string(from: workout.startDate),
            duration: workout.duration,
            distance: workout.distance ?? 0,
            calories: workout.totalEnergyBurned,
            pace: workout.averagePace,
            speed: workout.averageSpeed,
            heartRate: nil,
            minPace: nil,
            cadence: nil,
            strideLength: nil,
            runningPower: nil,
            vo2Max: nil,
            elevationGain: nil,
            groundContactTime: nil,
            verticalOscillation: nil,
            mobility: nil,
            splits: nil
        )
    }

    // MARK: - Local Model Inference

    private func handleLocalModelInference(systemPrompt: String, question: String, locale: Locale) async {
        // Check iOS version
        guard #available(iOS 26.0, *) else {
            await MainActor.run {
                self.error = String(localized: "Apple Intelligence requires iOS 26 or later", comment: "Error message when Apple Intelligence is not available (iOS version)")
                self.isStreaming = false
            }
            return
        }

        guard let service = await foundationModelsService else {
            await MainActor.run {
                self.error = String(localized: "FoundationModels service is not available", comment: "Error message when FoundationModels service cannot be initialized")
                self.isStreaming = false
            }
            return
        }

        // Check model availability
        await service.checkAvailability()

        guard await service.isAvailable else {
            let errorMsg: String
            if let availability = await service.availability {
                switch availability {
                case .unavailable(.deviceNotEligible):
                    errorMsg = String(localized: "This device does not support Apple Intelligence", comment: "Error message when device is not eligible for Apple Intelligence")
                case .unavailable(.appleIntelligenceNotEnabled):
                    errorMsg = String(localized: "Enable Apple Intelligence in Settings", comment: "Error message when Apple Intelligence is not enabled")
                case .unavailable(.modelNotReady):
                    errorMsg = String(localized: "Model is downloading, please try again later", comment: "Error message when model is still downloading")
                default:
                    errorMsg = String(localized: "Model is not available", comment: "Error message when model is not available")
                }
            } else {
                errorMsg = String(localized: "Unable to check model availability", comment: "Error message when unable to check model availability")
            }

            await MainActor.run {
                self.error = errorMsg
                self.isStreaming = false
            }
            return
        }

        do {
            // Show a message while the model is thinking (before first token)
            await MainActor.run {
                self.streamedResponse = String(localized: "🧠 Generating response...", comment: "Message while local model is generating response")
            }

            let stream = try await service.generate(prompt: question, systemPrompt: systemPrompt, locale: locale)

            // Stream chunks as they arrive
            for await chunk in stream {
                await MainActor.run {
                    // Clear "thinking" message on first chunk
                    if self.streamedResponse == String(localized: "🧠 Generating response...", comment: "Message while local model is generating response") {
                        self.streamedResponse = ""
                    }

                    // Append chunk to streamed response
                    self.streamedResponse += chunk
                }
            }

            await MainActor.run {
                self.isStreaming = false
                if !self.streamedResponse.isEmpty {
                    self.lastResponse = self.streamedResponse
                    self.generateContextualSuggestions()
                }
            }

        } catch {
            print("❌ WorkoutAIService: FoundationModels error: \(error)")

            let errorMessage = "❌ Erreur: \(error.localizedDescription)"

            await MainActor.run {
                self.error = errorMessage
                self.isStreaming = false
                self.streamedResponse = ""  // Clear any "thinking" message
            }
        }
    }

    // MARK: - Remote Model Inference

    private func handleRemoteModelInference(question: String, model: AIModel, mode: AIAssistantMode) async {
        do {
            // Show a message while waiting for response
            await MainActor.run {
                self.streamedResponse = String(localized: "🌐 Connecting to server...", comment: "Message while connecting to remote server")
            }

            // Build payload from mode data
            let payload = await buildChatPayload(question: question, model: model, mode: mode)

            // Use new API v2 with streaming
            let stream = try await backendClient.chatStreamV2(payload: payload)

            // Stream content as it arrives
            for await chunk in stream {
                await MainActor.run {
                    // Clear "connecting" message on first chunk
                    if self.streamedResponse == String(localized: "🌐 Connecting to server...", comment: "Message while connecting to remote server") {
                        self.streamedResponse = ""
                    }

                    // Append chunk to streamed response
                    self.streamedResponse += chunk
                }
            }

            await MainActor.run {
                self.isStreaming = false
                if !self.streamedResponse.isEmpty {
                    self.lastResponse = self.streamedResponse
                    self.generateContextualSuggestions()
                }
            }

        } catch let error as BackendError {
            print("❌ WorkoutAIService: Backend error: \(error)")

            let errorMessage: String
            switch error {
            case .unauthorized:
                errorMessage = String(localized: "Authentication error with server", comment: "Error message for authentication failures")
            case .rateLimitExceeded:
                errorMessage = String(localized: "Too many requests. Try again in a few minutes.", comment: "Error message for rate limit exceeded")
            case .serverError:
                errorMessage = String(localized: "Server error. Try again later.", comment: "Error message for server errors")
            case .invalidResponse:
                errorMessage = String(localized: "Invalid response from server", comment: "Error message for invalid server responses")
            case .unknownError(let code):
                errorMessage = String(localized: "Error %@. Try again later.", comment: "Generic error message with error code").replacingOccurrences(of: "%@", with: String(code))
            }

            await MainActor.run {
                self.error = errorMessage
                self.isStreaming = false
                self.streamedResponse = ""
            }

        } catch {
            print("❌ WorkoutAIService: Unexpected error: \(error)")

            await MainActor.run {
                self.error = "❌ Erreur: \(error.localizedDescription)"
                self.isStreaming = false
                self.streamedResponse = ""
            }
        }
    }

    // MARK: - Payload Builder

    private func getUserLanguage() -> String {
        // Get user's preferred language
        let preferredLanguage = Locale.current.language.languageCode?.identifier ?? "en"

        // Map to supported language codes
        let supportedLanguages = ["fr", "en", "es", "de", "it", "pt", "nl", "ja", "zh", "ko", "ar"]
        return supportedLanguages.contains(preferredLanguage) ? preferredLanguage : "en"
    }

    private func buildChatPayload(question: String, model: AIModel, mode: AIAssistantMode) async -> ChatRequestV2 {
        // Load historical summary if available
        let historicalSummary = await HistoricalSummaryStorage.shared.load()?.summary

        if let summary = historicalSummary {
            print("✅ WorkoutAIService: Using historical summary (\(summary.count) chars)")
        }

        var chatData = ChatDataPayload(
            workout: nil,
            recovery: nil,
            profile: nil,
            recentWorkouts: nil,
            historicalSummary: historicalSummary
        )

        // Extract data from mode
        switch mode {
        case .singleWorkout(let workout, let metrics):
            chatData = ChatDataPayload(
                workout: convertToWorkoutData(workout: workout, metrics: metrics),
                recovery: nil,
                profile: nil,
                recentWorkouts: nil,
                historicalSummary: historicalSummary
            )
        case .recentWorkouts(let workouts, let metricsDict):
            let totalDistance = workouts.compactMap { $0.distance }.reduce(0, +)
            let totalDuration = workouts.map { $0.duration }.reduce(0, +)
            let totalCalories = workouts.compactMap { $0.totalEnergyBurned }.reduce(0, +)
            let avgPace = calculateAveragePace(workouts: workouts) ?? 0

            chatData = ChatDataPayload(
                workout: nil,
                recovery: nil,
                profile: nil,
                recentWorkouts: RecentWorkoutsData(
                    workouts: workouts.map { workout in
                        let metrics = metricsDict[workout.id]
                        return convertToWorkoutData(workout: workout, metrics: metrics)
                    },
                    totalDistance: totalDistance,
                    totalDuration: totalDuration,
                    totalCalories: totalCalories,
                    avgPace: avgPace,
                    weeklyVolumeChange: nil,
                    daysSinceLastWorkout: nil
                ),
                historicalSummary: historicalSummary
            )
        case .recoveryCoaching(let recoveryMetrics):
            chatData = ChatDataPayload(
                workout: nil,
                recovery: convertToRecoveryData(metrics: recoveryMetrics),
                profile: nil,
                recentWorkouts: nil,
                historicalSummary: historicalSummary
            )
        }

        // Detect language from the question (priority), fallback to device language
        let detectedLanguage = detectLanguage(from: question)

        return ChatRequestV2(
            promptType: "workout_coach",
            model: model.modelId,
            userQuestion: question,
            language: detectedLanguage,
            data: chatData
        )
    }

    private func convertToWorkoutData(workout: WorkoutModel, metrics: WorkoutMetrics?) -> WorkoutData {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        return WorkoutData(
            date: formatter.string(from: workout.startDate),
            duration: workout.duration,
            distance: workout.distance ?? 0,
            calories: workout.totalEnergyBurned,
            pace: workout.averagePace,
            speed: workout.averageSpeed,
            heartRate: metrics?.averageHeartRate != nil ? HeartRateData(
                avg: metrics?.averageHeartRate.map { Int($0) },
                min: metrics?.minHeartRate.map { Int($0) },
                max: metrics?.maxHeartRate.map { Int($0) }
            ) : nil,
            minPace: metrics?.minPace,
            cadence: metrics?.averageCadence.map { Int($0) },
            strideLength: metrics?.strideLength,
            runningPower: metrics?.runningPower.map { Int($0) },
            vo2Max: metrics?.vo2Max,
            elevationGain: metrics?.totalElevationAscent,
            groundContactTime: metrics?.groundContactTime.map { Int($0) },
            verticalOscillation: metrics?.verticalOscillation,
            mobility: metrics != nil && (
                metrics?.walkingSteadiness != nil ||
                metrics?.walkingAsymmetry != nil ||
                metrics?.doubleSupportPercentage != nil ||
                metrics?.walkingSpeed != nil ||
                metrics?.stairAscentSpeed != nil ||
                metrics?.stairDescentSpeed != nil
            ) ? MobilityData(
                walkingSteadiness: metrics?.walkingSteadiness,
                walkingAsymmetry: metrics?.walkingAsymmetry,
                doubleSupportPercentage: metrics?.doubleSupportPercentage,
                walkingSpeed: metrics?.walkingSpeed,
                stairAscentSpeed: metrics?.stairAscentSpeed,
                stairDescentSpeed: metrics?.stairDescentSpeed
            ) : nil,
            splits: metrics?.splits?.prefix(10).map { split in
                SplitData(
                    kilometer: split.kilometer,
                    pace: split.paceFormatted,
                    time: split.timeFormatted
                )
            }
        )
    }

    private func convertToRecoveryData(metrics: RecoveryMetrics) -> RecoveryData {
        return RecoveryData(
            restingHeartRate: metrics.restingHeartRate.map { Int($0) },
            hrv: metrics.hrvAverage.map { Int($0) },
            walkingHeartRate: metrics.walkingHeartRate.map { Int($0) },
            respiratoryRate: metrics.respiratoryRate.map { Int($0) },
            sleepData: metrics.sleepData != nil ? SleepDataPayload(
                totalDuration: metrics.sleepData!.totalSleepDuration,
                efficiency: Int(metrics.sleepData!.sleepEfficiency),
                deepDuration: metrics.sleepData?.deepSleepDuration,
                remDuration: metrics.sleepData?.remSleepDuration
            ) : nil
        )
    }

    // MARK: - Contextual Suggestions

    private func generateContextualSuggestions() {
        var suggestions: [String] = []

        let responseLower = lastResponse.lowercased()

        // Detect topics in the response and suggest related questions
        // Heart rate topics
        if responseLower.contains("fréquence cardiaque") || responseLower.contains("fc") || responseLower.contains("bpm") ||
           responseLower.contains("heart rate") || responseLower.contains("hr") {
            suggestions.append(String(localized: "How to improve my resting heart rate?", comment: "AI suggested question about improving resting heart rate"))
            suggestions.append(String(localized: "Is my heart rate in the right zone?", comment: "AI suggested question about heart rate zones"))
        }

        // Pace/speed topics
        if responseLower.contains("allure") || responseLower.contains("pace") || responseLower.contains("vitesse") || responseLower.contains("speed") {
            suggestions.append(String(localized: "How to improve my pace?", comment: "AI suggested question about improving pace"))
            suggestions.append(String(localized: "What pace should I target for my next workout?", comment: "AI suggested question about target pace"))
        }

        // Recovery topics
        if responseLower.contains("récupération") || responseLower.contains("repos") || responseLower.contains("fatigue") ||
           responseLower.contains("recovery") || responseLower.contains("rest") {
            suggestions.append(String(localized: "How many rest days do I need?", comment: "AI suggested question about rest days"))
            suggestions.append(String(localized: "What are the signs of overtraining?", comment: "AI suggested question about overtraining signs"))
        }

        // Progression topics
        if responseLower.contains("progression") || responseLower.contains("amélioration") || responseLower.contains("progrès") ||
           responseLower.contains("improvement") || responseLower.contains("progress") {
            suggestions.append(String(localized: "How to keep improving?", comment: "AI suggested question about continuing improvement"))
            suggestions.append(String(localized: "What's my next realistic goal?", comment: "AI suggested question about next goal"))
        }

        // Cadence topics
        if responseLower.contains("cadence") || responseLower.contains("foulée") || responseLower.contains("stride") {
            suggestions.append(String(localized: "What's the ideal cadence?", comment: "AI suggested question about ideal cadence"))
            suggestions.append(String(localized: "How to improve my running form?", comment: "AI suggested question about running form"))
        }

        // Elevation topics
        if responseLower.contains("dénivelé") || responseLower.contains("élévation") || responseLower.contains("côte") ||
           responseLower.contains("elevation") || responseLower.contains("hill") {
            suggestions.append(String(localized: "How to train on hills effectively?", comment: "AI suggested question about hill training"))
            suggestions.append(String(localized: "Does elevation improve performance?", comment: "AI suggested question about elevation benefits"))
        }

        // VO2 Max topics
        if responseLower.contains("vo2") || responseLower.contains("capacité aérobie") || responseLower.contains("aerobic capacity") {
            suggestions.append(String(localized: "How to improve my VO2 Max?", comment: "AI suggested question about improving VO2 Max"))
            suggestions.append(String(localized: "What training boosts VO2 Max?", comment: "AI suggested question about VO2 Max training"))
        }

        // General follow-ups if no specific topics
        if suggestions.isEmpty {
            suggestions = [
                String(localized: "Give me a personalized training plan", comment: "AI suggested question about personalized plan"),
                String(localized: "Analyze my progress this month", comment: "AI suggested question about monthly progress"),
                String(localized: "How to avoid injuries?", comment: "AI suggested question about injury prevention")
            ]
        }

        // Limit to 3 suggestions
        suggestedQuestions = Array(suggestions.prefix(3))
    }

    // MARK: - Helper Functions

    /// Calculate average pace across multiple workouts
    private func calculateAveragePace(workouts: [WorkoutModel]) -> Double? {
        let paces = workouts.compactMap { $0.averagePace }
        guard !paces.isEmpty else { return nil }
        return paces.reduce(0, +) / Double(paces.count)
    }
}
