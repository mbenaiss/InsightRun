import { Hono } from 'hono'
import type {
  CardiacLoadData,
  DailyActivityData,
  PersonalBaselineData,
  RecoveryData,
} from '../types'

type Bindings = {
  APP_SECRET: string
  RATE_LIMITER: KVNamespace
}

interface DailyReadinessRequest {
  recovery: RecoveryData
  baseline?: PersonalBaselineData
  dailyActivity?: DailyActivityData
  cardiacLoad?: CardiacLoadData
  language: string
}

interface ReadinessResponse {
  score: number // 0-100
  status: 'excellent' | 'good' | 'fair' | 'poor'
  recommendation: string
  suggestedWorkoutType: 'intense' | 'moderate' | 'easy' | 'rest'
  insights: ReadinessInsight[]
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

// Calculate readiness score based on recovery metrics and personal baseline
// Aligned with iOS RecoveryMetrics.calculateRecoveryScore()
// Uses z-score deviation from personal baseline when available (Whoop/Oura style)
// Scientific basis: Plews et al. (2013), Buchheit (2014), Flatt & Esco (2016)
function calculateReadinessScore(
  recovery: RecoveryData,
  baseline?: PersonalBaselineData
): { score: number; insights: ReadinessInsight[] } {
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
  if (recovery.sleepData) {
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
      if (baseline?.sleepEfficiencyAverage) {
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

      // Sleep stages scoring (deep + REM) - uses fixed ranges because baseline stage
      // percentages are not sent from iOS. Note: iOS scoreSleepStages uses baseline
      // deepSleepPercentageAverage/remSleepPercentageAverage when available.
      if (recovery.sleepData.deepDuration && recovery.sleepData.remDuration) {
        const totalSleep = recovery.sleepData.totalDuration
        const deepPct = (recovery.sleepData.deepDuration / totalSleep) * 100
        const remPct = (recovery.sleepData.remDuration / totalSleep) * 100

        let deepScore: number
        if (deepPct >= 15 && deepPct <= 20) deepScore = 1.0
        else if (deepPct >= 13 && deepPct <= 25) deepScore = 0.7
        else deepScore = 0.3

        let remScore: number
        if (remPct >= 20 && remPct <= 25) remScore = 1.0
        else if (remPct >= 18 && remPct <= 28) remScore = 0.7
        else remScore = 0.3

        const stagesScore = (deepScore + remScore) / 2
        // 60% duration/efficiency, 40% stages (aligned with iOS)
        sleepRawScore = durationEfficiencyScore * 0.6 + stagesScore * 0.4
      } else {
        sleepRawScore = durationEfficiencyScore
      }
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
  if (recovery.sleepData) {
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

// Determine status from score (aligned with iOS RecoveryStatus thresholds)
// Status thresholds adjusted for linear 0-100 scale (baseline day ≈ 50%)
function getStatusFromScore(score: number): 'excellent' | 'good' | 'fair' | 'poor' {
  if (score >= 67) return 'excellent'
  if (score >= 50) return 'good'
  if (score >= 33) return 'fair'
  return 'poor'
}

// Get workout recommendation based on status
function getWorkoutType(status: string): 'intense' | 'moderate' | 'easy' | 'rest' {
  switch (status) {
    case 'excellent':
      return 'intense'
    case 'good':
      return 'moderate'
    case 'fair':
      return 'easy'
    default:
      return 'rest'
  }
}

// Get recommendation text based on status, daily context, and language
function getRecommendation(
  status: string,
  language: string,
  activity?: DailyActivityData,
  cardiacLoad?: CardiacLoadData
): string {
  const lang = language.toLowerCase().slice(0, 2)
  const isFr = lang === 'fr'

  // Base recommendations
  const base: Record<string, Record<string, string>> = {
    excellent: {
      en: "You're fully recovered! Perfect day for high-intensity training like intervals or tempo runs.",
      fr: 'Vous êtes complètement récupéré ! Journée idéale pour un entraînement intense comme des intervalles ou du tempo.',
    },
    good: {
      en: 'Good recovery. A moderate workout like a steady-state run would be beneficial.',
      fr: 'Bonne récupération. Une séance modérée comme une course à allure régulière serait bénéfique.',
    },
    fair: {
      en: 'Partial recovery. Consider an easy run or cross-training today.',
      fr: "Récupération partielle. Envisagez une course facile ou du cross-training aujourd'hui.",
    },
    poor: {
      en: 'Rest recommended. Your body needs more recovery time. Light stretching or walking is okay.',
      fr: 'Repos recommandé. Votre corps a besoin de plus de récupération. Étirements légers ou marche sont OK.',
    },
  }

  let text = base[status]?.[lang] || base[status]?.en || ''

  // Append cardiac load context
  if (cardiacLoad) {
    if (cardiacLoad.status === 'increasing' && (status === 'fair' || status === 'poor')) {
      text += isFr
        ? ' Votre charge cardiaque est en hausse — privilégiez la récupération.'
        : ' Your cardiac load is increasing — prioritize recovery.'
    } else if (
      cardiacLoad.status === 'detraining' &&
      (status === 'excellent' || status === 'good')
    ) {
      text += isFr
        ? " Votre charge cardiaque est en baisse — bon moment pour relancer l'entraînement."
        : ' Your cardiac load is declining — good time to ramp up training.'
    }
  }

  // Append daily activity context
  if (activity) {
    if (activity.effortScore >= 70) {
      text += isFr
        ? ` Journée déjà active (${Math.round(activity.steps)} pas, ${Math.round(activity.exerciseMinutes)} min d'exercice).`
        : ` Already an active day (${Math.round(activity.steps)} steps, ${Math.round(activity.exerciseMinutes)} min exercise).`
    } else if (activity.effortScore <= 20 && (status === 'excellent' || status === 'good')) {
      text += isFr
        ? ' Journée peu active pour le moment — idéal pour bouger.'
        : ' Low activity so far — a great time to get moving.'
    }
  }

  return text
}

// POST /api/daily-readiness
app.post('/', async (c) => {
  try {
    const body = (await c.req.json()) as DailyReadinessRequest

    if (!body.recovery) {
      return c.json({ error: 'Bad Request', message: 'Recovery data is required' }, 400)
    }

    const language = body.language || 'en'

    // Calculate readiness score
    const { score, insights } = calculateReadinessScore(body.recovery, body.baseline)

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

    const status = getStatusFromScore(score)
    const suggestedWorkoutType = getWorkoutType(status)
    const recommendation = getRecommendation(status, language, body.dailyActivity, body.cardiacLoad)

    const response: ReadinessResponse = {
      score,
      status,
      recommendation,
      suggestedWorkoutType,
      insights,
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
