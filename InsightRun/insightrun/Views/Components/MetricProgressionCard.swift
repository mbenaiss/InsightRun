//
//  MetricProgressionCard.swift
//  InsightRun
//
//  Interactive chart card showing metric progression over time
//

import Charts
import SwiftUI

struct MetricProgressionCard: View {
    let series: StatisticsViewModel.MetricSeries
    @State private var selectedDate: Date?
    @State private var showingInfo = false

    private var selectedPoint: (date: Date, value: Double)? {
        guard let selectedDate else { return nil }
        return series.points.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            header
            chartView
        }
        .padding(Spacing.cardPadding)
        .detailCard()
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Text(series.name)
                .font(IRFont.footnote.weight(.semibold))
                .foregroundStyle(Color.irTextPrimary)

            Spacer()

            if let trend = series.trendPercentage {
                TrendBadge(percentage: trend, lowerIsBetter: series.lowerIsBetter)
            }

            if let infoKey = series.metricInfoKey {
                Button {
                    showingInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(IRFont.footnote)
                        .foregroundStyle(Color.irTextSecondary.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    String(
                        localized: "progression.info.label", defaultValue: "About this metric",
                        comment: "Accessibility label for the metric info button")
                )
                .sheet(isPresented: $showingInfo) {
                    MetricInfoSheet(metricInfo: MetricInfo(key: infoKey, currentValue: series.average))
                }
            }
        }
    }

    // MARK: - Chart

    private var chartView: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Current average value
            if let point = selectedPoint {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
                    Text(formatValue(point.value))
                        .font(IRFont.numMD)
                        .foregroundStyle(Color.irTextPrimary)

                    Text(series.unit)
                        .font(IRFont.body)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.irTextSecondary)

                    Spacer()

                    Text(formatDate(point.date))
                        .font(IRFont.caption)
                        .foregroundStyle(Color.irTextSecondary)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
                    Text(formatValue(series.average))
                        .font(IRFont.numMD)
                        .foregroundStyle(Color.irTextPrimary)

                    Text(series.unit)
                        .font(IRFont.body)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.irTextSecondary)

                    Spacer()

                    Text(String(localized: "progression.average", defaultValue: "avg", comment: "Average label"))
                        .font(IRFont.caption)
                        .foregroundStyle(Color.irTextSecondary)
                }
            }

            Chart {
                ForEach(Array(series.chartPoints.enumerated()), id: \.offset) { _, point in
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Value", displayValue(point.value))
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [series.color.opacity(0.3), series.color.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.linear)
                }

                ForEach(Array(series.chartPoints.enumerated()), id: \.offset) { _, point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", displayValue(point.value))
                    )
                    .foregroundStyle(series.color)
                    .interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }

                if let selected = selectedPoint {
                    PointMark(
                        x: .value("Date", selected.date),
                        y: .value("Value", displayValue(selected.value))
                    )
                    .foregroundStyle(series.color)
                    .symbolSize(50)

                    RuleMark(x: .value("Date", selected.date))
                        .foregroundStyle(Color.irTextSecondary.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .frame(height: 150)
            .chartXScale(range: .plotDimension(padding: 20))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(formatAxisDate(date)).fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                        .foregroundStyle(Color.irTextSecondary.opacity(0.2))
                    AxisValueLabel {
                        if let val = value.as(Double.self) {
                            Text(formatDisplayedValue(val))
                                .font(IRFont.microLabel)
                        }
                    }
                }
            }
            .chartXSelection(value: $selectedDate)
            .accessibilityLabel(series.name)
            .accessibilityValue("\(formatValue(series.average)) \(series.unit)")
        }
    }

    // MARK: - Formatters

    private func displayValue(_ value: Double) -> Double {
        if series.id == "averagePace" || series.id == "minPace" {
            return value / Formatters.distanceValue(km: 1)
        }
        return value
    }

    private func formatValue(_ value: Double) -> String {
        formatDisplayedValue(displayValue(value))
    }

    // Chart axis values are already in the display unit and must not be converted again.
    private func formatDisplayedValue(_ value: Double) -> String {
        if series.id == "minPace" || series.id == "averagePace" {
            return Formatters.paceClock(value * 60)
        }
        if value >= 100 {
            return Formatters.decimal(value, fractionDigits: 0)
        }
        return Formatters.decimal(value, fractionDigits: 1)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale.current
        return formatter.string(from: date)
    }

    private func formatAxisDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter.string(from: date)
    }
}

// MARK: - Trend Badge

struct TrendBadge: View {
    let percentage: Double
    let lowerIsBetter: Bool

    private var isPositive: Bool {
        lowerIsBetter ? percentage < 0 : percentage > 0
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: percentage > 0 ? "arrow.up.right" : "arrow.down.right")
                .font(IRFont.microLabel)

            Text(Formatters.percent(percentage, fractionDigits: 0, signed: true))
                .font(IRFont.microLabel)
                .fontWeight(.semibold)
        }
        .foregroundStyle(isPositive ? Color.irSuccess : Color.irError)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xxs)
        .background((isPositive ? Color.irSuccess : Color.irError).opacity(0.12))
        .clipShape(Capsule())
    }
}
