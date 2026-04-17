//
//  GoalDetailView.swift
//  InsightRun
//
//  Detailed view for a race goal with training plan calendar and progress
//

import SwiftUI

struct GoalDetailView: View {
    let goal: RaceGoal
    @ObservedObject var viewModel: GoalsViewModel
    @State private var showDeleteConfirmation = false
    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var selectedPlanTab = 0 // 0 = current week, 1 = full plan
    @Environment(\.dismiss) private var dismiss

    private var currentGoal: RaceGoal {
        viewModel.goals.first(where: { $0.id == goal.id }) ?? goal
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.base) {
                // Header card
                headerCard

                // Training plan section
                if let plan = currentGoal.trainingPlan {
                    trainingPlanSection(plan)
                } else if !currentGoal.isPastRace {
                    generatePlanCard
                }
            }
            .padding()
        }
        .background(Color.irBackgroundApp)
        .navigationTitle(currentGoal.raceName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        renameText = currentGoal.raceName
                        showRenameAlert = true
                    } label: {
                        Label(
                            String(localized: "goals.detail.rename", defaultValue: "Rename", comment: "Goal detail - rename"),
                            systemImage: "pencil"
                        )
                    }

                    if currentGoal.hasTrainingPlan {
                        Button {
                            Task {
                                await viewModel.adaptPlanIfNeeded(for: currentGoal)
                            }
                        } label: {
                            Label(
                                String(localized: "goals.detail.adapt", defaultValue: "Adapt Plan", comment: "Goal detail - adapt plan"),
                                systemImage: "wand.and.stars"
                            )
                        }

                        Button {
                            Task {
                                await viewModel.generateTrainingPlan(for: currentGoal)
                            }
                        } label: {
                            Label(
                                String(localized: "goals.detail.regenerate", defaultValue: "Regenerate Plan", comment: "Goal detail - regenerate"),
                                systemImage: "arrow.clockwise"
                            )
                        }
                    }

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label(
                            String(localized: "goals.detail.delete", defaultValue: "Delete Goal", comment: "Goal detail - delete"),
                            systemImage: "trash"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Color.irTextSecondary)
                }
            }
        }
        .confirmationDialog(
            String(localized: "goals.detail.deleteConfirmation", defaultValue: "Delete this goal?", comment: "Goal detail - delete confirmation"),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "goals.detail.deleteButton", defaultValue: "Delete", comment: "Delete button"), role: .destructive) {
                viewModel.deleteGoal(currentGoal)
                dismiss()
            }
        }
        .alert(
            String(localized: "goals.detail.renameTitle", defaultValue: "Rename Goal", comment: "Goal detail - rename title"),
            isPresented: $showRenameAlert
        ) {
            TextField("", text: $renameText)
            Button(String(localized: "goals.detail.ok", defaultValue: "OK", comment: "OK button")) {
                if !renameText.isEmpty {
                    viewModel.renameGoal(id: currentGoal.id, newName: renameText)
                }
            }
            Button(String(localized: "goals.form.cancel", defaultValue: "Cancel", comment: "Cancel button"), role: .cancel) {}
        }
        .alert(
            String(localized: "goals.detail.errorTitle", defaultValue: "Generation Error", comment: "Goal detail - error title"),
            isPresented: Binding(
                get: { viewModel.generationError != nil },
                set: { if !$0 { viewModel.generationError = nil } }
            )
        ) {
            Button(String(localized: "goals.detail.ok", defaultValue: "OK", comment: "OK button")) {
                viewModel.generationError = nil
            }
        } message: {
            if let error = viewModel.generationError {
                Text(error)
            }
        }
        .alert(
            String(localized: "goals.detail.adaptErrorTitle", defaultValue: "Adaptation Error", comment: "Goal detail - adapt error title"),
            isPresented: Binding(
                get: { viewModel.adaptationError != nil },
                set: { if !$0 { viewModel.adaptationError = nil } }
            )
        ) {
            Button(String(localized: "goals.detail.ok", defaultValue: "OK", comment: "OK button")) {
                viewModel.adaptationError = nil
            }
        } message: {
            if let error = viewModel.adaptationError {
                Text(error)
            }
        }
        .task {
            // Auto-adapt plan when opening goal detail (silently, respects throttle)
            if currentGoal.isActive && !currentGoal.isPast && currentGoal.hasTrainingPlan {
                await viewModel.adaptPlanIfNeeded(for: currentGoal)
            }
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(spacing: Spacing.xl) {
            // Main info & Countdown
            HStack(alignment: .center, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.sm) {
                        ZStack {
                            RoundedRectangle(cornerRadius: Radius.sm)
                                .fill(Color.irPrimaryAccent.opacity(0.1))
                                .frame(width: 36, height: 36)
                            Image(systemName: currentGoal.raceType.icon)
                                .foregroundStyle(Color.irPrimaryAccent.gradient)
                        }
                        
                        Text(currentGoal.raceType.displayName)
                            .font(.headline)
                            .foregroundStyle(Color.irTextSecondary)
                    }

                    Text(currentGoal.targetDate, style: .date)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.irTextPrimary)

                    Text(currentGoal.fitnessLevel.displayName)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.irPrimaryAccent)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 4)
                        .background(Color.irPrimaryAccent.opacity(0.1))
                        .clipShape(Capsule())
                }

                Spacer()

                // Modern countdown ring
                if !currentGoal.isPast {
                    countdownRing
                }
            }

            // Stats Dashboard
            if currentGoal.hasTrainingPlan {
                HStack(spacing: Spacing.md) {
                    detailStatItem(
                        icon: "calendar",
                        value: "\(currentGoal.trainingPlan?.totalWeeks ?? 0)",
                        label: String(localized: "goals.detail.weeks", defaultValue: "Weeks", comment: "Goal detail - weeks stat")
                    )
                    
                    detailStatItem(
                        icon: "figure.run",
                        value: "\(currentGoal.completedWorkouts)/\(currentGoal.totalPlannedWorkouts)",
                        label: String(localized: "goals.detail.workouts", defaultValue: "Workouts", comment: "Goal detail - workouts stat")
                    )
                    
                    detailStatItem(
                        icon: "percent",
                        value: "\(Int(currentGoal.workoutCompletionRate * 100))%",
                        label: String(localized: "goals.detail.completion", defaultValue: "Done", comment: "Goal detail - completion stat")
                    )
                }
            }

            // Finish time & Notes for past races
            if currentGoal.isPastRace {
                VStack(spacing: Spacing.md) {
                    if let time = currentGoal.formattedFinishTime {
                        HStack {
                            Label(
                                String(localized: "goals.detail.finishTime", defaultValue: "Finish Time", comment: "Goal detail - finish time"),
                                systemImage: "stopwatch.fill"
                            )
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.irTextSecondary)
                            
                            Spacer()
                            
                            Text(time)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.irTextPrimary)
                                .monospacedDigit()
                        }
                        .padding()
                        .background(Color.irSurface.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    }

                    if let notes = currentGoal.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(String(localized: "goals.detail.notes", defaultValue: "Coach's Post-Race Notes", comment: "Goal detail - notes"))
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.irTextSecondary)
                                .textCase(.uppercase)
                            
                            Text(notes)
                                .font(.subheadline)
                                .foregroundStyle(Color.irTextPrimary)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.irSurface.opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                        }
                    }
                }
            }
        }
        .cardStyle(padding: Spacing.lg)
    }

    private func detailStatItem(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(Color.irPrimaryAccent)
            
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(Color.irTextPrimary)
            
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.irTextSecondary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .background(Color.irSurface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private var countdownRing: some View {
        ZStack {
            Circle()
                .stroke(Color.irBorder.opacity(0.3), lineWidth: 8)
                .frame(width: 90, height: 90)

            Circle()
                .trim(from: 0, to: currentGoal.progressPercentage)
                .stroke(
                    LinearGradient(colors: [Color.irPrimaryAccent, Color.irPrimaryAccent.opacity(0.7)], startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 90, height: 90)
                .shadow(color: Color.irPrimaryAccent.opacity(0.2), radius: 4, x: 0, y: 2)

            VStack(spacing: -2) {
                Text("\(currentGoal.daysRemaining)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.irTextPrimary)
                Text(String(localized: "goals.detail.daysLabel", defaultValue: "days", comment: "Goal countdown - days"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.irTextSecondary)
                    .textCase(.uppercase)
            }
        }
    }

    // MARK: - Generate Plan Card

    private var generatePlanCard: some View {
        VStack(spacing: Spacing.xl) {
            if viewModel.isGeneratingPlan {
                VStack(spacing: Spacing.lg) {
                    ZStack {
                        Circle()
                            .stroke(Color.irPrimaryAccent.opacity(0.1), lineWidth: 4)
                            .frame(width: 80, height: 80)
                        
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(Color.irPrimaryAccent)
                    }
                    
                    VStack(spacing: Spacing.xs) {
                        Text(String(localized: "goals.detail.generating", defaultValue: "Crafting your plan...", comment: "Goal detail - generating"))
                            .font(.headline)
                            .foregroundStyle(Color.irTextPrimary)
                        Text(String(localized: "goals.detail.generatingHint", defaultValue: "AI Coach is analyzing your profile", comment: "Goal detail - generating hint"))
                            .font(.subheadline)
                            .foregroundStyle(Color.irTextSecondary)
                    }
                }
                .padding(.vertical, Spacing.xl)
            } else {
                ZStack {
                    Circle()
                        .fill(Color.irPrimaryAccent.opacity(0.1))
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.irPrimaryAccent.gradient)
                        .symbolEffect(.bounce, options: .repeating)
                }

                VStack(spacing: Spacing.md) {
                    Text(String(localized: "goals.detail.generateTitle", defaultValue: "AI Training Plan", comment: "Goal detail - generate title"))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.irTextPrimary)

                    Text(String(localized: "goals.detail.generateDescription", defaultValue: "Unlock a personalized multi-week plan powered by AI to reach your goal safely and efficiently.", comment: "Goal detail - generate description"))
                        .font(.subheadline)
                        .foregroundStyle(Color.irTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.md)
                }

                Button {
                    Task {
                        await viewModel.generateTrainingPlan(for: currentGoal)
                    }
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                        Text(String(localized: "goals.detail.generateButton", defaultValue: "Generate My Plan", comment: "Goal button"))
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.md)
                    .background(Color.irPrimaryAccent.gradient)
                    .clipShape(Capsule())
                    .shadow(color: Color.irPrimaryAccent.opacity(0.3), radius: 8, x: 0, y: 4)
                }
            }
        }
        .cardStyle(padding: Spacing.lg)
    }

    // MARK: - Training Plan Section

    private func trainingPlanSection(_ plan: TrainingPlan) -> some View {
        VStack(alignment: .leading, spacing: Spacing.base) {
            // Adaptation banner
            if let assessment = plan.adaptationAssessment {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(Color.irPrimaryAccent)

                    Text(assessment)
                        .font(.caption)
                        .foregroundStyle(Color.irTextSecondary)
                }
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.irPrimaryAccent.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            }

            if viewModel.isAdaptingPlan {
                HStack(spacing: Spacing.sm) {
                    ProgressView()
                        .controlSize(.small)
                    Text(String(localized: "goals.detail.adapting", defaultValue: "Adapting plan...", comment: "Goal detail - adapting"))
                        .font(.caption)
                        .foregroundStyle(Color.irTextSecondary)
                }
            }

            // Plan header
            Text(plan.name)
                .font(.headline)
                .foregroundStyle(Color.irTextPrimary)

            Text(plan.goal)
                .font(.subheadline)
                .foregroundStyle(Color.irTextSecondary)

            // Tab picker
            Picker("", selection: $selectedPlanTab) {
                Text(String(localized: "goals.plan.currentWeek", defaultValue: "This Week", comment: "Plan tab - current week"))
                    .tag(0)
                Text(String(localized: "goals.plan.fullPlan", defaultValue: "Full Plan", comment: "Plan tab - full plan"))
                    .tag(1)
            }
            .pickerStyle(.segmented)

            if selectedPlanTab == 0 {
                currentWeekView(plan)
            } else {
                TrainingCalendarView(
                    goal: currentGoal,
                    plan: plan,
                    onToggleCompletion: { weekIndex, dayIndex in
                        viewModel.toggleDayCompletion(
                            goalId: currentGoal.id,
                            weekIndex: weekIndex,
                            dayIndex: dayIndex
                        )
                    }
                )
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedPlanTab)
    }

    // MARK: - Current Week View

    private func currentWeekView(_ plan: TrainingPlan) -> some View {
        let weekIndex = plan.currentWeekIndex ?? 0
        let week = plan.weeks[weekIndex]

        return VStack(alignment: .leading, spacing: Spacing.md) {
            // Week header
            HStack(spacing: Spacing.sm) {
                Circle()
                    .fill(week.phase.themeColor)
                    .frame(width: 10, height: 10)

                Text(String(localized: "goals.calendar.week", defaultValue: "Week", comment: "") + " \(week.weekNumber)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.irTextPrimary)

                Text("—")
                    .foregroundStyle(Color.irBorder)

                Text(week.phase.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(week.phase.themeColor)

                Spacer()

                if let volume = week.weeklyVolume {
                    Text(String(format: "%.1f km", volume))
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.irTextSecondary)
                }
            }

            if let notes = week.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(Color.irTextSecondary)
            }

            // Day list
            ForEach(Array(week.days.enumerated()), id: \.element.id) { dayIndex, day in
                currentWeekDayRow(day: day, weekIndex: weekIndex, dayIndex: dayIndex)
            }
        }
        .cardStyle()
    }

    private func currentWeekDayRow(day: TrainingDay, weekIndex: Int, dayIndex: Int) -> some View {
        HStack(spacing: Spacing.md) {
            // Day label
            Text(day.dayOfWeek.shortName)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.irTextSecondary)
                .frame(width: 30, alignment: .leading)

            if let workout = day.workout {
                // Workout card
                NavigationLink {
                    PlannedWorkoutDetailView(workout: workout, day: day)
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Rectangle()
                            .fill(workout.intensity.themeColor)
                            .frame(width: 3, height: 36)
                            .clipShape(Capsule())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(workout.name)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.irTextPrimary)
                                .lineLimit(1)

                            HStack(spacing: Spacing.xs) {
                                if !workout.formattedDistance.isEmpty {
                                    Text(workout.formattedDistance)
                                }
                                if !workout.formattedDuration.isEmpty {
                                    Text(workout.formattedDuration)
                                }
                                if let pace = workout.targetPace {
                                    Text(pace + "/km")
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(Color.irTextSecondary)
                        }

                        Spacer()

                        // Completion toggle
                        VStack(spacing: 2) {
                            Button {
                                viewModel.toggleDayCompletion(goalId: currentGoal.id, weekIndex: weekIndex, dayIndex: dayIndex)
                            } label: {
                                Image(systemName: day.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(day.isCompleted ? Color.irSuccess : Color.irBorder)
                            }

                            if day.completedWorkoutId != nil {
                                Text(String(localized: "goals.detail.autoTracked", defaultValue: "Auto", comment: "Auto-tracked label"))
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(Color.irPrimaryAccent)
                            }
                        }
                    }
                    .padding(Spacing.sm)
                    .background(Color.irSurface.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                }
                .buttonStyle(.plain)
            } else {
                HStack {
                    Image(systemName: "zzz")
                        .font(.caption2)
                        .foregroundStyle(Color.irTextSecondary.opacity(0.4))
                    Text(String(localized: "goals.calendar.rest", defaultValue: "Rest", comment: ""))
                        .font(.caption)
                        .foregroundStyle(Color.irTextSecondary.opacity(0.4))
                    Spacer()
                }
                .padding(.vertical, Spacing.xs)
            }
        }
    }

}
