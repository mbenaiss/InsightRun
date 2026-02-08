//
//  WidgetSharedData.swift
//  InsightRun
//
//  Shared data models for widget communication via App Group
//  This file must be kept in sync with InsightRunWidgets/Shared/WidgetSharedData.swift
//

import Foundation

enum WidgetDataKeys {
    static let suiteName = "group.com.altcode.insightrun"
    static let readiness = "widget_readiness"
    static let weeklyStats = "widget_weekly_stats"
    static let lastWorkout = "widget_last_workout"
    static let healthVitals = "widget_health_vitals"
    static let sleepQuality = "widget_sleep_quality"
    static let trainingLoad = "widget_training_load"
}

struct WidgetReadinessData: Codable {
    let score: Int
    let status: String // "excellent", "good", "fair", "poor"
    let date: Date
    let hrvValue: Double?
    let rhrValue: Double?
}

struct WidgetWeeklyStatsData: Codable {
    let totalDistance: Double // meters
    let totalRuns: Int
    let averagePace: Double? // min/km
    let totalDuration: TimeInterval
    let totalCalories: Double
    let weekStartDate: Date
}

struct WidgetLastWorkoutData: Codable {
    let date: Date
    let distance: Double // meters
    let duration: TimeInterval
    let averagePace: Double? // min/km
    let averageHeartRate: Double?
    let calories: Double?
    let elevationGain: Double?
}

struct WidgetHealthVitalsData: Codable {
    let date: Date
    let hrv: Double?
    let restingHeartRate: Double?
    let oxygenSaturation: Double?
    let respiratoryRate: Double?
    let walkingHeartRate: Double?
}

struct WidgetSleepQualityData: Codable {
    let date: Date
    let totalSleepHours: Double
    let sleepEfficiency: Double
    let qualityScore: Int
    let deepSleepHours: Double?
    let remSleepHours: Double?
    let sleepStartTime: String // "HH:mm"
    let sleepEndTime: String // "HH:mm"
}

struct WidgetTrainingLoadData: Codable {
    let date: Date
    let weeklyVolumeChange: Double? // percentage
    let daysSinceLastWorkout: Int?
    let status: String // "normal", "overtraining", "inactive"
    let thisWeekDistance: Double // meters
    let lastWeekDistance: Double // meters
}
