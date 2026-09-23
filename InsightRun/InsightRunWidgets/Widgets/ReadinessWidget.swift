//
//  ReadinessWidget.swift
//  InsightRunWidgets
//
//  Daily recovery score widget — small (centred ring), medium (ring + coach
//  text + bio strip). Lock screen variants stay native.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct ReadinessEntry: TimelineEntry {
    let date: Date
    let data: WidgetReadinessData?
}

// MARK: - Timeline Provider

struct ReadinessProvider: TimelineProvider {
    func placeholder(in context: Context) -> ReadinessEntry {
        ReadinessEntry(
            date: Date(),
            data: WidgetReadinessData(score: 61, status: "good", date: Date(), hrvValue: 112, rhrValue: 53)
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ReadinessEntry) -> Void) {
        let data = WidgetDataReader.read(WidgetReadinessData.self, forKey: WidgetDataKeys.readiness)
        completion(ReadinessEntry(date: Date(), data: data))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReadinessEntry>) -> Void) {
        let data = WidgetDataReader.read(WidgetReadinessData.self, forKey: WidgetDataKeys.readiness)
        let now = Date()
        let calendar = Calendar.current
        let nextUpdate = calendar.date(byAdding: .hour, value: 1, to: now)!
        // Re-render at midnight so yesterday's score disappears even if the app is not opened.
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let entries = [ReadinessEntry(date: now, data: data), ReadinessEntry(date: midnight, data: data)]
        completion(Timeline(entries: entries, policy: .after(nextUpdate)))
    }
}

// MARK: - Widget Views

struct ReadinessWidgetView: View {
    let entry: ReadinessEntry
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

    // MARK: - Small (centred ring, "Récupération" eyebrow)

    private var smallView: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                WGHeader(label: String(localized: "Recovery", comment: "Widget recovery title"), icon: "heart.fill")
                Spacer()
            }

            WGMiniRing(
                value: score,
                size: 96,
                label: WGStatusColor.recoveryLabel(band),
                color: WGStatusColor.recovery(band)
            )
        }
        .padding(14)
        .wgContainerBackground(gradient: true)
    }

    // MARK: - Medium (ring + headline + bio strip)

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                WGHeader(label: String(localized: "This morning", comment: "Widget medium recovery header"), icon: "heart.fill")

                Spacer()

                if let todayData {
                    Text(timestampLabel(todayData.date))
                        .font(WGFont.mono(10, weight: .semibold))
                        .foregroundStyle(Color.wgTextTertiary)
                }
            }

            HStack(alignment: .center, spacing: 14) {
                WGMiniRing(
                    value: score,
                    size: 70,
                    color: WGStatusColor.recovery(band)
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(headlineText)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.wgTextPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(coachingText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.wgTextSecondary)
                        .lineSpacing(2)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 12)

            Spacer(minLength: 0)

            // Bio strip footer
            Rectangle()
                .fill(Color.wgBorder)
                .frame(height: 0.5)
                .padding(.bottom, 8)

            HStack(spacing: 0) {
                if let hrv = todayData?.hrvValue {
                    WGMiniStat(
                        label: String(localized: "HRV", comment: "Widget HRV label"),
                        value: String(format: "%.0f", hrv),
                        unit: "ms"
                    )
                }
                if let rhr = todayData?.rhrValue {
                    WGMiniStat(
                        label: String(localized: "Resting HR", comment: "Widget resting HR label"),
                        value: String(format: "%.0f", rhr),
                        unit: "bpm",
                        leadingDivider: todayData?.hrvValue != nil
                    )
                }
            }
        }
        .padding(14)
        .wgContainerBackground()
    }

    // MARK: - Lock Screen variants (system styling)

    private var accessoryCircularView: some View {
        Gauge(value: Double(score ?? 0), in: 0...100) {
            Text("R")
        } currentValueLabel: {
            Text(verbatim: score.map(String.init) ?? "—")
                .font(.system(.title3, design: .rounded, weight: .bold))
        }
        .gaugeStyle(.accessoryCircular)
        .containerBackground(for: .widget) { Color.clear }
    }

    private var accessoryRectangularView: some View {
        HStack(spacing: 8) {
            Gauge(value: Double(score ?? 0), in: 0...100) { Text("") }
                .gaugeStyle(.accessoryCircular)
                .scaleEffect(0.7)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Recovery", comment: "Widget recovery lock title"))
                    .font(.headline)
                    .widgetAccentable()
                Group {
                    if let score {
                        Text("\(score)/100 · \(statusText)")
                    } else {
                        Text(verbatim: statusText)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var accessoryInlineView: some View {
        HStack(spacing: 4) {
            Image(systemName: "heart.fill")
            if let score {
                Text("\(String(localized: "Recovery", comment: "Widget recovery inline")) \(score) · \(statusText)")
            } else {
                Text(verbatim: "\(String(localized: "Recovery", comment: "Widget recovery inline")) \(statusText)")
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    // MARK: - Computed properties

    // Yesterday's score must not be presented as this morning's.
    private var todayData: WidgetReadinessData? {
        guard let data = entry.data, Calendar.current.isDate(data.date, inSameDayAs: entry.date) else { return nil }
        return data
    }

    private var score: Int? { todayData?.score }

    private var band: ReadinessScoreBand? {
        todayData.map { ReadinessScoreBand(rawValue: $0.status) ?? ReadinessScoreBand(score: $0.score) }
    }

    private var statusText: String {
        switch band {
        case .excellent: return String(localized: "Excellent", comment: "Recovery status")
        case .good:      return String(localized: "Good", comment: "Recovery status")
        case .fair:      return String(localized: "Fair", comment: "Recovery status")
        case .poor:      return String(localized: "Rest", comment: "Recovery status")
        case nil:        return "—"
        }
    }

    private var headlineText: String {
        switch band {
        case .excellent: return String(localized: "Strong recovery", comment: "Widget recovery headline: high")
        case .good:      return String(localized: "Good recovery", comment: "Widget recovery headline: good")
        case .fair:      return String(localized: "Recovery is fair", comment: "Widget recovery headline: medium")
        case .poor:      return String(localized: "Take it easy", comment: "Widget recovery headline: low")
        case nil:        return String(localized: "No data", comment: "No data placeholder")
        }
    }

    private var coachingText: String {
        switch band {
        case .excellent: return String(localized: "You can push today.", comment: "Widget coaching: green light")
        case .good:      return String(localized: "Moderate run today.", comment: "Widget coaching: moderate")
        case .fair:      return String(localized: "Easy run, RPE 2–3.", comment: "Widget coaching: easy")
        case .poor:      return String(localized: "Rest day, prioritise sleep.", comment: "Widget coaching: rest")
        case nil:        return String(localized: "Open InsightRun to get today's score.", comment: "Widget coaching: no score today")
        }
    }

    private func timestampLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Widget Definition

struct ReadinessWidget: Widget {
    let kind = "ReadinessWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ReadinessProvider()) { entry in
            ReadinessWidgetView(entry: entry)
        }
        .configurationDisplayName(String(localized: "Recovery", comment: "Widget display name: recovery"))
        .description(String(localized: "Daily recovery and readiness score.", comment: "Recovery widget description"))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
