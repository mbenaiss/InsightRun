// Type definitions for chat request data

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
  model: string
  language: string // e.g., "fr", "en", "es", "de"
}

export interface HistoricalAnalysisResponse {
  summary: string
  workoutCount: number
  generatedAt: string
}
