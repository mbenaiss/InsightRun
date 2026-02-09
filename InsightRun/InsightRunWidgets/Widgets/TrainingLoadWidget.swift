//
//  TrainingLoadWidget.swift
//  InsightRunWidgets
//
//  Widget displaying training load status and weekly volume comparison
//

import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct TrainingLoadEntry: TimelineEntry {
    let date: Date
    let data: WidgetTrainingLoadData?
}

// MARK: - Timeline Provider

struct TrainingLoadProvider: TimelineProvider {
    func placeholder(in context: Context) -> TrainingLoadEntry {
        TrainingLoadEntry(
            date: Date(),
            data: WidgetTrainingLoadData(
                date: Date(),
                weeklyVolumeChange: 5.2,
                daysSinceLastWorkout: 1,
                status: "normal",
                thisWeekDistance: 28000,
                lastWeekDistance: 26600
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TrainingLoadEntry) -> Void) {
        let data = WidgetDataReader.read(WidgetTrainingLoadData.self, forKey: WidgetDataKeys.trainingLoad)
        completion(TrainingLoadEntry(date: Date(), data: data))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TrainingLoadEntry>) -> Void) {
        let data = WidgetDataReader.read(WidgetTrainingLoadData.self, forKey: WidgetDataKeys.trainingLoad)
        let entry = TrainingLoadEntry(date: Date(), data: data)
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 2, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

// MARK: - Widget Views

struct TrainingLoadWidgetView: View {
    let entry: TrainingLoadEntry
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
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Image(systemName: statusIcon)
                    .font(.caption)
                Text(statusShort)
                    .font(.system(size: 9, weight: .semibold))
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    // MARK: - Lock Screen: Rectangular

    private var accessoryRectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                Text(String(localized: "Load", comment: "Widget training load title"))
                    .font(.headline)
                    .widgetAccentable()
            }
            HStack(spacing: 8) {
                Text(statusTitle)
                    .font(.caption)
                    .fontWeight(.semibold)
                if let change = entry.data?.weeklyVolumeChange {
                    Text(String(format: "%+.0f%%", change))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let days = entry.data?.daysSinceLastWorkout {
                    Text(days == 0 ? String(localized: "Today", comment: "Today abbreviation") : String(localized: "\(days)d ago", comment: "Days since last workout"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    // MARK: - Lock Screen: Inline

    private var accessoryInlineView: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
            Text(statusTitle)
            if let change = entry.data?.weeklyVolumeChange {
                Text(String(format: "(%+.0f%%)", change))
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    // MARK: - Small Widget

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.caption2)
                    .foregroundStyle(statusColor)
                Text(String(localized: "Load", comment: "Widget training load title"))
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
            }

            Spacer()

            // Status indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                Text(statusTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            // Volume change
            if let change = entry.data?.weeklyVolumeChange {
                HStack(spacing: 2) {
                    Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10))
                        .foregroundStyle(change >= 0 ? .orange : .blue)
                    Text(String(format: "%+.0f%%", change))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    Text(String(localized: "vs last wk", comment: "Compared to last week"))
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Days since last workout
            if let days = entry.data?.daysSinceLastWorkout {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text(days == 0 ? String(localized: "Today", comment: "Today") : days == 1 ? String(localized: "Yesterday", comment: "Yesterday") : String(localized: "\(days)d ago", comment: "Days ago"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }

    // MARK: - Medium Widget

    private var mediumView: some View {
        HStack(spacing: 16) {
            // Left: Status
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.15))
                        .frame(width: 64, height: 64)

                    Image(systemName: statusIcon)
                        .font(.title2)
                        .foregroundStyle(statusColor)
                }

                Text(statusTitle)
                    .font(.caption)
                    .fontWeight(.semibold)
            }

            // Right: Details
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.caption)
                        .foregroundStyle(statusColor)
                    Text(String(localized: "Training Load", comment: "Widget training load header"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Spacer()
                }

                // Volume comparison
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "This Week", comment: "This week label"))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Text(formattedDistance(entry.data?.thisWeekDistance ?? 0))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Last Week", comment: "Last week label"))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Text(formattedDistance(entry.data?.lastWeekDistance ?? 0))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    if let change = entry.data?.weeklyVolumeChange {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "Change", comment: "Volume change label"))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 2) {
                                Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                                    .font(.system(size: 10))
                                Text(String(format: "%+.0f%%", change))
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(change > 10 ? .orange : change < -10 ? .blue : .green)
                        }
                    }
                }

                // Days since last workout
                if let days = entry.data?.daysSinceLastWorkout {
                    HStack(spacing: 4) {
                        Image(systemName: "figure.run")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Text(lastWorkoutText(days))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }

    // MARK: - Computed Properties

    private var statusColor: Color {
        switch entry.data?.status {
        case "normal": return .green
        case "overtraining": return .orange
        case "inactive": return .blue
        default: return .gray
        }
    }

    private var statusTitle: String {
        switch entry.data?.status {
        case "normal": return String(localized: "On Track", comment: "Training status: normal")
        case "overtraining": return String(localized: "High Load", comment: "Training status: overtraining")
        case "inactive": return String(localized: "Inactive", comment: "Training status: inactive")
        default: return "--"
        }
    }

    private var statusShort: String {
        switch entry.data?.status {
        case "normal": return "OK"
        case "overtraining": return String(localized: "High", comment: "Training status short: overtraining")
        case "inactive": return String(localized: "Rest", comment: "Training status short: inactive")
        default: return "--"
        }
    }

    private var statusIcon: String {
        switch entry.data?.status {
        case "normal": return "checkmark.circle.fill"
        case "overtraining": return "exclamationmark.triangle.fill"
        case "inactive": return "zzz"
        default: return "questionmark.circle"
        }
    }

    private func formattedDistance(_ meters: Double) -> String {
        let km = meters / 1000.0
        return String(format: "%.1f km", km)
    }

    private func lastWorkoutText(_ days: Int) -> String {
        switch days {
        case 0: return String(localized: "Last run: today", comment: "Last workout today")
        case 1: return String(localized: "Last run: yesterday", comment: "Last workout yesterday")
        default: return String(localized: "Last run: \(days) days ago", comment: "Last workout days ago")
        }
    }
}

// MARK: - Widget Definition

struct TrainingLoadWidget: Widget {
    let kind = "TrainingLoadWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrainingLoadProvider()) { entry in
            TrainingLoadWidgetView(entry: entry)
        }
        .configurationDisplayName(String(localized: "Training Load", comment: "Widget display name"))
        .description(String(localized: "Weekly volume tracking and overtraining detection.", comment: "Training load widget description"))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
