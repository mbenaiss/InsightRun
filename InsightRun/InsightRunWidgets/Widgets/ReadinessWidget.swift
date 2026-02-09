//
//  ReadinessWidget.swift
//  InsightRunWidgets
//
//  Widget displaying daily recovery/readiness score with circular gauge
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
            data: WidgetReadinessData(score: 78, status: "good", date: Date(), hrvValue: 45, rhrValue: 55)
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

    // MARK: - Lock Screen: Circular

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

    // MARK: - Lock Screen: Rectangular

    private var accessoryRectangularView: some View {
        HStack(spacing: 8) {
            Gauge(value: Double(score), in: 0...100) {
                Text("")
            }
            .gaugeStyle(.accessoryCircular)
            .scaleEffect(0.7)
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Readiness", comment: "Widget readiness title"))
                    .font(.headline)
                    .widgetAccentable()
                Text("\(score)/100 - \(statusText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    // MARK: - Lock Screen: Inline

    private var accessoryInlineView: some View {
        HStack(spacing: 4) {
            Image(systemName: "bolt.heart.fill")
            Text("\(String(localized: "Readiness", comment: "Widget readiness inline")) \(score)/100")
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    // MARK: - Small Widget

    private var smallView: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "bolt.heart.fill")
                    .font(.caption2)
                    .foregroundStyle(scoreColor)
                Text(String(localized: "Readiness", comment: "Widget readiness title"))
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
            }

            Spacer()

            ZStack {
                Circle()
                    .stroke(scoreColor.opacity(0.15), lineWidth: 8)
                    .frame(width: 72, height: 72)

                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 72, height: 72)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut, value: score)

                VStack(spacing: 0) {
                    Text("\(score)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(statusText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(scoreColor)
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
        HStack(spacing: 20) {
            // Circular gauge
            ZStack {
                Circle()
                    .stroke(scoreColor.opacity(0.15), lineWidth: 10)
                    .frame(width: 100, height: 100)

                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(
                        scoreGradient,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text("\(score)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(statusText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(scoreColor)
                }
            }

            // Details
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "bolt.heart.fill")
                        .font(.subheadline)
                        .foregroundStyle(scoreColor)
                    Text(String(localized: "Readiness", comment: "Widget readiness title"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }

                Divider()

                if let hrv = entry.data?.hrvValue {
                    WidgetMetricRow(
                        icon: "waveform.path.ecg",
                        label: "HRV",
                        value: String(format: "%.0f %@", hrv, String(localized: "ms", comment: "Unit: milliseconds")),
                        color: .purple
                    )
                }

                if let rhr = entry.data?.rhrValue {
                    WidgetMetricRow(
                        icon: "heart.fill",
                        label: String(localized: "Resting HR", comment: "Resting heart rate label"),
                        value: String(format: "%.0f %@", rhr, String(localized: "bpm", comment: "Unit: beats per minute")),
                        color: .red
                    )
                }

                if entry.data?.hrvValue == nil && entry.data?.rhrValue == nil {
                    Text(String(localized: "Open the app to sync", comment: "Prompt to open app"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }

    // MARK: - Computed Properties

    private var score: Int {
        entry.data?.score ?? 0
    }

    private var statusText: String {
        guard let status = entry.data?.status else { return "--" }
        switch status {
        case "excellent": return String(localized: "Excellent", comment: "Readiness status")
        case "good": return String(localized: "Good", comment: "Readiness status")
        case "fair": return String(localized: "Fair", comment: "Readiness status")
        case "poor": return String(localized: "Poor", comment: "Readiness status")
        default: return status.capitalized
        }
    }

    private var scoreColor: Color {
        switch entry.data?.status {
        case "excellent": return .green
        case "good": return .yellow
        case "fair": return .orange
        default: return .red
        }
    }

    private var scoreGradient: AngularGradient {
        AngularGradient(
            gradient: Gradient(colors: [scoreColor.opacity(0.5), scoreColor]),
            center: .center,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * Double(score) / 100)
        )
    }
}

// MARK: - Widget Definition

struct ReadinessWidget: Widget {
    let kind = "ReadinessWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ReadinessProvider()) { entry in
            ReadinessWidgetView(entry: entry)
        }
        .configurationDisplayName(String(localized: "Readiness", comment: "Widget display name"))
        .description(String(localized: "Daily readiness and recovery score.", comment: "Readiness widget description"))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
