//
//  WorkoutAIService.swift
//  InsightRun
//
//  AI Service for workout analysis using OpenRouter API
//

import Foundation
import Combine
import NaturalLanguage
import HealthKit

class WorkoutAIService: NSObject, ObservableObject, URLSessionDataDelegate {
    @Published var isStreaming = false
    @Published var streamedResponse = ""
    @Published var error: String?
    @Published var suggestedQuestions: [String] = []
    @Published var lastFunctionResult: BackendAPIClient.AgentFunctionResult?
    @Published var needsConsent = false
    @Published var needsIndexation = false

    // Backend API client (sécurisé)
    private let backendClient = BackendAPIClient.shared

    private var lastResponse = ""

    // Language detection cache (question -> language code)
    private var languageCache: [String: String] = [:]
    private let languageCacheMaxSize = 10

    // Store the last question for retry
    private var lastQuestion: String?
    private var lastMode: AIAssistantMode?

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

    func askQuestion(question: String, mode: AIAssistantMode, language: String? = nil) async {
        // Check AI consent (Apple 5.1.1 compliance)
        guard await MainActor.run(body: { ConsentService.shared.hasConsentedToAIDataSharing }) else {
            await MainActor.run {
                self.needsConsent = true
                self.error = String(localized: "AI consent is required to analyze your workouts.", comment: "Error when AI consent is missing")
            }
            return
        }

        // Check historical indexation (required for personalized AI)
        if await HistoricalSummaryStorage.shared.requiresIndexation() {
            await MainActor.run { self.needsIndexation = true }
            return
        }

        // Store for retry
        lastQuestion = question
        lastMode = mode

        await MainActor.run {
            self.isStreaming = true
            self.streamedResponse = ""
            self.error = nil
            self.suggestedQuestions = []
            self.lastFunctionResult = nil
        }

        // Use ModelRouter to classify complexity and get RequestType
        let requestType = await ModelRouter.shared.selectRequestType(for: question, mode: mode)
        print("🎯 WorkoutAIService: Using requestType: \(requestType.rawValue) → Backend will select appropriate model")

        // Backend builds the full prompt from structured data and selects the model
        await handleRemoteModelInference(question: question, requestType: requestType, mode: mode, language: language)
    }

    // MARK: - Remote Model Inference

    private func handleRemoteModelInference(question: String, requestType: RequestType, mode: AIAssistantMode, language: String? = nil) async {
        do {
            let payload = await buildAgentPayload(question: question, mode: mode, languageOverride: language)
            let stream = try await backendClient.agentChatStream(payload: payload)

            for try await event in stream {
                await MainActor.run {
                    switch event {
                    case .content(let chunk):
                        self.streamedResponse += chunk

                    case .functionResult(let result):
                        self.lastFunctionResult = result
                    }
                }
            }

            await MainActor.run {
                self.isStreaming = false
                if !self.streamedResponse.isEmpty || self.lastFunctionResult != nil {
                    self.lastResponse = self.streamedResponse
                    self.generateContextualSuggestions()
                    RevenueCatManager.shared.incrementFreeRequestCount()
                }
            }

        } catch let error as BackendError {
            print("❌ WorkoutAIService: Backend error: \(error)")

            let errorMessage: String
            switch error {
            case .unauthorized:
                errorMessage = String(localized: "Authentication error with server", comment: "Error message for authentication failures")
            case .blocked:
                errorMessage = String(localized: "Your account has been blocked. Please contact support.", comment: "Error message for blocked users")
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
                self.error = String(localized: "❌ Error: \(error.localizedDescription)", comment: "AI service error message")
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

    private func buildAgentPayload(question: String, mode: AIAssistantMode, languageOverride: String? = nil) async -> AgentChatRequest {
        let chatPayload = await buildChatPayload(question: question, requestType: .complex, mode: mode)
        let detectedLanguage = languageOverride ?? detectLanguage(from: question)

        return AgentChatRequest(
            userQuestion: question,
            language: detectedLanguage,
            data: chatPayload.data,
            conversationHistory: nil
        )
    }

    private func buildChatPayload(question: String, requestType: RequestType, mode: AIAssistantMode) async -> ChatRequestV2 {
        // Load historical summary if available
        let historicalSummary = await HistoricalSummaryStorage.shared.load()

        if let summary = historicalSummary {
            print("✅ WorkoutAIService: Using historical summary (\(summary.workoutCount) workouts)")
            print("📊 WorkoutAIService: Summary covers \(summary.dateRangeFormatted)")
        } else {
            print("⚠️ WorkoutAIService: No historical summary available")

            // Track AI message sent without historical context
            let contextType: AIContextType = {
                switch mode {
                case .singleWorkout, .recentWorkouts:
                    return .workout
                case .recoveryCoaching:
                    return .recovery
                case .unified:
                    return .workout // Unified mode covers all contexts
                }
            }()
            await MainActor.run {
                AnalyticsService.shared.trackAIMessageSentWithoutContext(contextType: contextType)
            }
        }

        // Load health profile for personalized coaching
        let healthProfile = await loadHealthProfile()
        if healthProfile != nil {
            print("✅ WorkoutAIService: Health profile loaded")
        }

        // Load personal baseline for deviation-based analysis
        let personalBaseline = loadPersonalBaseline()
        if let baseline = personalBaseline {
            print("✅ WorkoutAIService: Personal baseline loaded (\(baseline.dataPointCount) days, reliable: \(baseline.isReliable))")
        }

        var chatData = ChatDataPayload(
            workout: nil,
            recovery: nil,
            profile: healthProfile,
            baseline: personalBaseline,
            recentWorkouts: nil,
            historicalSummary: historicalSummary?.summary
        )

        // Extract data from mode (always keep profile and baseline)
        switch mode {
        case .singleWorkout(let workout, let metrics):
            chatData = ChatDataPayload(
                workout: convertToWorkoutData(workout: workout, metrics: metrics),
                recovery: nil,
                profile: healthProfile,
                baseline: personalBaseline,
                recentWorkouts: nil,
                historicalSummary: historicalSummary?.summary
            )
        case .recentWorkouts(let workouts, let metricsDict):
            // ✅ OPTIMIZATION: Limit to 10 most recent workouts
            let recentWorkouts = Array(workouts.prefix(10))

            // Calculate stats on recent workouts only
            let totalDistance = recentWorkouts.compactMap { $0.distance }.reduce(0, +)
            let totalDuration = recentWorkouts.map { $0.duration }.reduce(0, +)
            let totalCalories = recentWorkouts.compactMap { $0.totalEnergyBurned }.reduce(0, +)
            let avgPace = recentWorkouts.averagePace ?? 0

            print("📊 WorkoutAIService: Sending \(recentWorkouts.count) recent workouts + historical context")
            if let summary = historicalSummary {
                print("📈 WorkoutAIService: Historical context covers \(summary.workoutCount - recentWorkouts.count) older workouts")
            }

            chatData = ChatDataPayload(
                workout: nil,
                recovery: nil,
                profile: healthProfile,
                baseline: personalBaseline,
                recentWorkouts: RecentWorkoutsData(
                    workouts: recentWorkouts.map { workout in
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
                historicalSummary: historicalSummary?.summary
            )
        case .recoveryCoaching(let recoveryMetrics):
            chatData = ChatDataPayload(
                workout: nil,
                recovery: convertToRecoveryData(metrics: recoveryMetrics),
                profile: healthProfile,
                baseline: personalBaseline,
                recentWorkouts: nil,
                historicalSummary: historicalSummary?.summary
            )
        case .unified:
            // Unified mode - load all data from UnifiedAIContextProvider
            let (workouts, metricsDict, recoveryMetrics, selectedWorkout, selectedMetrics) = await MainActor.run {
                let cp = UnifiedAIContextProvider.shared
                return (cp.recentWorkouts, cp.workoutsMetrics, cp.recoveryMetrics, cp.selectedWorkout, cp.selectedWorkoutMetrics)
            }

            print("📊 WorkoutAIService: Unified mode - \(workouts.count) workouts, recovery: \(recoveryMetrics != nil)")

            // Build recovery data if available
            var recoveryData: RecoveryData? = nil
            if let recovery = recoveryMetrics {
                recoveryData = convertToRecoveryData(metrics: recovery)
            }

            // Build workouts data
            var recentWorkoutsData: RecentWorkoutsData? = nil
            if !workouts.isEmpty {
                let totalDistance = workouts.compactMap { $0.distance }.reduce(0, +)
                let totalDuration = workouts.map { $0.duration }.reduce(0, +)
                let totalCalories = workouts.compactMap { $0.totalEnergyBurned }.reduce(0, +)
                let avgPace = workouts.averagePace ?? 0

                recentWorkoutsData = RecentWorkoutsData(
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
                )
            }

            // Build selected workout data if viewing workout detail
            var selectedWorkoutData: WorkoutData? = nil
            if let workout = selectedWorkout {
                selectedWorkoutData = convertToWorkoutData(workout: workout, metrics: selectedMetrics)
            }

            chatData = ChatDataPayload(
                workout: selectedWorkoutData,
                recovery: recoveryData,
                profile: healthProfile,
                baseline: personalBaseline,
                recentWorkouts: recentWorkoutsData,
                historicalSummary: historicalSummary?.summary
            )
        }

        // Detect language from the question (priority), fallback to device language
        let detectedLanguage = detectLanguage(from: question)

        return ChatRequestV2(
            promptType: "workout_coach",
            requestType: requestType.rawValue,
            model: nil, // Backend will select model based on requestType
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


    // MARK: - Profile & Baseline Loading

    /// Load health profile from HealthKit for personalized coaching
    private func loadHealthProfile() async -> HealthProfileData? {
        do {
            let profile = try await MainActor.run {
                HealthKitManager.shared
            }.fetchHealthProfile()

            return HealthProfileData(
                age: profile.age,
                sex: profile.biologicalSex?.rawValue == 1 ? "Female" : profile.biologicalSex?.rawValue == 2 ? "Male" : nil,
                bodyMass: profile.bodyMass,
                bodyFatPercentage: profile.bodyFatPercentage,
                exerciseTime: profile.exerciseTime.map { Int($0) },
                cyclingDistance: profile.cyclingDistance,
                swimmingDistance: profile.swimmingDistance
            )
        } catch {
            print("⚠️ WorkoutAIService: Failed to load health profile: \(error)")
            return nil
        }
    }

    /// Load personal baseline from storage for deviation-based analysis
    private func loadPersonalBaseline() -> PersonalBaselineData? {
        guard let baseline = PersonalBaselineStorage.shared.load() else {
            return nil
        }

        return PersonalBaselineData(
            restingHeartRateAverage: baseline.restingHeartRateAverage,
            restingHeartRateStdDev: baseline.restingHeartRateStdDev,
            hrvAverage: baseline.hrvAverage,
            hrvStdDev: baseline.hrvStdDev,
            sleepDurationAverage: baseline.sleepDurationAverage,
            sleepEfficiencyAverage: baseline.sleepEfficiencyAverage,
            respiratoryRateAverage: baseline.respiratoryRateAverage,
            respiratoryRateStdDev: baseline.respiratoryRateStdDev,
            dataPointCount: baseline.dataPointCount,
            isReliable: baseline.isReliable
        )
    }
}
