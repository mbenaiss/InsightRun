//
//  WorkoutAnalysisViewModel.swift
//  InsightRun
//
//  ViewModel for managing AI workout analysis with local SwiftData persistence
//

import Combine
import CryptoKit
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
    @Published private(set) var isOutdated = false

    private static let signatureVersion = "v2:"

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

        // An outdated analysis stays visible: regenerating it costs a request, so only the user decides.
        if let cached = fetchCachedAnalysis() {
            if AIResponseValidator.isComplete(cached.analysisText) {
                showCachedAnalysis(cached)
                error = nil
                needsConsent = false
                needsIndexation = false
                return
            }
            print("⚠️ WorkoutAnalysisViewModel: Cached analysis is invalid, deleting and regenerating")
            modelContext.delete(cached)
            try? modelContext.save()
            clearAnalysis()
        }

        guard allowGeneration else { return }
        print("⚠️ WorkoutAnalysisViewModel: No valid cache, generating new analysis")
        await generateAnalysis()
    }

    private func showCachedAnalysis(_ cached: WorkoutAnalysis) {
        let signature = inputSignature()
        // Signatures written before the stable field subset cannot be compared; adopt them once.
        if let signature, cached.inputSignature?.hasPrefix(Self.signatureVersion) != true {
            cached.inputSignature = signature
            try? modelContext.save()
        }
        analysisText = cached.analysisText
        analysisSource = .cache
        analyzedAt = cached.analyzedAt
        isOutdated = cached.contextVersion != WorkoutAnalysis.currentContextVersion
            || !Self.isSameHeartRateReference(cached.estimatedMaxHR, maximumHeartRate())
            || cached.inputSignature != signature
    }

    private func clearAnalysis() {
        analysisText = nil
        analysisSource = nil
        analyzedAt = nil
        isOutdated = false
    }

    private func restoreCachedAnalysis() {
        if let cached = fetchCachedAnalysis(), AIResponseValidator.isComplete(cached.analysisText) {
            showCachedAnalysis(cached)
        } else {
            clearAnalysis()
        }
    }

    // 220 − age moves by one beat on a birthday, which does not change the interpretation.
    private static func isSameHeartRateReference(_ saved: Int?, _ current: Int?) -> Bool {
        guard let saved, let current else { return saved == current }
        return abs(saved - current) <= 1
    }

    // MARK: - Generate Analysis

    /// Get analysis prompt in user's language
    private func getAnalysisPrompt() -> String {
        let languageCode = AppLanguage.current

        if languageCode == "fr" {
            return """
                Analyse cette séance en un seul paragraphe continu, en texte simple, de 180 mots maximum. Aucun titre, aucune liste, aucune séparation ni retour à la ligne. Adresse-toi directement au coureur en le tutoyant.

                Commence directement par un bilan personnalisé, sans annoncer « l'enseignement principal ». Appuie-le sur 2 à 3 observations pertinentes et explique leurs liens : évolution de l'allure, effort, fréquence cardiaque, objectif et ressenti disponibles. Résume les variations plutôt que d'énumérer tous les temps au kilomètre. Explique ce que ces observations signifient ensemble, sans affirmer une cause non mesurée. Distingue estimation Apple et ressenti déclaré : l'estimation reste un repère utile, à exprimer sur 10, pas une donnée à écarter. Compare à l'historique personnel uniquement si les séances et les conditions sont comparables. Termine naturellement par un conseil concret découlant de l'analyse, en expliquant pourquoi il est utile.

                Règles strictes :
                - Ton neutre, précis, factuel. Pas d'emojis, pas d'exclamations, pas de superlatifs creux.
                - N'utilise que les métriques effectivement présentes. Si une limite change réellement l'interprétation, intègre-la brièvement dans le raisonnement. Ne transforme pas le paragraphe en inventaire des données manquantes ou en avertissement systématique. Si les données sont rares, reste plus court plutôt que de remplir.
                - La fréquence maximale calculée avec l'âge ne permet ni de qualifier cette séance de facile, tempo ou seuil, ni de juger qu'elle est trop intense, ni de prescrire une cible cardiaque.
                - N'invente aucune cadence idéale, aucun seuil de variabilité d'allure ni objectif de récupération. L'absence d'objectif ou de ressenti n'est pas une erreur du coureur.
                - Sur tapis, la météo associée à l'activité ne mesure pas les conditions dans la salle. Ne lui attribue aucun effet sur l'effort.
                - Appuie le conseil sur l'objectif et le ressenti disponibles. S'ils manquent, propose une action simple, sans cible physiologique inventée.
                """
        } else {
            return """
                Analyze this workout in one continuous paragraph of plain text, at most 180 words. No headings, lists, separate sections or line breaks. Address the runner directly.

                Open directly with a personalized assessment, without announcing "the main takeaway". Support it with 2 to 3 relevant observations and explain how they relate: pacing over time, effort, heart rate, and the supplied goal and feedback. Summarize changes instead of listing every kilometre split. Explain what these observations mean together without claiming an unmeasured cause. Distinguish an Apple estimate from self-reported effort: the estimate remains useful context, expressed out of 10, rather than something to dismiss. Compare with personal history only when sessions and conditions are comparable. Close naturally with one concrete recommendation arising from the analysis and explain why it is useful.

                Strict rules:
                - Neutral, precise, factual tone. No emojis, no exclamations, no empty superlatives.
                - Only use supplied metrics. If a limitation materially changes the interpretation, weave it briefly into the reasoning. Do not turn the paragraph into an inventory of missing data or routine disclaimers. With sparse data, write less rather than filling space.
                - An age-based maximum heart rate cannot establish easy, tempo or threshold intensity, prove that this session was too hard, or justify a heart-rate target.
                - Do not invent an ideal cadence, a pacing-variability cutoff or a recovery goal. An unknown goal or perceived effort is not a runner's mistake.
                - For treadmill runs, attached outdoor weather does not measure conditions inside the room. Do not attribute effort to that weather.
                - Base the next action on the supplied goal and perceived effort. If absent, suggest a simple action without inventing physiological targets.
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
        clearAnalysis()
        lastViewedAnalysis = nil
        lastViewedSource = nil
        analytics.trackWorkoutAnalysisStarted()

        print("🔵 WorkoutAnalysisViewModel: isLoading set to true")

        // Backend will build context from workout data
        print("🔵 WorkoutAnalysisViewModel: Sending workout data to backend for context generation")

        // Get analysis prompt in user's language
        let question = getAnalysisPrompt()
        let estimatedMaxHR = maximumHeartRate()
        let requestSignature = inputSignature()

        // ModelRouter will automatically select appropriate model based on request complexity
        // askQuestion only returns once the stream is fully consumed, so the final
        // text is available synchronously on aiService.streamedResponse afterwards.
        await aiService.askQuestion(
            question: question,
            mode: .singleWorkout(workout, metrics)
        )

        isLoading = false

        // A cancelled request may still return partial text; it is neither saved nor reported.
        guard !Task.isCancelled else {
            restoreCachedAnalysis()
            return
        }

        // Read the authoritative final text from the service rather than analysisText,
        // which is delivered through an async Combine sink that may lag a runloop tick.
        let finalAnalysis = aiService.streamedResponse
        guard requestSignature == inputSignature() else {
            restoreCachedAnalysis()
            return
        }

        guard aiService.error == nil else {
            restoreCachedAnalysis()
            error = aiService.error
            analytics.trackWorkoutAnalysisFailed(reason: .serviceError)
            return
        }

        guard !finalAnalysis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            restoreCachedAnalysis()
            error = String(localized: "Error during analysis")
            analytics.trackWorkoutAnalysisFailed(reason: .emptyResponse)
            return
        }

        guard AIResponseValidator.isComplete(finalAnalysis) else {
            restoreCachedAnalysis()
            error = String(localized: "analysis.incomplete_response", defaultValue: "The analysis was interrupted. Try again.")
            analytics.trackWorkoutAnalysisFailed(reason: .incompleteResponse)
            return
        }
        analysisText = finalAnalysis
        analysisSource = .generated
        analyzedAt = Date()
        isOutdated = false
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
        analysis.inputSignature = requestSignature

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

    // Only inputs that change the interpretation, so new payload fields never mark every analysis outdated.
    private struct SignatureInput: Encodable {
        let language: String
        let start: Int?
        let durationSeconds: Int?
        let distanceMeters: Int?
        let averageHeartRate: Int?
        let maximumHeartRate: Int?
        let elevationGainMeters: Int?
        let heartRateCoverageTenths: Int?
        let effort: Int?
        let effortIsEstimated: Bool?
        let isIndoor: Bool
        let feedback: WorkoutFeedback?
    }

    func inputSignature(language: String = AppLanguage.current) -> String? {
        func whole(_ value: Double?, scale: Double = 1) -> Int? {
            guard let value, value.isFinite else { return nil }
            return Int(exactly: (value * scale).rounded())
        }
        let coverage = metrics?.evidence?.signals.first { $0.metric == "heartRate" }?.coverage
        let input = SignatureInput(
            language: language,
            start: whole(workout.startDate.timeIntervalSince1970),
            durationSeconds: whole(workout.duration),
            distanceMeters: whole(workout.distance),
            averageHeartRate: whole(metrics?.averageHeartRate),
            maximumHeartRate: whole(metrics?.maxHeartRate),
            elevationGainMeters: whole(metrics?.totalElevationAscent),
            heartRateCoverageTenths: whole(coverage, scale: 10),
            effort: whole(workout.effortScore),
            effortIsEstimated: workout.effortScore == nil ? nil : workout.effortIsEstimated,
            isIndoor: workout.isIndoor,
            feedback: WorkoutFeedbackStore.shared.feedback(for: workout)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(input) else { return nil }
        return Self.signatureVersion + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

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
