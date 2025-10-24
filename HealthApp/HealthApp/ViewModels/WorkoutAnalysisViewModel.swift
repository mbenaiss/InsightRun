//
//  WorkoutAnalysisViewModel.swift
//  HealthApp
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
                if !response.isEmpty && response != "🌐 Connexion au serveur..." {
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

        // First, try to load from local cache
        if let cached = fetchCachedAnalysis() {
            print("✅ WorkoutAnalysisViewModel: Found cached analysis")
            print("   - Text length: \(cached.analysisText.count) chars")
            print("   - First 100 chars: \(String(cached.analysisText.prefix(100)))")

            // Validate that the cached analysis is not empty
            if !cached.analysisText.isEmpty && cached.analysisText != "🌐 Connexion au serveur..." {
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
        // No cache, generate new analysis
        await generateAnalysis()
    }

    // MARK: - Generate Analysis

    /// Generate new AI analysis and save to SwiftData
    func generateAnalysis() async {
        print("🔵 WorkoutAnalysisViewModel: generateAnalysis() started")
        isLoading = true
        error = nil
        analysisText = nil

        print("🔵 WorkoutAnalysisViewModel: isLoading set to true")

        // Build context for AI
        let context = aiService.generateSingleWorkoutContext(workout: workout, metrics: metrics)
        print("🔵 WorkoutAnalysisViewModel: Context built (\(context.count) chars)")

        // Ask AI to analyze this specific workout with a concise, structured response
        let question = """
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

        // Use Grok-4-fast for automatic analysis (always use Grok to keep costs low)
        await aiService.askQuestion(
            about: context,
            question: question,
            mode: .singleWorkout(workout, metrics),
            model: .grok4
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
            error = aiService.error ?? "Erreur lors de l'analyse"
            print("❌ WorkoutAnalysisViewModel: No response received")
            return
        }

        print("✅ WorkoutAnalysisViewModel: Streaming complete, saving to SwiftData (\(finalAnalysis.count) chars)")

        // Save to SwiftData
        let analysis = WorkoutAnalysis(
            workoutId: workout.id,
            analysisText: finalAnalysis,
            analyzedAt: Date(),
            model: "grok-4-fast"
        )

        modelContext.insert(analysis)

        do {
            try modelContext.save()
            analyzedAt = analysis.analyzedAt
            print("✅ WorkoutAnalysisViewModel: Saved to SwiftData")

        } catch {
            self.error = "Erreur lors de la sauvegarde: \(error.localizedDescription)"
            print("❌ WorkoutAnalysisViewModel: Save failed: \(error)")
        }
    }

    // MARK: - Cache Management

    /// Fetch cached analysis from SwiftData
    private func fetchCachedAnalysis() -> WorkoutAnalysis? {
        let workoutId = workout.id
        let descriptor = FetchDescriptor<WorkoutAnalysis>(
            predicate: #Predicate<WorkoutAnalysis> { analysis in
                analysis.workoutId == workoutId
            }
        )

        do {
            let results = try modelContext.fetch(descriptor)
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
