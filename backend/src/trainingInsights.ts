import { z } from 'zod'
import { wrapUserData } from './utils'

const positive = z.number().positive().optional()
const nonnegative = z.number().nonnegative().optional()
const text = z.string().max(200)
const timestamp = z.string().datetime({ offset: true })
const evidenceData = (value: unknown) =>
  wrapUserData(JSON.stringify(value).replaceAll('<', '\\u003c').replaceAll('>', '\\u003e'))
const phase = z.object({
  index: z.number().int().min(0).max(2),
  startOffsetSeconds: z.number().nonnegative(),
  durationSeconds: z.number().positive(),
  heartRate: positive,
  speed: positive,
  power: positive,
  strideLength: positive,
  groundContactTime: positive,
  verticalOscillation: positive,
})

export const workoutInsightsSchema = z.object({
  effort: z.number().min(1).max(10).optional(),
  effortSource: z.enum(['apple_estimated', 'user_rated']).optional(),
  isIndoor: z.boolean().optional(),
  temperatureCelsius: z.number().min(-80).max(65).optional(),
  humidityPercent: z.number().min(0).max(100).optional(),
  pausedSeconds: nonnegative,
  feedback: z
    .object({
      effort: z.number().int().min(1).max(10).optional(),
      intent: z.enum(['easy', 'long', 'tempo', 'intervals', 'race']).optional(),
      legs: z.enum(['fresh', 'normal', 'heavy', 'sore']).optional(),
      goalAchieved: z.enum(['yes', 'partly', 'no']).optional(),
    })
    .optional(),
  intervals: z
    .array(
      z.object({
        index: z.number().int().nonnegative(),
        type: z.enum(['warmup', 'work', 'recovery', 'cooldown', 'unknown']),
        duration: z.number().positive(),
        distance: nonnegative,
        pace: positive,
        heartRate: positive,
        power: positive,
        targetPaceMin: positive,
        targetPaceMax: positive,
      })
    )
    .max(200)
    .optional(),
  evidence: z
    .object({
      measuredAt: timestamp,
      source: text,
      device: text.optional(),
      softwareVersion: text.optional(),
      zones: z
        .object({
          source: z.enum(['system', 'user', 'app']),
          zones: z
            .array(
              z.object({
                index: z.number().int().min(0).max(8),
                minimum: positive,
                maximum: positive,
                seconds: z.number().nonnegative(),
              })
            )
            .min(3)
            .max(9),
        })
        .optional(),
      signals: z
        .array(
          z.object({
            metric: z.enum([
              'heartRate',
              'speed',
              'power',
              'strideLength',
              'groundContactTime',
              'verticalOscillation',
            ]),
            sampleCount: z.number().int().nonnegative(),
            coverage: z.number().min(0).max(1),
            longestGapSeconds: z.number().nonnegative(),
            sourceCount: z.number().int().nonnegative(),
          })
        )
        .max(6),
      phases: z.array(phase).max(3),
    })
    .optional(),
  execution: z
    .object({
      heartRateChangePercent: z.number().optional(),
      comparisonBasis: z.enum(['speed_within_5_percent', 'power_within_5_percent']).optional(),
      unavailableReason: text.optional(),
      workPaceVariationPercent: nonnegative,
      intervalsWithinTarget: z.number().int().nonnegative().optional(),
      intervalsWithTarget: z.number().int().nonnegative().optional(),
      strideLengthChangePercent: z.number().optional(),
      groundContactTimeChangePercent: z.number().optional(),
      verticalOscillationChangePercent: z.number().optional(),
    })
    .optional(),
})

const night = z.object({
  date: timestamp,
  median: z.number().positive(),
  sampleCount: z.number().int().min(3),
})
export const rmssdTrendSchema = z.object({
  metric: z.literal('RMSSD'),
  context: z.literal('asleep'),
  source: text,
  sourceChanged: z.boolean(),
  latestSampleAt: timestamp,
  measuredAt: timestamp,
  currentNight: night.optional(),
  baselineMedian: positive,
  baselineNights: z.number().int().min(0).max(28),
  recentMedian: positive,
  recentNights: z.number().int().min(0).max(7),
  nights: z.array(night).max(29),
})

export function buildWorkoutInsights(value: unknown): string {
  const parsed = workoutInsightsSchema.safeParse(value)
  if (!parsed.success)
    return '\nDetailed measurements failed validation; do not infer missing details.\n'
  const data = parsed.data
  if (Object.keys(data).length === 0) return ''
  let context = '\n## Recorded session evidence\n'
  context +=
    'Units: intervals use seconds, meters, minutes/km, bpm and watts. Phases are thirds of active time; speed is m/s, stride meters, contact milliseconds, oscillation centimeters.\n'
  context +=
    'Zone indices start at 0; display index + 1. Bounds are inclusive minimum, exclusive maximum. Recorded zones take precedence over age estimates. They are not measured lactate thresholds. Compare configurations before comparing time in zones across workouts.\n'
  context +=
    'Coverage is the fraction of active time between observations at most 15 seconds apart. Missing, sparse or mixed-source measurements limit conclusions. Import time (measuredAt) is not the time of physiological measurement.\n'
  context +=
    'First-to-last-third changes are descriptive, not a diagnosis or proof of fatigue. Account for terrain, weather, pauses, intended session and perceived effort. Do not compare interval variability to a steady-run target. Feedback effort is user-rated; Apple-estimated effort is an estimate.\n'
  context += evidenceData(data)
  return `${context}\n`
}

export function buildRMSSDContext(value: unknown): string {
  if (value === undefined) return ''
  const parsed = rmssdTrendSchema.safeParse(value)
  if (!parsed.success) return '\nRMSSD detail unavailable after validation.\n'
  const data = parsed.data
  if (data.baselineNights < 7) delete data.baselineMedian
  return `\n## Night-time RMSSD (milliseconds)\n${evidenceData(data)}\nNight medians use at least 3 samples recorded during sleep. The reference is the median of prior nightly medians from the same source, excluding the current night. It requires at least 7 prior nights; this is a data sufficiency rule, not clinical validation. A missing currentNight is unknown, not the latest night's value. RMSSD and SDNN are different measures: never merge them, apply SDNN cutoffs to RMSSD, or count them as independent recovery factors. RMSSD is descriptive context, not an additional score component. A source change resets comparable history. Interpret with dated sleep, resting heart rate, training and feedback; neither a high nor a low value alone proves recovery or illness.\n`
}

export const evidenceCoachingRules = `Cite supplied observations with their date or segment. Distinguish facts from hypotheses in natural prose. State limits affecting advice. No causal claims, injury or overtraining diagnoses, universal cadence or invented ideal ranges. Unknown is not zero or normal. Apple zones are not physiological thresholds. Recovery belongs to its stated date. Base confidence on coverage, source consistency, context and baseline sufficiency.`
