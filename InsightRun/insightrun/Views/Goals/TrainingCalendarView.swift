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
            PlannedWorkoutDetailView(workout: selected.workout, day: selected.day)
        }
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
                        HStack(spacing: 4) {
                            Circle()
                                .fill(week.phase.themeColor.gradient)
                                .frame(width: 8, height: 8)
                            Text(String(localized: "goals.calendar.week", defaultValue: "Week", comment: "Training calendar - week label") + " \(week.weekNumber)")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.irTextPrimary)
                        }
                        
                        Text(week.phase.displayName)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(week.phase.themeColor)
                            .textCase(.uppercase)
                    }

                    if isCurrentWeek {
                        Text(String(localized: "goals.calendar.current", defaultValue: "Current", comment: "Training calendar - current week"))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
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
                    .padding(.trailing, 4)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
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
                            .font(.caption)
                            .italic()
                            .foregroundStyle(Color.irTextSecondary)
                            .padding(.horizontal, Spacing.md)
                            .padding(.bottom, 4)
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
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
    }

    // MARK: - Day Row

    private func dayRow(day: TrainingDay, weekIndex: Int, dayIndex: Int) -> some View {
        HStack(spacing: Spacing.md) {
            // Day Label
            Text(day.dayOfWeek.shortName)
                .font(.system(size: 12, weight: .bold))
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
                            Text(workout.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.irTextPrimary)
                                .lineLimit(1)
                            
                            HStack(spacing: 6) {
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
                            .font(.system(size: 10, weight: .medium))
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
                // Rest Day
                HStack {
                    Image(systemName: "zzz")
                        .font(.caption2)
                        .foregroundStyle(Color.irTextSecondary.opacity(0.5))
                    Text(String(localized: "goals.calendar.rest", defaultValue: "Rest Day", comment: "Training calendar - rest day"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.irTextSecondary.opacity(0.5))
                    Spacer()
                }
                .padding(.vertical, 8)
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
                .font(.system(size: 8))
            configuration.title
        }
    }
}
