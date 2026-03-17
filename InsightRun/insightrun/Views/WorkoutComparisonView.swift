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
                VStack(spacing: 16) {
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
        }
    }

    // MARK: - Reference Header

    private var referenceHeader: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "flag.fill")
                    .foregroundStyle(Color.irPrimaryAccent.gradient)

                Text(String(localized: "Reference Workout", comment: "Reference workout header title"))
                    .font(.headline)
                    .foregroundStyle(Color.irTextPrimary)

                Spacer()
            }

            HStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text(viewModel.referenceDate)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.irTextPrimary)
                    Text(String(localized: "Date", comment: "Date label in reference header"))
                        .font(.caption2)
                        .foregroundStyle(Color.irTextSecondary)
                }

                VStack(spacing: 4) {
                    Text(viewModel.referenceDistance)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.irTextPrimary)
                    Text(String(localized: "Distance", comment: "Distance label in reference header"))
                        .font(.caption2)
                        .foregroundStyle(Color.irTextSecondary)
                }

                VStack(spacing: 4) {
                    Text(viewModel.referencePace)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.irTextPrimary)
                    Text(String(localized: "Pace", comment: "Pace label in reference header"))
                        .font(.caption2)
                        .foregroundStyle(Color.irTextSecondary)
                }

                Spacer()
            }
        }
        .padding()
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.irShadow, radius: 8, y: 4)
    }

    // MARK: - AI Comparison Analysis

    private var comparisonPrompt: String {
        var lines: [String] = []
        lines.append("Analyse la progression entre ces séances similaires.")
        lines.append("Séance de référence: \(viewModel.referenceDate), \(viewModel.referenceDistance), allure \(viewModel.referencePace)")

        for comp in viewModel.comparisons {
            let date = comp.workout.startDate.formatted(date: .abbreviated, time: .omitted)
            let dist = comp.workout.distanceFormatted
            let deltas = comp.deltas.map { "\($0.label): \($0.deltaText)" }.joined(separator: ", ")
            lines.append("vs \(date) (\(dist)): \(deltas)")
        }

        lines.append("Donne une analyse concise de la tendance (progression, régression, stabilité) et un conseil.")
        return lines.joined(separator: "\n")
    }

    private var aiComparisonSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .font(.title3)

                Text(String(localized: "AI Comparison", comment: "AI comparison analysis section title"))
                    .font(.headline)
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
                        await aiService.askQuestion(
                            question: comparisonPrompt,
                            mode: .unified
                        )
                    }
                } label: {
                    Label(
                        String(localized: "Regenerate", comment: "Regenerate AI analysis button"),
                        systemImage: "arrow.clockwise"
                    )
                    .font(.caption)
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
                            .font(.subheadline)
                            .foregroundStyle(Color.irTextSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
                }
            } else if let error = aiService.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.irError)
            } else {
                Button {
                    Task {
                        await aiService.askQuestion(
                            question: comparisonPrompt,
                            mode: .unified
                        )
                    }
                } label: {
                    Label(
                        String(localized: "Analyze comparison", comment: "Button to generate AI comparison analysis"),
                        systemImage: "sparkles"
                    )
                    .font(.subheadline)
                    .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.irPrimaryAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.irShadow, radius: 8, y: 4)
    }

    // MARK: - Comparison Card

    private func comparisonCard(_ comparison: WorkoutComparisonViewModel.WorkoutComparison) -> some View {
        VStack(spacing: 12) {
            // Card header - navigates to workout detail
            Button {
                selectedWorkout = comparison.workout
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(comparison.workout.startDate.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.irTextPrimary)
                        Text(comparison.workout.distanceFormatted)
                            .font(.caption)
                            .foregroundStyle(Color.irTextSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.irTextSecondary)
                }
            }
            .buttonStyle(.plain)

            Divider()

            // Metric deltas
            ForEach(comparison.deltas) { delta in
                deltaRow(delta)
            }
        }
        .padding()
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.irShadow, radius: 8, y: 4)
    }

    // MARK: - Delta Row

    private func deltaRow(_ delta: WorkoutComparisonViewModel.MetricDelta) -> some View {
        HStack(spacing: 8) {
            Image(systemName: delta.icon)
                .font(.caption)
                .foregroundStyle(Color.irTextSecondary)
                .frame(width: 20)

            Text(delta.label)
                .font(.caption)
                .foregroundStyle(Color.irTextSecondary)
                .frame(width: 60, alignment: .leading)

            Spacer()

            Text(delta.referenceValue)
                .font(.caption)
                .foregroundStyle(Color.irTextSecondary)
                .frame(width: 70, alignment: .trailing)

            Text(delta.comparedValue)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Color.irTextPrimary)
                .frame(width: 70, alignment: .trailing)

            HStack(spacing: 2) {
                Text(deltaArrow(delta.direction))
                    .font(.caption2)
                Text(delta.deltaText)
                    .font(.caption2)
                    .fontWeight(.medium)
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
