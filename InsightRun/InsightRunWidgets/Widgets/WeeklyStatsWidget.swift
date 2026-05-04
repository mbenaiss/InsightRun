//
//  WeeklyStatsWidget.swift
//  InsightRunWidgets
//
//  Weekly running statistics — small (X/7 days + day grid), medium
//  (3-column KPI strip + day grid).
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
                totalDistance: 21400,
                totalRuns: 4,
                averagePace: 5.45,
                totalDuration: 8280,
                totalCalories: 1420,
                weekStartDate: Date(),
                dailyDistancesKm: [5.2, 6.0, 0, 4.5, 0, 5.7, 0]
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

    // MARK: - Small (streak count + day grid)

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 0) {
            WGHeader(label: String(localized: "This week", comment: "Widget weekly stats short header"), icon: "calendar")

            Spacer(minLength: 8)

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text("\(totalRuns)")
                    .font(WGFont.num(32, weight: .heavy))
                    .kerning(WGTracking.numHero(32))
                    .foregroundStyle(Color.wgTextPrimary)

                Text(sessionsSuffix)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.wgTextSecondary)
            }

            Text(volumeSubtitle)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.wgTextTertiary)
                .padding(.top, 2)

            Spacer()

            DayBarGrid(daily: dailyKm, todayIdx: todayIdx, height: 22)
        }
        .padding(14)
        .wgContainerBackground()
    }

    // MARK: - Medium (3-KPI strip + day grid)

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 0) {
            WGHeader(label: String(localized: "Weekly stats", comment: "Widget weekly stats header"), icon: "chart.bar.fill")

            HStack(spacing: 0) {
                WGMiniStat(
                    label: String(localized: "Distance", comment: "Widget distance label"),
                    value: distanceLabel,
                    unit: "km"
                )
                WGMiniStat(
                    label: String(localized: "Runs", comment: "Widget runs label"),
                    value: "\(totalRuns)",
                    leadingDivider: true
                )
                WGMiniStat(
                    label: String(localized: "Time", comment: "Widget time label"),
                    value: durationLabel,
                    mono: true,
                    leadingDivider: true
                )
            }
            .padding(.top, 14)

            Spacer(minLength: 0)

            DayBarGrid(daily: dailyKm, todayIdx: todayIdx, height: 26)
        }
        .padding(14)
        .wgContainerBackground()
    }

    // MARK: - Lock screen variants

    private var accessoryCircularView: some View {
        VStack(spacing: 1) {
            Image(systemName: "figure.run")
                .font(.caption)
            Text(String(format: "%.0fk", (entry.data?.totalDistance ?? 0) / 1000.0))
                .font(.system(.caption, design: .rounded, weight: .bold))
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var accessoryRectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "chart.bar.fill")
                Text(String(localized: "This week", comment: "Lock screen weekly title"))
                    .font(.headline)
                    .widgetAccentable()
            }
            HStack(spacing: 8) {
                Text("\(distanceLabel) km").font(.caption).fontWeight(.semibold)
                Text(String(localized: "\(totalRuns) runs", comment: "Number of runs"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var accessoryInlineView: some View {
        HStack(spacing: 4) {
            Image(systemName: "figure.run")
            Text("\(distanceLabel) km · \(String(localized: "\(totalRuns) runs", comment: "Number of runs"))")
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    // MARK: - Helpers

    private var totalRuns: Int { entry.data?.totalRuns ?? 0 }

    private var sessionsSuffix: String {
        String(localized: "/ 7 days", comment: "Suffix after run count, e.g. 4 / 7 days")
    }

    private var distanceLabel: String {
        String(format: "%.1f", (entry.data?.totalDistance ?? 0) / 1000.0)
    }

    private var durationLabel: String {
        let total = Int(entry.data?.totalDuration ?? 0)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 {
            return String(format: "%dh%02d", h, m)
        }
        return String(format: "%dmin", m)
    }

    private var volumeSubtitle: String {
        let km = (entry.data?.totalDistance ?? 0) / 1000.0
        return String(format: "%.1f km · %@", km, durationLabel)
    }

    private var dailyKm: [Double] {
        entry.data?.dailyDistancesKm ?? Array(repeating: 0.0, count: 7)
    }

    private var todayIdx: Int {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: Date())
        return (weekday - calendar.firstWeekday + 7) % 7
    }
}

// MARK: - Day bar grid (7 columns)

private struct DayBarGrid: View {
    let daily: [Double]
    let todayIdx: Int
    let height: CGFloat

    private var letters: [String] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let firstWeekday = calendar.firstWeekday
        return (0..<7).map { offset in
            let weekdayNumber = ((firstWeekday - 1 + offset) % 7) + 1
            return symbols[(weekdayNumber - 1) % symbols.count].uppercased()
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { idx in
                let value = idx < daily.count ? daily[idx] : 0
                let isToday = idx == todayIdx
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(value > 0 ? Color.wgAccent : (isToday ? Color.white.opacity(0.14) : Color.white.opacity(0.05)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(isToday && value <= 0 ? Color.wgAccent : Color.clear, lineWidth: 0.5)
                        )
                        .frame(height: height)

                    Text(letters[idx])
                        .font(WGFont.mono(8, weight: isToday ? .heavy : .semibold))
                        .foregroundStyle(isToday ? Color.wgAccent : Color.wgTextTertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Widget Definition

struct WeeklyStatsWidget: Widget {
    let kind = "WeeklyStatsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WeeklyStatsProvider()) { entry in
            WeeklyStatsWidgetView(entry: entry)
        }
        .configurationDisplayName(String(localized: "Weekly Stats", comment: "Widget display name"))
        .description(String(localized: "Distance, runs and pace for the current week.", comment: "Weekly stats widget description"))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
