//
//  HealthVitalsWidget.swift
//  InsightRunWidgets
//
//  Health vitals widget — small (HRV hero + sparkline), medium (4-tile bio
//  grid: HRV, FC repos, SpO₂, Resp.).
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
                hrv: 112,
                restingHeartRate: 53,
                oxygenSaturation: 99.0,
                respiratoryRate: 13.5,
                walkingHeartRate: 85,
                hrvSeries: [104, 108, 102, 110, 116, 109, 112],
                rhrSeries: [51, 50, 52, 54, 53, 55, 53],
                hrvDelta: 4,
                rhrDelta: 2
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

    // MARK: - Small (HRV hero + sparkline at bottom)

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 0) {
            WGHeader(label: String(localized: "HRV", comment: "Widget HRV header"), icon: "waveform.path.ecg")

            Spacer(minLength: 12)

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(hrvValue)
                    .font(WGFont.num(36, weight: .heavy))
                    .kerning(WGTracking.numHero(36))
                    .foregroundStyle(Color.wgTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("ms")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.wgTextTertiary)
            }

            if let delta = entry.data?.hrvDelta {
                HStack(spacing: 2) {
                    Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 9, weight: .heavy))
                    Text(String(format: "%+.0f ms", delta))
                        .font(WGFont.mono(10, weight: .bold))
                }
                .foregroundStyle(delta >= 0 ? Color.wgSuccess : Color.wgWarning)
                .padding(.top, 2)
            }

            Spacer()

            WGSparkline(values: entry.data?.hrvSeries ?? [], color: .wgAccent)
                .frame(height: 36)
                .padding(.horizontal, -4)
                .padding(.bottom, -4)
        }
        .padding(14)
        .wgContainerBackground()
    }

    // MARK: - Medium (4-tile bio grid)

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                WGHeader(label: String(localized: "Vitals", comment: "Widget vitals header"), icon: "heart.text.square.fill")

                Spacer()

                Text(timestampLabel)
                    .font(WGFont.mono(10, weight: .semibold))
                    .foregroundStyle(Color.wgTextTertiary)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                spacing: 8
            ) {
                if let hrv = entry.data?.hrv {
                    WGBioMini(
                        label: String(localized: "HRV", comment: "Bio tile: HRV"),
                        value: String(format: "%.0f", hrv),
                        unit: "ms",
                        delta: entry.data?.hrvDelta.map { String(format: "%+.0f", $0) },
                        deltaPositive: (entry.data?.hrvDelta ?? 0) >= 0,
                        color: .wgAccent
                    )
                }
                if let rhr = entry.data?.restingHeartRate {
                    WGBioMini(
                        label: String(localized: "Resting HR", comment: "Bio tile: resting HR"),
                        value: String(format: "%.0f", rhr),
                        unit: "bpm",
                        delta: entry.data?.rhrDelta.map { String(format: "%+.0f", $0) },
                        deltaPositive: (entry.data?.rhrDelta ?? 0) <= 0,
                        color: .wgError
                    )
                }
                if let spo2 = entry.data?.oxygenSaturation {
                    WGBioMini(
                        label: String(localized: "SpO2", comment: "Bio tile: SpO2"),
                        value: String(format: "%.1f", spo2),
                        unit: "%",
                        delta: nil,
                        color: Color(uiColor: UIColor(red: 0.36, green: 0.76, blue: 1.0, alpha: 1.0))
                    )
                }
                if let resp = entry.data?.respiratoryRate {
                    WGBioMini(
                        label: String(localized: "Resp.", comment: "Bio tile: respiratory rate"),
                        value: String(format: "%.1f", resp),
                        unit: "rpm",
                        delta: nil,
                        color: .wgPurple
                    )
                }
            }
            .padding(.top, 10)

            Spacer(minLength: 0)
        }
        .padding(14)
        .wgContainerBackground()
    }

    // MARK: - Lock screen variants

    private var accessoryCircularView: some View {
        VStack(spacing: 1) {
            Image(systemName: "waveform.path.ecg")
                .font(.caption)
            Text(hrvValue)
                .font(.system(.caption, design: .rounded, weight: .bold))
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var accessoryRectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "heart.text.square.fill")
                Text(String(localized: "Vitals", comment: "Lock screen vitals title"))
                    .font(.headline)
                    .widgetAccentable()
            }
            HStack(spacing: 8) {
                if let hrv = entry.data?.hrv {
                    Text(String(format: "HRV %.0f ms", hrv))
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                if let rhr = entry.data?.restingHeartRate {
                    Text(String(format: "RHR %.0f", rhr))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var accessoryInlineView: some View {
        HStack(spacing: 4) {
            Image(systemName: "waveform.path.ecg")
            Text(String(format: "HRV %@ ms", hrvValue))
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    // MARK: - Helpers

    private var hrvValue: String {
        guard let hrv = entry.data?.hrv else { return "—" }
        return String(format: "%.0f", hrv)
    }

    private var timestampLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: entry.data?.date ?? Date())
    }
}

// MARK: - Widget Definition

struct HealthVitalsWidget: Widget {
    let kind = "HealthVitalsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HealthVitalsProvider()) { entry in
            HealthVitalsWidgetView(entry: entry)
        }
        .configurationDisplayName(String(localized: "Health Vitals", comment: "Widget display name"))
        .description(String(localized: "HRV, resting heart rate, SpO₂ and respiratory rate.", comment: "Health vitals widget description"))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
