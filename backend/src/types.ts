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

// Zod schema for HistoricalAnalysisRequest validation
export const historicalAnalysisRequestSchema = z.object({
  workouts: z.array(workoutDataSchema).min(1).max(500),
  profile: healthProfileDataSchema.optional(),
  language: z.string().min(2).max(5),
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
  model: string
  userQuestion: string
  language: string // e.g., "fr", "en", "es", "de"
  data: ChatDataPayload
}

export interface HistoricalAnalysisRequest {
  workouts: WorkoutData[]
  profile?: HealthProfileData // User health profile for personalized analysis
  language: string // e.g., "fr", "en", "es", "de"
  // Note: model is always 'x-ai/grok-4-fast' on backend (hardcoded for consistency)
}

export interface HistoricalAnalysisResponse {
  summary: string
  workoutCount: number
  tokenCount: number
  generatedAt: string
}
