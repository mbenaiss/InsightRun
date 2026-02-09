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

// Calculate readiness score based on recovery metrics and personal baseline
function calculateReadinessScore(
  recovery: RecoveryData,
  baseline?: PersonalBaselineData
): { score: number; insights: ReadinessInsight[] } {
  const insights: ReadinessInsight[] = []
  let totalScore = 0
  let totalWeight = 0

  // HRV Score (25% weight) - Higher is better
  if (recovery.hrv !== undefined) {
    const weight = 0.25
    let hrvScore: number

    if (baseline?.hrvAverage && baseline.isReliable) {
      const deviation = ((recovery.hrv - baseline.hrvAverage) / baseline.hrvAverage) * 100
      const stdDevs = baseline.hrvStdDev
        ? (recovery.hrv - baseline.hrvAverage) / baseline.hrvStdDev
        : 0

      if (stdDevs >= 1) {
        hrvScore = 100
      } else if (stdDevs >= 0) {
        hrvScore = 70 + stdDevs * 30
      } else if (stdDevs >= -1) {
        hrvScore = 50 + (stdDevs + 1) * 20
      } else {
        hrvScore = Math.max(20, 50 + stdDevs * 15)
      }

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
      // Fixed range scoring without baseline
      hrvScore = recovery.hrv >= 50 ? 90 : recovery.hrv >= 35 ? 70 : recovery.hrv >= 20 ? 50 : 30

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

    totalScore += hrvScore * weight
    totalWeight += weight
  }

  // Resting Heart Rate Score (20% weight) - Lower is better
  if (recovery.restingHeartRate !== undefined) {
    const weight = 0.2
    let rhrScore: number

    if (baseline?.restingHeartRateAverage && baseline.isReliable) {
      const deviation =
        ((recovery.restingHeartRate - baseline.restingHeartRateAverage) /
          baseline.restingHeartRateAverage) *
        100
      const stdDevs = baseline.restingHeartRateStdDev
        ? (recovery.restingHeartRate - baseline.restingHeartRateAverage) /
          baseline.restingHeartRateStdDev
        : 0

      // Lower is better, so negative deviation is good
      if (stdDevs <= -1) {
        rhrScore = 100
      } else if (stdDevs <= 0) {
        rhrScore = 70 + (1 - Math.abs(stdDevs)) * 30
      } else if (stdDevs <= 1) {
        rhrScore = 50 + (1 - stdDevs) * 20
      } else {
        rhrScore = Math.max(20, 50 - stdDevs * 15)
      }

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
      // Fixed range scoring
      rhrScore =
        recovery.restingHeartRate <= 50
          ? 95
          : recovery.restingHeartRate <= 60
            ? 80
            : recovery.restingHeartRate <= 70
              ? 60
              : 40

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

    totalScore += rhrScore * weight
    totalWeight += weight
  }

  // Sleep Score (30% weight)
  if (recovery.sleepData) {
    const weight = 0.3
    const hours = recovery.sleepData.totalDuration / 3600
    const efficiency = recovery.sleepData.efficiency

    let sleepScore = 0

    // Duration score (optimal 7-9h)
    if (hours >= 7 && hours <= 9) {
      sleepScore += 50
    } else if (hours >= 6 && hours < 7) {
      sleepScore += 30
    } else if (hours >= 5 && hours < 6) {
      sleepScore += 15
    } else if (hours > 9) {
      sleepScore += 40 // Oversleep
    } else {
      sleepScore += 5 // <5h
    }

    // Efficiency score
    if (efficiency >= 90) {
      sleepScore += 50
    } else if (efficiency >= 85) {
      sleepScore += 40
    } else if (efficiency >= 80) {
      sleepScore += 30
    } else if (efficiency >= 75) {
      sleepScore += 20
    } else {
      sleepScore += 10
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

    totalScore += sleepScore * weight
    totalWeight += weight
  }

  // Respiratory Rate Score (15% weight)
  if (recovery.respiratoryRate !== undefined) {
    const weight = 0.15
    let rrScore: number

    if (baseline?.respiratoryRateAverage && baseline.isReliable) {
      const deviation =
        ((recovery.respiratoryRate - baseline.respiratoryRateAverage) /
          baseline.respiratoryRateAverage) *
        100

      // Lower respiratory rate at rest is generally better
      if (deviation <= -5) {
        rrScore = 90
      } else if (deviation <= 5) {
        rrScore = 75
      } else if (deviation <= 15) {
        rrScore = 55
      } else {
        rrScore = 35
      }

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
      // Fixed range scoring (normal adult: 12-20 breaths/min)
      rrScore =
        recovery.respiratoryRate <= 14
          ? 85
          : recovery.respiratoryRate <= 18
            ? 70
            : recovery.respiratoryRate <= 22
              ? 50
              : 35

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

    totalScore += rrScore * weight
    totalWeight += weight
  }

  // Walking Heart Rate Score (10% weight)
  if (recovery.walkingHeartRate !== undefined) {
    const weight = 0.1
    let whrScore: number

    // Lower walking HR indicates better cardiovascular fitness/recovery
    if (recovery.walkingHeartRate <= 80) {
      whrScore = 90
    } else if (recovery.walkingHeartRate <= 95) {
      whrScore = 75
    } else if (recovery.walkingHeartRate <= 110) {
      whrScore = 55
    } else {
      whrScore = 35
    }

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

    totalScore += whrScore * weight
    totalWeight += weight
  }

  // Calculate final score
  const finalScore = totalWeight > 0 ? Math.round(totalScore / totalWeight) : 50

  return { score: finalScore, insights }
}

// Determine status from score
function getStatusFromScore(score: number): 'excellent' | 'good' | 'fair' | 'poor' {
  if (score >= 80) return 'excellent'
  if (score >= 65) return 'good'
  if (score >= 50) return 'fair'
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
