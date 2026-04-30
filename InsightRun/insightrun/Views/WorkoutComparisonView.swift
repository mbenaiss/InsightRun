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

    private let referenceWorkoutId: UUID

    init(referenceWorkout: WorkoutModel, similarWorkouts: [WorkoutModel]) {
        _viewModel = StateObject(wrappedValue: WorkoutComparisonViewModel(
            referenceWorkout: referenceWorkout,
            similarWorkouts: similarWorkouts
        ))
        self.referenceWorkoutId = referenceWorkout.id
    }

    private var cacheKey: String {
        "comparison_analysis_\(referenceWorkoutId.uuidString)"
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
                WorkoutDetailView(workout: workout)
            }
            .onAppear {
                // Load cached analysis
                cachedAnalysis = UserDefaults.standard.string(forKey: cacheKey)
            }
            .onChange(of: aiService.isStreaming) { _, isStreaming in
                // Persist when streaming finishes
                if !isStreaming && !aiService.streamedResponse.isEmpty {
                    cachedAnalysis = aiService.streamedResponse
                    UserDefaults.standard.set(aiService.streamedResponse, forKey: cacheKey)
                }
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
            lines.append("Analyse la progression entre ces séances similaires.")
            lines.append("Séance de référence: \(viewModel.referenceDate), \(viewModel.referenceDistance), allure \(viewModel.referencePace)")
        } else {
            lines.append("Analyze the progression between these similar workouts.")
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
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.irPrimaryAccent, Color.irPrimaryAccent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
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
            } else if let error = aiService.error {
                Text(error)
                    .font(IRFont.caption)
                    .foregroundStyle(Color.irError)
            } else {
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
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .shadow(color: Color.irShadow, radius: 8, y: 4)
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
            mode: .unified
        )
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
            .background(Color.irCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .shadow(color: Color.irShadow, radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Delta Row

    private func deltaRow(_ delta: WorkoutComparisonViewModel.MetricDelta) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: delta.icon)
                .font(IRFont.caption)
                .foregroundStyle(Color.irTextSecondary)
                .frame(width: 20)

            Text(delta.label)
                .font(IRFont.caption)
                .foregroundStyle(Color.irTextSecondary)
                .frame(width: 60, alignment: .leading)

            Spacer()

            Text(delta.referenceValue)
                .font(IRFont.caption)
                .foregroundStyle(Color.irTextSecondary)
                .frame(width: 70, alignment: .trailing)

            Text(delta.comparedValue)
                .font(IRFont.body.weight(.medium))
                .foregroundStyle(Color.irTextPrimary)
                .frame(width: 70, alignment: .trailing)

            HStack(spacing: 2) {
                Text(deltaArrow(delta.direction))
                    .font(IRFont.microLabel)
                Text(delta.deltaText)
                    .font(IRFont.microLabel.weight(.medium))
            }
            .foregroundStyle(deltaColor(delta.direction))
            .frame(width: 80, alignment: .trailing)
        }
    }

    // MARK: - Helpers

    private func deltaArrow(_ direction: WorkoutComparisonViewModel.DeltaDirection) -> String {
        switch direction {
        case .improved: return "\u{2191}"
        case .regressed: return "\u{2193}"
        case .neutral: return "\u{2194}"
        }
    }

    private func deltaColor(_ direction: WorkoutComparisonViewModel.DeltaDirection) -> Color {
        switch direction {
        case .improved: return Color.irSuccess
        case .regressed: return Color.irError
        case .neutral: return Color.irWarning
        }
    }
}
