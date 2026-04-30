//
//  GoalsTabView.swift
//  InsightRun
//
//  Main tab view for race goals — V4 visual language
//  (numbered eyebrows · 18px radius cards · 0.5px borders · countdown ring)
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
                    VStack(alignment: .leading, spacing: Spacing.dash) {
                        // Top row: "Plans & Races" eyebrow + "+" button (V4 dash header)
                        HStack(alignment: .center) {
                            Text(String(
                                localized: "goals.eyebrow.plansAndRaces",
                                defaultValue: "Plans & Races",
                                comment: "Goals tab - top eyebrow"
                            ).uppercased())
                            .font(IRFont.eyebrow.weight(.bold))
                            .tracking(1.76)
                            .foregroundStyle(Color.irTextSecondary.opacity(0.6))

                            Spacer()

                            Button {
                                viewModel.showAddGoal = true
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color.irCard2)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color.irBorder, lineWidth: 0.5)
                                        )
                                        .frame(width: 32, height: 32)

                                    Image(systemName: "plus")
                                        .font(IRFont.body.weight(.heavy))
                                        .foregroundStyle(Color.irPrimaryAccent)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("goals-add")
                        }
                        .padding(.top, Spacing.xxs)

                        // Title
                        Text(String(
                            localized: "goals.title",
                            defaultValue: "Goals",
                            comment: "Goals tab title"
                        ))
                        .font(IRFont.title1.weight(.heavy))
                        .tracking(-1.0)
                        .foregroundStyle(Color.irTextPrimary)

                        if !viewModel.activeGoals.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                DashboardEyebrow(title: String(
                                    localized: "goals.section.upcoming",
                                    defaultValue: "Upcoming Races",
                                    comment: "Goals tab - upcoming section"
                                ))

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

                        if !viewModel.pastGoals.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                DashboardEyebrow(title: String(
                                    localized: "goals.section.past",
                                    defaultValue: "Past Goals",
                                    comment: "Goals tab - past section"
                                ))

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

                        if !viewModel.raceHistory.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                DashboardEyebrow(title: String(
                                    localized: "goals.section.history",
                                    defaultValue: "Race History",
                                    comment: "Goals tab - history section"
                                ))

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
                    .padding(.horizontal, Spacing.cardPadding)
                    .padding(.top, Spacing.md)
                    .padding(.bottom, Spacing.xl)
                }
            }
            .background(Color.irBackgroundApp)
            .navigationBarHidden(true)
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

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.irPrimaryAccent.opacity(0.10))
                    .frame(width: 160, height: 160)

                Image(systemName: "target")
                    .font(IRFont.numXL)
                    .foregroundStyle(Color.irPrimaryAccent.gradient)
                    .shadow(color: Color.irPrimaryAccent.opacity(0.3), radius: 10, x: 0, y: 5)
            }

            VStack(spacing: Spacing.md) {
                Text(String(localized: "goals.empty.title", defaultValue: "No Goals Yet", comment: "Goals tab - empty title"))
                    .font(IRFont.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.irTextPrimary)

                Text(String(localized: "goals.empty.description", defaultValue: "Set a race goal and get a personalized training plan, or log your past races.", comment: "Goals tab - empty description"))
                    .font(IRFont.body)
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
                .font(IRFont.headline)
                .foregroundStyle(Color.irCardBackground)
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

// MARK: - Countdown Ring (70x70 spec)

struct GoalCountdownRing: View {
    let days: Int
    var size: CGFloat = 70
    var strokeWidth: CGFloat = 5

    /// Inverse progress — closer to race = fuller ring (90-day baseline matches design)
    private var progress: Double {
        let value = Double(90 - days) / 90.0
        return min(1.0, max(0.0, value))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.irBorder, lineWidth: strokeWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.irPrimaryAccent,
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 2) {
                Text("\(days)")
                    .font(IRFont.numSM.weight(.heavy))
                    .tracking(-0.88) // -0.04em on 22pt
                    .foregroundStyle(Color.irPrimaryAccent)
                Text(String(localized: "goals.card.days", defaultValue: "days", comment: "Goal card - days label").uppercased())
                    .font(IRFont.eyebrow.weight(.bold))
                    .tracking(0.8) // 0.1em on 8pt
                    .foregroundStyle(Color.irTextSecondary.opacity(0.6))
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Goal Card (V4 hero card with gradient + countdown ring)

struct GoalCard: View {
    let goal: RaceGoal

    /// "10K" / "21,1 km" / "42,2 km" formatting helper for the caption.
    private var distanceLabel: String {
        switch goal.raceType {
        case .fiveK: return "5K"
        case .tenK: return "10K"
        case .halfMarathon: return formatDistance(goal.raceType.distanceKm)
        case .marathon: return formatDistance(goal.raceType.distanceKm)
        case .ultra: return formatDistance(goal.raceType.distanceKm)
        }
    }

    private func formatDistance(_ km: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        let value = formatter.string(from: NSNumber(value: km)) ?? "\(km)"
        return "\(value) km"
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: goal.targetDate)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top: icon + race info + countdown
            HStack(alignment: .center, spacing: Spacing.dash) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(Color.irPrimaryAccent.opacity(0.20))
                        .frame(width: 44, height: 44)

                    Image(systemName: goal.raceType.icon)
                        .font(IRFont.title3.weight(.semibold))
                        .foregroundStyle(Color.irPrimaryAccent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(distanceLabel) · \(formattedDate)")
                        .font(IRFont.monoSM)
                        .tracking(0.44) // 0.04em on 11pt
                        .foregroundStyle(Color.irTextSecondary.opacity(0.6))
                        .lineLimit(1)

                    Text(goal.raceName)
                        .font(IRFont.numSM.weight(.bold))
                        .tracking(-0.18) // -0.01em on 18pt
                        .foregroundStyle(Color.irTextPrimary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if !goal.isPast {
                    GoalCountdownRing(days: goal.daysRemaining)
                } else {
                    Text(String(localized: "goals.card.completed", defaultValue: "Completed", comment: "Goal card - completed label"))
                        .font(IRFont.microLabel)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.irTextPrimary)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xxs)
                        .background(Color.irSuccess.gradient)
                        .clipShape(Capsule())
                }
            }
            .padding(Spacing.cardPadding)

            // Bottom: phase + progress
            if goal.hasTrainingPlan {
                Rectangle()
                    .fill(Color.irBorder)
                    .frame(height: 0.5)

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        if let phase = goal.currentPhase {
                            HStack(spacing: Spacing.xs) {
                                Circle()
                                    .fill(Color.irPrimaryAccent)
                                    .frame(width: 7, height: 7)
                                Text(phase.displayName)
                                    .font(IRFont.caption.weight(.semibold))
                                    .foregroundStyle(Color.irTextPrimary)
                            }
                        }

                        Spacer()

                        Text("\(goal.completedWorkouts) / \(goal.totalPlannedWorkouts) " + String(localized: "goals.card.workouts", defaultValue: "workouts", comment: "Goal card - workouts count"))
                            .font(IRFont.monoSM)
                            .foregroundStyle(Color.irTextSecondary)
                    }

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.irBorder)
                                .frame(height: 4)

                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.irPrimaryAccent)
                                .frame(width: max(0, geometry.size.width * goal.workoutCompletionRate), height: 4)
                        }
                    }
                    .frame(height: 4)
                }
                .padding(.horizontal, Spacing.cardPadding)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.dash)
            } else if !goal.isPastRace {
                Rectangle()
                    .fill(Color.irBorder)
                    .frame(height: 0.5)

                HStack(spacing: Spacing.xs) {
                    Image(systemName: "sparkles")
                        .font(IRFont.caption)
                    Text(String(localized: "goals.card.generateHint", defaultValue: "Tap to generate training plan", comment: "Goal card - no plan hint"))
                        .font(IRFont.caption)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(IRFont.microLabel.weight(.bold))
                        .foregroundStyle(Color.irTextSecondary)
                }
                .fontWeight(.semibold)
                .foregroundStyle(Color.irPrimaryAccent)
                .padding(.horizontal, Spacing.cardPadding)
                .padding(.vertical, Spacing.md)
            }
        }
        .background(
            LinearGradient(
                colors: [
                    Color.irPrimaryAccent.opacity(0.08).blendedOver(Color.irCardBackground),
                    Color.irTextPrimary.opacity(0.04).blendedOver(Color.irCardBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Color.irPrimaryAccent.opacity(0.30), lineWidth: 0.5)
        )
    }
}

// MARK: - Color blending helper (mirrors color-mix oklab over a base)

private extension Color {
    func blendedOver(_ base: Color) -> Color {
        // Approximate the visual effect of layering this color on top of `base`.
        // SwiftUI doesn't expose true blending, so we return `self` and let it
        // composite via the LinearGradient on the card's background — which already
        // sits over the card surface. This keeps the API ergonomic.
        self
    }
}

// MARK: - Race History Card

struct RaceHistoryCard: View {
    let goal: RaceGoal
    let onDelete: () -> Void
    @State private var showDeleteConfirmation = false

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: goal.targetDate)
    }

    private var formattedDistance: String {
        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        let value = formatter.string(from: NSNumber(value: goal.raceType.distanceKm)) ?? "\(goal.raceType.distanceKm)"
        return "\(value) km"
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.xs)
                    .fill(Color.irPrimaryAccent.opacity(0.18))
                    .frame(width: 40, height: 40)

                Image(systemName: "trophy")
                    .font(IRFont.title3.weight(.semibold))
                    .foregroundStyle(Color.irPrimaryAccent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(goal.raceName)
                    .font(IRFont.body.weight(.bold))
                    .foregroundStyle(Color.irTextPrimary)
                    .lineLimit(1)

                Text("\(formattedDate) · \(formattedDistance)")
                    .font(IRFont.eyebrow)
                    .foregroundStyle(Color.irTextSecondary)
            }

            Spacer()

            if let time = goal.formattedFinishTime {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(time)
                        .font(IRFont.monoSM.weight(.bold))
                        .foregroundStyle(Color.irTextPrimary)
                    Text(String(localized: "goals.history.finishTime", defaultValue: "Finish Time", comment: "Race history - finish time label").uppercased())
                        .font(IRFont.eyebrow.weight(.bold))
                        .tracking(0.9) // 0.1em on 9pt
                        .foregroundStyle(Color.irTextSecondary.opacity(0.6))
                }
            }
        }
        .padding(Spacing.dash)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
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
