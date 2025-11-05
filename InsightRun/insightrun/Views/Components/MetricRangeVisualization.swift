//
//  MetricRangeVisualization.swift
//  InsightRun
//
//  Component for visualizing metric ranges with colored bars
//

import SwiftUI

// MARK: - Metric Range Model

struct MetricRangeModel {
    let ranges: [RangeSegment]
    let unit: String

    struct RangeSegment: Identifiable {
        let id = UUID()
        let label: String
        let minValue: Double
        let maxValue: Double
        let color: Color

        func contains(_ value: Double) -> Bool {
            return value >= minValue && value <= maxValue
        }
    }

    func getRangeLabel(for value: Double) -> String? {
        return ranges.first { $0.contains(value) }?.label
    }
}

// MARK: - Metric Range Visualization Component

struct MetricRangeVisualization: View {
    let rangeModel: MetricRangeModel
    let currentValue: Double?

    private var totalRange: Double {
        guard let max = rangeModel.ranges.map({ $0.maxValue }).max(),
              let min = rangeModel.ranges.map({ $0.minValue }).min() else {
            return 100
        }
        return max - min
    }

    private var minValue: Double {
        rangeModel.ranges.map({ $0.minValue }).min() ?? 0
    }

    private func rangeDescription(for range: MetricRangeModel.RangeSegment) -> String {
        let format = String(localized: "%@ (from %d to %d %@)", comment: "Range description format: label, min value, max value, unit")
        return String(format: format, range.label, Int(range.minValue), Int(range.maxValue), rangeModel.unit)
    }

    var body: some View {
        VStack(spacing: 8) {
            // Range visualization with bars
            VStack(alignment: .leading, spacing: 6) {
                // Colored bars with indicator
                VStack(spacing: 0) {
                    // Current value indicator (triangle pointing down) with value
                    if let value = currentValue {
                        GeometryReader { geometry in
                            if value >= minValue && value <= (minValue + totalRange) {
                                let position = geometry.size.width * CGFloat((value - minValue) / totalRange)

                                VStack(spacing: 2) {
                                    HStack(spacing: 3) {
                                        Text(String(format: "%.0f", value))
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundStyle(.primary)

                                        Text(String(localized: "current", comment: "Label for current value indicator"))
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(.secondary)
                                    }

                                    Image(systemName: "arrowtriangle.down.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.primary)
                                }
                                .offset(x: position - 25, y: 0)
                            }
                        }
                        .frame(height: 40)
                    }

                    // Colored bars
                    HStack(spacing: 0) {
                        ForEach(rangeModel.ranges) { range in
                            Rectangle()
                                .fill(range.color)
                                .frame(maxWidth: .infinity)
                                .frame(height: 10)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                    // Values below bars
                    HStack(spacing: 0) {
                        ForEach(Array(rangeModel.ranges.enumerated()), id: \.element.id) { index, range in
                            HStack(spacing: 0) {
                                Text("\(Int(range.minValue))")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)

                                if index == rangeModel.ranges.count - 1 {
                                    Spacer()
                                    Text("\(Int(range.maxValue))+")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.secondary)
                                } else {
                                    Spacer()
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.top, 3)
                }
                
                // Current range description
                if let value = currentValue,
                   let currentRange = rangeModel.ranges.first(where: { $0.contains(value) }) {
                    Text(rangeDescription(for: currentRange))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
            }
        }
        .padding(.horizontal, 0)
        .padding(.vertical, 0)
    }
}

// MARK: - Predefined Metric Ranges

struct MetricRanges {

    // VO2 Max (ml/kg/min) - Based on age and fitness level
    // These are general values, ideally should be personalized by age/sex
    static let vo2Max = MetricRangeModel(
        ranges: [
            .init(label: String(localized: "Very Low", comment: "VO2 Max range: Very Low"), minValue: 15, maxValue: 30, color: Color(red: 0.5, green: 0.5, blue: 0.5)),
            .init(label: String(localized: "Low", comment: "VO2 Max range: Low"), minValue: 30, maxValue: 38, color: Color(red: 0.35, green: 0.35, blue: 0.35)),
            .init(label: String(localized: "Average", comment: "VO2 Max range: Average"), minValue: 38, maxValue: 44, color: .blue),
            .init(label: String(localized: "Good", comment: "VO2 Max range: Good"), minValue: 44, maxValue: 52, color: .purple),
            .init(label: String(localized: "Excellent", comment: "VO2 Max range: Excellent"), minValue: 52, maxValue: 70, color: Color(red: 1.0, green: 0.4, blue: 0.8))
        ],
        unit: "ml/kg/min"
    )

    // Cadence (steps per minute)
    // Based on running research showing optimal range 160-180 spm
    static let cadence = MetricRangeModel(
        ranges: [
            .init(label: String(localized: "Low", comment: "Cadence range: Low"), minValue: 120, maxValue: 160, color: .orange),
            .init(label: String(localized: "Good", comment: "Cadence range: Good"), minValue: 160, maxValue: 170, color: .blue),
            .init(label: String(localized: "Optimal", comment: "Cadence range: Optimal"), minValue: 170, maxValue: 180, color: .green),
            .init(label: String(localized: "High", comment: "Cadence range: High"), minValue: 180, maxValue: 200, color: .purple)
        ],
        unit: "spm"
    )

    // Ground Contact Time (milliseconds)
    // Based on running biomechanics research
    static let groundContactTime = MetricRangeModel(
        ranges: [
            .init(label: String(localized: "Excellent", comment: "GCT range: Excellent"), minValue: 150, maxValue: 200, color: .green),
            .init(label: String(localized: "Good", comment: "GCT range: Good"), minValue: 200, maxValue: 220, color: .blue),
            .init(label: String(localized: "Average", comment: "GCT range: Average"), minValue: 220, maxValue: 250, color: .orange),
            .init(label: String(localized: "High", comment: "GCT range: High"), minValue: 250, maxValue: 300, color: .red)
        ],
        unit: "ms"
    )

    // Vertical Oscillation (centimeters)
    // Based on running efficiency research
    static let verticalOscillation = MetricRangeModel(
        ranges: [
            .init(label: String(localized: "Excellent", comment: "VO range: Excellent"), minValue: 4, maxValue: 7, color: .green),
            .init(label: String(localized: "Good", comment: "VO range: Good"), minValue: 7, maxValue: 9, color: .blue),
            .init(label: String(localized: "Average", comment: "VO range: Average"), minValue: 9, maxValue: 11, color: .orange),
            .init(label: String(localized: "High", comment: "VO range: High"), minValue: 11, maxValue: 15, color: .red)
        ],
        unit: "cm"
    )

    // Resting Heart Rate (bpm)
    // Based on cardiovascular fitness research
    static let restingHeartRate = MetricRangeModel(
        ranges: [
            .init(label: String(localized: "Athlete", comment: "RHR range: Athlete"), minValue: 40, maxValue: 60, color: .green),
            .init(label: String(localized: "Excellent", comment: "RHR range: Excellent"), minValue: 60, maxValue: 70, color: .blue),
            .init(label: String(localized: "Good", comment: "RHR range: Good"), minValue: 70, maxValue: 80, color: .cyan),
            .init(label: String(localized: "Average", comment: "RHR range: Average"), minValue: 80, maxValue: 90, color: .orange),
            .init(label: String(localized: "High", comment: "RHR range: High"), minValue: 90, maxValue: 110, color: .red)
        ],
        unit: "bpm"
    )

    // HRV - Heart Rate Variability (milliseconds)
    // Based on RMSSD values from research
    static let hrv = MetricRangeModel(
        ranges: [
            .init(label: String(localized: "Low", comment: "HRV range: Low"), minValue: 10, maxValue: 30, color: .red),
            .init(label: String(localized: "Below Average", comment: "HRV range: Below Average"), minValue: 30, maxValue: 50, color: .orange),
            .init(label: String(localized: "Average", comment: "HRV range: Average"), minValue: 50, maxValue: 80, color: .blue),
            .init(label: String(localized: "Good", comment: "HRV range: Good"), minValue: 80, maxValue: 120, color: .purple),
            .init(label: String(localized: "Excellent", comment: "HRV range: Excellent"), minValue: 120, maxValue: 200, color: .green)
        ],
        unit: "ms"
    )

    // Running Power (watts)
    static let runningPower = MetricRangeModel(
        ranges: [
            .init(label: String(localized: "Low", comment: "Power range: Low"), minValue: 100, maxValue: 200, color: .gray),
            .init(label: String(localized: "Moderate", comment: "Power range: Moderate"), minValue: 200, maxValue: 250, color: .blue),
            .init(label: String(localized: "Good", comment: "Power range: Good"), minValue: 250, maxValue: 300, color: .purple),
            .init(label: String(localized: "High", comment: "Power range: High"), minValue: 300, maxValue: 400, color: .orange)
        ],
        unit: "W"
    )

    // Stride Length (meters)
    static let strideLength = MetricRangeModel(
        ranges: [
            .init(label: String(localized: "Short", comment: "Stride range: Short"), minValue: 0.8, maxValue: 1.1, color: .orange),
            .init(label: String(localized: "Average", comment: "Stride range: Average"), minValue: 1.1, maxValue: 1.4, color: .blue),
            .init(label: String(localized: "Long", comment: "Stride range: Long"), minValue: 1.4, maxValue: 1.8, color: .green)
        ],
        unit: "m"
    )

    // Respiratory Rate (breaths per minute)
    static let respiratoryRate = MetricRangeModel(
        ranges: [
            .init(label: String(localized: "Low", comment: "Respiratory range: Low"), minValue: 8, maxValue: 12, color: .blue),
            .init(label: String(localized: "Normal", comment: "Respiratory range: Normal"), minValue: 12, maxValue: 18, color: .green),
            .init(label: String(localized: "Elevated", comment: "Respiratory range: Elevated"), minValue: 18, maxValue: 25, color: .orange)
        ],
        unit: "/min"
    )

    // Best Pace (seconds per km) - Lower is better
    static let bestPace = MetricRangeModel(
        ranges: [
            .init(label: String(localized: "Elite", comment: "Pace range: Elite"), minValue: 150, maxValue: 210, color: .green),
            .init(label: String(localized: "Advanced", comment: "Pace range: Advanced"), minValue: 210, maxValue: 270, color: .blue),
            .init(label: String(localized: "Intermediate", comment: "Pace range: Intermediate"), minValue: 270, maxValue: 360, color: .orange),
            .init(label: String(localized: "Beginner", comment: "Pace range: Beginner"), minValue: 360, maxValue: 480, color: .gray)
        ],
        unit: "s/km"
    )

    // Max Speed (km/h)
    static let maxSpeed = MetricRangeModel(
        ranges: [
            .init(label: String(localized: "Beginner", comment: "Speed range: Beginner"), minValue: 6, maxValue: 12, color: .gray),
            .init(label: String(localized: "Intermediate", comment: "Speed range: Intermediate"), minValue: 12, maxValue: 16, color: .orange),
            .init(label: String(localized: "Advanced", comment: "Speed range: Advanced"), minValue: 16, maxValue: 20, color: .blue),
            .init(label: String(localized: "Elite", comment: "Speed range: Elite"), minValue: 20, maxValue: 30, color: .green)
        ],
        unit: "km/h"
    )

    // Contact Balance (percentage) - 50% is ideal
    static let contactBalance = MetricRangeModel(
        ranges: [
            .init(label: String(localized: "Poor Left", comment: "Balance range: Poor Left"), minValue: 40, maxValue: 47, color: .red),
            .init(label: String(localized: "Good", comment: "Balance range: Good"), minValue: 47, maxValue: 49, color: .orange),
            .init(label: String(localized: "Ideal", comment: "Balance range: Ideal"), minValue: 49, maxValue: 51, color: .green),
            .init(label: String(localized: "Good", comment: "Balance range: Good"), minValue: 51, maxValue: 53, color: .orange),
            .init(label: String(localized: "Poor Right", comment: "Balance range: Poor Right"), minValue: 53, maxValue: 60, color: .red)
        ],
        unit: "%"
    )

    // Running Efficiency (percentage)
    static let runningEfficiency = MetricRangeModel(
        ranges: [
            .init(label: String(localized: "Low", comment: "Efficiency range: Low"), minValue: 40, maxValue: 60, color: .red),
            .init(label: String(localized: "Average", comment: "Efficiency range: Average"), minValue: 60, maxValue: 75, color: .orange),
            .init(label: String(localized: "Good", comment: "Efficiency range: Good"), minValue: 75, maxValue: 85, color: .blue),
            .init(label: String(localized: "Elite", comment: "Efficiency range: Elite"), minValue: 85, maxValue: 100, color: .green)
        ],
        unit: "%"
    )

    // Walking Steadiness (percentage)
    static let walkingSteadiness = MetricRangeModel(
        ranges: [
            .init(label: String(localized: "Very Low", comment: "Steadiness range: Very Low"), minValue: 0, maxValue: 40, color: .red),
            .init(label: String(localized: "Low", comment: "Steadiness range: Low"), minValue: 40, maxValue: 80, color: .orange),
            .init(label: String(localized: "OK", comment: "Steadiness range: OK"), minValue: 80, maxValue: 100, color: .green)
        ],
        unit: "%"
    )

    // Walking Asymmetry (percentage) - Lower is better
    static let walkingAsymmetry = MetricRangeModel(
        ranges: [
            .init(label: String(localized: "Normal", comment: "Asymmetry range: Normal"), minValue: 0, maxValue: 15, color: .green),
            .init(label: String(localized: "Asymmetric", comment: "Asymmetry range: Asymmetric"), minValue: 15, maxValue: 20, color: .orange),
            .init(label: String(localized: "High", comment: "Asymmetry range: High"), minValue: 20, maxValue: 50, color: .red)
        ],
        unit: "%"
    )

    // Double Support (percentage) - Lower is better for speed
    static let doubleSupport = MetricRangeModel(
        ranges: [
            .init(label: String(localized: "Fast", comment: "Support range: Fast"), minValue: 10, maxValue: 20, color: .green),
            .init(label: String(localized: "Normal", comment: "Support range: Normal"), minValue: 20, maxValue: 25, color: .blue),
            .init(label: String(localized: "Slow", comment: "Support range: Slow"), minValue: 25, maxValue: 30, color: .orange),
            .init(label: String(localized: "Very Slow", comment: "Support range: Very Slow"), minValue: 30, maxValue: 40, color: .gray)
        ],
        unit: "%"
    )

    // Walking Speed (km/h)
    static let walkingSpeed = MetricRangeModel(
        ranges: [
            .init(label: String(localized: "Slow", comment: "Walking speed: Slow"), minValue: 2, maxValue: 4.8, color: .gray),
            .init(label: String(localized: "Average", comment: "Walking speed: Average"), minValue: 4.8, maxValue: 6.4, color: .blue),
            .init(label: String(localized: "Brisk", comment: "Walking speed: Brisk"), minValue: 6.4, maxValue: 8.0, color: .green),
            .init(label: String(localized: "Very Brisk", comment: "Walking speed: Very Brisk"), minValue: 8.0, maxValue: 12, color: .purple)
        ],
        unit: "km/h"
    )

    // Stair Ascent Speed (m/s)
    static let stairAscentSpeed = MetricRangeModel(
        ranges: [
            .init(label: String(localized: "Reduced", comment: "Ascent speed: Reduced"), minValue: 0.2, maxValue: 0.5, color: .red),
            .init(label: String(localized: "Average", comment: "Ascent speed: Average"), minValue: 0.5, maxValue: 0.7, color: .blue),
            .init(label: String(localized: "Good", comment: "Ascent speed: Good"), minValue: 0.7, maxValue: 1.0, color: .green),
            .init(label: String(localized: "Athlete", comment: "Ascent speed: Athlete"), minValue: 1.0, maxValue: 1.5, color: .purple)
        ],
        unit: "m/s"
    )

    // Stair Descent Speed (m/s)
    static let stairDescentSpeed = MetricRangeModel(
        ranges: [
            .init(label: String(localized: "Reduced", comment: "Descent speed: Reduced"), minValue: 0.3, maxValue: 0.6, color: .red),
            .init(label: String(localized: "Average", comment: "Descent speed: Average"), minValue: 0.6, maxValue: 0.8, color: .blue),
            .init(label: String(localized: "Good", comment: "Descent speed: Good"), minValue: 0.8, maxValue: 1.0, color: .green),
            .init(label: String(localized: "Fast", comment: "Descent speed: Fast"), minValue: 1.0, maxValue: 1.5, color: .purple)
        ],
        unit: "m/s"
    )

    // Get range model for a specific metric key
    static func getRangeModel(for key: String) -> MetricRangeModel? {
        switch key {
        case "metric.vo2_max":
            return vo2Max
        case "metric.avg_cadence":
            return cadence
        case "metric.ground_contact_time":
            return groundContactTime
        case "metric.vertical_oscillation":
            return verticalOscillation
        case "metric.running_power":
            return runningPower
        case "metric.stride_length":
            return strideLength
        case "metric.best_pace":
            return bestPace
        case "metric.max_speed":
            return maxSpeed
        case "metric.contact_balance":
            return contactBalance
        case "metric.running_efficiency":
            return runningEfficiency
        case "metric.walking_steadiness":
            return walkingSteadiness
        case "metric.walking_asymmetry":
            return walkingAsymmetry
        case "metric.double_support":
            return doubleSupport
        case "metric.walking_speed":
            return walkingSpeed
        case "metric.stair_ascent_speed":
            return stairAscentSpeed
        case "metric.stair_descent_speed":
            return stairDescentSpeed
        default:
            return nil
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            MetricRangeVisualization(
                rangeModel: MetricRanges.vo2Max,
                currentValue: 43
            )

            MetricRangeVisualization(
                rangeModel: MetricRanges.cadence,
                currentValue: 175
            )

            MetricRangeVisualization(
                rangeModel: MetricRanges.groundContactTime,
                currentValue: 215
            )
        }
        .padding()
    }
}
