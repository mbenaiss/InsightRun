//
//  WorkoutAnalysisViewModel.swift
//  InsightRun
//
//  ViewModel for managing AI workout analysis with local SwiftData persistence
//

import Foundation
import SwiftData
import Combine

@MainActor
class WorkoutAnalysisViewModel: ObservableObject {
    @Published var analysisText: String?
    @Published var isLoading = false
    @Published var error: String?
    @Published var analyzedAt: Date?
    @Published var needsConsent = false
    @Published var needsIndexation = false

    private let workout: WorkoutModel
    private var metrics: WorkoutMetrics?
    private let modelContext: ModelContext
    private let aiService: WorkoutAIService
    private var cancellables = Set<AnyCancellable>()

    init(workout: WorkoutModel, metrics: WorkoutMetrics?, modelContext: ModelContext) {
        self.workout = workout
        self.metrics = metrics
        self.modelContext = modelContext
        self.aiService = WorkoutAIService()

        // Observe streaming response in real-time
        aiService.$streamedResponse
            .receive(on: DispatchQueue.main)
            .sink { [weak self] response in
                // Filter out system messages (indexation, etc.)
                let isSystemMessage = response.isEmpty ||
                                     response.contains("Analyse de votre historique") ||
                                     response.contains("Analyzing your training history") ||
                                     response.contains("Updating your athletic profile") ||
                                     response.contains("Failed to analyze your training history")

                if !isSystemMessage {
                    self?.analysisText = response
                }
            }
            .store(in: &cancellables)

        // Observe errors
        aiService.$error
            .receive(on: DispatchQueue.main)
            .sink { [weak self] errorMsg in
                self?.error = errorMsg
            }
            .store(in: &cancellables)
    }

    // MARK: - Update Metrics

    /// Update metrics before generating analysis
    func updateMetrics(_ newMetrics: WorkoutMetrics?) {
        self.metrics = newMetrics
    }

    // MARK: - Load Analysis

    /// Load analysis from SwiftData cache or generate new one
    func loadAnalysis() async {
        print("🔵 WorkoutAnalysisViewModel: loadAnalysis() called")

        if DemoMode.isEnabled {
            analysisText = MockData.sampleWorkoutAnalysis
            analyzedAt = Date()
            return
        }

        // First, try to load from local cache
        if let cached = fetchCachedAnalysis() {
            print("✅ WorkoutAnalysisViewModel: Found cached analysis")
            print("   - Text length: \(cached.analysisText.count) chars")
            print("   - First 100 chars: \(String(cached.analysisText.prefix(100)))")

            // Validate that the cached analysis is not empty
            if !cached.analysisText.isEmpty {
                analysisText = cached.analysisText
                analyzedAt = cached.analyzedAt
                print("✅ WorkoutAnalysisViewModel: Loaded valid cached analysis")
                return
            } else {
                print("⚠️ WorkoutAnalysisViewModel: Cached analysis is invalid, deleting and regenerating")
                // Delete invalid cache
                modelContext.delete(cached)
                try? modelContext.save()
            }
        }

        print("⚠️ WorkoutAnalysisViewModel: No valid cache, generating new analysis")
        await generateAnalysis()
    }

    // MARK: - Generate Analysis

    /// Get analysis prompt in user's language
    private func getAnalysisPrompt() -> String {
        let languageCode = Locale.current.language.languageCode?.identifier ?? "en"

        if languageCode == "fr" {
            return """
            Analyse ce workout en profondeur et fournis une réponse CONCISE (max 250 mots) en markdown avec cette structure exacte:

            ## 🎯 Points Clés
            - [2-3 insights sur la performance globale]

            ## ✅ Métriques Optimales
            - [Liste UNIQUEMENT les métriques qui sont dans les normes optimales, groupées en UNE ligne]
            - Exemple: "Cadence (178 spm), Asymétrie (2.5%), Vitesse marche (5.2 km/h) ✅"
            - Si AUCUNE métrique n'est optimale, omets cette section

            ## ⚠️ À Optimiser
            - [Liste UNIQUEMENT les métriques problématiques avec leurs valeurs et cibles]
            - Format: "Métrique actuelle → Cible optimale + Impact/Conseil"
            - Exemple: "Temps contact sol: 285 ms → 200-250 ms (perte efficacité ~8%)"
            - Si TOUT est optimal, omets cette section et mentionne-le dans Points Clés

            ## 💡 Actions Concrètes
            - [1-2 exercices spécifiques SEULEMENT s'il y a des métriques à améliorer]
            - Sinon omets cette section

            ## 🔄 Récupération
            - [1 conseil personnalisé basé sur l'intensité et la durée du workout]
            - Mentionne le temps de repos recommandé avant le prochain entraînement intense
            - Exemple: "48h de repos recommandé. Privilégie sommeil 8h+ et hydratation."

            RÈGLES STRICTES:
            - N'analyse QUE les métriques DISPONIBLES dans les données (ne mentionne JAMAIS "données non disponibles")
            - Groupe les métriques optimales, détaille seulement celles à améliorer
            - Sois concis: 1 ligne par métrique problématique max
            - Si tout est optimal, dis-le clairement et félicite l'athlète
            - Section Récupération TOUJOURS présente avec conseil adapté à l'effort
            """
        } else {
            // English version
            return """
            Analyze this workout in depth and provide a CONCISE response (max 250 words) in markdown with this exact structure:

            ## 🎯 Key Points
            - [2-3 insights on overall performance]

            ## ✅ Optimal Metrics
            - [List ONLY metrics that are within optimal ranges, grouped in ONE line]
            - Example: "Cadence (178 spm), Asymmetry (2.5%), Walking speed (5.2 km/h) ✅"
            - If NO metrics are optimal, omit this section

            ## ⚠️ To Optimize
            - [List ONLY problematic metrics with their values and targets]
            - Format: "Current metric → Optimal target + Impact/Advice"
            - Example: "Ground contact time: 285 ms → 200-250 ms (~8% efficiency loss)"
            - If EVERYTHING is optimal, omit this section and mention it in Key Points

            ## 💡 Concrete Actions
            - [1-2 specific exercises ONLY if there are metrics to improve]
            - Otherwise omit this section

            ## 🔄 Recovery
            - [1 personalized advice based on workout intensity and duration]
            - Mention recommended rest time before next intense training
            - Example: "48h rest recommended. Focus on 8h+ sleep and hydration."

            STRICT RULES:
            - Analyze ONLY AVAILABLE metrics in the data (NEVER mention "data not available")
            - Group optimal metrics, detail only those to improve
            - Be concise: max 1 line per problematic metric
            - If everything is optimal, say it clearly and congratulate the athlete
            - Recovery section ALWAYS present with advice adapted to the effort
            """
        }
    }

    /// Generate new AI analysis and save to SwiftData
    func generateAnalysis() async {
        guard ConsentService.shared.hasConsentedToAIDataSharing else {
            needsConsent = true
            return
        }

        if await HistoricalSummaryStorage.shared.requiresIndexation() {
            needsIndexation = true
            return
        }

        print("🔵 WorkoutAnalysisViewModel: generateAnalysis() started")
        isLoading = true
        error = nil
        analysisText = nil

        print("🔵 WorkoutAnalysisViewModel: isLoading set to true")

        // Backend will build context from workout data
        print("🔵 WorkoutAnalysisViewModel: Sending workout data to backend for context generation")

        // Get analysis prompt in user's language
        let question = getAnalysisPrompt()

        // ModelRouter will automatically select appropriate model based on request complexity
        // Backend builds context from structured workout data
        await aiService.askQuestion(
            question: question,
            mode: .singleWorkout(workout, metrics)
        )

        // Wait for streaming to complete by observing isStreaming
        var attempts = 0
        let maxAttempts = 60 // 30 seconds max

        while aiService.isStreaming && attempts < maxAttempts {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            attempts += 1
        }

        isLoading = false

        // Check if we got a response (analysisText is already set by Combine observer)
        guard let finalAnalysis = analysisText, !finalAnalysis.isEmpty, aiService.error == nil else {
            error = aiService.error ?? String(localized: "Error during analysis")
            print("❌ WorkoutAnalysisViewModel: No response received")
            return
        }

        print("✅ WorkoutAnalysisViewModel: Streaming complete, saving to SwiftData (\(finalAnalysis.count) chars)")
        print("🔍 WorkoutAnalysisViewModel: Saving with workoutId: \(workout.id)")

        // Save to SwiftData
        let analysis = WorkoutAnalysis(
            workoutId: workout.id,
            analysisText: finalAnalysis,
            analyzedAt: Date()
        )

        modelContext.insert(analysis)

        do {
            try modelContext.save()
            analyzedAt = analysis.analyzedAt
            print("✅ WorkoutAnalysisViewModel: Saved to SwiftData with ID: \(analysis.workoutId)")

        } catch {
            self.error = String(localized: "Error saving: \(error.localizedDescription)")
            print("❌ WorkoutAnalysisViewModel: Save failed: \(error)")
        }
    }

    // MARK: - Cache Management

    /// Fetch cached analysis from SwiftData
    private func fetchCachedAnalysis() -> WorkoutAnalysis? {
        let workoutId = workout.id
        print("🔍 WorkoutAnalysisViewModel: Looking for cached analysis with workoutId: \(workoutId)")

        let descriptor = FetchDescriptor<WorkoutAnalysis>(
            predicate: #Predicate<WorkoutAnalysis> { analysis in
                analysis.workoutId == workoutId
            }
        )

        do {
            let results = try modelContext.fetch(descriptor)
            print("🔍 WorkoutAnalysisViewModel: Found \(results.count) cached analyses")

            if results.count > 0 {
                print("🔍 WorkoutAnalysisViewModel: Cached analysis IDs: \(results.map { $0.workoutId })")
            }

            return results.first
        } catch {
            print("⚠️ WorkoutAnalysisViewModel: Failed to fetch cached analysis: \(error)")
            return nil
        }
    }

    /// Delete cached analysis and regenerate
    func regenerateAnalysis() async {
        // Delete existing cache
        if let cached = fetchCachedAnalysis() {
            modelContext.delete(cached)
            try? modelContext.save()
        }

        // Generate new
        await generateAnalysis()
    }
}
