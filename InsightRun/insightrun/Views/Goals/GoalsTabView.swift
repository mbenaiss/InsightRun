//
//  GoalsTabView.swift
//  InsightRun
//
//  Main tab view for race goals with countdown cards and race history
//

import SwiftUI

struct GoalsTabView: View {
    @StateObject private var viewModel = GoalsViewModel()
    @ObservedObject private var notificationRouter = NotificationRouter.shared
    @State private var deepLinkGoalId: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                if viewModel.activeGoals.isEmpty && viewModel.pastGoals.isEmpty && viewModel.raceHistory.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: Spacing.xl) {
                        // Active goals
                        if !viewModel.activeGoals.isEmpty {
                            VStack(alignment: .leading, spacing: Spacing.md) {
                                sectionHeader(String(localized: "goals.section.upcoming", defaultValue: "Upcoming Races", comment: "Goals tab - upcoming section"))

                                LazyVStack(spacing: Spacing.md) {
                                    ForEach(viewModel.activeGoals) { goal in
                                        NavigationLink(destination: GoalDetailView(goal: goal, viewModel: viewModel)) {
                                            GoalCard(goal: goal)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                            }
                        }

                        // Past goals (with training plans)
                        if !viewModel.pastGoals.isEmpty {
                            VStack(alignment: .leading, spacing: Spacing.md) {
                                sectionHeader(String(localized: "goals.section.past", defaultValue: "Past Goals", comment: "Goals tab - past section"))

                                LazyVStack(spacing: Spacing.md) {
                                    ForEach(viewModel.pastGoals) { goal in
                                        NavigationLink(destination: GoalDetailView(goal: goal, viewModel: viewModel)) {
                                            GoalCard(goal: goal)
                                                .opacity(0.85)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                            }
                        }

                        // Race history
                        if !viewModel.raceHistory.isEmpty {
                            VStack(alignment: .leading, spacing: Spacing.md) {
                                sectionHeader(String(localized: "goals.section.history", defaultValue: "Race History", comment: "Goals tab - history section"))

                                LazyVStack(spacing: Spacing.sm) {
                                    ForEach(viewModel.raceHistory) { goal in
                                        RaceHistoryCard(goal: goal) {
                                            viewModel.deleteGoal(goal)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .background(Color.irBackgroundApp)
            .navigationTitle(String(localized: "goals.title", defaultValue: "Goals", comment: "Goals tab title"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.showAddGoal = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.irPrimaryAccent.gradient)
                    }
                    .accessibilityIdentifier("goals-add")
                }
            }
            .sheet(isPresented: $viewModel.showAddGoal) {
                AddGoalSheet { goal in
                    viewModel.addGoal(goal)
                }
            }
            .navigationDestination(item: $deepLinkGoalId) { goalId in
                if let goal = viewModel.goals.first(where: { $0.id == goalId }) {
                    GoalDetailView(goal: goal, viewModel: viewModel)
                }
            }
            .onChange(of: notificationRouter.pendingGoalId, initial: true) { _, goalId in
                if let goalId {
                    viewModel.reload()
                    deepLinkGoalId = goalId
                    notificationRouter.pendingGoalId = nil
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .trainingDayCompleted)) { _ in
                viewModel.reload()
            }
            .task {
                let key = "goals.lastCatchUpAt"
                let now = Date().timeIntervalSince1970
                let last = UserDefaults.standard.double(forKey: key)
                guard now - last > 300 else { return } // throttle: 5 min
                UserDefaults.standard.set(now, forKey: key)
                await WorkoutMatchingService.shared.catchUpMatch()
                viewModel.reload()
            }
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.bold)
            .foregroundStyle(Color.irTextSecondary)
            .textCase(.uppercase)
            .padding(.leading, Spacing.xs)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.irPrimaryAccent.opacity(0.1))
                    .frame(width: 160, height: 160)
                
                Image(systemName: "target")
                    .font(.system(size: 80))
                    .foregroundStyle(Color.irPrimaryAccent.gradient)
                    .shadow(color: Color.irPrimaryAccent.opacity(0.3), radius: 10, x: 0, y: 5)
            }

            VStack(spacing: Spacing.md) {
                Text(String(localized: "goals.empty.title", defaultValue: "No Goals Yet", comment: "Goals tab - empty title"))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.irTextPrimary)

                Text(String(localized: "goals.empty.description", defaultValue: "Set a race goal and get a personalized training plan, or log your past races.", comment: "Goals tab - empty description"))
                    .font(.body)
                    .foregroundStyle(Color.irTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xxl)
            }

            Button {
                viewModel.showAddGoal = true
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Text(String(localized: "goals.empty.addButton", defaultValue: "Add a Goal", comment: "Goals tab - add button"))
                }
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, Spacing.md)
                .background(Color.irPrimaryAccent.gradient)
                .clipShape(Capsule())
                .shadow(color: Color.irPrimaryAccent.opacity(0.3), radius: 8, x: 0, y: 4)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

// MARK: - Goal Card

struct GoalCard: View {
    let goal: RaceGoal

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top) {
                // Icon with gradient background
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md)
                        .fill(Color.irPrimaryAccent.opacity(0.12))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: goal.raceType.icon)
                        .font(.title3)
                        .foregroundStyle(Color.irPrimaryAccent.gradient)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.raceName)
                        .font(.headline)
                        .foregroundStyle(Color.irTextPrimary)
                        .lineLimit(1)

                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                        Text(goal.targetDate, style: .date)
                            .font(.caption)
                    }
                    .foregroundStyle(Color.irTextSecondary)
                }

                Spacer()

                if !goal.isPast {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(goal.daysRemaining)")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(countdownColor.gradient)
                        Text(String(localized: "goals.card.days", defaultValue: "days", comment: "Goal card - days label"))
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.irTextSecondary)
                    }
                } else {
                    Text(String(localized: "goals.card.completed", defaultValue: "Completed", comment: "Goal card - completed label"))
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 4)
                        .background(Color.irSuccess.gradient)
                        .clipShape(Capsule())
                }
            }

            if goal.hasTrainingPlan {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        if let phase = goal.currentPhase {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(phase.themeColor)
                                    .frame(width: 6, height: 6)
                                Text(phase.displayName)
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(phase.themeColor)
                            }
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 4)
                            .background(phase.themeColor.opacity(0.1))
                            .clipShape(Capsule())
                        }

                        Spacer()

                        Text("\(goal.completedWorkouts)/\(goal.totalPlannedWorkouts) " + String(localized: "goals.card.workouts", defaultValue: "workouts", comment: "Goal card - workouts count"))
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.irTextSecondary)
                    }

                    // Modern Progress Bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.irBorder.opacity(0.5))
                                .frame(height: 6)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.irPrimaryAccent.gradient)
                                .frame(width: geometry.size.width * goal.workoutCompletionRate, height: 6)
                        }
                    }
                    .frame(height: 6)
                }
                .padding(.top, Spacing.xs)
            } else if !goal.isPastRace {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                    Text(String(localized: "goals.card.generateHint", defaultValue: "Tap to generate training plan", comment: "Goal card - no plan hint"))
                        .font(.caption)
                }
                .fontWeight(.semibold)
                .foregroundStyle(Color.irPrimaryAccent)
                .padding(.vertical, Spacing.xs)
            }
        }
        .cardStyle(padding: Spacing.base)
    }

    private var countdownColor: Color {
        if goal.daysRemaining <= 7 { return Color.irError }
        else if goal.daysRemaining <= 30 { return Color.irWarning }
        else { return Color.irPrimaryAccent }
    }

}

// MARK: - Race History Card

struct RaceHistoryCard: View {
    let goal: RaceGoal
    let onDelete: () -> Void
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(Color.irPrimaryAccent.opacity(0.1))
                    .frame(width: 40, height: 40)
                
                Image(systemName: goal.raceType.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.irPrimaryAccent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(goal.raceName)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.irTextPrimary)
                    .lineLimit(1)

                Text(goal.targetDate, style: .date)
                    .font(.caption2)
                    .foregroundStyle(Color.irTextSecondary)
            }

            Spacer()

            if let time = goal.formattedFinishTime {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(time)
                        .font(.system(.subheadline, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.irTextPrimary)
                    Text(String(localized: "goals.history.finishTime", defaultValue: "finish", comment: "Race history - finish time label"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.irTextSecondary)
                        .textCase(.uppercase)
                }
            }
        }
        .cardStyle(padding: Spacing.md, cornerRadius: Radius.lg)
        .contextMenu {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label(String(localized: "goals.history.delete", defaultValue: "Delete", comment: "Race history - delete"), systemImage: "trash")
            }
        }
        .confirmationDialog(
            String(localized: "goals.history.deleteConfirmation", defaultValue: "Delete this race?", comment: "Race history - delete confirmation"),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "goals.history.deleteButton", defaultValue: "Delete", comment: "Delete button"), role: .destructive) {
                onDelete()
            }
        }
    }
}
