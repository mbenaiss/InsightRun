//
//  WeeklyStatsWidget.swift
//  InsightRunWidgets
//
//  Widget displaying weekly running statistics
//

import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct WeeklyStatsEntry: TimelineEntry {
    let date: Date
    let data: WidgetWeeklyStatsData?
}

// MARK: - Timeline Provider

struct WeeklyStatsProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeeklyStatsEntry {
        WeeklyStatsEntry(
            date: Date(),
            data: WidgetWeeklyStatsData(
                totalDistance: 32500,
                totalRuns: 4,
                averagePace: 5.45,
                totalDuration: 9600,
                totalCalories: 2100,
                weekStartDate: Date()
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (WeeklyStatsEntry) -> Void) {
        let data = WidgetDataReader.read(WidgetWeeklyStatsData.self, forKey: WidgetDataKeys.weeklyStats)
        completion(WeeklyStatsEntry(date: Date(), data: data))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeeklyStatsEntry>) -> Void) {
        let data = WidgetDataReader.read(WidgetWeeklyStatsData.self, forKey: WidgetDataKeys.weeklyStats)
        let entry = WeeklyStatsEntry(date: Date(), data: data)
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

// MARK: - Widget Views

struct WeeklyStatsWidgetView: View {
    let entry: WeeklyStatsEntry
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
                Image(systemName: "chart.bar.fill")
                Text("Cette semaine")
                    .font(.headline)
                    .widgetAccentable()
            }
            HStack(spacing: 8) {
                Text(formattedDistance)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("\(totalRuns) sorties")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let pace = formattedPace {
                    Text(pace)
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
            Image(systemName: "figure.run")
            Text("\(formattedDistance) - \(totalRuns) sorties")
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    // MARK: - Small Widget

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.caption2)
                    .foregroundStyle(.blue)
                Text("Cette semaine")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
            }

            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                Text(formattedDistance)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                HStack(spacing: 12) {
                    Label("\(totalRuns)", systemImage: "figure.run")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let pace = formattedPace {
                        Label(pace, systemImage: "timer")
                            .font(.caption)
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

    // MARK: - Medium Widget

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
                Text("Statistiques de la semaine")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
            }

            HStack(spacing: 0) {
                // Distance
                StatMetricCard(
                    icon: "road.lanes",
                    value: formattedDistance,
                    label: "Distance",
                    color: .blue
                )

                Spacer()

                // Runs
                StatMetricCard(
                    icon: "figure.run",
                    value: "\(totalRuns)",
                    label: "Sorties",
                    color: .green
                )

                Spacer()

                // Pace
                StatMetricCard(
                    icon: "timer",
                    value: formattedPace ?? "--",
                    label: "Allure moy.",
                    color: .orange
                )

                Spacer()

                // Duration
                StatMetricCard(
                    icon: "clock.fill",
                    value: formattedDuration,
                    label: "Durée",
                    color: .purple
                )
            }
        }
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }

    // MARK: - Computed Properties

    private var totalRuns: Int {
        entry.data?.totalRuns ?? 0
    }

    private var formattedDistance: String {
        let km = (entry.data?.totalDistance ?? 0) / 1000.0
        if km >= 100 {
            return String(format: "%.0f km", km)
        }
        return String(format: "%.1f km", km)
    }

    private var formattedPace: String? {
        guard let pace = entry.data?.averagePace, pace > 0 else { return nil }
        let minutes = Int(pace)
        let seconds = Int((pace - Double(minutes)) * 60)
        return String(format: "%d:%02d /km", minutes, seconds)
    }

    private var formattedDistanceShort: String {
        let km = (entry.data?.totalDistance ?? 0) / 1000.0
        return String(format: "%.0f km", km)
    }

    private var formattedDuration: String {
        let duration = entry.data?.totalDuration ?? 0
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        if hours > 0 {
            return String(format: "%dh%02d", hours, minutes)
        }
        return String(format: "%d min", minutes)
    }
}

// MARK: - Stat Metric Card

private struct StatMetricCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)

            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Widget Definition

struct WeeklyStatsWidget: Widget {
    let kind = "WeeklyStatsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WeeklyStatsProvider()) { entry in
            WeeklyStatsWidgetView(entry: entry)
        }
        .configurationDisplayName("Statistiques hebdo")
        .description("Distance, sorties et allure de la semaine en cours.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
