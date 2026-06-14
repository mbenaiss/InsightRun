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
        let languageCode = AppLanguage.current

        if languageCode == "fr" {
            return """
            Analyse cette séance et rédige une synthèse professionnelle et concise (100 mots maximum) en markdown.

            ## Synthèse
            2 à 3 phrases qui qualifient la séance en s'appuyant sur les métriques clés disponibles (intensité, allure, fréquence cardiaque, technique).

            Règles strictes :
            - Ton neutre, précis, factuel. Pas d'emojis, pas d'exclamations, pas de superlatifs creux.
            - N'utilise que les métriques effectivement présentes dans les données. Ne signale jamais une donnée manquante.
            """
        } else {
            return """
            Analyze this workout and produce a professional, concise synthesis (100 words maximum) in markdown.

            ## Summary
            2 to 3 sentences characterizing the session based on the available key metrics (intensity, pace, heart rate, form).

            Strict rules:
            - Neutral, precise, factual tone. No emojis, no exclamations, no empty superlatives.
            - Only use metrics actually present in the data. Never flag missing data.
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
            AnalyticsService.shared.trackIndexationGateTriggered(source: "workout_analysis")
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
        // Backend builds context from structured workout data.
        // askQuestion only returns once the stream is fully consumed, so the final
        // text is available synchronously on aiService.streamedResponse afterwards.
        await aiService.askQuestion(
            question: question,
            mode: .singleWorkout(workout, metrics)
        )

        isLoading = false

        // Read the authoritative final text from the service rather than analysisText,
        // which is delivered through an async Combine sink that may lag a runloop tick.
        let finalAnalysis = aiService.streamedResponse

        // Only persist a complete analysis; a stream cut short by a transient failure
        // would otherwise be cached and displayed as a final, truncated synthesis.
        guard aiService.error == nil, Self.isCompleteAnalysis(finalAnalysis) else {
            analysisText = nil
            error = aiService.error ?? String(localized: "Error during analysis")
            print("❌ WorkoutAnalysisViewModel: No valid response received")
            return
        }

        analysisText = finalAnalysis

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

    // MARK: - Completeness

    /// A streamed analysis is complete when it has substantive content and ends on
    /// terminal punctuation. A bare prefix or a sentence cut mid-word fails this check.
    static func isCompleteAnalysis(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 40 else { return false }
        let lastChar = trimmed.last
        return lastChar == "." || lastChar == "!" || lastChar == "?" || lastChar == "\u{2026}"
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
