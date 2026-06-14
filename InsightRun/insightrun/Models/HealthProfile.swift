//
//  HealthProfile.swift
//  InsightRun
//
//  Model for user's health profile and body metrics
//

import Foundation
import HealthKit

struct HealthProfile: Identifiable {
    let id = UUID()
    let date: Date

    // User Characteristics
    let age: Int?
    let biologicalSex: HKBiologicalSex?

    // Body Metrics
    let bodyMass: Double? // kg
    let bodyMassDate: Date?
    let bodyFatPercentage: Double? // %
    let bodyFatDate: Date?
    let leanBodyMass: Double? // kg
    let leanBodyMassDate: Date?

    // Vital Signs
    let oxygenSaturation: Double? // SpO2 %
    let oxygenSaturationDate: Date?
    let bodyTemperature: Double? // Celsius
    let bodyTemperatureDate: Date?
    let respiratoryRate: Double? // breaths per minute
    let respiratoryRateDate: Date?

    // Activity Metrics (daily)
    let exerciseTime: Double? // minutes
    let standTime: Double? // minutes
    let flightsClimbed: Int?

    // Cross-training
    let cyclingDistance: Double? // meters (last 7 days)
    let swimmingDistance: Double? // meters (last 7 days)

    // Computed properties
    var bmi: Double? {
        guard bodyMass != nil, age != nil else { return nil }
        // BMI calculation would need height, which we'd need to add to permissions
        return nil
    }

    private var notAvailable: String {
        String(localized: "common.notAvailable", defaultValue: "N/A", comment: "Fallback when a metric value is unavailable")
    }

    var formattedAge: String {
        guard let age = age else { return notAvailable }
        return String(localized: "\(age) years", comment: "User age in years")
    }

    var formattedBodyMass: String {
        guard let mass = bodyMass else { return notAvailable }
        return "\(Formatters.decimal(mass, fractionDigits: 1)) kg"
    }

    var formattedBodyFat: String {
        guard let fat = bodyFatPercentage else { return notAvailable }
        return Formatters.percent(fat, fractionDigits: 1)
    }

    var formattedLeanMass: String {
        guard let lean = leanBodyMass else { return notAvailable }
        return "\(Formatters.decimal(lean, fractionDigits: 1)) kg"
    }

    var formattedSpO2: String {
        guard let spo2 = oxygenSaturation else { return notAvailable }
        return Formatters.percent(spo2, fractionDigits: 1)
    }

    var formattedTemperature: String {
        guard let temp = bodyTemperature else { return notAvailable }
        return "\(Formatters.decimal(temp, fractionDigits: 1)) °C"
    }

    var formattedRespiratoryRate: String {
        guard let rate = respiratoryRate else { return notAvailable }
        return "\(Formatters.integer(Int(rate.rounded()))) /min"
    }

    var formattedExerciseTime: String {
        guard let time = exerciseTime else { return notAvailable }
        return "\(Formatters.integer(Int(time.rounded()))) min"
    }

    var formattedStandTime: String {
        guard let time = standTime else { return notAvailable }
        return "\(Formatters.integer(Int(time.rounded()))) min"
    }

    var formattedCyclingDistance: String {
        guard let distance = cyclingDistance else { return notAvailable }
        return Formatters.distance(km: distance / 1000.0, fractionDigits: 1)
    }

    var formattedSwimmingDistance: String {
        guard let distance = swimmingDistance else { return notAvailable }
        return Formatters.distance(km: distance / 1000.0, fractionDigits: 1)
    }

    var biologicalSexString: String {
        guard let sex = biologicalSex else { return notAvailable }
        switch sex {
        case .female:
            return String(localized: "Female", comment: "Biological sex - female")
        case .male:
            return String(localized: "Male", comment: "Biological sex - male")
        case .other:
            return String(localized: "Other", comment: "Biological sex - other")
        case .notSet:
            return String(localized: "Not set", comment: "Biological sex - not set")
        @unknown default:
            return String(localized: "Unknown", comment: "Biological sex - unknown")
        }
    }

    // Helper to format date if it's old (more than 7 days)
    func formattedDate(_ date: Date?) -> String? {
        guard let date = date else { return nil }

        let calendar = Calendar.current
        let daysDifference = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day ?? 0

        // Only show date if older than 7 days
        guard daysDifference > 7 else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter.string(from: date)
    }
}

// Daily Activity Summary
struct DailyActivity: Identifiable {
    let id = UUID()
    let date: Date

    let exerciseTime: Double // minutes
    let standTime: Double // minutes
    let activeCalories: Double // kcal
    let steps: Int
    let flightsClimbed: Int

    var exerciseGoalPercentage: Double {
        // Apple's default goal is 30 minutes
        return min((exerciseTime / 30.0) * 100, 100)
    }

    var standGoalPercentage: Double {
        // Apple's default goal is 12 hours
        let standHours = standTime / 60.0
        return min((standHours / 12.0) * 100, 100)
    }
}

/// Daily activity data for effort score calculation (steps, calories, exercise minutes)
struct DailyActivityData {
    let steps: Double
    let activeCalories: Double
    let basalCalories: Double
    let exerciseMinutes: Double

    // nil → use fixed fallback (Apple Activity Rings goals)
    let activeCaloriesGoal: Double?
    let exerciseMinutesGoal: Double?

    var totalCalories: Double {
        activeCalories + basalCalories
    }
}
