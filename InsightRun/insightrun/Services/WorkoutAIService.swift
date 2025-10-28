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

    // Backend API client (sécurisé)
    private let backendClient = BackendAPIClient.shared

    private var lastResponse = ""

    // Language detection cache (question -> language code)
    private var languageCache: [String: String] = [:]
    private let languageCacheMaxSize = 10

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
        await MainActor.run {
            self.isStreaming = true
            self.streamedResponse = ""
            self.error = nil
            self.suggestedQuestions = []
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

    // MARK: - Local Model Inference

    private func handleLocalModelInference(systemPrompt: String, question: String, locale: Locale) async {
        // Check iOS version
        guard #available(iOS 26.0, *) else {
            await MainActor.run {
                self.error = "❌ Apple Intelligence nécessite iOS 26 ou supérieur"
                self.isStreaming = false
            }
            return
        }

        guard let service = await foundationModelsService else {
            await MainActor.run {
                self.error = "❌ Service FoundationModels non disponible"
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
                    errorMsg = "❌ Cet appareil ne supporte pas Apple Intelligence"
                case .unavailable(.appleIntelligenceNotEnabled):
                    errorMsg = "⚠️ Activez Apple Intelligence dans Réglages"
                case .unavailable(.modelNotReady):
                    errorMsg = "⏳ Modèle en téléchargement, réessayez plus tard"
                default:
                    errorMsg = "❌ Modèle non disponible"
                }
            } else {
                errorMsg = "❌ Impossible de vérifier la disponibilité du modèle"
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
                self.streamedResponse = "🧠 Génération de la réponse..."
            }

            let stream = try await service.generate(prompt: question, systemPrompt: systemPrompt, locale: locale)

            // Stream chunks as they arrive
            for await chunk in stream {
                await MainActor.run {
                    // Clear "thinking" message on first chunk
                    if self.streamedResponse == "🧠 Génération de la réponse..." {
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
                self.streamedResponse = "🌐 Connexion au serveur..."
            }

            // Build payload from mode data
            let payload = buildChatPayload(question: question, model: model, mode: mode)

            // Use new API v2 with streaming
            let stream = try await backendClient.chatStreamV2(payload: payload)

            // Stream content as it arrives
            for await chunk in stream {
                await MainActor.run {
                    // Clear "connecting" message on first chunk
                    if self.streamedResponse == "🌐 Connexion au serveur..." {
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
                errorMessage = "❌ Erreur d'authentification avec le serveur"
            case .rateLimitExceeded:
                errorMessage = "⏱️ Trop de requêtes. Réessayez dans quelques minutes."
            case .serverError:
                errorMessage = "❌ Erreur serveur. Réessayez plus tard."
            case .invalidResponse:
                errorMessage = "❌ Réponse invalide du serveur"
            case .unknownError(let code):
                errorMessage = "❌ Erreur \(code). Réessayez plus tard."
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

    private func buildChatPayload(question: String, model: AIModel, mode: AIAssistantMode) -> ChatRequestV2 {
        var chatData = ChatDataPayload(
            workout: nil,
            recovery: nil,
            profile: nil,
            recentWorkouts: nil
        )

        // Extract data from mode
        switch mode {
        case .singleWorkout(let workout, let metrics):
            chatData = ChatDataPayload(
                workout: convertToWorkoutData(workout: workout, metrics: metrics),
                recovery: nil,
                profile: nil,
                recentWorkouts: nil
            )
        case .recentWorkouts(let workouts):
            let totalDistance = workouts.compactMap { $0.distance }.reduce(0, +)
            let totalDuration = workouts.map { $0.duration }.reduce(0, +)
            let totalCalories = workouts.compactMap { $0.totalEnergyBurned }.reduce(0, +)
            let avgPace = calculateAveragePace(workouts: workouts) ?? 0

            chatData = ChatDataPayload(
                workout: nil,
                recovery: nil,
                profile: nil,
                recentWorkouts: RecentWorkoutsData(
                    workouts: workouts.map { convertToWorkoutData(workout: $0, metrics: nil) },
                    totalDistance: totalDistance,
                    totalDuration: totalDuration,
                    totalCalories: totalCalories,
                    avgPace: avgPace,
                    weeklyVolumeChange: nil,
                    daysSinceLastWorkout: nil
                )
            )
        case .recoveryCoaching(let recoveryMetrics):
            chatData = ChatDataPayload(
                workout: nil,
                recovery: convertToRecoveryData(metrics: recoveryMetrics),
                profile: nil,
                recentWorkouts: nil
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
            hrv: metrics.hrv.map { Int($0) },
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
        if responseLower.contains("fréquence cardiaque") || responseLower.contains("fc") || responseLower.contains("bpm") {
            suggestions.append("Comment améliorer ma fréquence cardiaque au repos ?")
            suggestions.append("Ma fréquence cardiaque est-elle dans la bonne zone ?")
        }

        if responseLower.contains("allure") || responseLower.contains("pace") || responseLower.contains("vitesse") {
            suggestions.append("Comment améliorer mon allure ?")
            suggestions.append("Quelle allure dois-je viser pour mon prochain workout ?")
        }

        if responseLower.contains("récupération") || responseLower.contains("repos") || responseLower.contains("fatigue") {
            suggestions.append("Combien de jours de repos ai-je besoin ?")
            suggestions.append("Quels sont les signes de surmenage ?")
        }

        if responseLower.contains("progression") || responseLower.contains("amélioration") || responseLower.contains("progrès") {
            suggestions.append("Comment continuer à progresser ?")
            suggestions.append("Quel est mon prochain objectif réaliste ?")
        }

        if responseLower.contains("cadence") || responseLower.contains("foulée") {
            suggestions.append("Quelle est la cadence idéale ?")
            suggestions.append("Comment améliorer ma technique de course ?")
        }

        if responseLower.contains("dénivelé") || responseLower.contains("élévation") || responseLower.contains("côte") {
            suggestions.append("Comment m'entraîner en côte efficacement ?")
            suggestions.append("Le dénivelé améliore-t-il mes performances ?")
        }

        if responseLower.contains("vo2") || responseLower.contains("capacité aérobie") {
            suggestions.append("Comment améliorer mon VO2 Max ?")
            suggestions.append("Quel entraînement booste le VO2 Max ?")
        }

        // General follow-ups if no specific topics
        if suggestions.isEmpty {
            suggestions = [
                "Donne-moi un plan d'entraînement personnalisé",
                "Analyse ma progression sur le mois",
                "Comment éviter les blessures ?"
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
