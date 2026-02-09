//
//  LastWorkoutWidget.swift
//  InsightRunWidgets
//
//  Widget displaying the most recent workout summary
//

import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct LastWorkoutEntry: TimelineEntry {
    let date: Date
    let data: WidgetLastWorkoutData?
}

// MARK: - Timeline Provider

struct LastWorkoutProvider: TimelineProvider {
    func placeholder(in context: Context) -> LastWorkoutEntry {
        LastWorkoutEntry(
            date: Date(),
            data: WidgetLastWorkoutData(
                date: Date().addingTimeInterval(-3600),
                distance: 8500,
                duration: 2700,
                averagePace: 5.30,
                averageHeartRate: 152,
                calories: 520,
                elevationGain: 85
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (LastWorkoutEntry) -> Void) {
        let data = WidgetDataReader.read(WidgetLastWorkoutData.self, forKey: WidgetDataKeys.lastWorkout)
        completion(LastWorkoutEntry(date: Date(), data: data))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LastWorkoutEntry>) -> Void) {
        let data = WidgetDataReader.read(WidgetLastWorkoutData.self, forKey: WidgetDataKeys.lastWorkout)
        let entry = LastWorkoutEntry(date: Date(), data: data)
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 2, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

// MARK: - Widget Views

struct LastWorkoutWidgetView: View {
    let entry: LastWorkoutEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        case .accessoryCircular:
            accessoryCircularView
        case .accessoryRectangular:
            accessoryRectangularView
        case .accessoryInline:
            accessoryInlineView
        default:
            smallView
        }
    }

    // MARK: - Lock Screen: Circular

    private var accessoryCircularView: some View {
        VStack(spacing: 1) {
            Image(systemName: "figure.run")
                .font(.caption)
            Text(formattedDistanceShort)
                .font(.system(.caption, design: .rounded, weight: .bold))
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    // MARK: - Lock Screen: Rectangular

    private var accessoryRectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "figure.run")
                Text(String(localized: "Last Workout", comment: "Widget last workout title"))
                    .font(.headline)
                    .widgetAccentable()
            }
            if entry.data != nil {
                HStack(spacing: 8) {
                    Text(formattedDistance)
                        .font(.caption)
                        .fontWeight(.semibold)
                    if let pace = formattedPace {
                        Text(pace)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(formattedDuration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(String(localized: "No workout", comment: "No workout placeholder"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    // MARK: - Lock Screen: Inline

    private var accessoryInlineView: some View {
        HStack(spacing: 4) {
            Image(systemName: "figure.run")
            if entry.data != nil {
                Text("\(formattedDistance) - \(formattedPace ?? formattedDuration)")
            } else {
                Text(String(localized: "No workout", comment: "No workout placeholder"))
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    // MARK: - Small Widget

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "figure.run")
                    .font(.caption2)
                    .foregroundStyle(.green)
                Text(String(localized: "Last Workout", comment: "Widget last workout title"))
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
            }

            if entry.data != nil {
                Text(relativeDate)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()

                Text(formattedDistance)
                    .font(.system(size: 26, weight: .bold, design: .rounded))

                HStack(spacing: 10) {
                    if let pace = formattedPace {
                        Text(pace)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(formattedDuration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Spacer()
                Text(String(localized: "No workout", comment: "No workout placeholder"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }

    // MARK: - Medium Widget

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "figure.run")
                    .font(.caption)
                    .foregroundStyle(.green)
                Text(String(localized: "Last Workout", comment: "Widget last workout title"))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                if entry.data != nil {
                    Text(relativeDate)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if entry.data != nil {
                HStack(spacing: 0) {
                    // Distance
                    VStack(spacing: 2) {
                        Image(systemName: "road.lanes")
                            .font(.caption)
                            .foregroundStyle(.blue)
                        Text(formattedDistance)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text(String(localized: "Distance", comment: "Widget distance label"))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    // Pace
                    VStack(spacing: 2) {
                        Image(systemName: "timer")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text(formattedPace ?? "--")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text(String(localized: "Pace", comment: "Widget pace label"))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    // Duration
                    VStack(spacing: 2) {
                        Image(systemName: "clock.fill")
                            .font(.caption)
                            .foregroundStyle(.purple)
                        Text(formattedDuration)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text(String(localized: "Duration", comment: "Widget duration label"))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    // Heart Rate
                    VStack(spacing: 2) {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                        Text(formattedHeartRate)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text(String(localized: "Avg HR", comment: "Widget average heart rate label"))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    // Calories
                    VStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text(formattedCalories)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text(String(localized: "Calories", comment: "Widget calories label"))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "figure.run")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text(String(localized: "No workout recorded", comment: "No workout recorded placeholder"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Spacer()
            }
        }
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }

    // MARK: - Computed Properties

    private var formattedDistance: String {
        let km = (entry.data?.distance ?? 0) / 1000.0
        return String(format: "%.2f km", km)
    }

    private var formattedDistanceShort: String {
        let km = (entry.data?.distance ?? 0) / 1000.0
        return String(format: "%.1f", km)
    }

    private var formattedPace: String? {
        guard let pace = entry.data?.averagePace, pace > 0 else { return nil }
        let minutes = Int(pace)
        let seconds = Int((pace - Double(minutes)) * 60)
        return String(format: "%d:%02d /km", minutes, seconds)
    }

    private var formattedDuration: String {
        let duration = entry.data?.duration ?? 0
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        let seconds = Int(duration) % 60
        if hours > 0 {
            return String(format: "%dh%02d", hours, minutes)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var formattedHeartRate: String {
        guard let hr = entry.data?.averageHeartRate else { return "--" }
        return String(format: "%.0f", hr)
    }

    private var formattedCalories: String {
        guard let cal = entry.data?.calories else { return "--" }
        return String(format: "%.0f", cal)
    }

    private var relativeDate: String {
        guard let workoutDate = entry.data?.date else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale.current
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: workoutDate, relativeTo: Date())
    }
}

// MARK: - Widget Definition

struct LastWorkoutWidget: Widget {
    let kind = "LastWorkoutWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LastWorkoutProvider()) { entry in
            LastWorkoutWidgetView(entry: entry)
        }
        .configurationDisplayName(String(localized: "Last Workout", comment: "Widget display name"))
        .description(String(localized: "Summary of your last running workout.", comment: "Last workout widget description"))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
