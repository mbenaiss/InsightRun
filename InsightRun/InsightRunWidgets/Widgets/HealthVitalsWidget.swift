//
//  HealthVitalsWidget.swift
//  InsightRunWidgets
//
//  Widget displaying key health vitals (HRV, RHR, SpO2, Respiratory Rate)
//

import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct HealthVitalsEntry: TimelineEntry {
    let date: Date
    let data: WidgetHealthVitalsData?
}

// MARK: - Timeline Provider

struct HealthVitalsProvider: TimelineProvider {
    func placeholder(in context: Context) -> HealthVitalsEntry {
        HealthVitalsEntry(
            date: Date(),
            data: WidgetHealthVitalsData(
                date: Date(),
                hrv: 48,
                restingHeartRate: 54,
                oxygenSaturation: 97.5,
                respiratoryRate: 14,
                walkingHeartRate: 85
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (HealthVitalsEntry) -> Void) {
        let data = WidgetDataReader.read(WidgetHealthVitalsData.self, forKey: WidgetDataKeys.healthVitals)
        completion(HealthVitalsEntry(date: Date(), data: data))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HealthVitalsEntry>) -> Void) {
        let data = WidgetDataReader.read(WidgetHealthVitalsData.self, forKey: WidgetDataKeys.healthVitals)
        let entry = HealthVitalsEntry(date: Date(), data: data)
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

// MARK: - Widget Views

struct HealthVitalsWidgetView: View {
    let entry: HealthVitalsEntry
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
            Image(systemName: "waveform.path.ecg")
                .font(.caption)
            Text(entry.data?.hrv.map { String(format: "%.0f", $0) } ?? "--")
                .font(.system(.caption, design: .rounded, weight: .bold))
            Text("ms")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    // MARK: - Lock Screen: Rectangular

    private var accessoryRectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "heart.text.clipboard")
                Text("Signes vitaux")
                    .font(.headline)
                    .widgetAccentable()
            }
            HStack(spacing: 10) {
                if let hrv = entry.data?.hrv {
                    Text("HRV \(String(format: "%.0f", hrv))ms")
                        .font(.caption)
                }
                if let rhr = entry.data?.restingHeartRate {
                    Text("FC \(String(format: "%.0f", rhr))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let spo2 = entry.data?.oxygenSaturation {
                    Text("SpO2 \(String(format: "%.0f", spo2))%")
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
            Image(systemName: "waveform.path.ecg")
            Text("HRV \(entry.data?.hrv.map { String(format: "%.0f ms", $0) } ?? "--")")
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    // MARK: - Small Widget

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "heart.text.clipboard")
                    .font(.caption2)
                    .foregroundStyle(.red)
                Text("Sante")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
            }

            Spacer()

            if let hrv = entry.data?.hrv {
                VStack(alignment: .leading, spacing: 2) {
                    Text("HRV")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.0f ms", hrv))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.purple)
                }
            }

            Spacer()

            HStack(spacing: 12) {
                if let rhr = entry.data?.restingHeartRate {
                    VStack(alignment: .leading, spacing: 0) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.red)
                        Text(String(format: "%.0f", rhr))
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                }

                if let spo2 = entry.data?.oxygenSaturation {
                    VStack(alignment: .leading, spacing: 0) {
                        Image(systemName: "lungs.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.blue)
                        Text(String(format: "%.0f%%", spo2))
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                }
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
                Image(systemName: "heart.text.clipboard")
                    .font(.caption)
                    .foregroundStyle(.red)
                Text("Signes vitaux")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
            }

            HStack(spacing: 0) {
                // HRV
                VitalCard(
                    icon: "waveform.path.ecg",
                    label: "HRV",
                    value: entry.data?.hrv.map { String(format: "%.0f", $0) } ?? "--",
                    unit: "ms",
                    color: .purple
                )

                Spacer()

                // Resting Heart Rate
                VitalCard(
                    icon: "heart.fill",
                    label: "FC repos",
                    value: entry.data?.restingHeartRate.map { String(format: "%.0f", $0) } ?? "--",
                    unit: "bpm",
                    color: .red
                )

                Spacer()

                // SpO2
                VitalCard(
                    icon: "lungs.fill",
                    label: "SpO2",
                    value: entry.data?.oxygenSaturation.map { String(format: "%.0f", $0) } ?? "--",
                    unit: "%",
                    color: .blue
                )

                Spacer()

                // Respiratory Rate
                VitalCard(
                    icon: "wind",
                    label: "Resp.",
                    value: entry.data?.respiratoryRate.map { String(format: "%.0f", $0) } ?? "--",
                    unit: "/min",
                    color: .teal
                )
            }
        }
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }
}

// MARK: - Vital Card

private struct VitalCard: View {
    let icon: String
    let label: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)

            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text(unit)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Widget Definition

struct HealthVitalsWidget: Widget {
    let kind = "HealthVitalsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HealthVitalsProvider()) { entry in
            HealthVitalsWidgetView(entry: entry)
        }
        .configurationDisplayName("Signes vitaux")
        .description("HRV, frequence cardiaque au repos, SpO2 et frequence respiratoire.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
