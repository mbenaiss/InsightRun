//
//  LastWorkoutWidget.swift
//  InsightRunWidgets
//
//  Last workout widget — small (date chip + distance hero), medium (distance
//  hero + 3 KPIs: pace, duration, HR).
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

    // MARK: - Small (date chip + distance hero + pace)

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 0) {
            WGHeader(label: String(localized: "Last run", comment: "Widget last workout short header"), icon: "figure.run", color: .wgAccent)

            if entry.data != nil {
                Spacer(minLength: 6)

                Text(relativeDate)
                    .font(WGFont.mono(10, weight: .semibold))
                    .foregroundStyle(Color.wgTextTertiary)

                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(distanceLabel)
                        .font(WGFont.num(32, weight: .heavy))
                        .kerning(WGTracking.numHero(32))
                        .foregroundStyle(Color.wgTextPrimary)
                    Text("km")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.wgTextTertiary)
                }
                .padding(.top, 2)

                Spacer()

                if let pace = paceLabel {
                    HStack(spacing: 6) {
                        Image(systemName: "timer")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.wgTextTertiary)
                        Text(pace)
                            .font(WGFont.mono(11, weight: .bold))
                            .foregroundStyle(Color.wgTextSecondary)
                        Text("·")
                            .foregroundStyle(Color.wgTextTertiary)
                        Text(durationLabel)
                            .font(WGFont.mono(11, weight: .bold))
                            .foregroundStyle(Color.wgTextSecondary)
                    }
                }
            } else {
                Spacer()
                emptyState
                Spacer()
            }
        }
        .padding(14)
        .wgContainerBackground()
    }

    // MARK: - Medium (distance hero + 3 KPI strip)

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                WGHeader(label: String(localized: "Last workout", comment: "Widget last workout header"), icon: "figure.run", color: .wgAccent)

                Spacer()

                if entry.data != nil {
                    Text(relativeDate)
                        .font(WGFont.mono(10, weight: .semibold))
                        .foregroundStyle(Color.wgTextTertiary)
                }
            }

            if entry.data != nil {
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(distanceLabel)
                        .font(WGFont.num(40, weight: .heavy))
                        .kerning(WGTracking.numHero(40))
                        .foregroundStyle(Color.wgTextPrimary)
                    Text("km")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.wgTextTertiary)
                }
                .padding(.top, 12)

                Spacer(minLength: 0)

                HStack(spacing: 0) {
                    WGMiniStat(
                        label: String(localized: "Pace", comment: "Widget pace label"),
                        value: paceLabel ?? "—",
                        unit: paceLabel == nil ? "" : "/km",
                        mono: true
                    )
                    WGMiniStat(
                        label: String(localized: "Time", comment: "Widget time label"),
                        value: durationLabel,
                        mono: true,
                        leadingDivider: true
                    )
                    WGMiniStat(
                        label: String(localized: "Avg HR", comment: "Widget average HR label"),
                        value: heartRateLabel,
                        unit: heartRateLabel == "—" ? "" : "bpm",
                        valueColor: .wgError,
                        leadingDivider: true
                    )
                }
            } else {
                Spacer()
                emptyState
                Spacer()
            }
        }
        .padding(14)
        .wgContainerBackground()
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "figure.run")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.wgTextTertiary)
            Text(String(localized: "No workout yet", comment: "No workout placeholder"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.wgTextTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Lock screen variants

    private var accessoryCircularView: some View {
        VStack(spacing: 1) {
            Image(systemName: "figure.run")
                .font(.caption)
            Text(distanceLabel)
                .font(.system(.caption, design: .rounded, weight: .bold))
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var accessoryRectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "figure.run")
                Text(String(localized: "Last run", comment: "Lock screen last run title"))
                    .font(.headline)
                    .widgetAccentable()
            }
            if entry.data != nil {
                HStack(spacing: 8) {
                    Text("\(distanceLabel) km").font(.caption).fontWeight(.semibold)
                    if let pace = paceLabel {
                        Text(pace).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(String(localized: "No workout", comment: "No workout placeholder"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var accessoryInlineView: some View {
        HStack(spacing: 4) {
            Image(systemName: "figure.run")
            if entry.data != nil {
                Text("\(distanceLabel) km · \(paceLabel ?? durationLabel)")
            } else {
                Text(String(localized: "No workout", comment: "No workout placeholder"))
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    // MARK: - Helpers

    private var distanceLabel: String {
        String(format: "%.1f", (entry.data?.distance ?? 0) / 1000.0)
    }

    private var paceLabel: String? {
        guard let pace = entry.data?.averagePace, pace > 0 else { return nil }
        let minutes = Int(pace)
        let seconds = Int((pace - Double(minutes)) * 60)
        return String(format: "%d'%02d", minutes, seconds)
    }

    private var durationLabel: String {
        let total = Int(entry.data?.duration ?? 0)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 {
            return String(format: "%dh%02d", h, m)
        }
        return String(format: "%dmin", m)
    }

    private var heartRateLabel: String {
        guard let hr = entry.data?.averageHeartRate else { return "—" }
        return String(format: "%.0f", hr)
    }

    private var relativeDate: String {
        guard let workoutDate = entry.data?.date else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale.current
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: workoutDate, relativeTo: Date()).uppercased()
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
