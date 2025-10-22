//
//  WorkoutAIService.swift
//  HealthApp
//
//  AI Service for workout analysis using OpenRouter API
//

import Foundation
import Combine
import FoundationModels

enum AIModel: String, CaseIterable, Sendable {
    case foundationModels = "local/apple-foundation-model"
    case claudeSonnet = "anthropic/claude-sonnet-4.5"
    case gpt5 = "openai/gpt-5"
    case grok4 = "x-ai/grok-4-fast"

    nonisolated var displayName: String {
        switch self {
        case .foundationModels:
            return "Apple Intelligence (Local)"
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
    private var currentContext = ""

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

    func askQuestion(about workoutContext: String, question: String, model: AIModel) async {
        await MainActor.run {
            self.isStreaming = true
            self.streamedResponse = ""
            self.error = nil
            self.currentContext = workoutContext
            self.suggestedQuestions = []
        }

        let systemPrompt = """
        You are an expert AI running coach specializing in data-driven performance optimization, injury prevention, and personalized training.

        # Your Core Mission
        Analyze comprehensive health and workout data to provide actionable insights that help runners:
        1. **Optimize Performance**: Identify training patterns and suggest improvements
        2. **Prevent Injuries**: Detect early warning signs of overtraining or biomechanical issues
        3. **Maximize Recovery**: Balance training load with adequate recovery
        4. **Track Progress**: Highlight improvements and areas for development

        # Available Data Context
        \(workoutContext)

        # Analysis Framework

        ## 1. Readiness Score (0-100)
        When asked about readiness or daily recommendations, calculate a score based on:
        - **Sleep Quality** (7-9h = optimal, <6h = red flag)
        - **Resting Heart Rate** (lower = better recovery, +5-10 bpm above baseline = warning)
        - **HRV (Heart Rate Variability)** (higher = better, <30ms = fatigue)
        - **Training Load** (days since last hard workout, cumulative weekly volume)
        - **Soreness/Pain** (if mentioned by user)

        **Score Interpretation:**
        - 85-100 ✅ "Perfect for intense training" - Long run, intervals, tempo
        - 70-84 🟡 "Good for moderate training" - Easy run, steady pace
        - 50-69 ⚠️ "Recovery recommended" - Light jog or cross-training
        - <50 🛑 "Rest required" - Complete rest or active recovery only

        ## 2. Injury Prevention Signals
        Actively monitor and alert on:
        - **Volume Increase**: >10% weekly mileage increase = injury risk
        - **Pace Drop**: Consistent slowdown without explanation
        - **HR Elevation**: Elevated heart rate at same pace
        - **Cadence Drop**: Significant decrease may indicate fatigue
        - **Asymmetry**: Ground contact time imbalance (if available)
        - **Repeated Pain**: User mentions same area multiple times

        **Alert Format:**
        ```
        ⚠️ INJURY RISK DETECTED
        Pattern: [describe the concerning trend]
        Risk Level: [Low/Medium/High]

        Recommended Actions:
        1. [immediate action]
        2. [preventive measure]
        3. [when to see a professional]
        ```

        ## 3. Training Recommendations
        Base your advice on:
        - **Current Fitness Level**: Analyze pace, HR zones, VO2 max
        - **Training History**: Recent workouts, frequency, intensity
        - **Recovery Status**: Sleep, RHR, HRV trends
        - **Goals**: Infer or ask about race targets

        Suggest:
        - Optimal training pace zones
        - Weekly structure (hard/easy days)
        - Cross-training opportunities
        - Rest day timing

        ## 4. Performance Metrics Analysis
        Focus on key indicators:
        - **Pace Progression**: Are they getting faster over time?
        - **Heart Rate Efficiency**: Lower HR at same pace = improved fitness
        - **Splits Consistency**: Even pacing = good energy management
        - **Cadence**: Optimal is 170-180 spm for most runners
        - **VO2 Max Trends**: Track cardiovascular fitness improvements

        ## 5. Recovery Optimization
        Evaluate:
        - Sleep quantity and quality (efficiency %)
        - Time between hard workouts
        - Active recovery activities
        - Nutrition cues (if mentioned)

        # Response Guidelines

        1. **Be Data-Driven**: Always cite specific metrics
        2. **Be Concise**: Bullet points > long paragraphs
        3. **Be Actionable**: Every insight = specific next step
        4. **Be Honest**: Don't sugarcoat risks or overtraining signs
        5. **Use Markdown**: Make it scannable (bold, lists, emojis)
        6. **Proactive Alerts**: Flag concerns even if not asked

        # Response Structure

        For general questions, organize as:
        ```
        ## 📊 Key Insights
        [2-3 bullet points of most important findings]

        ## 💡 Recommendations
        [Specific, actionable advice]

        ## ⚠️ Watch Out For
        [Any concerns or patterns to monitor]

        ## 🎯 Next Steps
        [What to do next]
        ```

        # Special Cases

        **If insufficient data**: Ask specific questions to fill gaps
        **If overtraining detected**: Be firm about rest requirements
        **If improvement shown**: Celebrate and explain the why
        **If inconsistent training**: Suggest sustainable routine

        # Tone
        - Professional but friendly
        - Motivating without being pushy
        - Evidence-based, not generic advice
        - Transparent about limitations

        Now analyze the data and respond to the user's question with expertise and precision.
        """

        // Route to appropriate service based on model type
        if model.isLocal {
            await handleLocalModelInference(systemPrompt: systemPrompt, question: question)
        } else {
            await handleRemoteModelInference(systemPrompt: systemPrompt, question: question, model: model)
        }
    }

    // MARK: - Local Model Inference

    private func handleLocalModelInference(systemPrompt: String, question: String) async {
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

            let stream = try await service.generate(prompt: question, systemPrompt: systemPrompt)

            // Clear the "thinking" message when first chunk arrives
            await MainActor.run {
                self.streamedResponse = ""  // Clear "thinking" message before streaming
            }

            for await chunk in stream {
                await MainActor.run {
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

    private func handleRemoteModelInference(systemPrompt: String, question: String, model: AIModel) async {
        do {
            // Show a message while waiting for response
            await MainActor.run {
                self.streamedResponse = "🌐 Connexion au serveur..."
            }

            // Use real streaming from backend
            let stream = try await backendClient.chatStream(
                prompt: question,
                systemPrompt: systemPrompt,
                model: model.modelId
            )

            // Clear connecting message when first chunk arrives
            var isFirstChunk = true

            // Stream content as it arrives
            for await chunk in stream {
                await MainActor.run {
                    if isFirstChunk {
                        self.streamedResponse = "" // Clear "connecting" message
                        isFirstChunk = false
                    }
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

    // MARK: - Context Generation

    func generateSingleWorkoutContext(workout: WorkoutModel, metrics: WorkoutMetrics?) -> String {
        var context = "Single Workout Analysis:\n"
        context += "Date: \(formatDate(workout.startDate))\n"
        context += "Duration: \(workout.durationFormatted)\n"
        context += "Distance: \(workout.distanceFormatted)\n"

        if let calories = workout.totalEnergyBurned {
            context += "Calories: \(Int(calories)) kcal\n"
        }

        if let pace = workout.averagePace {
            context += "Average Pace: \(formatPace(pace))\n"
        }

        if let speed = workout.averageSpeed {
            context += "Average Speed: \(String(format: "%.1f km/h", speed))\n"
        }

        if let metrics = metrics {
            context += "\nDetailed Metrics:\n"

            if let avgHR = metrics.averageHeartRate {
                context += "- Heart Rate: Avg \(Int(avgHR)) bpm"
                if let minHR = metrics.minHeartRate, let maxHR = metrics.maxHeartRate {
                    context += " (Range: \(Int(minHR))-\(Int(maxHR)) bpm)"
                }
                context += "\n"
            }

            if let minPace = metrics.minPace {
                context += "- Best Pace: \(formatPace(minPace))\n"
            }

            if let cadence = metrics.averageCadence {
                context += "- Cadence: \(Int(cadence)) spm\n"
            }

            if let stride = metrics.strideLength {
                context += "- Stride Length: \(String(format: "%.2f m", stride))\n"
            }

            if let power = metrics.runningPower {
                context += "- Running Power: \(Int(power)) W\n"
            }

            if let vo2Max = metrics.vo2Max {
                context += "- VO2 Max: \(String(format: "%.1f ml/kg/min", vo2Max))\n"
            }

            if let ascent = metrics.totalElevationAscent {
                context += "- Elevation Gain: \(Int(ascent)) m\n"
            }

            if let splits = metrics.splits, !splits.isEmpty {
                context += "\nSplits (per km):\n"
                for split in splits.prefix(10) {
                    context += "  km \(split.kilometer): \(split.paceFormatted) (\(split.timeFormatted))\n"
                }
            }
        }

        return context
    }

    func generateRecentWorkoutsContext(workouts: [WorkoutModel]) -> String {
        var context = "Recent Workouts Summary (Last \(workouts.count) runs):\n\n"

        let totalDistance = workouts.compactMap { $0.distance }.reduce(0, +)
        let totalDuration = workouts.map { $0.duration }.reduce(0, +)
        let totalCalories = workouts.compactMap { $0.totalEnergyBurned }.reduce(0, +)
        let avgPace = workouts.compactMap { $0.averagePace }.reduce(0, +) / Double(workouts.filter { $0.averagePace != nil }.count)

        context += "Overall Statistics:\n"
        context += "- Total Distance: \(String(format: "%.2f km", totalDistance / 1000.0))\n"
        context += "- Total Time: \(formatDuration(totalDuration))\n"
        context += "- Total Calories: \(Int(totalCalories)) kcal\n"
        context += "- Average Pace: \(formatPace(avgPace))\n"
        context += "- Workouts: \(workouts.count)\n\n"

        context += "Individual Workouts:\n"
        for (index, workout) in workouts.prefix(10).enumerated() {
            context += "\n\(index + 1). \(formatDate(workout.startDate))\n"
            context += "   Distance: \(workout.distanceFormatted), "
            context += "Duration: \(workout.durationFormatted), "
            if let pace = workout.averagePace {
                context += "Pace: \(formatPace(pace))"
            }
            context += "\n"
        }

        return context
    }

    func generateRecoveryCoachingContext(metrics: RecoveryMetrics) -> String {
        let recoveryService = RecoveryCoachingService.shared
        return recoveryService.generateRecoveryContext(metrics: metrics)
    }

    /// Generate comprehensive context including recovery metrics and training history
    func generateEnhancedContext(
        recentWorkouts: [WorkoutModel],
        recoveryMetrics: RecoveryMetrics?,
        healthProfile: HealthProfile?
    ) -> String {
        var context = ""

        // 1. Recovery Status (Most Important)
        if let recovery = recoveryMetrics {
            let insight = RecoveryCoachingService.shared.analyzeRecovery(metrics: recovery)
            context += """

            # 🏃 Readiness Status
            **Score: \(insight.readinessScore)/100** \(insight.status.emoji)

            """

            if let rhr = recovery.restingHeartRate {
                context += "- Resting HR: \(Int(rhr)) bpm\n"
            }
            if let hrv = recovery.hrv {
                context += "- HRV: \(Int(hrv)) ms (SDNN)\n"
            }
            if let sleep = recovery.sleepData {
                let hours = sleep.totalSleepDuration / 3600
                context += "- Sleep: \(String(format: "%.1fh", hours)) (efficiency: \(Int(sleep.sleepEfficiency))%)\n"
                if let deep = sleep.deepSleepDuration, let rem = sleep.remSleepDuration {
                    let deepHours = deep / 3600
                    let remHours = rem / 3600
                    context += "  - Deep: \(String(format: "%.1fh", deepHours)), REM: \(String(format: "%.1fh", remHours))\n"
                }
            }
            context += "\n**Status**: \(insight.message)\n\n"
        }

        // 2. Recent Training History
        if !recentWorkouts.isEmpty {
            context += "# 📅 Recent Training History (Last \(min(recentWorkouts.count, 7)) runs)\n\n"

            let totalDistance = recentWorkouts.prefix(7).compactMap { $0.distance }.reduce(0, +)
            let totalDuration = recentWorkouts.prefix(7).map { $0.duration }.reduce(0, +)
            let avgWorkoutsPerWeek = Double(recentWorkouts.prefix(7).count)

            context += "**Weekly Summary:**\n"
            context += "- Total Volume: \(String(format: "%.1f km", totalDistance / 1000))\n"
            context += "- Total Time: \(formatDuration(totalDuration))\n"
            context += "- Frequency: \(Int(avgWorkoutsPerWeek)) runs/week\n"

            if let avgPace = calculateAveragePace(workouts: Array(recentWorkouts.prefix(7))) {
                context += "- Average Pace: \(formatPace(avgPace))\n"
            }

            // Calculate training load trend
            if recentWorkouts.count >= 14 {
                let lastWeekDistance = recentWorkouts.prefix(7).compactMap { $0.distance }.reduce(0, +)
                let previousWeekDistance = recentWorkouts.dropFirst(7).prefix(7).compactMap { $0.distance }.reduce(0, +)

                if previousWeekDistance > 0 {
                    let changePercent = ((lastWeekDistance - previousWeekDistance) / previousWeekDistance) * 100
                    if changePercent > 10 {
                        context += "\n⚠️ **Training Load Alert**: Volume increased by \(String(format: "%.1f%%", changePercent)) - high injury risk!\n"
                    } else if changePercent > 0 {
                        context += "\n✅ Volume increased by \(String(format: "%.1f%%", changePercent)) (safe progression)\n"
                    }
                }
            }

            // Days since last workout
            if let lastWorkout = recentWorkouts.first {
                let daysSince = Calendar.current.dateComponents([.day], from: lastWorkout.startDate, to: Date()).day ?? 0
                context += "\n**Time Since Last Run**: \(daysSince) day(s) ago"
                if daysSince > 3 {
                    context += " ⚠️ (extended break)\n"
                } else {
                    context += "\n"
                }
            }

            context += "\n**Recent Workouts Detail:**\n"
            for (index, workout) in recentWorkouts.prefix(5).enumerated() {
                let daysAgo = Calendar.current.dateComponents([.day], from: workout.startDate, to: Date()).day ?? 0
                context += "\n\(index + 1). \(daysAgo) day(s) ago: "
                context += "\(workout.distanceFormatted) in \(workout.durationFormatted)"
                if let pace = workout.averagePace {
                    context += " @ \(formatPace(pace))"
                }
                if let hr = workout.totalEnergyBurned {
                    context += ", \(Int(hr)) kcal"
                }
            }
            context += "\n\n"
        }

        // 3. Health Profile
        if let profile = healthProfile {
            context += "# 👤 Health Profile\n\n"

            if let age = profile.age {
                context += "- Age: \(age) years\n"
            }
            if let sex = profile.biologicalSex {
                context += "- Sex: \(profile.biologicalSexString)\n"
            }
            if let mass = profile.bodyMass {
                context += "- Weight: \(String(format: "%.1f kg", mass))\n"
            }
            if let bodyFat = profile.bodyFatPercentage {
                context += "- Body Fat: \(String(format: "%.1f%%", bodyFat))\n"
            }

            // Activity metrics
            if let exercise = profile.exerciseTime {
                context += "- Today's Exercise: \(Int(exercise)) min\n"
            }

            // Cross-training
            var hasCrossTraining = false
            if let cycling = profile.cyclingDistance, cycling > 0 {
                context += "- Cycling (7d): \(String(format: "%.1f km", cycling / 1000))\n"
                hasCrossTraining = true
            }
            if let swimming = profile.swimmingDistance, swimming > 0 {
                context += "- Swimming (7d): \(String(format: "%.1f km", swimming / 1000))\n"
                hasCrossTraining = true
            }

            if !hasCrossTraining {
                context += "\n💡 No cross-training detected - consider adding cycling/swimming for balanced fitness\n"
            }
            context += "\n"
        }

        return context
    }

    // Helper to calculate average pace across multiple workouts
    private func calculateAveragePace(workouts: [WorkoutModel]) -> Double? {
        let paces = workouts.compactMap { $0.averagePace }
        guard !paces.isEmpty else { return nil }
        return paces.reduce(0, +) / Double(paces.count)
    }

    // MARK: - Formatting Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatPace(_ pace: Double) -> String {
        let minutes = Int(pace)
        let seconds = Int((pace - Double(minutes)) * 60)
        return String(format: "%d'%02d\"/km", minutes, seconds)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        } else {
            return String(format: "%dm", minutes)
        }
    }
}
