//
//  TrendDataPoint.swift
//  InsightRun
//

import SwiftUI

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
