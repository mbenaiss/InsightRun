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
            data: WidgetReadinessData(score: 61, status: "fair", date: Date(), hrvValue: 112, rhrValue: 53)
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ReadinessEntry) -> Void) {
        let data = WidgetDataReader.read(WidgetReadinessData.self, forKey: WidgetDataKeys.readiness)
        completion(ReadinessEntry(date: Date(), data: data))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReadinessEntry>) -> Void) {
        let data = WidgetDataReader.read(WidgetReadinessData.self, forKey: WidgetDataKeys.readiness)
        let entry = ReadinessEntry(date: Date(), data: data)
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
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
                label: WGStatusColor.recoveryLabel(score: score),
                color: WGStatusColor.recovery(score: score)
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

                Text(timestampLabel)
                    .font(WGFont.mono(10, weight: .semibold))
                    .foregroundStyle(Color.wgTextTertiary)
            }

            HStack(alignment: .center, spacing: 14) {
                WGMiniRing(
                    value: score,
                    size: 70,
                    color: WGStatusColor.recovery(score: score)
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
                if let hrv = entry.data?.hrvValue {
                    WGMiniStat(
                        label: String(localized: "HRV", comment: "Widget HRV label"),
                        value: String(format: "%.0f", hrv),
                        unit: "ms"
                    )
                }
                if let rhr = entry.data?.rhrValue {
                    WGMiniStat(
                        label: String(localized: "Resting HR", comment: "Widget resting HR label"),
                        value: String(format: "%.0f", rhr),
                        unit: "bpm",
                        leadingDivider: entry.data?.hrvValue != nil
                    )
                }
            }
        }
        .padding(14)
        .wgContainerBackground()
    }

    // MARK: - Lock Screen variants (system styling)

    private var accessoryCircularView: some View {
        Gauge(value: Double(score), in: 0...100) {
            Text("R")
        } currentValueLabel: {
            Text("\(score)")
                .font(.system(.title3, design: .rounded, weight: .bold))
        }
        .gaugeStyle(.accessoryCircular)
        .containerBackground(for: .widget) { Color.clear }
    }

    private var accessoryRectangularView: some View {
        HStack(spacing: 8) {
            Gauge(value: Double(score), in: 0...100) { Text("") }
                .gaugeStyle(.accessoryCircular)
                .scaleEffect(0.7)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Recovery", comment: "Widget recovery lock title"))
                    .font(.headline)
                    .widgetAccentable()
                Text("\(score)/100 · \(statusText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var accessoryInlineView: some View {
        HStack(spacing: 4) {
            Image(systemName: "heart.fill")
            Text("\(String(localized: "Recovery", comment: "Widget recovery inline")) \(score) · \(statusText)")
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    // MARK: - Computed properties

    private var score: Int { entry.data?.score ?? 0 }

    private var statusText: String {
        switch entry.data?.status {
        case "excellent": return String(localized: "Excellent", comment: "Recovery status")
        case "good":      return String(localized: "Good", comment: "Recovery status")
        case "fair":      return String(localized: "Fair", comment: "Recovery status")
        case "poor":      return String(localized: "Rest", comment: "Recovery status")
        default:          return "—"
        }
    }

    private var headlineText: String {
        switch score {
        case 75...:    return String(localized: "Strong recovery", comment: "Widget recovery headline: high")
        case 55..<75:  return String(localized: "Recovery is fair", comment: "Widget recovery headline: medium")
        case 35..<55:  return String(localized: "Recovery is mixed", comment: "Widget recovery headline: low-medium")
        default:       return String(localized: "Take it easy", comment: "Widget recovery headline: low")
        }
    }

    private var coachingText: String {
        switch score {
        case 75...:    return String(localized: "You can push today.", comment: "Widget coaching: green light")
        case 55..<75:  return String(localized: "Easy run, RPE 2–3.", comment: "Widget coaching: easy")
        case 35..<55:  return String(localized: "20–30 min footing, no more.", comment: "Widget coaching: easy short")
        default:       return String(localized: "Rest day, prioritise sleep.", comment: "Widget coaching: rest")
        }
    }

    private var timestampLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: entry.data?.date ?? Date())
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
