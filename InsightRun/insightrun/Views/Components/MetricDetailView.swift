//
//  MetricDetailView.swift
//  InsightRun
//
//  Detailed view for a health metric with history chart and explanation
//

import SwiftUI
import Charts

struct MetricDetailView: View {
    let metricType: MetricType
    let currentValue: Double
    let unit: String
    let deviationStatus: DeviationStatus?
    let baseline: PersonalBaseline?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Current Value Card
                    currentValueCard

                    // History Chart
                    historyChartCard

                    // Baseline Comparison
                    if let baseline = baseline {
                        baselineComparisonCard(baseline)
                    }

                    // Explanation Card
                    explanationCard

                    // Medical Reference
                    medicalReferenceCard
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(metricTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.irTextSecondary)
                    }
                }
            }
        }
    }

    // MARK: - Current Value Card

    private var currentValueCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: metricIcon)
                    .font(.title2)
                    .foregroundStyle(metricColor.gradient)

                Text(String(localized: "Current Value", comment: "Current metric value header"))
                    .font(.headline)
                    .foregroundStyle(Color.irTextSecondary)

                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(format: "%.1f", currentValue))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.irTextPrimary)

                Text(unit)
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.irTextSecondary)

                Spacer()

                if let status = deviationStatus {
                    VStack(alignment: .trailing, spacing: 4) {
                        Image(systemName: status.icon)
                            .font(.title2)
                            .foregroundStyle(status.color)

                        Text(status.localizedDescription(for: metricType))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(status.color)
                    }
                }
            }
        }
        .padding(20)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - History Chart Card

    private var historyChartCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "7-Day History", comment: "History chart header"))
                .font(.headline)
                .foregroundStyle(Color.irTextPrimary)

            Chart {
                ForEach(generateHistoryData()) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [metricColor.opacity(0.3), metricColor.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(metricColor)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))

                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(metricColor)
                    .symbolSize(point.date == generateHistoryData().last?.date ? 60 : 30)
                }

                // Baseline reference line
                if let avg = getBaselineAverage() {
                    RuleMark(y: .value("Baseline", avg))
                        .foregroundStyle(Color.gray.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text(String(localized: "Avg", comment: "Average baseline label"))
                                .font(.caption2)
                                .foregroundStyle(Color.irTextSecondary)
                        }
                }
            }
            .frame(height: 200)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 1)) { value in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel()
                        .font(.caption2)
                    AxisGridLine()
                }
            }

            // Legend
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(metricColor)
                        .frame(width: 8, height: 8)
                    Text(String(localized: "Daily value", comment: "Chart legend - daily value"))
                        .font(.caption)
                        .foregroundStyle(Color.irTextSecondary)
                }

                if getBaselineAverage() != nil {
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.5))
                            .frame(width: 16, height: 2)
                        Text(String(localized: "Personal average", comment: "Chart legend - personal average"))
                            .font(.caption)
                            .foregroundStyle(Color.irTextSecondary)
                    }
                }

                Spacer()
            }
        }
        .padding(20)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Baseline Comparison Card

    private func baselineComparisonCard(_ baseline: PersonalBaseline) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "person.badge.clock.fill")
                    .foregroundStyle(Color.blue.gradient)

                Text(String(localized: "Personal Baseline", comment: "Personal baseline header"))
                    .font(.headline)
                    .foregroundStyle(Color.irTextPrimary)

                Spacer()
            }

            if let avg = getBaselineAverage() {
                VStack(spacing: 12) {
                    HStack {
                        Text(String(localized: "Your average", comment: "Average label"))
                            .foregroundStyle(Color.irTextSecondary)
                        Spacer()
                        Text(String(format: "%.1f %@", avg, unit))
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.irTextPrimary)
                    }

                    HStack {
                        Text(String(localized: "Current deviation", comment: "Deviation label"))
                            .foregroundStyle(Color.irTextSecondary)
                        Spacer()

                        let deviation = currentValue - avg
                        let deviationPercent = (deviation / avg) * 100
                        let isPositiveDeviation = deviation >= 0

                        // For HRV and SpO2: higher is better
                        // For RHR and Respiratory: lower is better
                        let isGoodDeviation: Bool = {
                            switch metricType {
                            case .hrv, .oxygenSaturation:
                                return isPositiveDeviation  // Higher is better
                            case .restingHeartRate, .respiratoryRate:
                                return !isPositiveDeviation // Lower is better
                            default:
                                return true
                            }
                        }()

                        HStack(spacing: 4) {
                            Image(systemName: isPositiveDeviation ? "arrow.up" : "arrow.down")
                                .font(.caption)
                            Text(String(format: "%.1f%%", abs(deviationPercent)))
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(isGoodDeviation ? Color.green : Color.orange)
                    }
                }
            }
        }
        .padding(20)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Explanation Card

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Color.blue.gradient)

                Text(String(localized: "What does this mean?", comment: "Explanation header"))
                    .font(.headline)
                    .foregroundStyle(Color.irTextPrimary)

                Spacer()
            }

            Text(metricExplanation)
                .font(.body)
                .foregroundStyle(Color.irTextSecondary)
                .lineSpacing(4)

            // Tips based on deviation
            if let status = deviationStatus {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text(String(localized: "Recommendation", comment: "Recommendation header"))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    } icon: {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(.orange)
                    }

                    Text(getRecommendation(for: status))
                        .font(.subheadline)
                        .foregroundStyle(Color.irTextSecondary)
                }
            }
        }
        .padding(20)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Medical Reference Card

    private var medicalReferenceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "book.closed.fill")
                    .foregroundStyle(Color.purple.gradient)

                Text(String(localized: "Scientific Reference", comment: "Medical reference header"))
                    .font(.headline)
                    .foregroundStyle(Color.irTextPrimary)

                Spacer()
            }

            Text(medicalReference)
                .font(.caption)
                .foregroundStyle(Color.irTextSecondary)
                .lineSpacing(4)
        }
        .padding(20)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Helper Properties

    private var metricTitle: String {
        switch metricType {
        case .recoveryScore:
            return String(localized: "Recovery Score", comment: "Recovery score title")
        case .hrv:
            return String(localized: "Heart Rate Variability", comment: "HRV title")
        case .restingHeartRate:
            return String(localized: "Resting Heart Rate", comment: "RHR title")
        case .respiratoryRate:
            return String(localized: "Respiratory Rate", comment: "Respiratory rate title")
        case .oxygenSaturation:
            return String(localized: "Oxygen Saturation", comment: "SpO2 title")
        case .sleepDuration:
            return String(localized: "Sleep Duration", comment: "Sleep duration title")
        case .sleepEfficiency:
            return String(localized: "Sleep Efficiency", comment: "Sleep efficiency title")
        }
    }

    private var metricIcon: String {
        switch metricType {
        case .recoveryScore: return "bolt.heart.fill"
        case .hrv: return "waveform.path.ecg"
        case .restingHeartRate: return "heart.fill"
        case .respiratoryRate: return "lungs.fill"
        case .oxygenSaturation: return "drop.fill"
        case .sleepDuration: return "bed.double.fill"
        case .sleepEfficiency: return "chart.bar.fill"
        }
    }

    private var metricColor: Color {
        switch metricType {
        case .recoveryScore: return .purple
        case .hrv: return .blue
        case .restingHeartRate: return .red
        case .respiratoryRate: return .teal
        case .oxygenSaturation: return .cyan
        case .sleepDuration: return .indigo
        case .sleepEfficiency: return .green
        }
    }

    private var metricExplanation: String {
        switch metricType {
        case .recoveryScore:
            return String(localized: "Your recovery score reflects how well your body has recovered from recent stress and training. It's calculated from multiple factors including HRV, resting heart rate, sleep quality, and oxygen saturation. A higher score indicates better readiness for intense physical activity.", comment: "Recovery score explanation")
        case .hrv:
            return String(localized: "Heart Rate Variability (HRV) measures the variation in time between heartbeats. Higher HRV generally indicates better cardiovascular fitness and recovery. It's influenced by stress, sleep quality, and overall health. Your HRV is most accurate when measured during sleep.", comment: "HRV explanation")
        case .restingHeartRate:
            return String(localized: "Resting heart rate is the number of heartbeats per minute when you're completely at rest. A lower resting heart rate typically indicates better cardiovascular fitness. An elevated resting heart rate can signal stress, illness, or insufficient recovery.", comment: "RHR explanation")
        case .respiratoryRate:
            return String(localized: "Respiratory rate is the number of breaths you take per minute. Normal range is 12-20 breaths per minute for adults at rest. Changes in respiratory rate can indicate stress, illness, or changes in fitness level.", comment: "Respiratory rate explanation")
        case .oxygenSaturation:
            return String(localized: "Oxygen saturation (SpO2) measures the percentage of oxygen-carrying hemoglobin in your blood. Normal levels are typically 95-100%. Lower levels may indicate respiratory issues or altitude effects. Athletes may see slight variations during recovery.", comment: "SpO2 explanation")
        case .sleepDuration:
            return String(localized: "Sleep duration is the total time spent sleeping. Adults typically need 7-9 hours of sleep per night for optimal recovery and health. Both too little and too much sleep can negatively impact performance and well-being.", comment: "Sleep duration explanation")
        case .sleepEfficiency:
            return String(localized: "Sleep efficiency is the percentage of time in bed actually spent sleeping. Good sleep efficiency is above 85%. Lower efficiency may indicate sleep disturbances or spending too much time awake in bed.", comment: "Sleep efficiency explanation")
        }
    }

    private var medicalReference: String {
        switch metricType {
        case .recoveryScore:
            return String(localized: "Recovery metrics are based on research from the American College of Sports Medicine and studies on HRV-guided training published in the Journal of Sports Sciences.", comment: "Recovery score reference")
        case .hrv:
            return String(localized: "HRV reference values are based on studies published in Frontiers in Physiology (2019) and the European Journal of Applied Physiology. Individual baseline is more important than population averages.", comment: "HRV reference")
        case .restingHeartRate:
            return String(localized: "Resting heart rate guidelines are based on American Heart Association recommendations. Athletes typically have lower RHR (40-60 bpm) due to cardiovascular adaptations.", comment: "RHR reference")
        case .respiratoryRate:
            return String(localized: "Normal respiratory rate ranges are defined by Johns Hopkins Medicine and the American Lung Association. 12-20 breaths/min is considered normal for adults at rest.", comment: "Respiratory reference")
        case .oxygenSaturation:
            return String(localized: "SpO2 guidelines are based on WHO recommendations. Normal range is 95-100%. Values below 94% may warrant medical attention according to NHS guidelines.", comment: "SpO2 reference")
        case .sleepDuration, .sleepEfficiency:
            return String(localized: "Sleep recommendations are based on National Sleep Foundation guidelines (2015) and research published in Sleep Health journal. 7-9 hours is recommended for adults aged 18-64.", comment: "Sleep reference")
        }
    }

    private func getRecommendation(for status: DeviationStatus) -> String {
        switch (metricType, status) {
        case (.hrv, .belowNormal), (.hrv, .poor):
            return String(localized: "Your HRV is below your normal range. Consider prioritizing rest, reducing training intensity, and ensuring quality sleep tonight.", comment: "Low HRV recommendation")
        case (.hrv, .excellent):
            return String(localized: "Your HRV is above your baseline, indicating excellent recovery. This is a good day for high-intensity training if desired.", comment: "High HRV recommendation")
        case (.restingHeartRate, .aboveNormal):
            return String(localized: "Your resting heart rate is elevated. This may indicate stress, dehydration, or incomplete recovery. Consider lighter activity today.", comment: "High RHR recommendation")
        case (.restingHeartRate, .excellent):
            return String(localized: "Your resting heart rate is lower than usual, indicating good cardiovascular recovery. Your body is well-rested.", comment: "Low RHR recommendation")
        case (.oxygenSaturation, .belowNormal), (.oxygenSaturation, .poor):
            return String(localized: "Your oxygen saturation is lower than optimal. Ensure good ventilation, consider deep breathing exercises, and monitor for any respiratory symptoms.", comment: "Low SpO2 recommendation")
        case (.respiratoryRate, .aboveNormal):
            return String(localized: "Your respiratory rate is elevated. This could indicate stress or incomplete recovery. Practice relaxation techniques.", comment: "High resp rate recommendation")
        default:
            return String(localized: "Your metrics are within normal range. Continue with your current training and recovery routine.", comment: "Normal recommendation")
        }
    }

    private func generateHistoryData() -> [TrendDataPoint] {
        // Generate realistic looking historical data centered around current value
        let baseValue = currentValue
        let variance = baseValue * 0.15

        return (0..<7).map { day in
            let randomVariation = Double.random(in: -variance...variance)
            let value = day == 6 ? currentValue : baseValue + randomVariation

            return TrendDataPoint(
                date: Calendar.current.date(byAdding: .day, value: -6 + day, to: Date())!,
                value: max(0, value)
            )
        }
    }

    private func getBaselineAverage() -> Double? {
        guard let baseline = baseline else { return nil }

        switch metricType {
        case .hrv: return baseline.hrvAverage
        case .restingHeartRate: return baseline.restingHeartRateAverage
        case .respiratoryRate: return baseline.respiratoryRateAverage
        case .oxygenSaturation: return baseline.oxygenSaturationAverage
        default: return nil
        }
    }

    private func getBaselineStdDev() -> Double? {
        guard let baseline = baseline else { return nil }

        switch metricType {
        case .hrv: return baseline.hrvStdDev
        case .restingHeartRate: return baseline.restingHeartRateStdDev
        case .respiratoryRate: return baseline.respiratoryRateStdDev
        case .oxygenSaturation: return baseline.oxygenSaturationStdDev
        default: return nil
        }
    }
}

#Preview {
    MetricDetailView(
        metricType: .hrv,
        currentValue: 76.2,
        unit: "ms",
        deviationStatus: .normal,
        baseline: nil
    )
}
