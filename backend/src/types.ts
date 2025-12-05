// Type definitions for chat request data
import { z } from 'zod'

// Zod schema for WorkoutData validation
export const workoutDataSchema = z.object({
  id: z.string().optional(),
  date: z.string().min(1),
  duration: z.number().positive({ message: 'Duration must be a positive number' }),
  distance: z.number().nonnegative({ message: 'Distance must be non-negative' }),
  calories: z.number().optional(),
  pace: z.number().optional(),
  speed: z.number().optional(),
  heartRate: z
    .object({
      avg: z.number().optional(),
      min: z.number().optional(),
      max: z.number().optional(),
    })
    .optional(),
  minPace: z.number().optional(),
  cadence: z.number().optional(),
  strideLength: z.number().optional(),
  runningPower: z.number().optional(),
  vo2Max: z.number().optional(),
  elevationGain: z.number().optional(),
  groundContactTime: z.number().optional(),
  verticalOscillation: z.number().optional(),
  mobility: z
    .object({
      walkingSteadiness: z.number().optional(),
      walkingAsymmetry: z.number().optional(),
      doubleSupportPercentage: z.number().optional(),
      walkingSpeed: z.number().optional(),
      stairAscentSpeed: z.number().optional(),
      stairDescentSpeed: z.number().optional(),
    })
    .optional(),
  splits: z
    .array(
      z.object({
        kilometer: z.number(),
        pace: z.string(),
        time: z.string(),
      })
    )
    .optional(),
})

// Zod schema for HealthProfileData
export const healthProfileDataSchema = z.object({
  age: z.number().int().min(1).max(120).optional(),
  sex: z.string().optional(),
  bodyMass: z.number().positive().optional(),
  bodyFatPercentage: z.number().min(0).max(100).optional(),
  exerciseTime: z.number().nonnegative().optional(),
  cyclingDistance: z.number().nonnegative().optional(),
  swimmingDistance: z.number().nonnegative().optional(),
})

export interface WorkoutData {
  date: string
  duration: number
  distance: number
  calories?: number
  pace?: number
  speed?: number
  heartRate?: {
    avg?: number
    min?: number
    max?: number
  }
  minPace?: number
  cadence?: number
  strideLength?: number
  runningPower?: number
  vo2Max?: number
  elevationGain?: number
  groundContactTime?: number
  verticalOscillation?: number
  mobility?: {
    walkingSteadiness?: number
    walkingAsymmetry?: number
    doubleSupportPercentage?: number
    walkingSpeed?: number
    stairAscentSpeed?: number
    stairDescentSpeed?: number
  }
  splits?: Array<{
    kilometer: number
    pace: string
    time: string
  }>
}

export interface RecoveryData {
  restingHeartRate?: number
  hrv?: number
  walkingHeartRate?: number
  respiratoryRate?: number
  sleepData?: {
    totalDuration: number
    efficiency: number
    deepDuration?: number
    remDuration?: number
  }
}

export interface HealthProfileData {
  age?: number
  sex?: string
  bodyMass?: number
  bodyFatPercentage?: number
  exerciseTime?: number
  cyclingDistance?: number
  swimmingDistance?: number
}

export interface RecentWorkoutsData {
  workouts: WorkoutData[]
  totalDistance: number
  totalDuration: number
  totalCalories: number
  avgPace: number
  weeklyVolumeChange?: number
  daysSinceLastWorkout?: number
}

export interface ChatDataPayload {
  workout?: WorkoutData
  recovery?: RecoveryData
  profile?: HealthProfileData
  recentWorkouts?: RecentWorkoutsData
  historicalSummary?: string // One-time deep analysis summary
}

export interface ChatRequestV2 {
  promptType: 'workout_coach'
  requestType?: string // Optional: 'SIMPLE', 'MODERATE', 'COMPLEX' - if not provided, backend will classify
  model?: string // Optional: for backward compatibility or manual override
  userQuestion: string
  language: string // e.g., "fr", "en", "es", "de"
  data: ChatDataPayload
}

// Zod schema for BatchAnalysisRequest validation
export const batchAnalysisRequestSchema = z.object({
  workouts: z.array(workoutDataSchema).min(1).max(50),
  batchIndex: z.number().int().min(0),
  language: z.string().min(2).max(5),
  requestType: z.string().optional(), // e.g., 'BATCH_PROCESSING'
  model: z.string().optional(), // Fallback for backward compatibility
})

// Zod schema for ConsolidateRequest validation
export const consolidateRequestSchema = z.object({
  batchSummaries: z.array(z.string().min(1)).min(1).max(20),
  totalWorkouts: z.number().int().min(1),
  profile: healthProfileDataSchema.optional(),
  language: z.string().min(2).max(5),
  requestType: z.string().optional(), // e.g., 'MODERATE'
  model: z.string().optional(), // Fallback for backward compatibility
})

export interface BatchAnalysisRequest {
  workouts: WorkoutData[]
  batchIndex: number
  language: string
  requestType?: string
  model?: string
}

export interface BatchAnalysisResponse {
  batchIndex: number
  partialSummary: string
  workoutCount: number
  tokenCount: number
}

export interface ConsolidateRequest {
  batchSummaries: string[]
  totalWorkouts: number
  profile?: HealthProfileData
  language: string
  requestType?: string
  model?: string
}

export interface ConsolidateResponse {
  summary: string
  workoutCount: number
  tokenCount: number
}
