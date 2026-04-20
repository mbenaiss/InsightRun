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
    let trainingPlan: TrainingPlanData?
}

// MARK: - Training Plan Data (sent to AI)

struct TrainingPlanData: Encodable {
    let raceName: String
    let raceType: String
    let raceDistanceKm: Double
    let targetDate: String // ISO-8601 date
    let daysRemaining: Int
    let fitnessLevel: String
    let targetTimeSeconds: Int?
    let preferredDays: [String]
    let injury: String?

    let planName: String
    let planGoal: String
    let planStartDate: String? // ISO-8601
    let totalWeeks: Int
    let currentWeekNumber: Int? // 1-indexed, nil if plan not started
    let currentPhase: String?
    let completedWorkouts: Int
    let totalPlannedWorkouts: Int
    let completionRate: Double
    let lastAdaptationDate: String?
    let adaptationAssessment: String?

    let weeks: [TrainingWeekData]
    let todaySession: PlannedWorkoutData?
}

struct TrainingWeekData: Encodable {
    let weekNumber: Int
    let phase: String
    let volumeKm: Double?
    let notes: String?
    let days: [TrainingDayData]
}

struct TrainingDayData: Encodable {
    let dayOfWeek: String
    let isRestDay: Bool
    let isCompleted: Bool
    let autoMatched: Bool
    let workout: PlannedWorkoutData?
}

struct PlannedWorkoutData: Encodable {
    let name: String
    let type: String
    let intensity: String
    let description: String
    let targetDistanceM: Double?
    let targetDurationS: Double?
    let targetPace: String?
    let steps: [PlannedWorkoutStepData]
}

struct PlannedWorkoutStepData: Encodable {
    let type: String
    let description: String
    let durationS: Double?
    let distanceM: Double?
    let targetPace: String?
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

// MARK: - Training Plan Generation

struct TrainingPlanGenerationRequest: Encodable {
    let raceType: String
    let targetDate: String // ISO 8601
    let startDate: String? // ISO 8601 — user-chosen plan start date
    let fitnessLevel: String
    let currentWeeklyVolumeKm: Double?
    let avgPace: Double?
    let language: String
    let trainingDaysPerWeek: Int?
    let preferredDays: [Int]? // 1=Sunday...7=Saturday
    let injury: String?
    let targetTimeSeconds: Int? // Target finish time in seconds
}

struct TrainingPlanGenerationResponse: Decodable {
    let plan: GeneratedTrainingPlanData
    let metadata: TrainingPlanMetadata

    struct GeneratedTrainingPlanData: Decodable {
        let name: String
        let goal: String
        let weeks: [GeneratedWeekData]
    }

    struct GeneratedWeekData: Decodable {
        let weekNumber: Int
        let phase: String
        let workouts: [GeneratedPlannedWorkoutData]
        let weeklyVolume: Double?
        let notes: String?
    }

    struct GeneratedPlannedWorkoutData: Decodable {
        let type: String
        let name: String
        let description: String
        let targetDuration: Double?
        let targetDistance: Double?
        let targetPace: String?
        let intensity: String
        let steps: [GeneratedStepData]?
    }

    struct GeneratedStepData: Decodable {
        let type: String
        let duration: Double?
        let distance: Double?
        let targetPace: String?
        let description: String
    }

    struct TrainingPlanMetadata: Decodable {
        let generationTimeMs: Int
        let modelUsed: String
        let attempts: Int
        let weeksGenerated: Int
    }
}

// MARK: - Training Plan Adaptation

struct AdaptTrainingPlanRequest: Encodable {
    let raceType: String
    let targetDate: String
    let fitnessLevel: String
    let language: String
    let trainingDaysPerWeek: Int
    let preferredDays: [Int]
    let targetTimeSeconds: Int?
    let injury: String?
    let currentWeekNumber: Int
    let remainingWeeksCount: Int
    let originalPlanName: String
    let originalPlanGoal: String
    let completedWeeks: [CompletedWeekPayload]
}

struct CompletedWeekPayload: Encodable {
    let weekNumber: Int
    let phase: String
    let completionRate: Double
    let workouts: [CompletedWorkoutPayload]
}

struct CompletedWorkoutPayload: Encodable {
    let type: String
    let planned: PlannedWorkoutPayload
    let actual: ActualWorkoutPayload?
}

struct PlannedWorkoutPayload: Encodable {
    let distance: Double?
    let duration: Double?
    let pace: String?
    let intensity: String
}

struct ActualWorkoutPayload: Encodable {
    let distance: Double
    let duration: Double
    let pace: Double?
    let heartRate: Double?
}

struct AdaptTrainingPlanResponse: Decodable {
    let plan: AdaptedPlanData
    let metadata: TrainingPlanGenerationResponse.TrainingPlanMetadata

    struct AdaptedPlanData: Decodable {
        let weeks: [TrainingPlanGenerationResponse.GeneratedWeekData]
        let adaptation: AdaptationAnalysis
    }

    struct AdaptationAnalysis: Decodable {
        let assessment: String
        let adjustments: String
        let goalAchievable: Bool
        let confidenceLevel: String
    }
}
