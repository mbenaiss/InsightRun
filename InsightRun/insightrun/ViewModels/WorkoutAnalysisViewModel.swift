//
//  WorkoutAnalysisViewModel.swift
//  InsightRun
//
//  ViewModel for managing AI workout analysis with local SwiftData persistence
//

import Combine
import Foundation
import SwiftData

@MainActor
protocol WorkoutAnalysisClient: AnyObject {
    var streamedResponse: String { get }
    var error: String? { get }
    var responsePublisher: AnyPublisher<String, Never> { get }
    func askQuestion(question: String, mode: AIAssistantMode) async
}

@MainActor
final class WorkoutAnalysisServiceClient: WorkoutAnalysisClient {
    private let service = WorkoutAIService()

    var streamedResponse: String { service.streamedResponse }
    var error: String? { service.error }

    var responsePublisher: AnyPublisher<String, Never> {
        service.$streamedResponse.eraseToAnyPublisher()
    }

    func askQuestion(question: String, mode: AIAssistantMode) async {
        await service.askQuestion(question: question, mode: mode, requiresCompleteResponse: true)
    }
}

@MainActor
class WorkoutAnalysisViewModel: ObservableObject {
    @Published var analysisText: String?
    @Published private(set) var analysisSource: WorkoutAnalysisSource?
    @Published var isLoading = false
    @Published var error: String?
    @Published var analyzedAt: Date?
    @Published var needsConsent = false
    @Published var needsIndexation = false

    private let workout: WorkoutModel
    private var metrics: WorkoutMetrics?
    private let modelContext: ModelContext
    private let aiService: any WorkoutAnalysisClient
    private let analytics: any WorkoutAnalysisTracking
    private let hasAIConsent: @MainActor () -> Bool
    private let requiresIndexation: @MainActor () async -> Bool
    private let isDemo: Bool
    private let maximumHeartRate: @MainActor () -> Int?
    private var isPreparingAnalysis = false
    private var lastViewedAnalysis: String?
    private var lastViewedSource: WorkoutAnalysisSource?
    private var cancellables = Set<AnyCancellable>()

    private var isSampleWorkout: Bool {
        workout.metadata?["is_sample"] as? Bool == true
    }

    init(
        workout: WorkoutModel,
        metrics: WorkoutMetrics?,
        modelContext: ModelContext,
        aiService: (any WorkoutAnalysisClient)? = nil,
        analytics: (any WorkoutAnalysisTracking)? = nil,
        hasAIConsent: (@MainActor () -> Bool)? = nil,
        requiresIndexation: (@MainActor () async -> Bool)? = nil,
        isDemo: Bool? = nil,
        maximumHeartRate: (@MainActor () -> Int?)? = nil
    ) {
        self.workout = workout
        self.metrics = metrics
        self.modelContext = modelContext
        self.aiService = aiService ?? WorkoutAnalysisServiceClient()
        self.analytics = analytics ?? AnalyticsService.shared
        self.hasAIConsent = hasAIConsent ?? { ConsentService.shared.hasConsentedToAIDataSharing }
        self.requiresIndexation = requiresIndexation ?? { await HistoricalSummaryStorage.shared.requiresIndexation() }
        self.isDemo = isDemo ?? DemoMode.isEnabled
        self.maximumHeartRate = maximumHeartRate ?? {
            HeartRateReference.maximum(age: HealthKitManager.shared.currentAge)
        }

        // Observe streaming response in real-time
        self.aiService.responsePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] response in
                guard let self, self.isLoading else { return }
                // Filter out system messages (indexation, etc.)
                let isSystemMessage =
                    response.isEmpty || response.contains("Analyse de votre historique")
                    || response.contains("Analyzing your training history") || response.contains("Updating your athletic profile")
                    || response.contains("Failed to analyze your training history")

                if !isSystemMessage {
                    self.analysisText = response
                }
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
    func loadAnalysis(allowGeneration: Bool = true) async {
        guard !isLoading, !isPreparingAnalysis else { return }
        if isDemo || isSampleWorkout {
            showSampleAnalysis()
            return
        }

        // First, try to load from local cache
        if let cached = fetchCachedAnalysis() {
            print("✅ WorkoutAnalysisViewModel: Found cached analysis")
            if AIResponseValidator.isComplete(cached.analysisText),
               cached.contextVersion == WorkoutAnalysis.currentContextVersion,
               cached.estimatedMaxHR == maximumHeartRate() {
                analysisText = cached.analysisText
                analysisSource = .cache
                analyzedAt = cached.analyzedAt
                error = nil
                needsConsent = false
                needsIndexation = false
                print("✅ WorkoutAnalysisViewModel: Loaded valid cached analysis")
                return
            } else if !AIResponseValidator.isComplete(cached.analysisText) {
                print("⚠️ WorkoutAnalysisViewModel: Cached analysis is invalid, deleting and regenerating")
                // Delete invalid cache
                modelContext.delete(cached)
                try? modelContext.save()
            }
            analysisText = nil
            analysisSource = nil
            analyzedAt = nil
        }

        guard allowGeneration else { return }
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

                ## Prochaine action
                Une action précise et réaliste pour la prochaine séance ou la récupération du coureur.

                Règles strictes :
                - Ton neutre, précis, factuel. Pas d'emojis, pas d'exclamations, pas de superlatifs creux.
                - N'utilise que les métriques effectivement présentes dans les données. Ne signale jamais une donnée manquante.
                """
        } else {
            return """
                Analyze this workout and produce a professional, concise synthesis (100 words maximum) in markdown.

                ## Summary
                2 to 3 sentences characterizing the session based on the available key metrics (intensity, pace, heart rate, form).

                ## Next action
                One specific, realistic action for the runner's next session or recovery.

                Strict rules:
                - Neutral, precise, factual tone. No emojis, no exclamations, no empty superlatives.
                - Only use metrics actually present in the data. Never flag missing data.
                """
        }
    }

    /// Generate new AI analysis and save to SwiftData
    func generateAnalysis() async {
        guard !isLoading, !isPreparingAnalysis else { return }
        isPreparingAnalysis = true
        defer { isPreparingAnalysis = false }

        if isDemo || isSampleWorkout {
            showSampleAnalysis()
            return
        }

        needsConsent = false
        needsIndexation = false
        error = nil

        guard hasAIConsent() else {
            needsConsent = true
            return
        }

        if await requiresIndexation() {
            AnalyticsService.shared.trackIndexationGateTriggered(source: "workout_analysis")
            needsIndexation = true
            return
        }

        print("🔵 WorkoutAnalysisViewModel: generateAnalysis() started")
        isLoading = true
        error = nil
        analysisText = nil
        analysisSource = nil
        analyzedAt = nil
        lastViewedAnalysis = nil
        lastViewedSource = nil
        analytics.trackWorkoutAnalysisStarted()

        print("🔵 WorkoutAnalysisViewModel: isLoading set to true")

        // Backend will build context from workout data
        print("🔵 WorkoutAnalysisViewModel: Sending workout data to backend for context generation")

        // Get analysis prompt in user's language
        let question = getAnalysisPrompt()
        let estimatedMaxHR = maximumHeartRate()

        // ModelRouter will automatically select appropriate model based on request complexity
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

        guard aiService.error == nil else {
            analysisText = nil
            error = aiService.error
            analytics.trackWorkoutAnalysisFailed(reason: .serviceError)
            return
        }

        guard !finalAnalysis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            analysisText = nil
            error = String(localized: "Error during analysis")
            analytics.trackWorkoutAnalysisFailed(reason: .emptyResponse)
            return
        }

        guard AIResponseValidator.isComplete(finalAnalysis) else {
            analysisText = nil
            error = String(localized: "analysis.incomplete_response", defaultValue: "The analysis was interrupted. Try again.")
            analytics.trackWorkoutAnalysisFailed(reason: .incompleteResponse)
            return
        }
        analysisText = finalAnalysis
        analysisSource = .generated
        analyzedAt = Date()
        analytics.trackWorkoutAnalysisCompleted(isSample: false)

        print("✅ WorkoutAnalysisViewModel: Streaming complete, saving to SwiftData (\(finalAnalysis.count) chars)")
        print("🔍 WorkoutAnalysisViewModel: Saving with workoutId: \(workout.id)")

        // Save to SwiftData
        let analysis: WorkoutAnalysis
        if let cached = fetchCachedAnalysis() {
            cached.analysisText = finalAnalysis
            cached.analyzedAt = Date()
            analysis = cached
        } else {
            analysis = WorkoutAnalysis(workoutId: workout.id, analysisText: finalAnalysis, analyzedAt: Date())
            modelContext.insert(analysis)
        }
        analysis.contextVersion = WorkoutAnalysis.currentContextVersion
        analysis.estimatedMaxHR = estimatedMaxHR

        do {
            try modelContext.save()
            analyzedAt = analysis.analyzedAt
            print("✅ WorkoutAnalysisViewModel: Saved to SwiftData with ID: \(analysis.workoutId)")

        } catch {
            analytics.trackWorkoutAnalysisFailed(reason: .cacheSaveFailed)
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
            analytics.trackWorkoutAnalysisFailed(reason: .cacheReadFailed)
            return nil
        }
    }

    /// Delete cached analysis and regenerate
    func regenerateAnalysis() async {
        await generateAnalysis()
    }

    func recordAnalysisViewed() {
        guard !isLoading, let analysisText, let analysisSource,
            analysisText != lastViewedAnalysis || analysisSource != lastViewedSource
        else { return }
        analytics.trackWorkoutAnalysisViewed(source: analysisSource)
        lastViewedAnalysis = analysisText
        lastViewedSource = analysisSource
    }

    private func showSampleAnalysis() {
        analysisText = MockData.sampleWorkoutAnalysis
        analysisSource = .sample
        analyzedAt = Date()
        error = nil
        needsConsent = false
        needsIndexation = false
    }
}
