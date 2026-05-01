//
//  SleepQualityWidget.swift
//  InsightRunWidgets
//
//  Widget displaying last night's sleep quality and stages
//

import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct SleepQualityEntry: TimelineEntry {
    let date: Date
    let data: WidgetSleepQualityData?
}

// MARK: - Timeline Provider

struct SleepQualityProvider: TimelineProvider {
    func placeholder(in context: Context) -> SleepQualityEntry {
        SleepQualityEntry(
            date: Date(),
            data: WidgetSleepQualityData(
                date: Date(),
                totalSleepHours: 7.5,
                sleepEfficiency: 88,
                qualityScore: 82,
                deepSleepHours: 1.5,
                remSleepHours: 1.8,
                sleepStartTime: "23:15",
                sleepEndTime: "06:45"
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (SleepQualityEntry) -> Void) {
        let data = WidgetDataReader.read(WidgetSleepQualityData.self, forKey: WidgetDataKeys.sleepQuality)
        completion(SleepQualityEntry(date: Date(), data: data))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SleepQualityEntry>) -> Void) {
        let data = WidgetDataReader.read(WidgetSleepQualityData.self, forKey: WidgetDataKeys.sleepQuality)
        let entry = SleepQualityEntry(date: Date(), data: data)
        // Refresh every 6 hours (sleep data doesn't change frequently)
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 6, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

// MARK: - Widget Views

struct SleepQualityWidgetView: View {
    let entry: SleepQualityEntry
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

    @ViewBuilder
    private var accessoryCircularView: some View {
        if let data = entry.data {
            Gauge(value: Double(data.qualityScore), in: 0...100) {
                Text("S")
            } currentValueLabel: {
                Image(systemName: "moon.zzz.fill")
                    .font(.caption)
            }
            .gaugeStyle(.accessoryCircular)
            .containerBackground(for: .widget) { Color.clear }
        } else {
            // No sleep tracking — render a neutral icon instead of an empty 0% gauge.
            Image(systemName: "moon.zzz")
                .font(.title3)
                .foregroundStyle(.secondary)
                .containerBackground(for: .widget) { Color.clear }
        }
    }

    // MARK: - Lock Screen: Rectangular

    private var accessoryRectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "moon.zzz.fill")
                Text(String(localized: "Sleep", comment: "Widget sleep title"))
                    .font(.headline)
                    .widgetAccentable()
            }
            if let data = entry.data {
                HStack(spacing: 8) {
                    Text(formattedSleepDuration(data.totalSleepHours))
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("\(data.qualityScore)/100")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(data.sleepStartTime)-\(data.sleepEndTime)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(String(localized: "No data", comment: "No data placeholder"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    // MARK: - Lock Screen: Inline

    private var accessoryInlineView: some View {
        HStack(spacing: 4) {
            Image(systemName: "moon.zzz.fill")
            if let data = entry.data {
                Text("\(formattedSleepDuration(data.totalSleepHours)) - Score \(data.qualityScore)")
            } else {
                Text(String(localized: "No sleep data", comment: "No sleep data placeholder"))
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    // MARK: - Small Widget

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "moon.zzz.fill")
                    .font(.caption2)
                    .foregroundStyle(.indigo)
                Text(String(localized: "Sleep", comment: "Widget sleep title"))
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
            }

            if let data = entry.data {
                Spacer()

                VStack(alignment: .leading, spacing: 2) {
                    Text(formattedSleepDuration(data.totalSleepHours))
                        .font(.system(size: 26, weight: .bold, design: .rounded))

                    Text(qualityText(data.qualityScore))
                        .font(.caption)
                        .foregroundStyle(qualityColor(data.qualityScore))
                        .fontWeight(.medium)
                }

                Spacer()

                HStack {
                    Text(data.sleepStartTime)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 7))
                        .foregroundStyle(.tertiary)
                    Text(data.sleepEndTime)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Spacer()
                Text(String(localized: "No data", comment: "No data placeholder"))
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
        HStack(spacing: 16) {
            // Left: Score gauge
            if let data = entry.data {
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .stroke(qualityColor(data.qualityScore).opacity(0.15), lineWidth: 8)
                            .frame(width: 72, height: 72)

                        Circle()
                            .trim(from: 0, to: CGFloat(data.qualityScore) / 100)
                            .stroke(
                                qualityColor(data.qualityScore),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round)
                            )
                            .frame(width: 72, height: 72)
                            .rotationEffect(.degrees(-90))

                        VStack(spacing: 0) {
                            Text("\(data.qualityScore)")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                            Text(String(localized: "Score", comment: "Sleep quality score label"))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(formattedSleepDuration(data.totalSleepHours))
                        .font(.caption)
                        .fontWeight(.semibold)
                }
            }

            // Right: Details
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "moon.zzz.fill")
                        .font(.caption)
                        .foregroundStyle(.indigo)
                    Text(String(localized: "Sleep", comment: "Widget sleep title"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Spacer()
                }

                if let data = entry.data {
                    // Sleep time range
                    HStack(spacing: 4) {
                        Image(systemName: "bed.double.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.indigo)
                        Text("\(data.sleepStartTime) - \(data.sleepEndTime)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Efficiency
                    HStack(spacing: 4) {
                        Image(systemName: "percent")
                            .font(.system(size: 9))
                            .foregroundStyle(.blue)
                        Text("\(String(localized: "Efficiency", comment: "Sleep efficiency label")): \(String(format: "%.0f%%", data.sleepEfficiency))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Stages
                    if let deep = data.deepSleepHours {
                        HStack(spacing: 4) {
                            Image(systemName: "moon.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.purple)
                            Text("\(String(localized: "Deep", comment: "Deep sleep label")): \(formattedSleepDuration(deep))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let rem = data.remSleepHours {
                        HStack(spacing: 4) {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 9))
                                .foregroundStyle(.cyan)
                            Text("\(String(localized: "REM", comment: "REM sleep label")): \(formattedSleepDuration(rem))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Spacer()
                    Text(String(localized: "No sleep data", comment: "No sleep data placeholder"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            Spacer()
        }
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }

    // MARK: - Helpers

    private func formattedSleepDuration(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return String(format: "%dh%02d", h, m)
    }

    private func qualityText(_ score: Int) -> String {
        switch score {
        case 80...100: return String(localized: "Excellent", comment: "Sleep quality")
        case 60..<80: return String(localized: "Good", comment: "Sleep quality")
        case 40..<60: return String(localized: "Fair", comment: "Sleep quality")
        default: return String(localized: "Insufficient", comment: "Sleep quality")
        }
    }

    private func qualityColor(_ score: Int) -> Color {
        switch score {
        case 80...100: return .green
        case 60..<80: return .yellow
        case 40..<60: return .orange
        default: return .red
        }
    }
}

// MARK: - Widget Definition

struct SleepQualityWidget: Widget {
    let kind = "SleepQualityWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SleepQualityProvider()) { entry in
            SleepQualityWidgetView(entry: entry)
        }
        .configurationDisplayName(String(localized: "Sleep", comment: "Widget display name"))
        .description(String(localized: "Sleep quality, duration and stage breakdown.", comment: "Sleep widget description"))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
