//
//  GoalDetailView.swift
//  InsightRun
//
//  Artboard 09 — V4 goal detail (gradient hero · KPI grid · coach summary · week / plan tabs)
//

import SwiftUI

struct GoalDetailView: View {
    let goal: RaceGoal
    @ObservedObject var viewModel: GoalsViewModel
    @EnvironmentObject private var revenueCatManager: RevenueCatManager
    @State private var showDeleteConfirmation = false
    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var selectedPlanTab = 0 // 0 = current week, 1 = full plan
    @State private var showSubscriptionPaywall = false
    @Environment(\.dismiss) private var dismiss

    private var currentGoal: RaceGoal {
        viewModel.goals.first(where: { $0.id == goal.id }) ?? goal
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                heroCard

                if currentGoal.hasTrainingPlan {
                    targetTimeAndKpiCard
                }

                if let plan = currentGoal.trainingPlan,
                   let assessment = plan.adaptationAssessment,
                   !assessment.isEmpty
                {
                    coachSummaryCard(assessment: assessment)
                }

                if let plan = currentGoal.trainingPlan, !plan.goal.isEmpty {
                    missionText(plan.goal)
                }

                if currentGoal.isPastRace {
                    pastRaceFooter
                }

                if let plan = currentGoal.trainingPlan {
                    trainingPlanSection(plan)
                } else if !currentGoal.isPastRace {
                    generatePlanCard
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Color.irBackgroundApp)
        .navigationTitle(currentGoal.raceName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { trailingMenu }
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
        .sheet(isPresented: $showSubscriptionPaywall) {
            SubscriptionPaywallView(isInitialFlow: false)
                .environmentObject(revenueCatManager)
        }
        .sheet(isPresented: $viewModel.needsConsent) {
            AIConsentSheet(
                onConsent: {
                    viewModel.needsConsent = false
                    Task { await viewModel.resumePendingGeneration() }
                },
                onDecline: {
                    viewModel.needsConsent = false
                    viewModel.clearPendingGeneration()
                }
            )
        }
        .task {
            if currentGoal.isActive && !currentGoal.isPast && currentGoal.hasTrainingPlan {
                await viewModel.adaptPlanIfNeeded(for: currentGoal)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var trailingMenu: some ToolbarContent {
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
                            await viewModel.setPlanStartDate(goalId: currentGoal.id, newStart: Date())
                        }
                    } label: {
                        Label(
                            String(localized: "goals.detail.startToday", defaultValue: "Start Today", comment: "Goal detail - start today"),
                            systemImage: "calendar.badge.clock"
                        )
                    }

                    Button {
                        handleGenerateTap(for: currentGoal)
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
                ZStack {
                    Circle()
                        .fill(Color.irSurface)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.irBorder, lineWidth: 0.5)
                        )

                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Color.irTextSecondary)
                }
            }
        }
    }

    // MARK: - Plan Generation

    private var generateButtonTitle: String {
        if revenueCatManager.hasAIAccess {
            return String(localized: "goals.detail.generateButton", defaultValue: "Generate My Plan", comment: "Goal button")
        }
        return String(localized: "goals.detail.subscribeToGenerate", defaultValue: "Subscribe to Unlock", comment: "Goal button - subscribe CTA")
    }

    private func handleGenerateTap(for goal: RaceGoal) {
        if !revenueCatManager.hasAIAccess {
            showSubscriptionPaywall = true
            return
        }
        Task {
            await viewModel.generateTrainingPlan(for: goal)
        }
    }

    // MARK: - Hero card (V4 gradient)

    private var heroCard: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(Color.irPrimaryAccent.opacity(0.20))
                            .frame(width: 32, height: 32)

                        Image(systemName: currentGoal.raceType.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.irPrimaryAccent)
                    }

                    Text(currentGoal.raceType.displayName)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.irTextSecondary)
                }
                .padding(.bottom, 6)

                Text(formattedHeroDate)
                    .font(.system(size: 22, weight: .heavy))
                    .tracking(-0.44) // -0.02em on 22pt
                    .foregroundStyle(Color.irTextPrimary)

                Text(formattedHeroWeekday)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.irTextSecondary)
                    .padding(.top, 4)
            }

            Spacer(minLength: 8)

            if !currentGoal.isPast {
                GoalCountdownRing(days: currentGoal.daysRemaining)
            } else {
                Text(String(localized: "goals.card.completed", defaultValue: "Completed", comment: "Goal card - completed label"))
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.irSuccess)
                    .clipShape(Capsule())
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    // accent 8% over #141416
                    Color(red: 0.0784, green: 0.0784, blue: 0.0863).blended(with: Color.irPrimaryAccent, fraction: 0.08),
                    // #0e0e10 at 80%
                    Color(red: 0.0549, green: 0.0549, blue: 0.0627)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }

    private var formattedHeroDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: currentGoal.targetDate)
    }

    private var formattedHeroWeekday: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "EEEE"
        return formatter.string(from: currentGoal.targetDate).lowercased()
    }

    // MARK: - Target time + KPI grid

    private var targetTimeAndKpiCard: some View {
        VStack(spacing: 0) {
            if let formatted = currentGoal.formattedTargetTime {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(Color.irPrimaryAccent)

                        Text(String(localized: "goals.detail.targetTime", defaultValue: "Target time", comment: "Goal detail - target time label"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.irTextPrimary)
                    }

                    Spacer()

                    Text(formatted)
                        .font(.system(size: 24, weight: .heavy, design: .monospaced))
                        .tracking(-0.48) // -0.02em on 24pt
                        .foregroundStyle(Color.irTextPrimary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Rectangle()
                    .fill(Color.irBorder)
                    .frame(height: 0.5)
            }

            kpiGrid
        }
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }

    private var kpiGrid: some View {
        HStack(spacing: 0) {
            kpiCell(
                icon: "calendar",
                value: "\(currentGoal.trainingPlan?.totalWeeks ?? 0)",
                label: String(localized: "goals.detail.weeks", defaultValue: "Weeks", comment: "Goal detail - weeks stat"),
                monospaced: false
            )

            Rectangle()
                .fill(Color.irBorder)
                .frame(width: 0.5)

            kpiCell(
                icon: "figure.run",
                value: "\(currentGoal.completedWorkouts) / \(currentGoal.totalPlannedWorkouts)",
                label: String(localized: "goals.detail.workouts", defaultValue: "Workouts", comment: "Goal detail - workouts stat"),
                monospaced: true
            )

            Rectangle()
                .fill(Color.irBorder)
                .frame(width: 0.5)

            kpiCell(
                icon: "percent",
                value: "\(Int(currentGoal.workoutCompletionRate * 100))%",
                label: String(localized: "goals.detail.completion", defaultValue: "Done", comment: "Goal detail - completion stat"),
                monospaced: false,
                valueColor: Color.irPrimaryAccent
            )
        }
    }

    private func kpiCell(
        icon: String,
        value: String,
        label: String,
        monospaced: Bool,
        valueColor: Color = Color.irTextPrimary
    ) -> some View {
        VStack(spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Color.irPrimaryAccent)
                .frame(width: 14, height: 14)
                .padding(.bottom, 6)

            Text(value)
                .font(.system(size: 18, weight: .heavy, design: monospaced ? .monospaced : .rounded))
                .tracking(-0.36) // -0.02em on 18pt
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.08) // 0.12em on 9pt
                .foregroundStyle(Color.irTextSecondary.opacity(0.6))
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
    }

    // MARK: - Coach summary (highlighter "100%" effect)

    private func coachSummaryCard(assessment: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(
                        LinearGradient(
                            colors: [Color.irPrimaryAccent, Color.irAIAccentSecondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 22, height: 22)

                Text("✦")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.black)
            }
            .padding(.top, 2)

            Text(assessment)
                .font(.system(size: 12.5))
                .lineSpacing(6) // ~ line-height 1.55 on 12.5pt
                .foregroundStyle(Color.irTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Mission

    private func missionText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14))
            .lineSpacing(3) // ~ line-height 1.5 on 14pt
            .foregroundStyle(Color.irTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    // MARK: - Past race footer

    private var pastRaceFooter: some View {
        VStack(spacing: 12) {
            if let time = currentGoal.formattedFinishTime {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "stopwatch.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.irPrimaryAccent)
                        Text(String(localized: "goals.detail.finishTime", defaultValue: "Finish Time", comment: "Goal detail - finish time"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.irTextPrimary)
                    }

                    Spacer()

                    Text(time)
                        .font(.system(size: 22, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Color.irTextPrimary)
                }
                .padding(16)
                .background(Color.irCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Color.irBorder, lineWidth: 0.5)
                )
            }

            if let notes = currentGoal.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "goals.detail.notes", defaultValue: "Coach's Post-Race Notes", comment: "Goal detail - notes"))
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.4)
                        .foregroundStyle(Color.irTextSecondary)
                        .textCase(.uppercase)

                    Text(notes)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.irTextPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.irCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Color.irBorder, lineWidth: 0.5)
                )
            }
        }
    }

    // MARK: - Generate Plan Card

    private var generatePlanCard: some View {
        VStack(spacing: 24) {
            if viewModel.isGeneratingPlan {
                generatingPlanView
            } else {
                generatePlanCallToAction
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }

    private var generatingPlanView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color.irPrimaryAccent.opacity(0.10), lineWidth: 4)
                    .frame(width: 80, height: 80)

                ProgressView()
                    .scaleEffect(1.5)
                    .tint(Color.irPrimaryAccent)
            }

            VStack(spacing: 6) {
                Text(String(localized: "goals.detail.generating", defaultValue: "Crafting your plan...", comment: "Goal detail - generating"))
                    .font(.headline)
                    .foregroundStyle(Color.irTextPrimary)
                Text(String(localized: "goals.detail.generatingHint", defaultValue: "AI Coach is analyzing your profile", comment: "Goal detail - generating hint"))
                    .font(.subheadline)
                    .foregroundStyle(Color.irTextSecondary)
            }
        }
        .padding(.vertical, 24)
    }

    private var generatePlanCallToAction: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.irPrimaryAccent.opacity(0.10))
                    .frame(width: 100, height: 100)

                Image(systemName: "sparkles")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.irPrimaryAccent.gradient)
                    .symbolEffect(.bounce, options: .repeating)
            }

            VStack(spacing: 12) {
                Text(String(localized: "goals.detail.generateTitle", defaultValue: "AI Training Plan", comment: "Goal detail - generate title"))
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.irTextPrimary)

                Text(String(localized: "goals.detail.generateDescription", defaultValue: "Unlock a personalized multi-week plan powered by AI to reach your goal safely and efficiently.", comment: "Goal detail - generate description"))
                    .font(.subheadline)
                    .foregroundStyle(Color.irTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }

            Button {
                handleGenerateTap(for: currentGoal)
            } label: {
                HStack {
                    Image(systemName: revenueCatManager.hasAIAccess ? "sparkles" : "lock.fill")
                    Text(generateButtonTitle)
                }
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.irPrimaryAccent.gradient)
                .clipShape(Capsule())
                .shadow(color: Color.irPrimaryAccent.opacity(0.3), radius: 8, x: 0, y: 4)
            }
        }
    }

    // MARK: - Training plan section (tabs)

    private func trainingPlanSection(_ plan: TrainingPlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if viewModel.isAdaptingPlan {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(String(localized: "goals.detail.adapting", defaultValue: "Adapting plan...", comment: "Goal detail - adapting"))
                        .font(.caption)
                        .foregroundStyle(Color.irTextSecondary)
                }
            }

            planTabPicker

            if selectedPlanTab == 0 {
                currentWeekView(plan)
            } else {
                fullPlanList(plan)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedPlanTab)
    }

    private var planTabPicker: some View {
        HStack(spacing: 0) {
            ForEach(0..<2, id: \.self) { index in
                planTabButton(index: index)
            }
        }
        .padding(3)
        .background(Color.irSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }

    private func planTabButton(index: Int) -> some View {
        let label = index == 0
            ? String(localized: "goals.plan.currentWeek", defaultValue: "This Week", comment: "Plan tab - current week")
            : String(localized: "goals.plan.fullPlan", defaultValue: "Full Plan", comment: "Plan tab - full plan")

        let isActive = selectedPlanTab == index

        return Button {
            selectedPlanTab = index
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isActive ? Color.irTextPrimary : Color.irTextSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    isActive
                        ? AnyShapeStyle(Color.white.opacity(0.08))
                        : AnyShapeStyle(Color.clear)
                )
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Current Week View

    @ViewBuilder
    private func currentWeekView(_ plan: TrainingPlan) -> some View {
        if let weekIndex = plan.currentWeekIndex {
            weekContent(plan, weekIndex: weekIndex)
        } else if let start = plan.startDate, start > Date() {
            planNotStartedView(start: start)
        } else {
            weekContent(plan, weekIndex: 0)
        }
    }

    private func planNotStartedView(start: Date) -> some View {
        let days = max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: start)).day ?? 0)
        let template = String(localized: "goals.plan.notStartedMessage", defaultValue: "Your training plan begins on %1$@ (in %2$d days).", comment: "Plan not started - message: %1$@ = date, %2$d = days")
        let message = String(format: template, start.formatted(date: .long, time: .omitted), days)

        return VStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.largeTitle)
                .foregroundStyle(Color.irPrimaryAccent.gradient)

            Text(String(localized: "goals.plan.notStartedTitle", defaultValue: "Plan starts soon", comment: "Plan not started - title"))
                .font(.headline)
                .foregroundStyle(Color.irTextPrimary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.irTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }

    private func weekContent(_ plan: TrainingPlan, weekIndex: Int) -> some View {
        let week = plan.weeks[weekIndex]

        return VStack(alignment: .leading, spacing: 0) {
            weekHeader(week)
                .padding(.bottom, 4)

            if let notes = week.notes, !notes.isEmpty {
                Text(notes)
                    .font(.system(size: 12))
                    .italic()
                    .lineSpacing(2)
                    .foregroundStyle(Color.irTextSecondary)
                    .padding(.bottom, 14)
            } else {
                Spacer().frame(height: 14)
            }

            VStack(spacing: 8) {
                ForEach(Array(week.days.enumerated()), id: \.element.id) { dayIndex, day in
                    dayRow(day: day, weekIndex: weekIndex, dayIndex: dayIndex)
                }
            }
        }
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 14, trailing: 16))
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }

    private func weekHeader(_ week: TrainingWeek) -> some View {
        let phaseColor = phaseColor(week.phase)
        return HStack(spacing: 8) {
            Circle()
                .fill(phaseColor)
                .frame(width: 7, height: 7)

            Text(String(localized: "goals.calendar.week", defaultValue: "Week", comment: "") + " \(week.weekNumber)")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.irTextPrimary)

            Text(week.phase.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(phaseColor)

            Spacer()

            if let volume = week.weeklyVolume {
                Text(String(format: "%.1f km", volume))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.irTextSecondary)
            }
        }
    }

    // MARK: - Day rows

    @ViewBuilder
    private func dayRow(day: TrainingDay, weekIndex: Int, dayIndex: Int) -> some View {
        if day.workout == nil {
            restDayRow(day: day)
        } else {
            workoutDayRow(day: day, weekIndex: weekIndex, dayIndex: dayIndex)
        }
    }

    private func restDayRow(day: TrainingDay) -> some View {
        HStack(spacing: 12) {
            Text(day.dayOfWeek.shortName.lowercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.irTextSecondary.opacity(0.6))
                .frame(width: 36, alignment: .leading)

            Image(systemName: "moon.zzz")
                .font(.system(size: 11))
                .foregroundStyle(Color.irTextSecondary.opacity(0.6))
                .frame(width: 14, height: 14)

            Text(String(localized: "goals.calendar.rest", defaultValue: "Rest", comment: ""))
                .font(.system(size: 12.5))
                .foregroundStyle(Color.irTextSecondary.opacity(0.6))

            Spacer()
        }
        .padding(.vertical, 6)
    }

    private func workoutDayRow(day: TrainingDay, weekIndex: Int, dayIndex: Int) -> some View {
        guard let workout = day.workout else {
            return AnyView(EmptyView())
        }

        let isDone = day.isCompleted
        let intensityColor = workoutIntensityColor(workout)

        return AnyView(
            HStack(spacing: 12) {
                Text(day.dayOfWeek.shortName.lowercased())
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.irTextSecondary)
                    .frame(width: 36, alignment: .leading)

                NavigationLink {
                    PlannedWorkoutDetailView(
                        workout: workout,
                        day: day,
                        isPast: isDayPast(weekIndex: weekIndex, day: day),
                        currentDate: currentGoal.trainingPlan?.effectiveDate(weekIndex: weekIndex, day: day),
                        onToggleSkip: isRaceDay(weekIndex: weekIndex, day: day) ? nil : {
                            viewModel.toggleDaySkipped(
                                goalId: currentGoal.id,
                                weekIndex: weekIndex,
                                dayIndex: dayIndex
                            )
                        },
                        onMove: isRaceDay(weekIndex: weekIndex, day: day) ? nil : { newDate in
                            viewModel.setDayDateOverride(
                                goalId: currentGoal.id,
                                weekIndex: weekIndex,
                                dayIndex: dayIndex,
                                newDate: newDate
                            )
                        }
                    )
                } label: {
                    workoutCard(workout: workout, isDone: isDone, intensityColor: intensityColor)
                }
                .buttonStyle(.plain)

                completionBadge(isCompleted: isDone, isSkipped: day.isSkipped) {
                    viewModel.toggleDayCompletion(
                        goalId: currentGoal.id,
                        weekIndex: weekIndex,
                        dayIndex: dayIndex
                    )
                }
            }
        )
    }

    private func workoutCard(
        workout: PlannedWorkout,
        isDone: Bool,
        intensityColor: Color
    ) -> some View {
        ZStack(alignment: .leading) {
            VStack(alignment: .leading, spacing: 0) {
                workoutTitle(workout)
                    .padding(.bottom, 2)

                workoutStats(workout)
            }
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Left intensity bar (top 8, bottom 8 inset → use vertical padding)
            RoundedRectangle(cornerRadius: 2)
                .fill(intensityColor)
                .frame(width: 3)
                .padding(.vertical, 8)
        }
        .background(
            isDone
                ? Color.irSuccess.opacity(0.04)
                : Color.irSurface
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isDone ? Color.irSuccess.opacity(0.25) : Color.irBorder,
                    lineWidth: 0.5
                )
        )
    }

    @ViewBuilder
    private func workoutTitle(_ workout: PlannedWorkout) -> some View {
        let parts = splitWorkoutTitle(workout.name)
        if let subtitle = parts.subtitle {
            HStack(spacing: 4) {
                Text(parts.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.irTextPrimary)

                Text("— \(subtitle)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.irTextSecondary)
            }
            .lineLimit(1)
        } else {
            Text(workout.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.irTextPrimary)
                .lineLimit(1)
        }
    }

    private func splitWorkoutTitle(_ name: String) -> (title: String, subtitle: String?) {
        // Match "Title — subtitle" or "Title - subtitle" patterns.
        for separator in [" — ", " – ", " - "] {
            if let range = name.range(of: separator) {
                return (String(name[..<range.lowerBound]), String(name[range.upperBound...]))
            }
        }
        return (name, nil)
    }

    private func workoutStats(_ workout: PlannedWorkout) -> some View {
        HStack(spacing: 10) {
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
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(Color.irTextSecondary.opacity(0.6))
    }

    private func completionBadge(
        isCompleted: Bool,
        isSkipped: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isCompleted ? Color.irSuccess : Color.clear)
                    .frame(width: 24, height: 24)

                Circle()
                    .strokeBorder(
                        isCompleted ? Color.irSuccess : Color.white.opacity(0.14),
                        lineWidth: 1.5
                    )
                    .frame(width: 24, height: 24)

                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.black)
                } else if isSkipped {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Color.irTextSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Full plan list (V4 weeks)

    private func fullPlanList(_ plan: TrainingPlan) -> some View {
        VStack(spacing: 8) {
            ForEach(Array(plan.weeks.enumerated()), id: \.element.id) { weekIndex, week in
                fullPlanWeekRow(plan: plan, week: week, weekIndex: weekIndex)
            }
        }
    }

    private func fullPlanWeekRow(plan: TrainingPlan, week: TrainingWeek, weekIndex: Int) -> some View {
        let phaseColor = phaseColor(week.phase)
        let isCurrent = plan.currentWeekIndex == weekIndex
        let totalWorkouts = week.workoutCount
        let doneWorkouts = week.days.filter { $0.workout != nil && $0.isCompleted }.count

        return HStack(spacing: 12) {
            Circle()
                .fill(phaseColor)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(String(localized: "goals.calendar.week", defaultValue: "Week", comment: "") + " \(week.weekNumber)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.irTextPrimary)

                    if isCurrent {
                        Text(String(localized: "goals.plan.current", defaultValue: "IN PROGRESS", comment: "Plan - current week badge"))
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(0.36) // 0.04em on 9pt
                            .foregroundStyle(Color.irPrimaryAccent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(Color.irPrimaryAccent.opacity(0.18))
                            )
                    }
                }

                Text(week.phase.displayName.uppercased())
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.2) // 0.12em on 10pt
                    .foregroundStyle(phaseColor)
            }

            Spacer(minLength: 8)

            if totalWorkouts > 0 {
                HStack(spacing: 3) {
                    ForEach(0..<totalWorkouts, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(i < doneWorkouts ? phaseColor : Color.white.opacity(0.10))
                            .frame(width: 6, height: 6)
                    }
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.irTextSecondary.opacity(0.6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(
                    isCurrent ? Color.irPrimaryAccent.opacity(0.40) : Color.irBorder,
                    lineWidth: 0.5
                )
        )
    }

    // MARK: - Helpers

    private func isDayPast(weekIndex: Int, day: TrainingDay) -> Bool {
        guard let plan = currentGoal.trainingPlan else { return false }
        return TrainingCalendarView.isDayPast(plan: plan, weekIndex: weekIndex, day: day)
    }

    private func isRaceDay(weekIndex: Int, day: TrainingDay) -> Bool {
        guard let plan = currentGoal.trainingPlan else { return false }
        return TrainingCalendarView.isRaceDay(plan: plan, goal: currentGoal, weekIndex: weekIndex, day: day)
    }

    /// V4 phase palette: base = lime accent, build = warn, peak = red, taper = success, recovery = purple.
    private func phaseColor(_ phase: TrainingPhase) -> Color {
        switch phase {
        case .base: return Color.irPrimaryAccent
        case .build: return Color.irWarning
        case .peak: return .red
        case .taper: return Color.irSuccess
        case .recovery: return .purple
        }
    }

    /// Maps a workout's intensity / type to the V4 left-bar color.
    /// intervals & speed → warn, easy → success, long run → accent, fallback → accent.
    private func workoutIntensityColor(_ workout: PlannedWorkout) -> Color {
        switch workout.type {
        case .intervals, .hillRepeats, .fartlek, .tempo:
            return Color.irWarning
        case .easyRun, .recovery:
            return Color.irSuccess
        case .longRun:
            return Color.irPrimaryAccent
        case .crossTraining:
            return .purple
        }
    }
}

// MARK: - Color blending helper

private extension Color {
    /// Linear blend toward `other` by `fraction` (0…1) — RGB only, ignores alpha.
    /// Used to mimic CSS `color-mix(in oklab, A f%, B)` for static design swatches.
    func blended(with other: Color, fraction: Double) -> Color {
        let f = max(0, min(1, fraction))
        let a = UIColor(self)
        let b = UIColor(other)
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return Color(
            red: Double(ar) * (1 - f) + Double(br) * f,
            green: Double(ag) * (1 - f) + Double(bg) * f,
            blue: Double(ab) * (1 - f) + Double(bb) * f
        )
    }
}
