//
//  WorkoutComparisonView.swift
//  InsightRun
//
//  View that compares a reference workout with similar workouts,
//  showing metric deltas and AI analysis.
//

import SwiftUI

struct WorkoutComparisonView: View {
    @StateObject private var viewModel: WorkoutComparisonViewModel
    @StateObject private var aiService = WorkoutAIService()
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var revenueCatManager: RevenueCatManager
    @State private var selectedWorkout: WorkoutModel?
    @State private var cachedAnalysis: String?
    @State private var shouldResumeComparisonAnalysis = false

    init(referenceWorkout: WorkoutModel, similarWorkouts: [WorkoutModel]) {
        _viewModel = StateObject(wrappedValue: WorkoutComparisonViewModel(
            referenceWorkout: referenceWorkout,
            similarWorkouts: similarWorkouts
        ))
    }

    private var cacheKey: String {
        viewModel.analysisCacheKey
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.base) {
                    // Reference workout header
                    referenceHeader

                    // AI comparison analysis
                    if revenueCatManager.hasAIAccess {
                        aiComparisonSection
                    }

                    // Similar workout comparison cards
                    ForEach(viewModel.comparisons) { comparison in
                        comparisonCard(comparison)
                    }
                }
                .padding()
            }
            .background(Color.irBackgroundApp)
            .navigationTitle(String(localized: "Compare Workouts", comment: "Comparison view navigation title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done", comment: "Dismiss button")) {
                        dismiss()
                    }
                }
            }
            .navigationDestination(item: $selectedWorkout) { workout in
                WorkoutDetailView(workout: workout, allWorkouts: [viewModel.referenceWorkout] + viewModel.similarWorkouts)
            }
            .onAppear {
                // Load cached analysis
                cachedAnalysis = UserDefaults.standard.string(forKey: cacheKey)
            }
            .sheet(isPresented: $aiService.needsConsent) {
                AIConsentSheet(
                    onConsent: {
                        aiService.needsConsent = false
                        Task {
                            if await HistoricalSummaryStorage.shared.requiresIndexation() {
                                aiService.needsIndexation = true
                            } else {
                                await runComparisonAnalysisIfNeeded()
                            }
                        }
                    },
                    onDecline: {
                        aiService.needsConsent = false
                        shouldResumeComparisonAnalysis = false
                    }
                )
            }
            .indexationGate(isPresented: $aiService.needsIndexation) {
                await runComparisonAnalysisIfNeeded()
            }
        }
    }

    // MARK: - Reference Header

    private var referenceHeader: some View {
        VStack(spacing: Spacing.md) {
            HStack {
                Image(systemName: "flag.fill")
                    .foregroundStyle(Color.irPrimaryAccent.gradient)

                Text(String(localized: "Reference Workout", comment: "Reference workout header title"))
                    .font(IRFont.headline)
                    .foregroundStyle(Color.irTextPrimary)

                Spacer()
            }

            HStack(spacing: Spacing.xl) {
                VStack(spacing: Spacing.xxs) {
                    Text(viewModel.referenceDate)
                        .font(IRFont.body.weight(.bold))
                        .foregroundStyle(Color.irPrimaryAccent)
                    Text(String(localized: "Date", comment: "Date label in reference header"))
                        .font(IRFont.microLabel)
                        .foregroundStyle(Color.irTextSecondary)
                }

                VStack(spacing: Spacing.xxs) {
                    Text(viewModel.referenceDistance)
                        .font(IRFont.body.weight(.bold))
                        .foregroundStyle(Color.irPrimaryAccent)
                    Text(String(localized: "Distance", comment: "Distance label in reference header"))
                        .font(IRFont.microLabel)
                        .foregroundStyle(Color.irTextSecondary)
                }

                VStack(spacing: Spacing.xxs) {
                    Text(viewModel.referencePace)
                        .font(IRFont.body.weight(.bold))
                        .foregroundStyle(Color.irPrimaryAccent)
                    Text(String(localized: "Pace", comment: "Pace label in reference header"))
                        .font(IRFont.microLabel)
                        .foregroundStyle(Color.irTextSecondary)
                }

                Spacer()
            }
        }
        .padding()
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Color.irPrimaryAccent.opacity(0.4), lineWidth: 1.5)
        )
        .shadow(color: Color.irShadow, radius: 8, y: 4)
    }

    // MARK: - AI Comparison Analysis

    private var isFrench: Bool {
        AppLanguage.current == "fr"
    }

    private var comparisonPrompt: String {
        var lines: [String] = []

        if isFrench {
            lines.append("Compare cette séance à des séances antérieures de distance proche et de même environnement. Les écarts sont référence moins séance antérieure. Une distance, durée ou dépense énergétique plus élevée ne prouve pas une progression. Ne conclus pas sur la forme sans tenir compte de l’allure, du relief et de l’effort.")
            lines.append("Séance de référence: \(viewModel.referenceDate), \(viewModel.referenceDistance), allure \(viewModel.referencePace)")
        } else {
            lines.append("Compare this workout with earlier workouts of similar distance in the same environment. Deltas are reference minus earlier workout. More distance, duration or calories do not prove progress. Consider pace, elevation and effort before drawing fitness conclusions.")
            lines.append("Reference workout: \(viewModel.referenceDate), \(viewModel.referenceDistance), pace \(viewModel.referencePace)")
        }

        for comp in viewModel.comparisons {
            let date = comp.workout.startDate.formatted(date: .abbreviated, time: .omitted)
            let dist = comp.workout.distanceFormatted
            let deltas = comp.deltas.map { "\($0.label): \($0.deltaText)" }.joined(separator: ", ")
            lines.append("vs \(date) (\(dist)): \(deltas)")
        }

        if isFrench {
            lines.append("Donne une analyse concise de la tendance (progression, régression, stabilité) et un conseil.")
        } else {
            lines.append("Give a concise analysis of the trend (progression, regression, stability) and one piece of advice.")
        }

        return lines.joined(separator: "\n")
    }

    private var aiComparisonSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(LinearGradient.irAIAccent)
                    .font(IRFont.title3)

                Text(String(localized: "AI Comparison", comment: "AI comparison analysis section title"))
                    .font(IRFont.headline)
                    .foregroundStyle(Color.irTextPrimary)
            }

            if let cached = cachedAnalysis, !aiService.isStreaming {
                // Persisted analysis
                MarkdownView(cached)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    cachedAnalysis = nil
                    UserDefaults.standard.removeObject(forKey: cacheKey)
                    Task {
                        await prepareComparisonAnalysis()
                    }
                } label: {
                    Label(
                        String(localized: "Regenerate", comment: "Regenerate AI analysis button"),
                        systemImage: "arrow.clockwise"
                    )
                    .font(IRFont.caption)
                }
                .buttonStyle(.borderless)
                .tint(Color.irPrimaryAccent)
                .frame(maxWidth: .infinity, alignment: .trailing)
            } else if aiService.isStreaming || !aiService.streamedResponse.isEmpty {
                // Streaming or just finished
                MarkdownView(aiService.streamedResponse)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if aiService.isStreaming && aiService.streamedResponse.isEmpty {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text(String(localized: "Analyzing...", comment: "AI analysis loading indicator"))
                            .font(IRFont.body)
                            .foregroundStyle(Color.irTextSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Spacing.md)
                }
            } else {
                if let error = aiService.error {
                    Text(error)
                        .font(IRFont.caption)
                        .foregroundStyle(Color.irError)
                }
                Button {
                    Task {
                        await prepareComparisonAnalysis()
                    }
                } label: {
                    Label(
                        String(localized: "Analyze comparison", comment: "Button to generate AI comparison analysis"),
                        systemImage: "sparkles"
                    )
                    .font(IRFont.body.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.irPrimaryAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xxs)
            }
        }
        .padding()
        .detailCard()
    }

    private func prepareComparisonAnalysis() async {
        shouldResumeComparisonAnalysis = true

        guard ConsentService.shared.hasConsentedToAIDataSharing else {
            await MainActor.run {
                aiService.needsConsent = true
            }
            return
        }

        if await HistoricalSummaryStorage.shared.requiresIndexation() {
            await MainActor.run {
                AnalyticsService.shared.trackIndexationGateTriggered(source: "workout_comparison")
                aiService.needsIndexation = true
            }
            return
        }

        await runComparisonAnalysisIfNeeded()
    }

    private func runComparisonAnalysisIfNeeded() async {
        guard shouldResumeComparisonAnalysis else { return }
        shouldResumeComparisonAnalysis = false

        await aiService.askQuestion(
            question: comparisonPrompt,
            mode: .unified,
            requiresCompleteResponse: true
        )
        guard !Task.isCancelled, aiService.error == nil else { return }
        guard AIResponseValidator.isComplete(aiService.streamedResponse) else {
            aiService.streamedResponse = ""
            aiService.error = String(localized: "Invalid response from server")
            return
        }
        cachedAnalysis = aiService.streamedResponse
        UserDefaults.standard.set(aiService.streamedResponse, forKey: cacheKey)
    }

    // MARK: - Comparison Card

    private func comparisonCard(_ comparison: WorkoutComparisonViewModel.WorkoutComparison) -> some View {
        Button {
            selectedWorkout = comparison.workout
        } label: {
            VStack(spacing: Spacing.md) {
                // Card header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(comparison.workout.startDate.formatted(date: .abbreviated, time: .omitted))
                            .font(IRFont.body.weight(.semibold))
                            .foregroundStyle(Color.irTextPrimary)
                        Text(comparison.workout.distanceFormatted)
                            .font(IRFont.caption)
                            .foregroundStyle(Color.irTextSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(IRFont.caption)
                        .foregroundStyle(Color.irTextSecondary)
                }

                Divider()

                // Metric deltas
                ForEach(comparison.deltas) { delta in
                    deltaRow(delta)
                }
            }
            .padding()
            .detailCard()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("similar-workout-" + comparison.id.uuidString)
    }

    // MARK: - Delta Row

    private func deltaRow(_ delta: WorkoutComparisonViewModel.MetricDelta) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Label(delta.label, systemImage: delta.icon)
                .font(IRFont.caption)
                .foregroundStyle(Color.irTextSecondary)
            HStack(spacing: Spacing.sm) {
                Text(delta.referenceValue)
                    .foregroundStyle(Color.irTextSecondary)
                Image(systemName: "arrow.right")
                    .font(IRFont.microLabel)
                    .foregroundStyle(Color.irTextTertiary)
                Text(delta.comparedValue)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.irTextPrimary)
                Spacer(minLength: Spacing.xxs)
                Text(delta.deltaText)
                    .foregroundStyle(deltaColor(delta.direction))
            }
            .font(IRFont.caption)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
    }

    // MARK: - Helpers

    private func deltaColor(_ direction: WorkoutComparisonViewModel.DeltaDirection) -> Color {
        switch direction {
        case .improved: return Color.irSuccess
        case .regressed: return Color.irError
        case .neutral: return Color.irWarning
        }
    }
}
