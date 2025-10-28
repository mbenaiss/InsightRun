//
//  HealthProfile.swift
//  HealthApp
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

    var formattedAge: String {
        guard let age = age else { return "N/A" }
        return "\(age) ans"
    }

    var formattedBodyMass: String {
        guard let mass = bodyMass else { return "N/A" }
        return String(format: "%.1f kg", mass)
    }

    var formattedBodyFat: String {
        guard let fat = bodyFatPercentage else { return "N/A" }
        return String(format: "%.1f%%", fat)
    }

    var formattedLeanMass: String {
        guard let lean = leanBodyMass else { return "N/A" }
        return String(format: "%.1f kg", lean)
    }

    var formattedSpO2: String {
        guard let spo2 = oxygenSaturation else { return "N/A" }
        return String(format: "%.1f%%", spo2)
    }

    var formattedTemperature: String {
        guard let temp = bodyTemperature else { return "N/A" }
        return String(format: "%.1f°C", temp)
    }

    var formattedRespiratoryRate: String {
        guard let rate = respiratoryRate else { return "N/A" }
        return String(format: "%.0f /min", rate)
    }

    var formattedExerciseTime: String {
        guard let time = exerciseTime else { return "N/A" }
        return String(format: "%.0f min", time)
    }

    var formattedStandTime: String {
        guard let time = standTime else { return "N/A" }
        return String(format: "%.0f min", time)
    }

    var formattedCyclingDistance: String {
        guard let distance = cyclingDistance else { return "N/A" }
        let km = distance / 1000.0
        return String(format: "%.1f km", km)
    }

    var formattedSwimmingDistance: String {
        guard let distance = swimmingDistance else { return "N/A" }
        let km = distance / 1000.0
        return String(format: "%.1f km", km)
    }

    var biologicalSexString: String {
        guard let sex = biologicalSex else { return "N/A" }
        switch sex {
        case .female:
            return "Femme"
        case .male:
            return "Homme"
        case .other:
            return "Autre"
        case .notSet:
            return "Non défini"
        @unknown default:
            return "Inconnu"
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
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "d MMM"
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
