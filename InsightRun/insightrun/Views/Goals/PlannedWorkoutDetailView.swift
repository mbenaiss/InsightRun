//
//  PlannedWorkoutDetailView.swift
//  InsightRun
//
//  Detail view for a planned workout with AI explanation and Apple Fitness export
//

import SwiftUI

struct PlannedWorkoutDetailView: View {
    let workout: PlannedWorkout
    let day: TrainingDay
    var isPast: Bool = false
    var onToggleSkip: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var isExporting = false
    @State private var showExportSuccess = false
    @State private var exportError: String?
    @State private var showSkipConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.base) {
                    headerCard
                    metricsCard
                    aiExplanationCard

                    if !workout.steps.isEmpty {
                        stepsCard
                    }

                    if !isPast {
                        exportCard

                        if onToggleSkip != nil {
                            skipCard
                        }
                    }
                }
                .padding()
            }
            .background(Color.irBackgroundApp)
            .navigationTitle(workout.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.irTextSecondary)
                    }
                }
            }
            .sheet(isPresented: $showExportSuccess) {
                WorkoutExportSuccessView()
            }
            .alert(
                String(localized: "goals.workout.exportError", defaultValue: "Export Failed", comment: "Workout export error title"),
                isPresented: Binding(
                    get: { exportError != nil },
                    set: { if !$0 { exportError = nil } }
                )
            ) {
                Button("OK") { exportError = nil }
            } message: {
                if let error = exportError {
                    Text(error)
                }
            }
            .confirmationDialog(
                String(localized: "goals.workout.skipConfirmTitle", defaultValue: "Skip this workout?", comment: "Skip workout confirmation title"),
                isPresented: $showSkipConfirmation,
                titleVisibility: .visible
            ) {
                Button(
                    String(localized: "goals.workout.skipConfirm", defaultValue: "Skip", comment: "Skip workout confirm button"),
                    role: .destructive
                ) {
                    onToggleSkip?()
                    dismiss()
                }
                Button(String(localized: "common.cancel", defaultValue: "Cancel", comment: "Cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "goals.workout.skipConfirmMessage", defaultValue: "The coach will treat this as a deliberate de-load when adapting upcoming weeks.", comment: "Skip workout confirmation message"))
            }
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(workout.intensity.themeColor.opacity(0.1))
                    .frame(width: 56, height: 56)

                Image(systemName: workout.type.icon)
                    .font(.title2)
                    .foregroundStyle(workout.intensity.themeColor.gradient)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(workout.name)
                    .font(.headline)
                    .foregroundStyle(Color.irTextPrimary)

                HStack(spacing: Spacing.sm) {
                    Text(workout.type.displayName)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.irTextSecondary)
                        .textCase(.uppercase)

                    Text("•")
                        .foregroundStyle(Color.irBorder)

                    Text(workout.intensity.displayName)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(workout.intensity.themeColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(workout.intensity.themeColor.opacity(0.1))
                        .clipShape(Capsule())
                }
            }

            Spacer()
            
            if day.isCompleted {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(Color.irSuccess.gradient)
            }
        }
        .cardStyle(padding: Spacing.md)
    }

    // MARK: - Metrics Card

    private var metricsCard: some View {
        let metrics = buildMetrics()
        return Group {
            if !metrics.isEmpty {
                HStack(spacing: Spacing.xs) {
                    ForEach(Array(metrics.enumerated()), id: \.offset) { index, metric in
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(Color.irPrimaryAccent.opacity(0.05))
                                    .frame(width: 32, height: 32)
                                Image(systemName: metric.icon)
                                    .font(.caption2)
                                    .foregroundStyle(Color.irPrimaryAccent)
                            }
                            
                            Text(metric.value)
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.irTextPrimary)
                                .monospacedDigit()
                            
                            Text(metric.label)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.irTextSecondary)
                                .textCase(.uppercase)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(Color.irSurface.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    }
                }
            }
        }
    }

    // MARK: - AI Explanation Card

    private var aiExplanationCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.1))
                        .frame(width: 36, height: 36)
                    Image(systemName: "sparkles")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.purple.gradient)
                }

                Text(String(localized: "goals.workout.aiExplanation", defaultValue: "Coach's Briefing", comment: "Workout detail - AI explanation title"))
                    .font(.headline)
                    .foregroundStyle(Color.irTextPrimary)
            }

            Text(workout.description)
                .font(.subheadline)
                .foregroundStyle(Color.irTextPrimary.opacity(0.9))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            // Workout purpose badge
            HStack(spacing: Spacing.sm) {
                Image(systemName: workoutPurposeIcon)
                    .font(.caption)
                    .foregroundStyle(Color.irPrimaryAccent)
                Text(workoutPurposeText)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.irTextSecondary)
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.irPrimaryAccent.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        }
        .cardStyle(padding: Spacing.lg)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl)
                .stroke(Color.purple.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Steps Card

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text(String(localized: "goals.workout.stepsTitle", defaultValue: "Workout Structure", comment: "Workout detail - steps title"))
                .font(.headline)
                .foregroundStyle(Color.irTextPrimary)

            VStack(spacing: 0) {
                ForEach(Array(workout.steps.enumerated()), id: \.element.id) { index, step in
                    HStack(alignment: .top, spacing: Spacing.md) {
                        // Timeline indicator
                        VStack(spacing: 0) {
                            ZStack {
                                Circle()
                                    .fill(step.type.themeColor.gradient)
                                    .frame(width: 24, height: 24)
                                    .shadow(color: step.type.themeColor.opacity(0.3), radius: 4)
                                
                                Text("\(index + 1)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                            }

                            if index < workout.steps.count - 1 {
                                Rectangle()
                                    .fill(
                                        LinearGradient(colors: [step.type.themeColor.opacity(0.5), workout.steps[index+1].type.themeColor.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                                    )
                                    .frame(width: 2)
                                    .frame(maxHeight: .infinity)
                            }
                        }
                        .frame(width: 24)

                        // Step content
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(step.type.displayName)
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundStyle(Color.irTextPrimary)

                                Spacer()

                                HStack(spacing: Spacing.xs) {
                                    if let duration = step.duration {
                                        Text(formatStepDuration(duration))
                                    }
                                    if let distance = step.distance {
                                        Text(String(format: "%.0f m", distance))
                                    }
                                }
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundStyle(Color.irTextSecondary)
                            }

                            Text(step.description)
                                .font(.caption)
                                .foregroundStyle(Color.irTextSecondary)
                                .lineLimit(2)

                            if let pace = step.targetPace {
                                HStack(spacing: 4) {
                                    Image(systemName: "speedometer")
                                        .font(.system(size: 10))
                                    Text(pace + "/km")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                }
                                .foregroundStyle(Color.irPrimaryAccent)
                                .padding(.top, 2)
                            }
                        }
                        .padding(.bottom, index < workout.steps.count - 1 ? Spacing.lg : 0)
                    }
                }
            }
        }
        .cardStyle(padding: Spacing.lg)
    }

    // MARK: - Export Card

    private var exportCard: some View {
        VStack(spacing: Spacing.lg) {
            HStack(spacing: Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(.orange.opacity(0.1))
                        .frame(width: 44, height: 44)
                    Image(systemName: "applewatch")
                        .font(.title3)
                        .foregroundStyle(.orange.gradient)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "goals.workout.exportTitle", defaultValue: "Apple Watch Sync", comment: "Workout detail - export title"))
                        .font(.subheadline)
                        .fontWeight(.bold)
                    Text(String(localized: "goals.workout.exportHint", defaultValue: "Start this workout from your wrist", comment: "Workout detail - export hint"))
                        .font(.caption2)
                        .foregroundStyle(Color.irTextSecondary)
                }

                Spacer()
            }

            Button {
                Task { await exportToFitness() }
            } label: {
                HStack(spacing: Spacing.sm) {
                    if isExporting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.up.forward.app.fill")
                    }
                    Text(isExporting
                        ? String(localized: "goals.workout.exporting", defaultValue: "Syncing...", comment: "Workout detail - exporting")
                        : String(localized: "goals.workout.exportButton", defaultValue: "Sync to Fitness", comment: "Workout detail - export button")
                    )
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(Color.irPrimaryAccent.gradient)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                .shadow(color: Color.irPrimaryAccent.opacity(0.3), radius: 6, y: 3)
            }
            .disabled(isExporting)
        }
        .cardStyle(padding: Spacing.lg)
    }

    // MARK: - Skip Card

    private var skipCard: some View {
        VStack(spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(.gray.opacity(0.1))
                        .frame(width: 44, height: 44)
                    Image(systemName: day.isSkipped ? "arrow.uturn.backward" : "forward.end.fill")
                        .font(.title3)
                        .foregroundStyle(.gray.gradient)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(day.isSkipped
                        ? String(localized: "goals.workout.unskipTitle", defaultValue: "Unskip workout", comment: "Unskip workout title")
                        : String(localized: "goals.workout.skipTitle", defaultValue: "Skip this workout", comment: "Skip workout title")
                    )
                        .font(.subheadline)
                        .fontWeight(.bold)
                    Text(day.isSkipped
                        ? String(localized: "goals.workout.unskipHint", defaultValue: "Restore this session in your plan", comment: "Unskip workout hint")
                        : String(localized: "goals.workout.skipHint", defaultValue: "Tells the coach to drop it from progress tracking", comment: "Skip workout hint")
                    )
                        .font(.caption2)
                        .foregroundStyle(Color.irTextSecondary)
                }

                Spacer()
            }

            Button {
                if day.isSkipped {
                    onToggleSkip?()
                    dismiss()
                } else {
                    showSkipConfirmation = true
                }
            } label: {
                Text(day.isSkipped
                    ? String(localized: "goals.workout.unskipButton", defaultValue: "Restore workout", comment: "Restore workout button")
                    : String(localized: "goals.workout.skipButton", defaultValue: "Skip workout", comment: "Skip workout button")
                )
                .font(.headline)
                .foregroundStyle(Color.irTextPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(Color.irSurface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            }
            .disabled(day.isCompleted)
        }
        .cardStyle(padding: Spacing.lg)
    }

    // MARK: - Export Logic

    private func exportToFitness() async {
        isExporting = true
        exportError = nil

        // Convert PlannedWorkout → AIGeneratedWorkout
        let steps = workout.steps.map { step in
            let goalType: WorkoutGoal.GoalType
            let goalValue: Double
            if let distance = step.distance {
                goalType = .distance
                goalValue = distance
            } else if let duration = step.duration {
                goalType = .duration
                goalValue = duration
            } else {
                goalType = .open
                goalValue = 0
            }

            let stepType: WorkoutStep.StepType = switch step.type {
            case .warmup: .warmup
            case .work: .work
            case .recovery: .recovery
            case .cooldown: .cooldown
            case .interval: .interval
            case .rest: .recovery
            }

            return WorkoutStep(
                type: stepType,
                goal: WorkoutGoal(type: goalType, value: goalValue),
                targetPace: step.targetPace,
                repetitions: step.repetitions,
                instructions: step.description
            )
        }

        let aiWorkout = AIGeneratedWorkout(
            name: workout.name,
            description: workout.description,
            sport: .running,
            steps: steps,
            totalDistance: workout.targetDistance,
            estimatedDuration: workout.targetDuration
        )

        do {
            try await WorkoutKitManager.shared.exportToFitnessApp(aiWorkout)
            isExporting = false
            showExportSuccess = true
        } catch {
            isExporting = false
            exportError = error.localizedDescription
        }
    }

    // MARK: - Metrics Builder

    private struct MetricData {
        let icon: String
        let value: String
        let label: String
    }

    private func buildMetrics() -> [MetricData] {
        var metrics: [MetricData] = []
        if !workout.formattedDistance.isEmpty {
            metrics.append(MetricData(
                icon: "ruler",
                value: workout.formattedDistance,
                label: String(localized: "goals.workout.distance", defaultValue: "Distance", comment: "Workout detail - distance")
            ))
        }
        if !workout.formattedDuration.isEmpty {
            metrics.append(MetricData(
                icon: "clock",
                value: workout.formattedDuration,
                label: String(localized: "goals.workout.duration", defaultValue: "Duration", comment: "Workout detail - duration")
            ))
        }
        if let pace = workout.targetPace {
            metrics.append(MetricData(
                icon: "speedometer",
                value: pace + "/km",
                label: String(localized: "goals.workout.pace", defaultValue: "Pace", comment: "Workout detail - pace")
            ))
        }
        return metrics
    }

    // MARK: - Helpers

    private func formatStepDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if secs == 0 {
            return "\(minutes) min"
        }
        return "\(minutes):\(String(format: "%02d", secs))"
    }

    private var workoutPurposeIcon: String {
        switch workout.type {
        case .easyRun: return "heart"
        case .tempo: return "bolt"
        case .intervals: return "timer"
        case .longRun: return "arrow.right.circle"
        case .recovery: return "bed.double"
        case .hillRepeats: return "arrow.up.right"
        case .fartlek: return "shuffle"
        case .crossTraining: return "bicycle"
        }
    }

    private var workoutPurposeText: String {
        switch workout.type {
        case .easyRun:
            return String(localized: "goals.workout.purpose.easyRun", defaultValue: "Builds aerobic base and promotes recovery between hard sessions", comment: "Workout purpose - easy run")
        case .tempo:
            return String(localized: "goals.workout.purpose.tempo", defaultValue: "Improves lactate threshold and sustained speed", comment: "Workout purpose - tempo")
        case .intervals:
            return String(localized: "goals.workout.purpose.intervals", defaultValue: "Develops VO2max and running economy", comment: "Workout purpose - intervals")
        case .longRun:
            return String(localized: "goals.workout.purpose.longRun", defaultValue: "Builds endurance, fat adaptation and mental toughness", comment: "Workout purpose - long run")
        case .recovery:
            return String(localized: "goals.workout.purpose.recovery", defaultValue: "Active recovery to promote blood flow and reduce soreness", comment: "Workout purpose - recovery")
        case .hillRepeats:
            return String(localized: "goals.workout.purpose.hillRepeats", defaultValue: "Builds strength, power and running form", comment: "Workout purpose - hill repeats")
        case .fartlek:
            return String(localized: "goals.workout.purpose.fartlek", defaultValue: "Fun speed play that develops pace awareness", comment: "Workout purpose - fartlek")
        case .crossTraining:
            return String(localized: "goals.workout.purpose.crossTraining", defaultValue: "Reduces injury risk while maintaining fitness", comment: "Workout purpose - cross training")
        }
    }
}
