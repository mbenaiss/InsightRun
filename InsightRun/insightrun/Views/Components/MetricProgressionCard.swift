//
//  MetricProgressionCard.swift
//  InsightRun
//
//  Interactive chart card showing metric progression over time
//

import SwiftUI
import Charts

struct MetricProgressionCard: View {
    let series: StatisticsViewModel.MetricSeries
    @State private var selectedDate: Date?
    @State private var showingInfo = false

    private var selectedPoint: (date: Date, value: Double)? {
        guard let selectedDate else { return nil }
        return series.points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            chartView
        }
        .padding()
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.irShadow, radius: 8, y: 4)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: series.icon)
                .font(.subheadline)
                .foregroundStyle(series.color.opacity(0.8))

            Text(series.name)
                .font(.subheadline)
                .foregroundStyle(Color.irTextSecondary)

            Spacer()

            if let trend = series.trendPercentage {
                TrendBadge(percentage: trend, lowerIsBetter: series.lowerIsBetter)
            }

            if let infoKey = series.metricInfoKey {
                Button {
                    showingInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(Color.irTextSecondary)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showingInfo) {
                    MetricInfoSheet(metricInfo: MetricInfo(key: infoKey, currentValue: series.average))
                }
            }
        }
    }

    // MARK: - Chart

    private var chartView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Current average value
            if let point = selectedPoint {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formatValue(point.value))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.irTextPrimary)

                    Text(series.unit)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.irTextSecondary)

                    Spacer()

                    Text(formatDate(point.date))
                        .font(.caption)
                        .foregroundStyle(Color.irTextSecondary)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formatValue(series.average))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.irTextPrimary)

                    Text(series.unit)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.irTextSecondary)

                    Spacer()

                    Text(String(localized: "progression.average", defaultValue: "avg", comment: "Average label"))
                        .font(.caption)
                        .foregroundStyle(Color.irTextSecondary)
                }
            }

            Chart {
                ForEach(Array(series.points.enumerated()), id: \.offset) { _, point in
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [series.color.opacity(0.3), series.color.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }

                ForEach(Array(series.points.enumerated()), id: \.offset) { _, point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(series.color)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }

                if let selected = selectedPoint {
                    PointMark(
                        x: .value("Date", selected.date),
                        y: .value("Value", selected.value)
                    )
                    .foregroundStyle(series.color)
                    .symbolSize(50)

                    RuleMark(x: .value("Date", selected.date))
                        .foregroundStyle(Color.irTextSecondary.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .frame(height: 150)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(formatAxisDate(date))
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
                            Text(formatValue(val))
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartXSelection(value: $selectedDate)
        }
    }

    // MARK: - Formatters

    private func formatValue(_ value: Double) -> String {
        if series.id == "minPace" || series.id == "averagePace" {
            let minutes = Int(value)
            let seconds = Int((value - Double(minutes)) * 60)
            return String(format: "%d:%02d", minutes, seconds)
        }
        if value >= 100 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale.current
        return formatter.string(from: date)
    }

    private func formatAxisDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        formatter.locale = Locale.current
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
                .font(.caption2)

            Text(String(format: "%@%.0f%%", percentage >= 0 ? "+" : "", percentage))
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .foregroundStyle(isPositive ? .green : .red)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background((isPositive ? Color.green : Color.red).opacity(0.12))
        .clipShape(Capsule())
    }
}
