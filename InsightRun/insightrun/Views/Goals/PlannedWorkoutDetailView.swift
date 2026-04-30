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
    var currentDate: Date? = nil
    var onToggleSkip: (() -> Void)? = nil
    var onMove: ((Date?) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var isExporting = false
    @State private var showExportSuccess = false
    @State private var exportError: String?
    @State private var showSkipConfirmation = false
    @State private var showMoveSheet = false

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

                        if onMove != nil {
                            moveCard
                        }

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
                            .font(IRFont.title2)
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
            .sheet(isPresented: $showMoveSheet) {
                MoveWorkoutSheet(
                    initialDate: currentDate ?? Date(),
                    hasOverride: day.dateOverride != nil,
                    onConfirm: { newDate in
                        onMove?(newDate)
                        showMoveSheet = false
                        dismiss()
                    },
                    onClearOverride: {
                        onMove?(nil)
                        showMoveSheet = false
                        dismiss()
                    }
                )
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
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(workout.intensity.themeColor.opacity(0.1))
                    .frame(width: 56, height: 56)

                Image(systemName: workout.type.icon)
                    .font(IRFont.title2)
                    .foregroundStyle(workout.intensity.themeColor.gradient)
            }

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(workout.name)
                    .font(IRFont.headline)
                    .foregroundStyle(Color.irTextPrimary)

                HStack(spacing: Spacing.sm) {
                    Text(workout.type.displayName)
                        .font(IRFont.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.irTextSecondary)
                        .textCase(.uppercase)

                    Text("•")
                        .foregroundStyle(Color.irBorder)

                    Text(workout.intensity.displayName)
                        .font(IRFont.microLabel.weight(.bold))
                        .foregroundStyle(workout.intensity.themeColor)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, 2)
                        .background(workout.intensity.themeColor.opacity(0.1))
                        .clipShape(Capsule())
                }
            }

            Spacer()
            
            if day.isCompleted {
                Image(systemName: "checkmark.seal.fill")
                    .font(IRFont.title2)
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
                        VStack(spacing: Spacing.xxs) {
                            ZStack {
                                Circle()
                                    .fill(Color.irPrimaryAccent.opacity(0.05))
                                    .frame(width: 32, height: 32)
                                Image(systemName: metric.icon)
                                    .font(IRFont.microLabel)
                                    .foregroundStyle(Color.irPrimaryAccent)
                            }

                            Text(metric.value)
                                .font(IRFont.numSM.weight(.bold))
                                .foregroundStyle(Color.irTextPrimary)

                            Text(metric.label)
                                .font(IRFont.eyebrow.weight(.bold))
                                .foregroundStyle(Color.irTextSecondary)
                                .textCase(.uppercase)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(Color.irCard2.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
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
                        .fill(Color.irPrimaryAccent.opacity(0.1))
                        .frame(width: 36, height: 36)
                    Image(systemName: "sparkles")
                        .font(IRFont.headline)
                        .foregroundStyle(Color.irPrimaryAccent.gradient)
                }

                Text(String(localized: "goals.workout.aiExplanation", defaultValue: "Coach's Briefing", comment: "Workout detail - AI explanation title"))
                    .font(IRFont.headline)
                    .foregroundStyle(Color.irTextPrimary)
            }

            Text(workout.description)
                .font(IRFont.body)
                .foregroundStyle(Color.irTextPrimary.opacity(0.9))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            // Workout purpose badge
            HStack(spacing: Spacing.sm) {
                Image(systemName: workoutPurposeIcon)
                    .font(IRFont.caption)
                    .foregroundStyle(Color.irPrimaryAccent)
                Text(workoutPurposeText)
                    .font(IRFont.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.irTextSecondary)
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.irPrimaryAccent.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
        }
        .cardStyle(padding: Spacing.lg)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(Color.irPrimaryAccent.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Steps Card

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text(String(localized: "goals.workout.stepsTitle", defaultValue: "Workout Structure", comment: "Workout detail - steps title"))
                .font(IRFont.headline)
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
                                    .font(IRFont.microLabel.weight(.bold))
                                    .foregroundStyle(Color.irTextPrimary)
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
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            HStack {
                                Text(step.type.displayName)
                                    .font(IRFont.body)
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
                                .font(IRFont.monoSM)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.irTextSecondary)
                            }

                            Text(step.description)
                                .font(IRFont.caption)
                                .foregroundStyle(Color.irTextSecondary)
                                .lineLimit(2)

                            if let pace = step.targetPace {
                                HStack(spacing: Spacing.xxs) {
                                    Image(systemName: "speedometer")
                                        .font(IRFont.microLabel)
                                    Text(pace + "/km")
                                        .font(IRFont.monoSM.weight(.bold))
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
                    RoundedRectangle(cornerRadius: Radius.xs)
                        .fill(Color.irWarning.opacity(0.1))
                        .frame(width: 44, height: 44)
                    Image(systemName: "applewatch")
                        .font(IRFont.title3)
                        .foregroundStyle(Color.irWarning.gradient)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "goals.workout.exportTitle", defaultValue: "Apple Watch Sync", comment: "Workout detail - export title"))
                        .font(IRFont.body)
                        .fontWeight(.bold)
                    Text(String(localized: "goals.workout.exportHint", defaultValue: "Start this workout from your wrist", comment: "Workout detail - export hint"))
                        .font(IRFont.microLabel)
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
                .font(IRFont.headline)
                .foregroundStyle(Color.irCardBackground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(Color.irPrimaryAccent.gradient)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                .shadow(color: Color.irPrimaryAccent.opacity(0.3), radius: 6, y: 3)
            }
            .disabled(isExporting)
        }
        .cardStyle(padding: Spacing.lg)
    }

    // MARK: - Move Card

    private var moveCard: some View {
        VStack(spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.xs)
                        .fill(Color.irPrimaryAccent.opacity(0.1))
                        .frame(width: 44, height: 44)
                    Image(systemName: "calendar.badge.clock")
                        .font(IRFont.title3)
                        .foregroundStyle(Color.irPrimaryAccent.gradient)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "goals.workout.moveTitle", defaultValue: "Reschedule", comment: "Move workout card title"))
                        .font(IRFont.body)
                        .fontWeight(.bold)
                    Text(moveCardSubtitle)
                        .font(IRFont.microLabel)
                        .foregroundStyle(Color.irTextSecondary)
                }

                Spacer()
            }

            Button {
                showMoveSheet = true
            } label: {
                Text(day.dateOverride != nil
                    ? String(localized: "goals.workout.moveAgainButton", defaultValue: "Pick a new date", comment: "Move workout button - already moved")
                    : String(localized: "goals.workout.moveButton", defaultValue: "Move to another day", comment: "Move workout button")
                )
                .font(IRFont.headline)
                .foregroundStyle(Color.irTextPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(Color.irCard2)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            }
            .disabled(day.isCompleted)
        }
        .cardStyle(padding: Spacing.lg)
    }

    private var moveCardSubtitle: String {
        if let override = day.dateOverride {
            let template = String(localized: "goals.workout.moveSubtitleMoved", defaultValue: "Moved to %@", comment: "Move workout subtitle - moved (date)")
            return String(format: template, override.formatted(date: .abbreviated, time: .omitted))
        }
        return String(localized: "goals.workout.moveSubtitle", defaultValue: "Shift this session to another date — the rest of the plan stays the same", comment: "Move workout subtitle")
    }

    // MARK: - Skip Card

    private var skipCard: some View {
        VStack(spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.xs)
                        .fill(Color.irTextTertiary.opacity(0.1))
                        .frame(width: 44, height: 44)
                    Image(systemName: day.isSkipped ? "arrow.uturn.backward" : "forward.end.fill")
                        .font(IRFont.title3)
                        .foregroundStyle(Color.irTextTertiary.gradient)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(day.isSkipped
                        ? String(localized: "goals.workout.unskipTitle", defaultValue: "Unskip workout", comment: "Unskip workout title")
                        : String(localized: "goals.workout.skipTitle", defaultValue: "Skip this workout", comment: "Skip workout title")
                    )
                        .font(IRFont.body)
                        .fontWeight(.bold)
                    Text(day.isSkipped
                        ? String(localized: "goals.workout.unskipHint", defaultValue: "Restore this session in your plan", comment: "Unskip workout hint")
                        : String(localized: "goals.workout.skipHint", defaultValue: "Tells the coach to drop it from progress tracking", comment: "Skip workout hint")
                    )
                        .font(IRFont.microLabel)
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
                .font(IRFont.headline)
                .foregroundStyle(Color.irTextPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(Color.irCard2)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
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

// MARK: - Move Workout Sheet

private struct MoveWorkoutSheet: View {
    let initialDate: Date
    let hasOverride: Bool
    let onConfirm: (Date) -> Void
    let onClearOverride: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate: Date

    init(
        initialDate: Date,
        hasOverride: Bool,
        onConfirm: @escaping (Date) -> Void,
        onClearOverride: @escaping () -> Void
    ) {
        self.initialDate = initialDate
        self.hasOverride = hasOverride
        self.onConfirm = onConfirm
        self.onClearOverride = onClearOverride
        self._selectedDate = State(initialValue: initialDate)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                Text(String(localized: "goals.workout.movePrompt", defaultValue: "Pick the new date for this session. The rest of your plan stays unchanged.", comment: "Move workout prompt"))
                    .font(IRFont.body)
                    .foregroundStyle(Color.irTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                DatePicker(
                    String(localized: "goals.workout.moveDateLabel", defaultValue: "New date", comment: "Move workout date picker label"),
                    selection: $selectedDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding(.horizontal)

                Spacer()

                VStack(spacing: Spacing.sm) {
                    Button {
                        onConfirm(selectedDate)
                    } label: {
                        Text(String(localized: "goals.workout.moveConfirm", defaultValue: "Move session", comment: "Move workout confirm button"))
                            .font(IRFont.headline)
                            .foregroundStyle(Color.irCardBackground)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.md)
                            .background(Color.irPrimaryAccent.gradient)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                    }
                    .disabled(Calendar.current.isDate(selectedDate, inSameDayAs: initialDate))

                    if hasOverride {
                        Button(role: .destructive) {
                            onClearOverride()
                        } label: {
                            Text(String(localized: "goals.workout.moveReset", defaultValue: "Reset to original date", comment: "Reset workout move button"))
                                .font(IRFont.body)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Spacing.sm)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .background(Color.irBackgroundApp)
            .navigationTitle(String(localized: "goals.workout.moveNavTitle", defaultValue: "Reschedule session", comment: "Move workout navigation title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.cancel", defaultValue: "Cancel", comment: "Cancel")) {
                        dismiss()
                    }
                }
            }
            .presentationDetents([.large])
        }
    }
}
