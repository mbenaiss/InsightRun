//
//  BackendModels.swift
//  InsightRun
//
//  Models for Backend API v2 communication
//

import Foundation

// MARK: - Request Type Enum

/// Semantic request types that map to specific AI models on the backend
/// Backend handles all model selection logic based on this type
enum RequestType: String, Encodable {
    case simple = "SIMPLE"
    case moderate = "MODERATE"
    case complex = "COMPLEX"
    case workoutGeneration = "WORKOUT_GENERATION"
    case batchProcessing = "BATCH_PROCESSING"
    case smartSuggestion = "SMART_SUGGESTION"
    case classification = "CLASSIFICATION"
}

// MARK: - Request Models

struct ChatRequestV2: Encodable {
    let promptType: String
    let requestType: String?
    let model: String?
    let userQuestion: String
    let language: String
    let data: ChatDataPayload
}

struct ChatDataPayload: Encodable {
    let workout: WorkoutData?
    let recovery: RecoveryData?
    let profile: HealthProfileData?
    let baseline: PersonalBaselineData?
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

// MARK: - Daily Activity & Cardiac Load

struct DailyActivityPayload: Encodable {
    let steps: Double
    let activeCalories: Double
    let exerciseMinutes: Double
    let effortScore: Int
}

struct CardiacLoadPayload: Encodable {
    let score: Int
    let status: String
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

// MARK: - Personal Baseline Data

struct PersonalBaselineData: Encodable {
    let restingHeartRateAverage: Double?
    let restingHeartRateStdDev: Double?
    let hrvAverage: Double?
    let hrvStdDev: Double?
    let sleepDurationAverage: Double? // in seconds
    let sleepEfficiencyAverage: Double? // percentage
    let respiratoryRateAverage: Double?
    let respiratoryRateStdDev: Double?
    let dataPointCount: Int
    let isReliable: Bool
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

// MARK: - Agent Chat Request

struct AgentChatRequest: Encodable {
    let userQuestion: String
    let language: String
    let data: ChatDataPayload
    let conversationHistory: [AgentConversationMessage]?
}

struct AgentConversationMessage: Encodable {
    let role: String
    let content: String
}

// MARK: - Batch Analysis

struct BatchAnalysisRequest: Encodable {
    let workouts: [WorkoutData]
    let batchIndex: Int
    let requestType: String?
    let model: String?
    let language: String
}

struct BatchAnalysisResponse: Decodable {
    let batchIndex: Int
    let partialSummary: String
    let workoutCount: Int
    let tokenCount: Int
}

// MARK: - Consolidation (New)

struct ConsolidationRequest: Encodable {
    let batchSummaries: [String]
    let totalWorkouts: Int
    let profile: HealthProfileData?
    let requestType: String?
    let model: String?
    let language: String
}

struct ConsolidationResponse: Decodable {
    let summary: String
    let workoutCount: Int
    let tokenCount: Int
}

// MARK: - Workout Generation

struct WorkoutGenerationRequest: Encodable {
    let userQuestion: String
    let language: String
    let userContext: UserContext?
    let requestType: String?
    let model: String?

    struct UserContext: Encodable {
        let avgPace: Double? // minutes per km
        let vo2Max: Double?
        let recentWorkouts: Int? // count
        let fitnessLevel: String? // "beginner", "intermediate", "advanced"
    }
}

struct WorkoutGenerationResponse: Decodable {
    let workout: GeneratedWorkoutData
    let metadata: GenerationMetadata

    struct GeneratedWorkoutData: Decodable {
        let name: String
        let description: String
        let sport: String
        let steps: [GeneratedWorkoutStep]
        let totalDistance: Double?
        let estimatedDuration: Double?
    }

    struct GeneratedWorkoutStep: Decodable {
        let type: String // "warmup", "work", "recovery", "cooldown", "interval"
        let goal: StepGoal
        let targetPace: String? // Single pace value (e.g., "5:09")
        let targetPaceMin: String? // Minimum pace for range (e.g., "6:52")
        let targetPaceMax: String? // Maximum pace for range (e.g., "7:22")
        let targetHeartRateZone: Int?
        let instructions: String?
    }

    struct StepGoal: Decodable {
        let type: String // "distance", "duration", "open"
        let value: Double // meters for distance, seconds for duration
    }

    struct GenerationMetadata: Decodable {
        let generationTimeMs: Int
        let modelUsed: String
        let attempts: Int
    }
}

// MARK: - Smart Workout Suggestion Response

struct SmartSuggestionResponse: Decodable {
    let suggestion: String
}
