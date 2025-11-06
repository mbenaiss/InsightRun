//
//  BackendModels.swift
//  InsightRun
//
//  Models for Backend API v2 communication
//

import Foundation

// MARK: - Request Models

struct ChatRequestV2: Encodable {
    let promptType: String
    let model: String
    let userQuestion: String
    let language: String
    let data: ChatDataPayload
}

struct ChatDataPayload: Encodable {
    let workout: WorkoutData?
    let recovery: RecoveryData?
    let profile: HealthProfileData?
    let recentWorkouts: RecentWorkoutsData?
    let historicalSummary: String? // One-time deep analysis summary
}

// MARK: - Workout Data

struct WorkoutData: Encodable {
    let date: String
    let duration: Double
    let distance: Double
    let calories: Double?
    let pace: Double?
    let speed: Double?
    let heartRate: HeartRateData?
    let minPace: Double?
    let cadence: Int?
    let strideLength: Double?
    let runningPower: Int?
    let vo2Max: Double?
    let elevationGain: Double?
    let groundContactTime: Int?
    let verticalOscillation: Double?
    let mobility: MobilityData?
    let splits: [SplitData]?
}

struct HeartRateData: Encodable {
    let avg: Int?
    let min: Int?
    let max: Int?
}

struct MobilityData: Encodable {
    let walkingSteadiness: Double?
    let walkingAsymmetry: Double?
    let doubleSupportPercentage: Double?
    let walkingSpeed: Double?
    let stairAscentSpeed: Double?
    let stairDescentSpeed: Double?
}

struct SplitData: Encodable {
    let kilometer: Int
    let pace: String
    let time: String
}

// MARK: - Recovery Data

struct RecoveryData: Encodable {
    let restingHeartRate: Int?
    let hrv: Int?
    let walkingHeartRate: Int?
    let respiratoryRate: Int?
    let sleepData: SleepDataPayload?
}

struct SleepDataPayload: Encodable {
    let totalDuration: Double
    let efficiency: Int
    let deepDuration: Double?
    let remDuration: Double?
}

// MARK: - Health Profile Data

struct HealthProfileData: Encodable {
    let age: Int?
    let sex: String?
    let bodyMass: Double?
    let bodyFatPercentage: Double?
    let exerciseTime: Int?
    let cyclingDistance: Double?
    let swimmingDistance: Double?
}

// MARK: - Recent Workouts Data

struct RecentWorkoutsData: Encodable {
    let workouts: [WorkoutData]
    let totalDistance: Double
    let totalDuration: Double
    let totalCalories: Double
    let avgPace: Double
    let weeklyVolumeChange: Double?
    let daysSinceLastWorkout: Int?
}

// MARK: - Historical Analysis (One-Time Deep Analysis)

struct HistoricalAnalysisRequest: Encodable {
    let workouts: [WorkoutData]
    let profile: HealthProfileData?
    let model: String
    let language: String
}

struct HistoricalAnalysisResponse: Decodable {
    let summary: String
    let workoutCount: Int
    let generatedAt: String
}
