//
//  TrainingCalendarView.swift
//  InsightRun
//
//  Calendar grid showing the training plan week by week with phase colors
//

import SwiftUI

struct TrainingCalendarView: View {
    let goal: RaceGoal
    let plan: TrainingPlan
    let onToggleCompletion: (Int, Int) -> Void
    var onToggleSkip: ((Int, Int) -> Void)? = nil
    var onMoveDay: ((Int, Int, Date?) -> Void)? = nil

    @State private var expandedWeekIndex: Int?
    @State private var selectedWorkout: SelectedWorkout?

    struct SelectedWorkout: Identifiable {
        let id = UUID()
        let weekIndex: Int
        let dayIndex: Int
        let workout: PlannedWorkout
        let day: TrainingDay
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: Spacing.md) {
            // Week list
            ForEach(Array(plan.weeks.enumerated()), id: \.element.id) { weekIndex, week in
                weekRow(week: week, weekIndex: weekIndex)
            }
        }
        .sheet(item: $selectedWorkout) { selected in
            let isRace = Self.isRaceDay(plan: plan, goal: goal, weekIndex: selected.weekIndex, day: selected.day)
            PlannedWorkoutDetailView(
                workout: selected.workout,
                day: selected.day,
                isPast: Self.isDayPast(plan: plan, weekIndex: selected.weekIndex, day: selected.day),
                currentDate: plan.effectiveDate(weekIndex: selected.weekIndex, day: selected.day),
                onToggleSkip: isRace ? nil : onToggleSkip.map { handler in
                    { handler(selected.weekIndex, selected.dayIndex) }
                },
                onMove: isRace ? nil : onMoveDay.map { handler in
                    { newDate in handler(selected.weekIndex, selected.dayIndex, newDate) }
                }
            )
        }
    }

    static func isDayPast(plan: TrainingPlan, weekIndex: Int, day: TrainingDay) -> Bool {
        guard let currentWeek = plan.currentWeekIndex else { return false }
        if weekIndex < currentWeek { return true }
        if weekIndex > currentWeek { return false }
        let todayWeekday = Calendar.current.component(.weekday, from: Date())
        return day.dayOfWeek.rawValue < todayWeekday
    }

    static func isRaceDay(plan: TrainingPlan, goal: RaceGoal, weekIndex: Int, day: TrainingDay) -> Bool {
        guard weekIndex == plan.weeks.count - 1 else { return false }
        let raceWeekday = Calendar.current.component(.weekday, from: goal.targetDate)
        return day.dayOfWeek.rawValue == raceWeekday
    }

    // MARK: - Week Row

    private func weekRow(week: TrainingWeek, weekIndex: Int) -> some View {
        let isCurrentWeek = plan.currentWeekIndex == weekIndex
        let isExpanded = expandedWeekIndex == weekIndex

        return VStack(spacing: 0) {
            // Week header
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    expandedWeekIndex = isExpanded ? nil : weekIndex
                }
            } label: {
                HStack(spacing: Spacing.md) {
                    // Phase Indicator with Label
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Spacing.xxs) {
                            Circle()
                                .fill(week.phase.themeColor.gradient)
                                .frame(width: 8, height: 8)
                            Text(String(localized: "goals.calendar.week", defaultValue: "Week", comment: "Training calendar - week label") + " \(week.weekNumber)")
                                .font(IRFont.body.weight(.bold))
                                .foregroundStyle(Color.irTextPrimary)
                        }
                        
                        Text(week.phase.displayName)
                            .font(IRFont.microLabel)
                            .foregroundStyle(week.phase.themeColor)
                            .textCase(.uppercase)
                    }

                    if isCurrentWeek {
                        Text(String(localized: "goals.calendar.current", defaultValue: "Current", comment: "Training calendar - current week"))
                            .font(IRFont.microLabel)
                            .foregroundStyle(Color.irCardBackground)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, 2)
                            .background(Color.irPrimaryAccent.gradient)
                            .clipShape(Capsule())
                    }

                    Spacer()

                    // Mini Progress Visualization
                    HStack(spacing: 3) {
                        ForEach(Array(week.days.enumerated()), id: \.element.id) { _, day in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(dayIndicatorColor(day))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .padding(.trailing, Spacing.xxs)

                    Image(systemName: "chevron.right")
                        .font(IRFont.caption.weight(.bold))
                        .foregroundStyle(Color.irTextSecondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.vertical, Spacing.md)
                .padding(.horizontal, Spacing.md)
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                VStack(spacing: Spacing.xs) {
                    if let notes = week.notes, !notes.isEmpty {
                        Text(notes)
                            .font(IRFont.caption)
                            .italic()
                            .foregroundStyle(Color.irTextSecondary)
                            .padding(.horizontal, Spacing.md)
                            .padding(.bottom, Spacing.xxs)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    ForEach(Array(week.days.enumerated()), id: \.element.id) { dayIndex, day in
                        dayRow(day: day, weekIndex: weekIndex, dayIndex: dayIndex)
                    }
                }
                .padding(.bottom, Spacing.sm)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider()
                .padding(.horizontal, Spacing.md)
        }
        .background(isCurrentWeek ? Color.irPrimaryAccent.opacity(0.04) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
    }

    // MARK: - Day Row

    private func dayRow(day: TrainingDay, weekIndex: Int, dayIndex: Int) -> some View {
        HStack(spacing: Spacing.md) {
            // Day Label
            Text(day.dayOfWeek.shortName)
                .font(IRFont.caption.weight(.bold))
                .foregroundStyle(Color.irTextSecondary)
                .frame(width: 30, alignment: .leading)

            if let workout = day.workout {
                // Workout Card
                Button {
                    selectedWorkout = SelectedWorkout(weekIndex: weekIndex, dayIndex: dayIndex, workout: workout, day: day)
                } label: {
                    HStack(spacing: Spacing.sm) {
                        // Intensity Stripe
                        Rectangle()
                            .fill(workout.intensity.themeColor.gradient)
                            .frame(width: 3)
                            .clipShape(Capsule())
                        
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: Spacing.xxs) {
                                Text(workout.name)
                                    .font(IRFont.footnote)
                                    .foregroundStyle(Color.irTextPrimary)
                                    .lineLimit(1)

                                if let override = day.dateOverride {
                                    Label(
                                        override.formatted(date: .abbreviated, time: .omitted),
                                        systemImage: "arrow.right.circle.fill"
                                    )
                                    .font(IRFont.microLabel)
                                    .foregroundStyle(Color.irPrimaryAccent)
                                    .labelStyle(CompactLabelStyle())
                                }
                            }

                            HStack(spacing: Spacing.xs) {
                                if !workout.formattedDistance.isEmpty {
                                    Label(workout.formattedDistance, systemImage: "ruler")
                                } else if !workout.formattedDuration.isEmpty {
                                    Label(workout.formattedDuration, systemImage: "clock")
                                }

                                if let pace = workout.targetPace {
                                    Text("•")
                                    Text(pace)
                                }
                            }
                            .font(IRFont.microLabel.weight(.medium))
                            .foregroundStyle(Color.irTextSecondary)
                            .labelStyle(CompactLabelStyle())
                        }
                        
                        Spacer()
                        
                        // Completion Toggle
                        VStack(spacing: 2) {
                            Button {
                                onToggleCompletion(weekIndex, dayIndex)
                            } label: {
                                Image(systemName: day.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .font(IRFont.title3)
                                    .foregroundStyle(day.isCompleted ? Color.irSuccess : Color.irBorder)
                            }

                            if day.completedWorkoutId != nil {
                                Text(String(localized: "goals.detail.autoTracked", defaultValue: "Auto", comment: "Auto-tracked label"))
                                    .font(IRFont.microLabel)
                                    .foregroundStyle(Color.irPrimaryAccent)
                            }
                        }
                    }
                    .padding(Spacing.sm)
                    .background(Color.irCard2.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
                }
                .buttonStyle(.plain)
            } else {
                // Rest Day
                HStack {
                    Image(systemName: "zzz")
                        .font(IRFont.microLabel)
                        .foregroundStyle(Color.irTextSecondary.opacity(0.5))
                    Text(String(localized: "goals.calendar.rest", defaultValue: "Rest Day", comment: "Training calendar - rest day"))
                        .font(IRFont.caption)
                        .foregroundStyle(Color.irTextSecondary.opacity(0.5))
                    Spacer()
                }
                .padding(.vertical, Spacing.sm)
            }
        }
        .padding(.horizontal, Spacing.md)
    }

    // MARK: - Helpers

    private func dayIndicatorColor(_ day: TrainingDay) -> Color {
        if day.isRestDay { return Color.irBorder.opacity(0.2) }
        return day.isCompleted ? Color.irSuccess : Color.irBorder.opacity(0.5)
    }

}

// Compact label style for the calendar
struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) {
            configuration.icon
                .font(IRFont.microLabel)
            configuration.title
        }
    }
}
