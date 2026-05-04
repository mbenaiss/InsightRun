//
//  SleepQualityWidget.swift
//  InsightRunWidgets
//
//  Sleep quality widget — small (duration hero), medium (duration + 2 KPIs +
//  bedtime → wake range).
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
                totalSleepHours: 7.33,
                sleepEfficiency: 95,
                qualityScore: 82,
                deepSleepHours: 1.1,
                remSleepHours: 1.6,
                sleepStartTime: "23:42",
                sleepEndTime: "07:05"
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
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 2, to: Date())!
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

    // MARK: - Small (duration hero + range)

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 0) {
            WGHeader(label: String(localized: "Sleep", comment: "Widget sleep title"), icon: "moon.fill", color: .wgPurple)

            Spacer(minLength: 12)

            sleepDurationDisplay

            if let q = entry.data?.qualityScore {
                Text(qualityLabel(q))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(qualityColor(q))
                    .padding(.top, 2)
            }

            Spacer()

            if let data = entry.data {
                HStack(spacing: 4) {
                    Text(data.sleepStartTime)
                        .font(WGFont.mono(10, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 7, weight: .bold))
                    Text(data.sleepEndTime)
                        .font(WGFont.mono(10, weight: .semibold))
                }
                .foregroundStyle(Color.wgTextTertiary)
            }
        }
        .padding(14)
        .wgContainerBackground()
    }

    // MARK: - Medium (duration + 2 KPI + range)

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 0) {
            WGHeader(label: String(localized: "Sleep", comment: "Widget sleep title"), icon: "moon.fill", color: .wgPurple)

            HStack(alignment: .bottom) {
                sleepDurationDisplay

                Spacer()

                if let data = entry.data {
                    HStack(spacing: 16) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "%.0f", data.sleepEfficiency))
                                .font(WGFont.num(18, weight: .bold))
                                .foregroundStyle(Color.wgTextPrimary)
                            + Text("%")
                                .font(WGFont.mono(11, weight: .semibold))
                                .foregroundStyle(Color.wgTextTertiary)

                            Text(String(localized: "EFFICIENCY", comment: "Widget sleep efficiency").uppercased())
                                .font(WGFont.microLabel)
                                .tracking(WGTracking.microLabel)
                                .foregroundStyle(Color.wgTextTertiary)
                        }

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(data.qualityScore)")
                                .font(WGFont.num(18, weight: .bold))
                                .foregroundStyle(Color.wgTextPrimary)

                            Text(String(localized: "QUALITY", comment: "Widget sleep quality").uppercased())
                                .font(WGFont.microLabel)
                                .tracking(WGTracking.microLabel)
                                .foregroundStyle(Color.wgTextTertiary)
                        }
                    }
                }
            }
            .padding(.top, 14)

            Spacer(minLength: 0)

            if let data = entry.data {
                HStack(spacing: 6) {
                    Image(systemName: "bed.double.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.wgTextTertiary)
                    Text(data.sleepStartTime)
                        .font(WGFont.mono(11, weight: .semibold))
                        .foregroundStyle(Color.wgTextSecondary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.wgTextTertiary)
                    Image(systemName: "sunrise.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.wgTextTertiary)
                    Text(data.sleepEndTime)
                        .font(WGFont.mono(11, weight: .semibold))
                        .foregroundStyle(Color.wgTextSecondary)
                }
            }
        }
        .padding(14)
        .wgContainerBackground()
    }

    // MARK: - Sleep duration display ("7h 20")

    private var sleepDurationDisplay: some View {
        let hours = Int(entry.data?.totalSleepHours ?? 0)
        let minutes = Int(((entry.data?.totalSleepHours ?? 0) - Double(hours)) * 60)
        return HStack(alignment: .lastTextBaseline, spacing: 3) {
            Text("\(hours)")
                .font(WGFont.num(36, weight: .heavy))
                .kerning(WGTracking.numHero(36))
                .foregroundStyle(Color.wgTextPrimary)
            Text("h")
                .font(WGFont.num(18, weight: .semibold))
                .foregroundStyle(Color.wgTextSecondary)
            Text(String(format: "%02d", minutes))
                .font(WGFont.num(36, weight: .heavy))
                .kerning(WGTracking.numHero(36))
                .foregroundStyle(Color.wgTextPrimary)
        }
    }

    // MARK: - Lock screen variants

    private var accessoryCircularView: some View {
        VStack(spacing: 1) {
            Image(systemName: "moon.zzz.fill")
                .font(.caption2)
            Text(formattedSleepDurationShort(entry.data?.totalSleepHours ?? 0))
                .font(.system(.caption2, design: .rounded, weight: .bold))
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var accessoryRectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "moon.zzz.fill")
                Text(String(localized: "Sleep", comment: "Lock screen sleep title"))
                    .font(.headline)
                    .widgetAccentable()
            }
            if let data = entry.data {
                HStack(spacing: 8) {
                    Text(formattedSleepDurationShort(data.totalSleepHours))
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("\(data.qualityScore)/100")
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

    private var accessoryInlineView: some View {
        HStack(spacing: 4) {
            Image(systemName: "moon.zzz.fill")
            if let data = entry.data {
                Text("\(formattedSleepDurationShort(data.totalSleepHours)) · \(data.qualityScore)")
            } else {
                Text(String(localized: "No sleep data", comment: "No sleep data placeholder"))
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    // MARK: - Helpers

    private func formattedSleepDurationShort(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return String(format: "%dh%02d", h, m)
    }

    private func qualityColor(_ score: Int) -> Color {
        switch score {
        case 80...:    return .wgSuccess
        case 60..<80:  return .wgAccent
        case 40..<60:  return .wgWarning
        default:       return .wgError
        }
    }

    private func qualityLabel(_ score: Int) -> String {
        switch score {
        case 80...:    return String(localized: "Restful", comment: "Sleep quality: high")
        case 60..<80:  return String(localized: "Good", comment: "Sleep quality: medium")
        case 40..<60:  return String(localized: "Fragmented", comment: "Sleep quality: low-medium")
        default:       return String(localized: "Poor", comment: "Sleep quality: low")
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
        .configurationDisplayName(String(localized: "Sleep", comment: "Widget display name: sleep"))
        .description(String(localized: "Last night's sleep duration and quality.", comment: "Sleep widget description"))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
