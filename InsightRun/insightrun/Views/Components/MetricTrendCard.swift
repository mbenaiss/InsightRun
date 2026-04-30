//
//  MetricTrendCard.swift
//  InsightRun
//
//  Enhanced metric card with deviation indicator and mini trend chart
//

import SwiftUI
import Charts

// MARK: - Deviation Status

enum DeviationStatus {
    case normal
    case aboveNormal
    case belowNormal
    case excellent
    case poor

    var color: Color {
        switch self {
        case .normal: return Color.irSuccess
        case .aboveNormal: return Color.irWarning
        case .belowNormal: return Color.irWarning
        case .excellent: return Color.irSuccess
        case .poor: return Color.irError
        }
    }

    var icon: String {
        switch self {
        case .normal: return "checkmark.circle.fill"
        case .aboveNormal: return "arrow.up.circle.fill"
        case .belowNormal: return "arrow.down.circle.fill"
        case .excellent: return "checkmark.circle.fill"
        case .poor: return "exclamationmark.circle.fill"
        }
    }

    func localizedDescription(for metricType: MetricType) -> String {
        switch self {
        case .normal:
            return String(localized: "Normal range", comment: "Metric status - normal range")
        case .aboveNormal:
            return String(localized: "Above normal", comment: "Metric status - above normal")
        case .belowNormal:
            return String(localized: "Below normal", comment: "Metric status - below normal")
        case .excellent:
            return String(localized: "Excellent", comment: "Metric status - excellent")
        case .poor:
            return String(localized: "Needs attention", comment: "Metric status - needs attention")
        }
    }
}

enum MetricType {
    case recoveryScore
    case hrv
    case restingHeartRate
    case respiratoryRate
    case oxygenSaturation
    case sleepDuration
    case sleepEfficiency
    case totalCalories
}

// MARK: - Trend Data Point

struct TrendDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

struct CaloriesBreakdownPoint: Identifiable {
    let id = UUID()
    let date: Date
    let active: Double
    let resting: Double

    var total: Double { active + resting }
}

// MARK: - Metric Trend Card

struct MetricTrendCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: Double
    let unit: String
    let deviationStatus: DeviationStatus?
    let metricType: MetricType
    let trendData: [TrendDataPoint]?
    let baseline: PersonalBaseline?
    let recoveryMetrics: RecoveryMetrics?
    let activityData: DailyActivityData?
    let caloriesBreakdown: [CaloriesBreakdownPoint]?

    @State private var showingDetail = false

    init(
        icon: String,
        iconColor: Color,
        title: String,
        value: Double,
        unit: String = "",
        deviationStatus: DeviationStatus? = nil,
        metricType: MetricType = .hrv,
        trendData: [TrendDataPoint]? = nil,
        baseline: PersonalBaseline? = nil,
        recoveryMetrics: RecoveryMetrics? = nil,
        activityData: DailyActivityData? = nil,
        caloriesBreakdown: [CaloriesBreakdownPoint]? = nil
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.value = value
        self.unit = unit
        self.deviationStatus = deviationStatus
        self.metricType = metricType
        self.trendData = trendData
        self.baseline = baseline
        self.recoveryMetrics = recoveryMetrics
        self.activityData = activityData
        self.caloriesBreakdown = caloriesBreakdown
    }

    var body: some View {
        Button {
            showingDetail = true
        } label: {
            HStack(spacing: Spacing.md) {
                // Left side: Icon, Title, Value, Status
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    // Header with icon and title
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: icon)
                            .font(IRFont.body)
                            .foregroundStyle(iconColor.opacity(0.8))

                        Text(title)
                            .font(IRFont.body)
                            .foregroundStyle(Color.irTextSecondary)
                    }

                    // Value with unit
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
                        Text(String(format: "%.1f", value))
                            .font(IRFont.numMD)
                            .foregroundStyle(Color.irTextPrimary)

                        if !unit.isEmpty {
                            Text(unit)
                                .font(IRFont.body)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.irTextSecondary)
                        }
                    }

                    // Deviation status indicator
                    if let status = deviationStatus {
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: status.icon)
                                .font(IRFont.caption)
                                .foregroundStyle(status.color)

                            Text(status.localizedDescription(for: metricType))
                                .font(IRFont.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(status.color)
                        }
                    }
                }

                Spacer()

                // Right side: Mini trend chart
                if let data = trendData, !data.isEmpty {
                    MiniTrendChart(data: data, accentColor: deviationStatus?.color ?? iconColor)
                        .frame(width: 100, height: 45)
                }

                // Arrow indicator for navigation
                Image(systemName: "chevron.right")
                    .font(IRFont.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.irTextSecondary.opacity(0.4))
            }
            .padding(Spacing.base)
            .background(Color.irCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingDetail) {
            ScoreExplanationSheet(
                metricType: metricType,
                currentValue: value,
                unit: unit,
                deviationStatus: deviationStatus,
                baseline: baseline,
                trendData: trendData,
                recoveryMetrics: recoveryMetrics,
                activityData: activityData,
                caloriesBreakdown: caloriesBreakdown
            )
        }
    }
}

// MARK: - Mini Trend Chart

struct MiniTrendChart: View {
    let data: [TrendDataPoint]
    let accentColor: Color

    var body: some View {
        Chart {
            // Area gradient fill
            ForEach(data) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [accentColor.opacity(0.3), accentColor.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }

            // Line on top
            ForEach(data) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(accentColor)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }

            // Current value point (last data point)
            if let lastPoint = data.last {
                PointMark(
                    x: .value("Date", lastPoint.date),
                    y: .value("Value", lastPoint.value)
                )
                .foregroundStyle(accentColor)
                .symbolSize(30)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }
}

// MARK: - Circular Progress View

struct CircularProgressView: View {
    let progress: Double // 0 to 1
    let score: Int
    let lineWidth: CGFloat
    let size: CGFloat

    init(score: Int, size: CGFloat = 180, lineWidth: CGFloat = 12) {
        self.score = score
        self.progress = Double(score) / 100.0
        self.size = size
        self.lineWidth = lineWidth
    }

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color.irTextTertiary.opacity(0.5), lineWidth: lineWidth)

            // Progress arc
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: gradientColors),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 1), value: progress)

            // Score text
            VStack(spacing: Spacing.xxs) {
                Text("\(score)")
                    .font(IRFont.numeric(size: size * 0.28, weight: .bold))
                    .foregroundStyle(Color.irTextPrimary)

                Text("%")
                    .font(IRFont.text(size: size * 0.1, weight: .medium))
                    .foregroundStyle(Color.irTextSecondary)

                Text(String(localized: "Recovered", comment: "Recovery score label"))
                    .font(IRFont.text(size: size * 0.08))
                    .foregroundStyle(Color.irTextSecondary)
            }
        }
        .frame(width: size, height: size)
    }

    private var gradientColors: [Color] {
        switch score {
        case 80...100:
            return [Color.irSuccess.opacity(0.7), Color.irSuccess]
        case 60..<80:
            return [Color.irWarning.opacity(0.7), Color.irWarning]
        case 40..<60:
            return [Color.irWarning.opacity(0.7), Color.irWarning]
        default:
            return [Color.irError.opacity(0.7), Color.irError]
        }
    }
}

// MARK: - Preview

#Preview {
    let sampleTrendData = (0..<7).map { day in
        TrendDataPoint(
            date: Calendar.current.date(byAdding: .day, value: -6 + day, to: Date())!,
            value: Double.random(in: 50...80)
        )
    }

    return ScrollView {
        VStack(spacing: Spacing.base) {
            CircularProgressView(score: 65)
                .padding()

            MetricTrendCard(
                icon: "waveform.path.ecg",
                iconColor: Color.irPrimaryAccent,
                title: "HRV at rest",
                value: 76.2,
                unit: "ms",
                deviationStatus: .normal,
                metricType: .hrv,
                trendData: sampleTrendData
            )

            MetricTrendCard(
                icon: "heart.fill",
                iconColor: Color.irError,
                title: "Resting HR",
                value: 64.9,
                unit: "bpm",
                deviationStatus: .aboveNormal,
                metricType: .restingHeartRate,
                trendData: sampleTrendData
            )

            MetricTrendCard(
                icon: "lungs.fill",
                iconColor: Color.irPrimaryAccent,
                title: "Respiratory rate",
                value: 14.5,
                unit: "rpm",
                deviationStatus: .normal,
                metricType: .respiratoryRate,
                trendData: sampleTrendData
            )

            MetricTrendCard(
                icon: "drop.fill",
                iconColor: Color.irPrimaryAccent,
                title: "Oxygen saturation",
                value: 97.4,
                unit: "%",
                deviationStatus: .excellent,
                metricType: .oxygenSaturation,
                trendData: sampleTrendData
            )
        }
        .padding()
    }
    .background(Color.irBackgroundApp)
}
