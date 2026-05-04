//
//  TrainingLoadWidget.swift
//  InsightRunWidgets
//
//  Weekly training load widget — small (status pill + delta) and medium
//  (status block + 3-column comparison + footer "x days ago").
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
                weeklyVolumeChange: -100,
                daysSinceLastWorkout: 3,
                status: "normal",
                thisWeekDistance: 0,
                lastWeekDistance: 18500
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

    // MARK: - Small (status pill + KPI)

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 0) {
            WGHeader(label: String(localized: "Load", comment: "Widget training load short header"), icon: "chart.line.uptrend.xyaxis", color: statusColor)

            Spacer(minLength: 8)

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(statusColor.opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(statusColor.opacity(0.30), lineWidth: 0.5)
                    )

                VStack(spacing: 4) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(statusColor)

                    Text(statusTitle)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(statusColor)
                }
            }
            .frame(width: 86, height: 86)
            .frame(maxWidth: .infinity, alignment: .center)

            Spacer(minLength: 6)

            if let change = entry.data?.weeklyVolumeChange {
                HStack(spacing: 3) {
                    Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 9, weight: .heavy))

                    Text(String(format: "%+.0f%%", change))
                        .font(WGFont.mono(11, weight: .bold))

                    Text(String(localized: "vs last wk", comment: "Compared to last week"))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.wgTextTertiary)
                }
                .foregroundStyle(deltaColor(change: change))
            }
        }
        .padding(14)
        .wgContainerBackground(gradient: true)
    }

    // MARK: - Medium (status pill + 3 KPI grid + footer)

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 0) {
            WGHeader(
                label: String(localized: "Training Load", comment: "Widget training load header"),
                icon: "chart.line.uptrend.xyaxis",
                color: statusColor
            )

            HStack(alignment: .top, spacing: 16) {
                // Status block
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(statusColor.opacity(0.18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(statusColor.opacity(0.30), lineWidth: 0.5)
                        )

                    VStack(spacing: 4) {
                        Image(systemName: statusIcon)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(statusColor)

                        Text(statusTitle)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(statusColor)
                    }
                }
                .frame(width: 86, height: 86)

                // 3-column grid
                HStack(spacing: 0) {
                    WGMiniStat(
                        label: String(localized: "This week", comment: "Widget this week label"),
                        value: distanceLabel(entry.data?.thisWeekDistance ?? 0),
                        unit: "km"
                    )
                    WGMiniStat(
                        label: String(localized: "Prev. week", comment: "Widget previous week label"),
                        value: distanceLabel(entry.data?.lastWeekDistance ?? 0),
                        unit: "km",
                        valueColor: Color.wgTextSecondary,
                        leadingDivider: true
                    )
                    if let change = entry.data?.weeklyVolumeChange {
                        WGMiniStat(
                            label: String(localized: "Change", comment: "Widget volume change label"),
                            value: String(format: "%+.0f", change),
                            unit: "%",
                            valueColor: deltaColor(change: change),
                            leadingDivider: true
                        )
                    }
                }
            }
            .padding(.top, 14)

            Spacer(minLength: 0)

            if let days = entry.data?.daysSinceLastWorkout {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.wgTextTertiary)
                    (
                        Text(String(localized: "Last run · ", comment: "Last run prefix"))
                            .foregroundStyle(Color.wgTextSecondary)
                        + Text(daysAgoLabel(days))
                            .foregroundStyle(Color.wgTextPrimary)
                            .fontWeight(.semibold)
                    )
                    .font(.system(size: 11, weight: .medium))
                }
            }
        }
        .padding(14)
        .wgContainerBackground(gradient: true)
    }

    // MARK: - Lock screen variants

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

    private var accessoryRectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                Text(String(localized: "Load", comment: "Lock screen load title"))
                    .font(.headline)
                    .widgetAccentable()
            }
            HStack(spacing: 8) {
                Text(statusTitle).font(.caption).fontWeight(.semibold)
                if let change = entry.data?.weeklyVolumeChange {
                    Text(String(format: "%+.0f%%", change))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

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

    // MARK: - Helpers

    private var statusColor: Color {
        switch entry.data?.status {
        case "normal":       return .wgSuccess
        case "overtraining": return .wgWarning
        case "inactive":     return Color(uiColor: UIColor(red: 0.36, green: 0.76, blue: 1.0, alpha: 1.0))
        default:             return Color.gray
        }
    }

    private var statusIcon: String {
        switch entry.data?.status {
        case "normal":       return "checkmark.circle.fill"
        case "overtraining": return "exclamationmark.triangle.fill"
        case "inactive":     return "zzz"
        default:             return "questionmark.circle"
        }
    }

    private var statusTitle: String {
        switch entry.data?.status {
        case "normal":       return String(localized: "On track", comment: "Training status: normal")
        case "overtraining": return String(localized: "High load", comment: "Training status: overtraining")
        case "inactive":     return String(localized: "Inactive", comment: "Training status: inactive")
        default:             return "—"
        }
    }

    private var statusShort: String {
        switch entry.data?.status {
        case "normal":       return "OK"
        case "overtraining": return String(localized: "High", comment: "Training status short: overtraining")
        case "inactive":     return String(localized: "Rest", comment: "Training status short: inactive")
        default:             return "—"
        }
    }

    private func distanceLabel(_ meters: Double) -> String {
        String(format: "%.1f", meters / 1000.0)
    }

    private func deltaColor(change: Double) -> Color {
        if change > 25  { return .wgWarning }
        if change < -25 { return .wgError }
        return .wgSuccess
    }

    private func daysAgoLabel(_ days: Int) -> String {
        switch days {
        case 0:  return String(localized: "today", comment: "Today, lowercase")
        case 1:  return String(localized: "yesterday", comment: "Yesterday, lowercase")
        default: return String(localized: "\(days) days ago", comment: "N days ago, lowercase")
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
