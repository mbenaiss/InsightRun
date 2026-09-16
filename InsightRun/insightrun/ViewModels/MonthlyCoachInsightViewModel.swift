//
//  MonthlyCoachInsightViewModel.swift
//  InsightRun
//
//  ViewModel for the AI-generated "Lecture du mois" coach insight on the
//  Statistics screen. Mirrors WorkoutAnalysisViewModel: streams from
//  WorkoutAIService, persists to SwiftData, gates on consent and indexation.
//

import Combine
import CryptoKit
import Foundation
import SwiftData

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
    private let hasConsent: @MainActor () -> Bool
    private let requiresIndexation: () async -> Bool
    private let generate: ((String, [WorkoutModel]) async throws -> String)?
    private var activeFingerprint: String?
    private var cancellables = Set<AnyCancellable>()

    private var thisMonthWorkouts: [WorkoutModel] = []
    private var lastMonthWorkouts: [WorkoutModel] = []
    private var workoutsMetrics: [UUID: WorkoutMetrics] = [:]

    init(
        modelContext: ModelContext,
        hasConsent: @escaping @MainActor () -> Bool = { ConsentService.shared.hasConsentedToAIDataSharing },
        requiresIndexation: @escaping () async -> Bool = { await HistoricalSummaryStorage.shared.requiresIndexation() },
        generate: ((String, [WorkoutModel]) async throws -> String)? = nil
    ) {
        self.hasConsent = hasConsent
        self.requiresIndexation = requiresIndexation
        self.generate = generate
        self.modelContext = modelContext
        self.aiService = WorkoutAIService()

        aiService.$streamedResponse
            .receive(on: DispatchQueue.main)
            .sink { [weak self] response in
                let isSystemMessage =
                    response.isEmpty || response.contains("Analyse de votre historique")
                    || response.contains("Analyzing your training history")
                    || response.contains("Updating your athletic profile")
                    || response.contains("Failed to analyze your training history")
                if !isSystemMessage, let self, self.isLoading, self.activeFingerprint == self.dataFingerprint {
                    self.body = response
                }
            }
            .store(in: &cancellables)

        aiService.$error
            .receive(on: DispatchQueue.main)
            .sink { [weak self] errorMsg in
                guard let self, self.isLoading, self.activeFingerprint == self.dataFingerprint else { return }
                self.error = errorMsg
            }
            .store(in: &cancellables)
    }

    // MARK: - Public API

    func loadInsight(
        thisMonth: [WorkoutModel],
        lastMonth: [WorkoutModel],
        metrics: [UUID: WorkoutMetrics] = [:],
        generateIfNeeded: Bool = false
    ) async {
        self.thisMonthWorkouts = thisMonth
        self.lastMonthWorkouts = lastMonth
        self.workoutsMetrics = metrics

        if DemoMode.isEnabled && generate == nil {
            let totals = StatisticsTotals(workouts: thisMonth, calendar: .current)
            body = String(
                format: String(
                    localized: "statistics.coach.demo.summary",
                    defaultValue: "This month: %@ covered in %@, with an average pace of %@."),
                Formatters.distance(km: totals.distance / 1000, fractionDigits: 1),
                String(format: "%dh %02dmin", Int(totals.duration) / 3600, Int(totals.duration) % 3600 / 60),
                totals.averagePace.map { Formatters.paceFromMinutesPerKm($0) } ?? "—")
            analyzedAt = Date()
            return
        }

        needsConsent = !hasConsent()
        if let cached = fetchCachedInsight(), cached.dataFingerprint == dataFingerprint, !cached.body.isEmpty {
            body = cached.body
            analyzedAt = cached.analyzedAt
            error = nil
            return
        }
        if activeFingerprint != dataFingerprint {
            body = nil
            analyzedAt = nil
            error = nil
        }
        if generateIfNeeded { await generateInsight() }
    }

    func regenerate() async {
        await generateInsight()
    }

    func generateInsight() async {
        guard !isLoading, !thisMonthWorkouts.isEmpty else { return }
        guard hasConsent() else {
            needsConsent = true
            return
        }
        isLoading = true
        needsConsent = false
        error = nil
        let fingerprint = dataFingerprint
        let cacheKey = currentMonthKey()
        activeFingerprint = fingerprint
        defer {
            isLoading = false
            activeFingerprint = nil
        }
        if await requiresIndexation() {
            needsIndexation = true
            AnalyticsService.shared.trackIndexationGateTriggered(source: "monthly_coach_insight")
            return
        }
        guard fingerprint == dataFingerprint, !Task.isCancelled else { return }
        needsIndexation = false
        let prompt = monthlyInsightPrompt()
        let workouts = thisMonthWorkouts
        do {
            let response: String
            if let generate {
                response = try await generate(prompt, workouts)
            } else {
                await aiService.askQuestion(
                    question: prompt, mode: .recentWorkouts(workouts, workoutsMetrics), requiresCompleteResponse: true)
                if let error = aiService.error {
                    throw NSError(domain: "MonthlyInsight", code: 1, userInfo: [NSLocalizedDescriptionKey: error])
                }
                response = aiService.streamedResponse
            }
            guard fingerprint == dataFingerprint, !Task.isCancelled, hasConsent() else { return }
            let cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
            guard !cleaned.isEmpty, AIResponseValidator.isComplete(cleaned) else {
                throw NSError(
                    domain: "MonthlyInsight", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: String(localized: "Error during analysis")])
            }
            body = cleaned
            let cache =
                fetchCachedInsight()
                ?? MonthlyStatsAnalysis(monthKey: cacheKey, body: cleaned, workoutCount: workouts.count)
            cache.body = cleaned
            cache.workoutCount = workouts.count
            cache.dataFingerprint = fingerprint
            cache.analyzedAt = Date()
            modelContext.insert(cache)
            try modelContext.save()
            analyzedAt = cache.analyzedAt
        } catch is CancellationError {
        } catch {
            guard fingerprint == dataFingerprint else { return }
            self.error = error.localizedDescription
        }
    }

    private var dataFingerprint: String {
        let parts = [thisMonthWorkouts, lastMonthWorkouts].map { workouts in
            workouts.sorted { $0.id.uuidString < $1.id.uuidString }.map {
                "\($0.id.uuidString):\($0.startDate.timeIntervalSince1970):\($0.distance ?? 0):\($0.duration)"
            }.joined(separator: "|")
        }.joined(separator: "#")
        return SHA256.hash(data: Data(parts.utf8)).map { String(format: "%02x", $0) }.joined()
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
        return "\(f.string(from: Date()))-\(AppLanguage.current)-v3"
    }

    // MARK: - Prompt

    /// Neutral, pre-computed one-line aggregate so the model echoes exact numbers
    /// that match the stats cards instead of re-summing the raw session list.
    private func monthAggregateLine(_ workouts: [WorkoutModel]) -> String {
        let totals = StatisticsTotals(workouts: workouts, calendar: .current)
        let distanceKm = totals.distance / 1000
        let totalMinutes = Int((totals.duration / 60).rounded())
        let durationText =
            totalMinutes >= 60
            ? "\(totalMinutes / 60)h\(String(format: "%02d", totalMinutes % 60))"
            : "\(totalMinutes)min"
        let paceText = totals.averagePace.map { Formatters.paceClock($0 * 60) } ?? "n/a"
        return "\(workouts.count) runs · \(String(format: "%.1f", distanceKm)) km · \(durationText) · \(paceText)/km"
    }

    private func monthlyInsightPrompt() -> String {
        let current = monthAggregateLine(thisMonthWorkouts)
        let previous = lastMonthWorkouts.isEmpty ? nil : monthAggregateLine(lastMonthWorkouts)

        if AppLanguage.current == "fr" {
            let stats =
                previous.map { "- Mois en cours : \(current)\n            - Même durée du mois précédent : \($0)" }
                ?? "- Mois en cours : \(current)"
            return """
                Tu écris la « Lecture du mois » : un résumé d'une seule phrase, factuel, qui compare le mois en cours à la même durée écoulée du mois précédent.

                CHIFFRES (utilise EXACTEMENT ces valeurs, ne recompte jamais depuis une liste de séances) :
                \(stats)

                Règles strictes :
                - Une seule phrase, 25 mots maximum, sans titre ni liste.
                - Ton neutre et factuel. Pas d'emojis, pas d'exclamations, pas de superlatifs creux.
                - Quantifie au moins une variable saillante (volume, allure, durée, fréquence) avec un signe et une unité explicite — ex. « −21 % vs mois précédent » ou « +12"/km ».
                - Si une donnée manque pour comparer, mentionne uniquement ce qui est mesurable. N'invente rien, ne signale jamais une donnée manquante.
                - Ne conclus pas qu’une allure plus rapide prouve une meilleure forme : parcours et types de séances peuvent différer.
                - Réponds uniquement par la phrase finale, sans préambule ni guillemets.
                """
        }
        let stats =
            previous.map { "- Current month: \(current)\n        - Same elapsed portion of the previous month: \($0)" }
            ?? "- Current month: \(current)"
        return """
            Write the "Read of the month": a single, factual sentence that compares the current month with the same elapsed portion of the previous month.

            FIGURES (use these EXACT values, never recompute from a session list):
            \(stats)

            Strict rules:
            - One sentence only, 25 words max, no heading, no list.
            - Neutral, factual tone. No emojis, no exclamations, no empty superlatives.
            - Quantify at least one salient variable (volume, pace, duration, frequency) with a sign and explicit unit — e.g. "−21% vs previous month" or "+12\"/km".
            - If a data point is missing, mention only what is measurable. Do not invent, do not flag missing data.
            - Do not infer improved fitness from faster average pace: routes and workout types can differ.
            - Answer with the final sentence only, no preamble, no surrounding quotes.
            """
    }
}
