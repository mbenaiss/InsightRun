import { Hono } from 'hono'
import { z } from 'zod'
import { RequestType, selectModelFromRequest } from '../modelRouter'
import { callOpenRouterWithRetry } from '../openrouter'
import type {
  CardiacLoadData,
  DailyActivityData,
  PersonalBaselineData,
  RecoveryData,
} from '../types'
import { formatPace, getLanguageName, READINESS_BANDS } from '../utils'

type Bindings = {
  OPENROUTER_API_KEY: string
  APP_SECRET: string
  RATE_LIMITER: KVNamespace
}

interface ReadinessWorkoutData {
  date: string
  distanceMeters: number
  durationSeconds: number
  avgHeartRate?: number
  maxHeartRate?: number
  pace?: number // min/km
  hoursAgo: number
}

interface DailyReadinessRequest {
  recovery: RecoveryData
  baseline?: PersonalBaselineData
  dailyActivity?: DailyActivityData
  cardiacLoad?: CardiacLoadData
  recentWorkouts?: ReadinessWorkoutData[]
  language: string
  /**
   * Morning score the client already computed today. When provided, the backend
   * returns it as-is and skips score recomputation/effort penalties — the
   * readiness score is product-defined as stable for the calendar day, only the
   * AI coaching text refreshes as the day's context evolves.
   */
  cachedScore?: number
  /** Accepted for older clients; response status is derived from the score. */
  cachedStatus?: string
  /**
   * Set by the iOS client when fewer than 3 nights of sleep have been tracked over
   * the last 14 days. The backend uses it to omit sleep from the AI prompt and
   * tag the response so the UI can swap to a sleep-independent presentation.
   * Defaults to false/undefined for users who track sleep.
   */
  noSleepMode?: boolean
}

const READINESS_STATUSES = ['excellent', 'good', 'fair', 'poor'] as const
type ReadinessStatus = (typeof READINESS_STATUSES)[number]

interface ReadinessResponse {
  score: number // 0-100
  status: ReadinessStatus
  /**
   * Legacy field — kept populated with the full coaching text for
   * backward compatibility with older app builds that only know this key.
   * New clients should prefer `summary` + `detail`.
   */
  recommendation: string
  /** One-sentence TL;DR shown collapsed in the dashboard coach card. */
  summary?: string
  /** Full multi-sentence explanation revealed when the user expands the card. */
  detail?: string
  suggestedWorkoutType: 'intense' | 'moderate' | 'easy' | 'rest'
  insights: ReadinessInsight[]
  coachingSource: 'ai' | 'fallback'
}

interface ReadinessInsight {
  metric: string
  value: number
  comparison: 'above' | 'at' | 'below'
  deviation?: number // percentage from baseline
  message: string
}

const app = new Hono<{ Bindings: Bindings }>()

// Metric-specific coefficients of variation for fallback stdDev calculation
// Based on typical physiological variability (aligned with iOS RecoveryMetrics.swift)
const MetricCV = {
  hrv: 0.3, // HRV: 20-40% CV, use 30%
  restingHR: 0.08, // RHR: 5-10% CV, use 8%
  respiratoryRate: 0.12, // Resp: 10-15% CV, use 12%
} as const

// Recovery weights aligned with iOS RecoveryMetrics.swift
// Sources: Plews et al. (Sports Medicine, 2013), Buchheit (IJSPP, 2014),
// Hirshkowitz et al. (Sleep Health, 2015), Bouzat et al. (BJSM, 2018)
const RecoveryWeights = {
  hrv: 0.25, // 25% - Primary recovery indicator (higher is better)
  restingHeartRate: 0.15, // 15% - Cardiovascular stress indicator (lower is better)
  oxygenSaturation: 0.1, // 10% - Oxygen saturation (higher is better, clinical thresholds)
  respiratoryRate: 0.1, // 10% - Stress indicator (lower is better)
  sleep: 0.4, // 40% - Sleep quality (duration + efficiency + stages)
} as const

const RecoveryCaps = {
  criticalSleepHours: 5,
  severeSleepHours: 6,
  criticalLowHRV: 30,
  maxScoreCriticalSleep: 32,
  // Combo alert (low HRV + short sleep) is more restrictive than either alone
  maxScoreComboAlert: 30,
} as const

// Thresholds for detecting hard efforts in recent workouts
// Two tiers: race-level efforts need longer recovery than standard hard efforts
const EffortThresholds = {
  hard: {
    distanceKm: 25,
    durationHours: 2.5,
    avgHeartRate: 170,
    recencyHours: 48,
    scorePenalty: 10,
  },
  race: {
    distanceKm: 35, // marathon-distance efforts
    durationHours: 3.5,
    recencyHours: 168, // 7 days recovery window
    maxPenalty: 15,
    minPenalty: 5, // degressive: penalty decreases as time passes
  },
} as const

// Convert z-score deviation to a 0-1 score (aligned with iOS scoreFromDeviation)
// Maps [-2, +2] stddev range to [0, 1]
// Note: iOS also supports isHigherBetter: nil (symmetric mode where any deviation is bad),
// but it's not currently used in the backend scoring path.
function scoreFromDeviation(
  value: number,
  average: number | undefined,
  stdDev: number | undefined,
  isHigherBetter: boolean,
  defaultCV: number
): number {
  if (average === undefined) return 0.5 // No baseline, neutral

  const std = stdDev && stdDev > 0 ? stdDev : average * defaultCV
  if (std <= 0) return 0.5

  const zScore = (value - average) / std
  const clampedZ = Math.max(-3, Math.min(3, zScore))

  if (isHigherBetter) {
    // Higher is better: +2 stddev = 1.0, baseline = 0.5, -2 stddev = 0.0
    return Math.min(Math.max((clampedZ + 2) / 4, 0), 1)
  } else {
    // Lower is better: -2 stddev = 1.0, baseline = 0.5, +2 stddev = 0.0
    return Math.min(Math.max((2 - clampedZ) / 4, 0), 1)
  }
}

// SpO2 scoring with clinical thresholds (aligned with iOS scoreSpO2)
// Source: WHO pulse oximetry guidelines, clinical consensus
function scoreSpO2(spo2: number): number {
  if (spo2 >= 98) return 1.0
  if (spo2 >= 96) return 0.9
  if (spo2 >= 95) return 0.75
  if (spo2 >= 93) return 0.5
  if (spo2 >= 90) return 0.25
  return 0.0
}

function normalizeSleepData(
  sleep: NonNullable<RecoveryData['sleepData']>
): RecoveryData['sleepData'] {
  if (sleep.totalDuration === 0) return undefined
  // Older clients can send phases that overlap across HealthKit sources.
  if ((sleep.deepDuration ?? 0) + (sleep.remDuration ?? 0) > sleep.totalDuration + 0.001) {
    return { totalDuration: sleep.totalDuration, efficiency: sleep.efficiency }
  }
  return sleep
}

// Calculate readiness score based on recovery metrics and personal baseline
// Aligned with iOS RecoveryMetrics.calculateRecoveryScore()
// Uses z-score deviation from personal baseline when available (Whoop/Oura style)
// Scientific basis: Plews et al. (2013), Buchheit (2014), Flatt & Esco (2016)
export function calculateReadinessScore(
  recovery: RecoveryData,
  baseline?: PersonalBaselineData,
  noSleepMode?: boolean
): { score: number; insights: ReadinessInsight[] } {
  if (recovery.sleepData) {
    recovery = { ...recovery, sleepData: normalizeSleepData(recovery.sleepData) }
  }
  const insights: ReadinessInsight[] = []
  const useBaseline = baseline?.isReliable === true
  let totalScore = 0
  let totalWeight = 0

  // HRV Score (25% weight) - Higher is better
  // Source: Frontiers in Sports and Active Living (2025), PMC (2024)
  if (recovery.hrv !== undefined) {
    const weight = RecoveryWeights.hrv
    let hrvRawScore: number

    if (useBaseline && baseline?.hrvAverage) {
      hrvRawScore = scoreFromDeviation(
        recovery.hrv,
        baseline.hrvAverage,
        baseline.hrvStdDev,
        true,
        MetricCV.hrv
      )

      const deviation = ((recovery.hrv - baseline.hrvAverage) / baseline.hrvAverage) * 100
      insights.push({
        metric: 'HRV',
        value: recovery.hrv,
        comparison: deviation > 5 ? 'above' : deviation < -5 ? 'below' : 'at',
        deviation: Math.round(deviation),
        message:
          deviation > 10
            ? 'Your HRV is significantly above your baseline - excellent recovery!'
            : deviation < -10
              ? 'Your HRV is below your baseline - consider easier training today'
              : 'Your HRV is within your normal range',
      })
    } else {
      // Fixed range scoring: 20-100ms range (PMC, 2024)
      hrvRawScore = Math.min(Math.max((recovery.hrv - 20) / 80, 0), 1)

      insights.push({
        metric: 'HRV',
        value: recovery.hrv,
        comparison: recovery.hrv >= 40 ? 'above' : recovery.hrv >= 25 ? 'at' : 'below',
        message:
          recovery.hrv >= 50
            ? 'Excellent HRV indicating good recovery'
            : recovery.hrv >= 35
              ? 'Good HRV level'
              : 'HRV is on the lower side - consider rest',
      })
    }

    totalScore += hrvRawScore * weight
    totalWeight += weight
  }

  // Resting Heart Rate Score (15% weight) - Lower is better
  // Source: PubMed (2018), Jensen et al. (Heart, 2013)
  if (recovery.restingHeartRate !== undefined) {
    const weight = RecoveryWeights.restingHeartRate
    let rhrRawScore: number

    if (useBaseline && baseline?.restingHeartRateAverage) {
      rhrRawScore = scoreFromDeviation(
        recovery.restingHeartRate,
        baseline.restingHeartRateAverage,
        baseline.restingHeartRateStdDev,
        false,
        MetricCV.restingHR
      )

      const deviation =
        ((recovery.restingHeartRate - baseline.restingHeartRateAverage) /
          baseline.restingHeartRateAverage) *
        100
      insights.push({
        metric: 'Resting Heart Rate',
        value: recovery.restingHeartRate,
        comparison: deviation < -5 ? 'below' : deviation > 5 ? 'above' : 'at',
        deviation: Math.round(deviation),
        message:
          deviation < -5
            ? 'Your resting HR is lower than usual - great recovery sign'
            : deviation > 10
              ? 'Elevated resting HR - your body may need more rest'
              : 'Resting HR is within your normal range',
      })
    } else {
      // Fixed range scoring: 40-80 bpm range
      rhrRawScore = Math.min(Math.max((80 - recovery.restingHeartRate) / 40, 0), 1)

      insights.push({
        metric: 'Resting Heart Rate',
        value: recovery.restingHeartRate,
        comparison:
          recovery.restingHeartRate <= 55
            ? 'below'
            : recovery.restingHeartRate <= 65
              ? 'at'
              : 'above',
        message:
          recovery.restingHeartRate <= 55
            ? 'Excellent resting heart rate'
            : recovery.restingHeartRate <= 65
              ? 'Good resting heart rate'
              : 'Elevated resting heart rate',
      })
    }

    totalScore += rhrRawScore * weight
    totalWeight += weight
  }

  // SpO2 Score (10% weight) - Clinical thresholds
  // Source: WHO pulse oximetry guidelines, Bouzat et al. (BJSM, 2018)
  if (recovery.oxygenSaturation !== undefined) {
    const weight = RecoveryWeights.oxygenSaturation
    const spo2RawScore = scoreSpO2(recovery.oxygenSaturation)

    insights.push({
      metric: 'Oxygen Saturation',
      value: recovery.oxygenSaturation,
      comparison:
        recovery.oxygenSaturation >= 96
          ? 'above'
          : recovery.oxygenSaturation >= 95
            ? 'at'
            : 'below',
      message:
        recovery.oxygenSaturation >= 96
          ? 'Excellent oxygen saturation'
          : recovery.oxygenSaturation >= 95
            ? 'Normal oxygen saturation'
            : 'Oxygen saturation is below optimal range',
    })

    totalScore += spo2RawScore * weight
    totalWeight += weight
  }

  // Sleep Score (40% weight)
  // Source: Hirshkowitz et al. (Sleep Health, 2015), Sleep Foundation (2024)
  // Skip when the client signals no-sleep mode: a single tracked night out of 14
  // would otherwise dominate the score for someone who doesn't track sleep.
  if (recovery.sleepData && !noSleepMode) {
    const weight = RecoveryWeights.sleep
    const hours = recovery.sleepData.totalDuration / 3600
    const efficiency = recovery.sleepData.efficiency

    let sleepRawScore: number

    if (useBaseline) {
      // Baseline-aware path (aligned with iOS scoreSleepVsBaseline + scoreSleepStages)

      // Duration score
      let durationScore: number
      if (hours >= 7 && hours <= 9) {
        durationScore = 0.9 + 0.1 * Math.min(hours / 8, 1)
      } else if (hours >= 6 && hours < 7) {
        durationScore = 0.6
      } else if (hours >= 5 && hours < 6) {
        durationScore = 0.3
      } else if (hours < 5) {
        durationScore = Math.max(0, hours / 10)
      } else {
        durationScore = 0.7 // Oversleep (>9h)
      }

      // Efficiency score: use baseline deviation when available (aligned with iOS)
      let efficiencyScore: number
      if (baseline?.sleepEfficiencyAverage !== undefined) {
        // stdDev 5.0 = typical population standard deviation for sleep efficiency (%)
        efficiencyScore = scoreFromDeviation(
          efficiency,
          baseline.sleepEfficiencyAverage,
          5.0,
          true,
          0.1
        )
      } else {
        efficiencyScore = Math.min(Math.max((efficiency - 75) / 20, 0), 1)
      }

      // Duration + efficiency: averaged 50/50 (aligned with iOS scoreSleepVsBaseline)
      const durationEfficiencyScore = (durationScore + efficiencyScore) / 2

      let stagesScore = 0.5
      if (
        recovery.sleepData.deepDuration !== undefined &&
        recovery.sleepData.remDuration !== undefined
      ) {
        const totalSleep = recovery.sleepData.totalDuration
        const deepPct = (recovery.sleepData.deepDuration / totalSleep) * 100
        const remPct = (recovery.sleepData.remDuration / totalSleep) * 100
        const deepScore =
          baseline?.deepSleepPercentageAverage !== undefined
            ? scoreFromDeviation(deepPct, baseline.deepSleepPercentageAverage, 5, true, 0.1)
            : deepPct >= 15 && deepPct <= 20
              ? 1
              : deepPct >= 13 && deepPct <= 25
                ? 0.7
                : 0.3
        const remScore =
          baseline?.remSleepPercentageAverage !== undefined
            ? scoreFromDeviation(remPct, baseline.remSleepPercentageAverage, 5, true, 0.1)
            : remPct >= 20 && remPct <= 25
              ? 1
              : remPct >= 18 && remPct <= 28
                ? 0.7
                : 0.3
        stagesScore = (deepScore + remScore) / 2
      }
      sleepRawScore = durationEfficiencyScore * 0.6 + stagesScore * 0.4
    } else {
      // Fixed-range path (aligned with iOS calculateSleepScore)
      let durationScore: number
      if (hours < 5) {
        durationScore = 0.0
      } else if (hours <= 9) {
        durationScore = (hours - 5) / 4
      } else if (hours <= 10) {
        durationScore = 1.0
      } else {
        durationScore = Math.max(0.7, 1.0 - (hours - 10) * 0.1)
      }

      const efficiencyScore = Math.min(Math.max((efficiency / 100 - 0.75) / 0.2, 0), 1)

      // 70% duration, 30% efficiency (aligned with iOS calculateSleepScore)
      sleepRawScore = durationScore * 0.7 + efficiencyScore * 0.3
    }

    insights.push({
      metric: 'Sleep',
      value: hours,
      comparison: hours >= 7 && hours <= 9 ? 'at' : hours < 7 ? 'below' : 'above',
      message:
        hours >= 7 && hours <= 9
          ? `Great sleep duration (${hours.toFixed(1)}h) with ${efficiency}% efficiency`
          : hours < 6
            ? `Short sleep (${hours.toFixed(1)}h) - aim for 7-9 hours`
            : `Sleep duration: ${hours.toFixed(1)}h with ${efficiency}% efficiency`,
    })

    totalScore += sleepRawScore * weight
    totalWeight += weight
  }

  // Respiratory Rate Score (10% weight) - Lower is better
  // Source: Johns Hopkins Medicine (2024), British Journal of Nursing (2017)
  if (recovery.respiratoryRate !== undefined) {
    const weight = RecoveryWeights.respiratoryRate
    let rrRawScore: number

    if (useBaseline && baseline?.respiratoryRateAverage) {
      rrRawScore = scoreFromDeviation(
        recovery.respiratoryRate,
        baseline.respiratoryRateAverage,
        baseline.respiratoryRateStdDev,
        false,
        MetricCV.respiratoryRate
      )

      const deviation =
        ((recovery.respiratoryRate - baseline.respiratoryRateAverage) /
          baseline.respiratoryRateAverage) *
        100
      insights.push({
        metric: 'Respiratory Rate',
        value: recovery.respiratoryRate,
        comparison: deviation < -5 ? 'below' : deviation > 5 ? 'above' : 'at',
        deviation: Math.round(deviation),
        message:
          deviation > 10
            ? 'Elevated respiratory rate - possible stress or fatigue'
            : deviation < -5
              ? 'Lower than usual respiratory rate - good recovery sign'
              : 'Respiratory rate is within your normal range',
      })
    } else {
      // Fixed range scoring: 12-16 optimal (Johns Hopkins Medicine, 2024)
      if (recovery.respiratoryRate >= 12 && recovery.respiratoryRate <= 16) {
        rrRawScore = 1.0
      } else if (recovery.respiratoryRate < 12) {
        rrRawScore = Math.min(Math.max((recovery.respiratoryRate - 8) / 4, 0.5), 1)
      } else {
        rrRawScore = Math.min(Math.max((22 - recovery.respiratoryRate) / 6, 0), 1)
      }

      insights.push({
        metric: 'Respiratory Rate',
        value: recovery.respiratoryRate,
        comparison:
          recovery.respiratoryRate <= 14
            ? 'below'
            : recovery.respiratoryRate <= 18
              ? 'at'
              : 'above',
        message:
          recovery.respiratoryRate <= 14
            ? 'Excellent respiratory rate'
            : recovery.respiratoryRate <= 18
              ? 'Normal respiratory rate'
              : 'Elevated respiratory rate',
      })
    }

    totalScore += rrRawScore * weight
    totalWeight += weight
  }

  // Walking Heart Rate - informational insight only (not part of core score)
  if (recovery.walkingHeartRate !== undefined) {
    insights.push({
      metric: 'Walking Heart Rate',
      value: recovery.walkingHeartRate,
      comparison:
        recovery.walkingHeartRate <= 85
          ? 'below'
          : recovery.walkingHeartRate <= 100
            ? 'at'
            : 'above',
      message:
        recovery.walkingHeartRate <= 85
          ? 'Low walking HR indicates good cardiovascular fitness'
          : recovery.walkingHeartRate <= 100
            ? 'Normal walking heart rate'
            : 'Elevated walking HR - may indicate fatigue',
    })
  }

  // Calculate final score (aligned with iOS formula)
  // Normalize by total weight, then map to 0-100 scale
  const rawScore = totalWeight > 0 ? totalScore / totalWeight : 0.5

  // Map raw 0-1 score to 0-100 for both baseline-aware and fixed-range
  const finalScore = rawScore * 100

  let score = Math.max(0, Math.min(100, Math.round(finalScore)))

  // Cap score when critical thresholds are breached (aligned with iOS)
  if (recovery.sleepData && !noSleepMode) {
    const hours = recovery.sleepData.totalDuration / 3600
    if (hours < RecoveryCaps.criticalSleepHours) {
      score = Math.min(score, RecoveryCaps.maxScoreCriticalSleep)
    }
    if (
      recovery.hrv !== undefined &&
      recovery.hrv < RecoveryCaps.criticalLowHRV &&
      hours < RecoveryCaps.severeSleepHours
    ) {
      score = Math.min(score, RecoveryCaps.maxScoreComboAlert)
    }
  }

  return { score, insights }
}

// Determine status from score using the shared READINESS_BANDS (single source of truth
// with the chat coach prompt) so a given score maps to the same band everywhere.
function getStatusFromScore(score: number): ReadinessStatus {
  if (score >= READINESS_BANDS.excellent) return 'excellent'
  if (score >= READINESS_BANDS.good) return 'good'
  if (score >= READINESS_BANDS.fair) return 'fair'
  return 'poor'
}

// Get workout recommendation based on status, cardiac load, and daily activity
function getWorkoutType(
  status: string,
  cardiacLoad?: CardiacLoadData,
  activity?: DailyActivityData,
  recentWorkouts: ReadinessWorkoutData[] = []
): 'intense' | 'moderate' | 'easy' | 'rest' {
  const clStatus = cardiacLoad?.status

  // Cardiac overload → always rest
  if (clStatus === 'overreaching') return 'rest'

  // Already exercised today → rest/easy regardless of recovery
  if ((activity?.exerciseMinutes ?? 0) >= 20 && (activity?.effortScore ?? 0) >= 60) {
    return 'rest'
  }

  if (recentWorkouts.some(isRecentRaceEffort)) return 'rest'
  const recentHardEffort = recentWorkouts.some(isRecentHardEffort)

  // Cardiac load increasing → downgrade by one level
  if (clStatus === 'increasing') {
    switch (status) {
      case 'excellent':
        return recentHardEffort ? 'easy' : 'moderate'
      case 'good':
        return 'easy'
      default:
        return 'rest'
    }
  }

  // Default: based on recovery status
  switch (status) {
    case 'excellent':
      return recentHardEffort ? 'easy' : 'intense'
    case 'good':
      return recentHardEffort ? 'easy' : 'moderate'
    case 'fair':
      return 'easy'
    default:
      return 'rest'
  }
}

function isRecentRaceEffort(workout: ReadinessWorkoutData): boolean {
  return (
    workout.hoursAgo <= EffortThresholds.race.recencyHours &&
    (workout.distanceMeters / 1000 >= EffortThresholds.race.distanceKm ||
      workout.durationSeconds / 3600 >= EffortThresholds.race.durationHours)
  )
}

function isRecentHardEffort(workout: ReadinessWorkoutData): boolean {
  return (
    workout.hoursAgo <= EffortThresholds.hard.recencyHours &&
    (workout.distanceMeters / 1000 >= EffortThresholds.hard.distanceKm ||
      workout.durationSeconds / 3600 >= EffortThresholds.hard.durationHours ||
      (workout.avgHeartRate ?? 0) >= EffortThresholds.hard.avgHeartRate)
  )
}

// Get recommendation text based on status, daily context, and language.
// Priority order: cardiac overload > already exercised today > recovery status > cardiac trend
function getRecommendation(
  status: string,
  language: string,
  activity?: DailyActivityData,
  cardiacLoad?: CardiacLoadData,
  recentWorkouts: ReadinessWorkoutData[] = []
): string {
  const lang = language.toLowerCase().slice(0, 2)
  const isFr = lang === 'fr'

  const alreadyExercised = (activity?.exerciseMinutes ?? 0) >= 20
  const highEffort = (activity?.effortScore ?? 0) >= 60
  const clStatus = cardiacLoad?.status ?? 'unknown'

  // 1. Cardiac overload takes absolute priority — rest regardless of recovery score
  if (clStatus === 'overreaching') {
    return isFr
      ? 'Votre charge cardiaque est en zone de surcharge. Repos complet ou récupération active légère (marche, étirements) pour éviter le surentraînement.'
      : 'Your cardiac load is in the overreaching zone. Take a full rest day or very light active recovery (walking, stretching) to avoid overtraining.'
  }

  if (recentWorkouts.some(isRecentRaceEffort)) {
    return isFr
      ? 'Votre effort long récent demande encore de la récupération. Privilégiez le repos ou une marche légère selon vos sensations, même si le score du matin est bon.'
      : 'Your recent long effort still calls for recovery. Prioritize rest or gentle walking according to how you feel, even if your morning score is good.'
  }
  if (recentWorkouts.some(isRecentHardEffort)) {
    return isFr
      ? 'Votre séance exigeante récente invite à récupérer. Repos ou activité très facile selon vos sensations, sans ajouter d’intensité aujourd’hui.'
      : 'Your recent hard session calls for recovery. Rest or very easy activity according to how you feel, without adding intensity today.'
  }

  // 2. Already exercised today — don't push more, acknowledge the effort
  if (alreadyExercised && highEffort) {
    const activitySuffix = isFr
      ? ` (${Math.round(activity?.exerciseMinutes ?? 0)} min d'exercice, ${Math.round(activity?.steps ?? 0)} pas)`
      : ` (${Math.round(activity?.exerciseMinutes ?? 0)} min exercise, ${Math.round(activity?.steps ?? 0)} steps)`

    if (clStatus === 'increasing') {
      return isFr
        ? `Bonne séance aujourd'hui${activitySuffix}. Votre charge cardiaque est en hausse — prévoyez une journée de récupération demain.`
        : `Good session today${activitySuffix}. Your cardiac load is increasing — plan a recovery day tomorrow.`
    }

    if (status === 'excellent' || status === 'good') {
      return isFr
        ? `Belle séance aujourd'hui${activitySuffix}. Votre récupération était bonne ce matin — laissez votre corps assimiler l'effort.`
        : `Great session today${activitySuffix}. Your morning recovery was solid — let your body absorb the training.`
    }

    return isFr
      ? `Séance effectuée${activitySuffix}. Votre récupération n'était pas optimale — surveillez votre fatigue et reposez-vous bien ce soir.`
      : `Session completed${activitySuffix}. Your recovery wasn't optimal — monitor your fatigue and get good rest tonight.`
  }

  // 3. Cardiac load increasing — temper the recommendation even if recovery is good
  if (clStatus === 'increasing') {
    if (status === 'excellent' || status === 'good') {
      return isFr
        ? "Bonne récupération mais votre charge cardiaque est en hausse. Optez pour une séance facile ou modérée plutôt qu'intense pour éviter la surcharge."
        : 'Good recovery but your cardiac load is rising. Go for an easy or moderate session rather than high-intensity to avoid overloading.'
    }
    return isFr
      ? 'Récupération incomplète et charge cardiaque en hausse. Repos ou sortie très facile recommandé.'
      : 'Incomplete recovery with rising cardiac load. Rest or a very easy session recommended.'
  }

  // 4. Base recommendations by recovery status
  const base: Record<string, Record<string, string>> = {
    excellent: {
      en: "You're fully recovered. Great day for a quality session — intervals, tempo, or a long run.",
      fr: 'Vous êtes bien récupéré. Bonne journée pour une séance de qualité — intervalles, tempo ou sortie longue.',
    },
    good: {
      en: 'Good recovery. A moderate run at steady pace would be ideal today.',
      fr: 'Bonne récupération. Une course modérée à allure régulière serait idéale.',
    },
    fair: {
      en: 'Partial recovery. Keep it easy today — short easy run or cross-training.',
      fr: "Récupération partielle. Restez léger aujourd'hui — course facile courte ou cross-training.",
    },
    poor: {
      en: 'Your body needs rest. Take a recovery day — light stretching, walking, or foam rolling.',
      fr: 'Votre corps a besoin de repos. Journée de récupération — étirements, marche ou foam rolling.',
    },
  }

  let text = base[status]?.[lang] || base[status]?.en || ''

  // 5. Cardiac detraining context — encourage training
  if (clStatus === 'detraining' && (status === 'excellent' || status === 'good')) {
    text += isFr
      ? " Votre charge d'entraînement diminue — bon moment pour relancer."
      : ' Your training load is declining — good time to ramp up.'
  }

  // 6. Low activity context — gentle nudge
  if (
    !alreadyExercised &&
    (activity?.effortScore ?? 0) <= 20 &&
    (status === 'excellent' || status === 'good')
  ) {
    text += isFr
      ? ' Journée calme pour le moment — idéal pour une sortie.'
      : ' Quiet day so far — ideal time for a run.'
  }

  return text
}

const READINESS_MAX_TOKENS = 600
const READINESS_TEMPERATURE = 0.3
const READINESS_TIMEOUT_MS = 12_000
const READINESS_FALLBACK_MODEL = 'google/gemini-2.5-flash-lite'

// Build a structured context string from all available readiness data
function buildReadinessContext(
  score: number,
  status: string,
  recovery: RecoveryData,
  baseline?: PersonalBaselineData,
  activity?: DailyActivityData,
  cardiacLoad?: CardiacLoadData,
  recentWorkouts?: ReadinessWorkoutData[],
  noSleepMode?: boolean
): string {
  let ctx = ''

  ctx += `Recovery Score: ${score}/100 (status: ${status})\n`

  if (noSleepMode) {
    ctx += 'Sleep measurements: NOT AVAILABLE.\n'
  }

  if (recovery.hrv !== undefined) {
    ctx += `HRV: ${Math.round(recovery.hrv)} ms`
    if (baseline?.hrvAverage) {
      ctx += ` (baseline: ${Math.round(baseline.hrvAverage)} ms)`
    }
    ctx += '\n'
  }

  if (recovery.restingHeartRate !== undefined) {
    ctx += `Resting HR: ${Math.round(recovery.restingHeartRate)} bpm`
    if (baseline?.restingHeartRateAverage) {
      ctx += ` (baseline: ${Math.round(baseline.restingHeartRateAverage)} bpm)`
    }
    ctx += '\n'
  }

  if (recovery.sleepData && !noSleepMode) {
    const hours = recovery.sleepData.totalDuration / 3600
    ctx += `Sleep: ${hours.toFixed(1)}h, efficiency ${Math.round(recovery.sleepData.efficiency)}%`
    if (recovery.sleepData.deepDuration && recovery.sleepData.remDuration) {
      const deepH = recovery.sleepData.deepDuration / 3600
      const remH = recovery.sleepData.remDuration / 3600
      ctx += ` (deep: ${deepH.toFixed(1)}h, REM: ${remH.toFixed(1)}h)`
    }
    if (baseline?.sleepDurationAverage) {
      ctx += ` [baseline: ${(baseline.sleepDurationAverage / 3600).toFixed(1)}h]`
    }
    ctx += '\n'
  }

  if (recovery.respiratoryRate !== undefined) {
    ctx += `Respiratory Rate: ${recovery.respiratoryRate.toFixed(1)} breaths/min`
    if (baseline?.respiratoryRateAverage) {
      ctx += ` (baseline: ${baseline.respiratoryRateAverage.toFixed(1)})`
    }
    ctx += '\n'
  }

  if (recovery.oxygenSaturation !== undefined) {
    ctx += `SpO2: ${recovery.oxygenSaturation}%\n`
  }

  if (cardiacLoad) {
    ctx += `Cardiac Load: score ${cardiacLoad.score}/20, trend: ${cardiacLoad.status}\n`
  }

  if (activity) {
    ctx += `Today's Activity: ${Math.round(activity.steps)} steps, ${Math.round(activity.activeCalories)} kcal burned, ${Math.round(activity.exerciseMinutes)} min exercise, effort score ${Math.round(activity.effortScore)}/100\n`
  }

  if (baseline) {
    ctx += `Baseline reliability: ${baseline.isReliable ? 'reliable' : 'building'} (${baseline.dataPointCount} data points)\n`
  }

  if (recentWorkouts && recentWorkouts.length > 0) {
    ctx += `\nRecent Workouts (last ${recentWorkouts.length}):\n`
    for (const w of recentWorkouts) {
      const distKm = (w.distanceMeters / 1000).toFixed(1)
      const durMin = Math.round(w.durationSeconds / 60)
      ctx += `- ${w.date} (${w.hoursAgo.toFixed(0)}h ago): ${distKm} km in ${durMin} min`
      if (w.pace) ctx += `, pace ${formatPace(w.pace)}`
      if (w.avgHeartRate) ctx += `, avg HR ${w.avgHeartRate} bpm`
      if (w.maxHeartRate) ctx += `, max HR ${w.maxHeartRate} bpm`
      ctx += '\n'
    }
  }

  return ctx
}

interface CoachingText {
  summary: string
  detail: string
}

// Split a long recommendation into a one-sentence TL;DR + the rest as detail.
// Used as a fallback when the AI returns plain text instead of structured JSON.
function deriveCoachingText(full: string): CoachingText {
  const trimmed = full.trim()
  // Match end-of-sentence punctuation followed by whitespace + remainder.
  const match = trimmed.match(/^([^.!?]+[.!?])\s+(\S.*)$/s)
  if (match?.[1] && match[2]) {
    return { summary: match[1].trim(), detail: trimmed }
  }
  return { summary: trimmed, detail: trimmed }
}

// Generate an AI-powered coaching recommendation using OpenRouter.
// Returns a structured {summary, detail} pair so clients can show a TL;DR
// upfront and reveal the full explanation on demand.
async function generateAIRecommendation(
  apiKey: string,
  model: string,
  score: number,
  status: string,
  language: string,
  recovery: RecoveryData,
  baseline?: PersonalBaselineData,
  activity?: DailyActivityData,
  cardiacLoad?: CardiacLoadData,
  recentWorkouts?: ReadinessWorkoutData[],
  noSleepMode?: boolean
): Promise<CoachingText> {
  const langName = getLanguageName(language)
  const readinessContext = buildReadinessContext(
    score,
    status,
    recovery,
    baseline,
    activity,
    cardiacLoad,
    recentWorkouts,
    noSleepMode
  )

  const workoutType = getWorkoutType(status, cardiacLoad, activity, recentWorkouts)
  const systemPrompt = `You are a running coach explaining today's measured recovery and training context.
Return only JSON: {"summary":"...","detail":"..."}, in ${langName}.
Summary: one actionable sentence, at most 90 characters. Detail: 2-3 short sentences, at most 80 words. No markdown.
The score and status are supplied by the app: never recalculate them or infer a different status.
Today's training ceiling is ${workoutType}: do not suggest a harder session. Rest allows only rest or gentle recovery activity.
Acknowledge today's completed exercise. Do not prescribe another session after 20 minutes of exercise with effort >=60.
Use at most 2 relevant measured values to explain the advice, prioritizing recent hard/long runs and cardiac load over a good morning score.
Only reference supplied data. Missing measurements are unknown, not zero or normal. A building baseline is not reliable for personal trend claims.
Do not invent a training plan, injury, diagnosis, heart-rate zone, pace target, or exact recovery deadline. Adapt to the runner's sensations.
${noSleepMode ? 'Sleep is unavailable: do not mention sleep or recommend tracking it.' : 'Mention sleep only if sleep measurements are supplied.'}
Use digits for numbers and explicit units. Keep the advice concise and consistent between summary and detail.`

  const userPrompt = `Here is the runner's readiness data for today:\n\n${readinessContext}\n\nReturn the JSON object now.`

  const { content } = await callOpenRouterWithRetry({
    apiKey,
    model,
    fallbackModel: READINESS_FALLBACK_MODEL,
    timeoutMs: READINESS_TIMEOUT_MS,
    networkAttempts: 1,
    title: 'InsightRun Daily Readiness',
    throwOnTruncation: true,
    body: {
      messages: [
        { role: 'system', content: systemPrompt },
        { role: 'user', content: userPrompt },
      ],
      max_tokens: READINESS_MAX_TOKENS,
      temperature: READINESS_TEMPERATURE,
      reasoning: { effort: 'low', exclude: true },
      stream: false,
      response_format: { type: 'json_object' },
    },
  })
  return parseCoachingJSON(content)
}

const coachingSchema = z.object({
  summary: z.string().trim().min(1).max(180),
  detail: z.string().trim().min(1).max(1200),
})

function parseCoachingJSON(content: string): CoachingText {
  const cleaned = content
    .trim()
    .replace(/^```(?:json)?\s*/i, '')
    .replace(/\s*```$/, '')
  return coachingSchema.parse(JSON.parse(cleaned))
}

const measurement = z.number().positive().optional()
const nonnegative = z.number().nonnegative().optional()
const readinessRequestSchema = z.object({
  recovery: z.object({
    restingHeartRate: measurement,
    hrv: measurement,
    walkingHeartRate: measurement,
    respiratoryRate: measurement,
    oxygenSaturation: z.number().positive().max(100).optional(),
    sleepData: z
      .object({
        totalDuration: z.number().nonnegative(),
        efficiency: z.number().min(0).max(100),
        deepDuration: nonnegative,
        remDuration: nonnegative,
      })
      .transform(normalizeSleepData)
      .optional(),
  }),
  baseline: z
    .object({
      restingHeartRateAverage: measurement,
      restingHeartRateStdDev: nonnegative,
      hrvAverage: measurement,
      hrvStdDev: nonnegative,
      respiratoryRateAverage: measurement,
      respiratoryRateStdDev: nonnegative,
      sleepDurationAverage: measurement,
      sleepEfficiencyAverage: z.number().min(0).max(100).optional(),
      deepSleepPercentageAverage: z.number().min(0).max(100).optional(),
      remSleepPercentageAverage: z.number().min(0).max(100).optional(),
      dataPointCount: z.number().int().nonnegative(),
      isReliable: z.boolean(),
    })
    .optional(),
  dailyActivity: z
    .object({
      steps: z.number().nonnegative(),
      activeCalories: z.number().nonnegative(),
      exerciseMinutes: z.number().nonnegative(),
      effortScore: z.number().min(0).max(100),
    })
    .optional(),
  cardiacLoad: z
    .object({
      score: z.number().min(0).max(20),
      status: z.enum(['increasing', 'maintaining', 'decreasing', 'detraining', 'overreaching']),
    })
    .optional(),
  recentWorkouts: z
    .array(
      z.object({
        date: z.string(),
        distanceMeters: z.number().nonnegative(),
        durationSeconds: z.number().nonnegative(),
        avgHeartRate: measurement,
        maxHeartRate: measurement,
        pace: nonnegative,
        hoursAgo: z.number().nonnegative(),
      })
    )
    .optional(),
  language: z.string().default('en'),
  cachedScore: z.number().int().min(0).max(100).optional(),
  cachedStatus: z.string().optional(),
  noSleepMode: z.boolean().optional(),
})

// POST /api/daily-readiness
app.post('/', async (c) => {
  try {
    const parsed = readinessRequestSchema.safeParse(await c.req.json().catch(() => null))
    if (!parsed.success) {
      return c.json({ error: 'Bad Request', message: 'Invalid readiness data' }, 400)
    }
    const body: DailyReadinessRequest = parsed.data
    const recovery = body.recovery
    const hasMeasurements =
      recovery.hrv !== undefined ||
      recovery.restingHeartRate !== undefined ||
      recovery.respiratoryRate !== undefined ||
      recovery.oxygenSaturation !== undefined ||
      (recovery.sleepData !== undefined && !body.noSleepMode)
    if (!hasMeasurements) {
      return c.json(
        { error: 'Insufficient Data', message: 'No recovery measurements available' },
        422
      )
    }

    const language = body.language || 'en'

    // Calculate readiness score. When the client provides a frozen morning score,
    // honor it for the response and downstream coaching context — the product rule
    // is one score per calendar day, only the recommendation may refresh.
    const computed = calculateReadinessScore(
      body.recovery,
      body.baseline,
      body.noSleepMode === true
    )
    const hasFrozenScore = typeof body.cachedScore === 'number'
    let score = body.cachedScore ?? computed.score
    const insights = computed.insights

    // Add daily activity insights
    if (body.dailyActivity) {
      const a = body.dailyActivity
      insights.push({
        metric: 'Daily Activity',
        value: a.effortScore,
        comparison: a.effortScore >= 60 ? 'above' : a.effortScore >= 30 ? 'at' : 'below',
        message: `${Math.round(a.steps)} steps, ${Math.round(a.activeCalories)} kcal, ${Math.round(a.exerciseMinutes)} min exercise`,
      })
    }

    // Add cardiac load insight
    if (body.cardiacLoad) {
      const cl = body.cardiacLoad
      insights.push({
        metric: 'Cardiac Load',
        value: cl.score,
        comparison:
          cl.status === 'maintaining' ? 'at' : cl.status === 'increasing' ? 'above' : 'below',
        message: `Training load is ${cl.status}`,
      })
    }

    // Add recent workouts insight and adjust score for hard efforts
    if (body.recentWorkouts && body.recentWorkouts.length > 0) {
      const mostRecent = body.recentWorkouts[0]
      const distKm = mostRecent.distanceMeters / 1000

      insights.push({
        metric: 'Recent Workout',
        value: distKm,
        comparison: distKm >= 15 ? 'above' : distKm >= 5 ? 'at' : 'below',
        message: `Last workout: ${distKm.toFixed(1)} km, ${Math.round(mostRecent.durationSeconds / 60)} min (${mostRecent.hoursAgo.toFixed(0)}h ago)`,
      })

      // Penalize score based on effort level and recency
      // Race-level efforts (marathon+) have a 7-day recovery window with degressive penalty
      // Standard hard efforts have a 48h window with fixed penalty
      let effortPenalty = 0
      let effortWorkout: ReadinessWorkoutData | undefined

      for (const w of body.recentWorkouts) {
        const km = w.distanceMeters / 1000
        const hours = w.durationSeconds / 3600

        // Check race-level effort first (marathon+): 7-day degressive penalty
        if (
          w.hoursAgo <= EffortThresholds.race.recencyHours &&
          (km >= EffortThresholds.race.distanceKm || hours >= EffortThresholds.race.durationHours)
        ) {
          const recoveryProgress = w.hoursAgo / EffortThresholds.race.recencyHours
          const penalty = Math.round(
            EffortThresholds.race.maxPenalty -
              recoveryProgress *
                (EffortThresholds.race.maxPenalty - EffortThresholds.race.minPenalty)
          )
          if (penalty > effortPenalty) {
            effortPenalty = penalty
            effortWorkout = w
          }
          continue
        }

        // Check standard hard effort: 48h fixed penalty
        if (
          w.hoursAgo <= EffortThresholds.hard.recencyHours &&
          (km >= EffortThresholds.hard.distanceKm ||
            hours >= EffortThresholds.hard.durationHours ||
            (w.avgHeartRate != null && w.avgHeartRate >= EffortThresholds.hard.avgHeartRate))
        ) {
          if (EffortThresholds.hard.scorePenalty > effortPenalty) {
            effortPenalty = EffortThresholds.hard.scorePenalty
            effortWorkout = w
          }
        }
      }

      if (effortWorkout && effortPenalty > 0) {
        // Skip the score penalty when the score is frozen for the day, but still
        // surface the insight so the AI coaching can reference the recent effort.
        if (!hasFrozenScore) {
          score = Math.max(0, score - effortPenalty)
        }
        const km = (effortWorkout.distanceMeters / 1000).toFixed(1)
        const isRace =
          effortWorkout.distanceMeters / 1000 >= EffortThresholds.race.distanceKm ||
          effortWorkout.durationSeconds / 3600 >= EffortThresholds.race.durationHours
        insights.push({
          metric: 'Recent Training Load',
          value: effortWorkout.hoursAgo,
          comparison: 'above',
          message: isRace
            ? `Race effort detected (${km} km, ${effortWorkout.hoursAgo.toFixed(0)}h ago) — full recovery takes 5-7 days, prioritize rest`
            : `Hard workout detected (${km} km, ${effortWorkout.hoursAgo.toFixed(0)}h ago) — your body may need extra recovery time`,
        })
      }
    }

    const status = getStatusFromScore(score)
    const suggestedWorkoutType = getWorkoutType(
      status,
      body.cardiacLoad,
      body.dailyActivity,
      body.recentWorkouts
    )

    // Generate AI recommendation with fallback to static one
    let coachingText: CoachingText
    let coachingSource: 'ai' | 'fallback' = 'ai'
    try {
      const userId = c.req.header('X-User-ID') || c.req.header('CF-Connecting-IP') || 'unknown'
      const { modelId } = await selectModelFromRequest(
        undefined,
        undefined,
        c.env.RATE_LIMITER,
        userId,
        RequestType.SIMPLE
      )

      coachingText = await generateAIRecommendation(
        c.env.OPENROUTER_API_KEY,
        modelId,
        score,
        status,
        language,
        body.recovery,
        body.baseline,
        body.dailyActivity,
        body.cardiacLoad,
        body.recentWorkouts,
        body.noSleepMode === true
      )
    } catch (aiError) {
      coachingSource = 'fallback'
      console.warn('AI recommendation failed, falling back to static:', aiError)
      const staticText = getRecommendation(
        status,
        language,
        body.dailyActivity,
        body.cardiacLoad,
        body.recentWorkouts
      )
      coachingText = deriveCoachingText(staticText)
    }

    const response: ReadinessResponse = {
      score,
      status,
      // Legacy field: keep populated with the long form so older app builds keep working.
      recommendation: coachingText.detail,
      summary: coachingText.summary,
      detail: coachingText.detail,
      suggestedWorkoutType,
      insights,
      coachingSource,
    }

    return c.json(response)
  } catch (error) {
    console.error('Daily readiness endpoint error:', error)
    return c.json(
      {
        error: 'Internal Server Error',
        message: error instanceof Error ? error.message : 'Unknown error',
      },
      500
    )
  }
})

export default app
