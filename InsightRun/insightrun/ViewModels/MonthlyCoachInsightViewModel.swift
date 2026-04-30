//
//  MonthlyCoachInsightViewModel.swift
//  InsightRun
//
//  ViewModel for the AI-generated "Lecture du mois" coach insight on the
//  Statistics screen. Mirrors WorkoutAnalysisViewModel: streams from
//  WorkoutAIService, persists to SwiftData, gates on consent and indexation.
//

import Foundation
import SwiftData
import Combine

@MainActor
final class MonthlyCoachInsightViewModel: ObservableObject {
    @Published var body: String?
    @Published var isLoading = false
    @Published var error: String?
    @Published var analyzedAt: Date?
    @Published var needsConsent = false
    @Published var needsIndexation = false

    private let modelContext: ModelContext
    private let aiService: WorkoutAIService
    private var cancellables = Set<AnyCancellable>()

    /// Snapshot of the workouts powering the prompt — refreshed on every load
    /// so cache invalidation can compare counts across renders.
    private var thisMonthWorkouts: [WorkoutModel] = []
    private var lastMonthWorkouts: [WorkoutModel] = []
    private var workoutsMetrics: [UUID: WorkoutMetrics] = [:]

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.aiService = WorkoutAIService()

        aiService.$streamedResponse
            .receive(on: DispatchQueue.main)
            .sink { [weak self] response in
                let isSystemMessage = response.isEmpty ||
                                     response.contains("Analyse de votre historique") ||
                                     response.contains("Analyzing your training history") ||
                                     response.contains("Updating your athletic profile") ||
                                     response.contains("Failed to analyze your training history")
                if !isSystemMessage {
                    self?.body = response
                }
            }
            .store(in: &cancellables)

        aiService.$error
            .receive(on: DispatchQueue.main)
            .sink { [weak self] errorMsg in
                self?.error = errorMsg
            }
            .store(in: &cancellables)
    }

    // MARK: - Public API

    /// Load from cache if fresh, otherwise generate via the LLM. Pass the workouts
    /// already filtered by the caller — the VM doesn't reach into HealthKit itself.
    func loadInsight(
        thisMonth: [WorkoutModel],
        lastMonth: [WorkoutModel],
        metrics: [UUID: WorkoutMetrics] = [:]
    ) async {
        self.thisMonthWorkouts = thisMonth
        self.lastMonthWorkouts = lastMonth
        self.workoutsMetrics = metrics

        if DemoMode.isEnabled {
            body = MockData.sampleMonthlyInsight
            analyzedAt = Date()
            return
        }

        // Cache is keyed on (year-month + language). It is invalidated when the
        // workout count for the current month changes.
        if let cached = fetchCachedInsight() {
            if cached.workoutCount == thisMonth.count, !cached.body.isEmpty {
                body = cached.body
                analyzedAt = cached.analyzedAt
                return
            }
            // Stale (count drifted) — drop it and regenerate.
            modelContext.delete(cached)
            try? modelContext.save()
        }

        await generateInsight()
    }

    func regenerate() async {
        if let cached = fetchCachedInsight() {
            modelContext.delete(cached)
            try? modelContext.save()
        }
        await generateInsight()
    }

    // MARK: - Generation

    func generateInsight() async {
        guard ConsentService.shared.hasConsentedToAIDataSharing else {
            needsConsent = true
            return
        }

        if await HistoricalSummaryStorage.shared.requiresIndexation() {
            AnalyticsService.shared.trackIndexationGateTriggered(source: "monthly_coach_insight")
            needsIndexation = true
            return
        }

        isLoading = true
        error = nil
        body = nil

        let prompt = monthlyInsightPrompt()
        // We feed the LLM both months so it can compute the delta narrative itself.
        let workouts = thisMonthWorkouts + lastMonthWorkouts

        await aiService.askQuestion(
            question: prompt,
            mode: .recentWorkouts(workouts, workoutsMetrics)
        )

        // Wait for the streaming response to finish, capped at 30s.
        var attempts = 0
        let maxAttempts = 60
        while aiService.isStreaming && attempts < maxAttempts {
            try? await Task.sleep(nanoseconds: 500_000_000)
            attempts += 1
        }

        isLoading = false

        guard let final = body, !final.isEmpty, aiService.error == nil else {
            error = aiService.error ?? String(localized: "Error during analysis", comment: "Generic AI failure error")
            return
        }

        // Strip stray markdown / surrounding quotes the model sometimes adds.
        let cleaned = final
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))

        let cache = MonthlyStatsAnalysis(
            monthKey: currentMonthKey(),
            body: cleaned,
            workoutCount: thisMonthWorkouts.count
        )
        modelContext.insert(cache)
        do {
            try modelContext.save()
            analyzedAt = cache.analyzedAt
            body = cleaned
        } catch {
            self.error = String(localized: "Error saving: \(error.localizedDescription)", comment: "SwiftData save error")
        }
    }

    // MARK: - Cache

    private func fetchCachedInsight() -> MonthlyStatsAnalysis? {
        let key = currentMonthKey()
        let descriptor = FetchDescriptor<MonthlyStatsAnalysis>(
            predicate: #Predicate<MonthlyStatsAnalysis> { entry in
                entry.monthKey == key
            }
        )
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func currentMonthKey() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"
        return "\(f.string(from: Date()))-\(AppLanguage.current)"
    }

    // MARK: - Prompt

    private func monthlyInsightPrompt() -> String {
        if AppLanguage.current == "fr" {
            return """
            Tu écris la « Lecture du mois » : un résumé d'une seule phrase, factuel, qui compare le mois en cours au mois précédent en t'appuyant sur les séances fournies.

            Règles strictes :
            - Une seule phrase, 25 mots maximum, sans titre ni liste.
            - Ton neutre et factuel. Pas d'emojis, pas d'exclamations, pas de superlatifs creux.
            - Quantifie au moins une variable saillante (volume, allure, durée, fréquence) avec un signe et une unité explicite — ex. « −21 % vs mars » ou « +12"/km ».
            - Si une donnée manque pour comparer, mentionne uniquement ce qui est mesurable. N'invente rien, ne signale jamais une donnée manquante.
            - Termine par une lecture qualitative concise (ex. « tu cours moins, mais mieux »), sans conseil prescriptif.
            - Réponds uniquement par la phrase finale, sans préambule ni guillemets.
            """
        }
        return """
        Write the "Read of the month": a single, factual sentence that compares the current month with the previous one using the workouts provided.

        Strict rules:
        - One sentence only, 25 words max, no heading, no list.
        - Neutral, factual tone. No emojis, no exclamations, no empty superlatives.
        - Quantify at least one salient variable (volume, pace, duration, frequency) with a sign and explicit unit — e.g. "−21% vs March" or "+12\"/km".
        - If a data point is missing, mention only what is measurable. Do not invent, do not flag missing data.
        - Close with a concise qualitative read (e.g. "you ran less but better") — no prescriptive advice.
        - Answer with the final sentence only, no preamble, no surrounding quotes.
        """
    }
}
