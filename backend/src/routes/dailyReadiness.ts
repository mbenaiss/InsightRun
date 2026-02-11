import { Hono } from 'hono'
import type { PersonalBaselineData, RecoveryData } from '../types'

type Bindings = {
  APP_SECRET: string
  RATE_LIMITER: KVNamespace
}

interface DailyReadinessRequest {
  recovery: RecoveryData
  baseline?: PersonalBaselineData
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
  hrv: 0.30, // HRV: 20-40% CV, use 30%
  restingHR: 0.08, // RHR: 5-10% CV, use 8%
  respiratoryRate: 0.12, // Resp: 10-15% CV, use 12%
} as const

// Recovery weights aligned with iOS RecoveryMetrics.swift
// Sources: Plews et al. (Sports Medicine, 2013), Buchheit (IJSPP, 2014),
// Hirshkowitz et al. (Sleep Health, 2015), Bouzat et al. (BJSM, 2018)
const RecoveryWeights = {
  hrv: 0.25, // 25% - Primary recovery indicator (higher is better)
  restingHeartRate: 0.20, // 20% - Cardiovascular stress indicator (lower is better)
  oxygenSaturation: 0.15, // 15% - Oxygen saturation (higher is better, clinical thresholds)
  respiratoryRate: 0.10, // 10% - Stress indicator (lower is better)
  sleep: 0.30, // 30% - Sleep quality (duration + efficiency)
} as const

// Convert z-score deviation to a 0-1 score (aligned with iOS scoreFromDeviation)
// Maps [-2, +2] stddev range to [0, 1]
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

  // Resting Heart Rate Score (20% weight) - Lower is better
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

  // SpO2 Score (15% weight) - Clinical thresholds
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

  // Sleep Score (30% weight)
  // Source: Hirshkowitz et al. (Sleep Health, 2015), Sleep Foundation (2024)
  if (recovery.sleepData) {
    const weight = RecoveryWeights.sleep
    const hours = recovery.sleepData.totalDuration / 3600
    const efficiency = recovery.sleepData.efficiency

    // Duration score (optimal 7-9h per Hirshkowitz et al., 2015)
    let durationScore: number
    if (hours >= 7 && hours <= 9) {
      durationScore = 0.9 + 0.1 * Math.min(hours / 8, 1)
    } else if (hours >= 6 && hours < 7) {
      durationScore = 0.6
    } else if (hours >= 5 && hours < 6) {
      durationScore = 0.3
    } else if (hours < 5) {
      durationScore = 0.1
    } else {
      durationScore = 0.7 // Oversleep (>9h)
    }

    // Efficiency score (85-95% normal, >95% optimal per PMC, 2020)
    const efficiencyScore = Math.min(Math.max((efficiency - 75) / 20, 0), 1)

    // Combined: 70% duration, 30% efficiency (aligned with iOS)
    const sleepRawScore = durationScore * 0.7 + efficiencyScore * 0.3

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
  // Kept for user feedback but excluded from weighted score to match iOS
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
  // Score 0.5 (at baseline) = 70%, perfect deviation = 100%, -2 stddev = 40%
  const rawScore = totalWeight > 0 ? totalScore / totalWeight : 0.5

  let finalScore: number
  if (useBaseline) {
    // Baseline-aware: map 0-1 raw score to 40-100 range (center at 70%)
    finalScore = 40 + rawScore * 60
  } else {
    // Fixed range: map 0-1 raw score to 0-100
    finalScore = rawScore * 100
  }

  return { score: Math.max(0, Math.min(100, Math.round(finalScore))), insights }
}

// Determine status from score (aligned with iOS RecoveryStatus thresholds)
function getStatusFromScore(score: number): 'excellent' | 'good' | 'fair' | 'poor' {
  if (score >= 80) return 'excellent'
  if (score >= 60) return 'good'
  if (score >= 40) return 'fair'
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

// Get recommendation text based on status and language
function getRecommendation(status: string, language: string): string {
  const recommendations: Record<string, Record<string, string>> = {
    excellent: {
      en: "You're fully recovered! Perfect day for high-intensity training like intervals or tempo runs.",
      fr: 'Vous êtes complètement récupéré ! Journée idéale pour un entraînement intense comme des intervalles ou du tempo.',
      es: '¡Estás completamente recuperado! Día perfecto para entrenamiento de alta intensidad como intervalos o tempo.',
      de: 'Du bist vollständig erholt! Perfekter Tag für intensives Training wie Intervalle oder Tempoläufe.',
      it: 'Sei completamente recuperato! Giornata perfetta per allenamento ad alta intensità come intervalli o tempo.',
      pt: 'Você está totalmente recuperado! Dia perfeito para treino de alta intensidade como intervalos ou tempo.',
      nl: 'Je bent volledig hersteld! Perfecte dag voor intensieve training zoals intervallen of temporuns.',
      ja: '完全に回復しています！インターバルやテンポランなどの高強度トレーニングに最適な日です。',
      zh: '您已完全恢复！非常适合进行间歇跑或节奏跑等高强度训练。',
      ko: '완전히 회복되었습니다! 인터벌이나 템포런 같은 고강도 훈련에 완벽한 날입니다.',
      ar: 'أنت متعافٍ تمامًا! يوم مثالي للتدريب عالي الكثافة مثل الفترات أو جري التيمبو.',
    },
    good: {
      en: 'Good recovery. A moderate workout like a steady-state run would be beneficial.',
      fr: 'Bonne récupération. Une séance modérée comme une course à allure régulière serait bénéfique.',
      es: 'Buena recuperación. Un entrenamiento moderado como una carrera a ritmo constante sería beneficioso.',
      de: 'Gute Erholung. Ein moderates Training wie ein gleichmäßiger Lauf wäre vorteilhaft.',
      it: 'Buon recupero. Un allenamento moderato come una corsa a ritmo costante sarebbe benefico.',
      pt: 'Boa recuperação. Um treino moderado como uma corrida em ritmo constante seria benéfico.',
      nl: 'Goed herstel. Een matige training zoals een steady-state run zou gunstig zijn.',
      ja: '良好な回復状態です。ステディランのような中程度のトレーニングが効果的です。',
      zh: '恢复良好。建议进行中等强度训练，如匀速跑。',
      ko: '좋은 회복 상태입니다. 일정한 페이스의 달리기 같은 중강도 운동이 좋겠습니다.',
      ar: 'تعافٍ جيد. تمرين معتدل مثل الجري بوتيرة ثابتة سيكون مفيدًا.',
    },
    fair: {
      en: 'Partial recovery. Consider an easy run or cross-training today.',
      fr: "Récupération partielle. Envisagez une course facile ou du cross-training aujourd'hui.",
      es: 'Recuperación parcial. Considera una carrera fácil o entrenamiento cruzado hoy.',
      de: 'Teilweise erholt. Erwäge einen leichten Lauf oder Cross-Training heute.',
      it: 'Recupero parziale. Considera una corsa facile o cross-training oggi.',
      pt: 'Recuperação parcial. Considere uma corrida leve ou treino cruzado hoje.',
      nl: 'Gedeeltelijk herstel. Overweeg een rustige loop of cross-training vandaag.',
      ja: '部分的な回復です。今日は軽いランニングかクロストレーニングを検討してください。',
      zh: '部分恢复。建议今天进行轻松跑或交叉训练。',
      ko: '부분적으로 회복되었습니다. 오늘은 가벼운 달리기나 크로스트레이닝을 고려하세요.',
      ar: 'تعافٍ جزئي. فكر في جري خفيف أو تدريب متعدد اليوم.',
    },
    poor: {
      en: 'Rest recommended. Your body needs more recovery time. Light stretching or walking is okay.',
      fr: 'Repos recommandé. Votre corps a besoin de plus de récupération. Étirements légers ou marche sont OK.',
      es: 'Se recomienda descanso. Tu cuerpo necesita más tiempo de recuperación. Estiramientos ligeros o caminar está bien.',
      de: 'Ruhe empfohlen. Dein Körper braucht mehr Erholungszeit. Leichtes Dehnen oder Spazierengehen ist okay.',
      it: 'Riposo consigliato. Il tuo corpo ha bisogno di più tempo per recuperare. Stretching leggero o camminata vanno bene.',
      pt: 'Descanso recomendado. Seu corpo precisa de mais tempo de recuperação. Alongamento leve ou caminhada estão OK.',
      nl: 'Rust aanbevolen. Je lichaam heeft meer hersteltijd nodig. Licht stretchen of wandelen is prima.',
      ja: '休息をおすすめします。体にもっと回復時間が必要です。軽いストレッチやウォーキングは問題ありません。',
      zh: '建议休息。您的身体需要更多恢复时间。轻度拉伸或散步是可以的。',
      ko: '휴식을 권장합니다. 몸이 더 많은 회복 시간이 필요합니다. 가벼운 스트레칭이나 걷기는 괜찮습니다.',
      ar: 'يُنصح بالراحة. جسمك يحتاج إلى مزيد من وقت التعافي. تمارين الإطالة الخفيفة أو المشي مقبولان.',
    },
  }

  const lang = language.toLowerCase().slice(0, 2)
  return recommendations[status]?.[lang] || recommendations[status]?.en || ''
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
    const status = getStatusFromScore(score)
    const suggestedWorkoutType = getWorkoutType(status)
    const recommendation = getRecommendation(status, language)

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
