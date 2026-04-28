import { Hono } from 'hono'
import { afterModelUsage, RequestType, selectModelFromRequest } from '../modelRouter'
import { captureLLMEvent, createPostHogClient } from '../posthog'
import { cleanJSONResponse, estimateTokenCount, getLanguageName, getRaceDistance } from '../utils'

type Bindings = {
  OPENROUTER_API_KEY: string
  APP_SECRET: string
  RATE_LIMITER: KVNamespace
  POSTHOG_API_KEY: string
  POSTHOG_HOST: string
}

type Variables = {
  rateLimitKey: string
}

interface CompletedWorkoutData {
  type: string
  planned: {
    distance?: number
    duration?: number
    pace?: string
    intensity: string
  }
  actual?: {
    distance: number
    duration: number
    pace?: number
    heartRate?: number
  }
  skipped?: boolean
}

interface CompletedWeekData {
  weekNumber: number
  phase: string
  completionRate: number
  workouts: CompletedWorkoutData[]
}

interface OriginalRemainingWorkoutData {
  type: string
  name: string
  intensity: string
  targetDistance?: number
  targetDuration?: number
  targetPace?: string
}

interface OriginalRemainingWeekData {
  weekNumber: number
  phase: string
  weeklyVolumeKm?: number
  workouts: OriginalRemainingWorkoutData[]
}

interface AdaptTrainingPlanRequest {
  raceType: 'marathon' | 'half_marathon' | '10k' | '5k' | 'ultra'
  targetDate: string
  fitnessLevel: 'beginner' | 'intermediate' | 'advanced'
  language: string
  trainingDaysPerWeek: number
  preferredDays: number[]
  targetTimeSeconds?: number
  injury?: string
  currentWeekNumber: number
  remainingWeeksCount: number
  originalPlanName: string
  originalPlanGoal: string
  completedWeeks: CompletedWeekData[]
  originalRemainingWeeks?: OriginalRemainingWeekData[]
}

interface GeneratedWorkoutStep {
  type: 'warmup' | 'work' | 'recovery' | 'cooldown' | 'interval' | 'rest'
  duration?: number
  distance?: number
  targetPace?: string
  repetitions?: number
  description: string
}

interface GeneratedPlannedWorkout {
  type: string
  name: string
  description: string
  targetDuration?: number
  targetDistance?: number
  targetPace?: string
  intensity: string
  steps: GeneratedWorkoutStep[]
}

interface GeneratedTrainingWeek {
  weekNumber: number
  phase: string
  workouts: GeneratedPlannedWorkout[]
  weeklyVolume?: number
  notes?: string
}

interface AdaptationAnalysis {
  assessment: string
  adjustments: string
  goalAchievable: boolean
  confidenceLevel: 'high' | 'medium' | 'low'
}

interface AdaptedTrainingPlan {
  weeks: GeneratedTrainingWeek[]
  adaptation: AdaptationAnalysis
}

const app = new Hono<{ Bindings: Bindings; Variables: Variables }>()

const OPENROUTER_API_URL = 'https://openrouter.ai/api/v1/chat/completions'
const MAX_TOKENS = 16000
const AI_TEMPERATURE = 0.3
const OPENROUTER_TIMEOUT_MS = 90_000

function formatCompletedWeeks(weeks: CompletedWeekData[]): string {
  return weeks
    .map((week) => {
      const workoutLines = week.workouts
        .map((w) => {
          let line = `  - ${w.type} (${w.planned.intensity})`
          if (w.planned.distance) line += ` | Planned: ${(w.planned.distance / 1000).toFixed(1)} km`
          if (w.planned.duration) line += ` ${Math.round(w.planned.duration / 60)} min`
          if (w.actual) {
            line += ` | Actual: ${(w.actual.distance / 1000).toFixed(1)} km`
            line += ` ${Math.round(w.actual.duration / 60)} min`
            if (w.actual.pace) line += ` @ ${w.actual.pace.toFixed(2)} min/km`
            if (w.actual.heartRate) line += ` HR ${Math.round(w.actual.heartRate)} bpm`
          } else if (w.skipped) {
            line += ' | SKIPPED (intentional — user opted out)'
          } else {
            line += ' | MISSED (no recorded workout)'
          }
          return line
        })
        .join('\n')

      return `Week ${week.weekNumber} (${week.phase}) — ${Math.round(week.completionRate * 100)}% completed:\n${workoutLines}`
    })
    .join('\n\n')
}

function formatOriginalRemainingWeeks(weeks: OriginalRemainingWeekData[]): string {
  return weeks
    .map((week) => {
      const header = `Week ${week.weekNumber} (${week.phase})${week.weeklyVolumeKm ? ` — ${week.weeklyVolumeKm.toFixed(1)} km` : ''}`
      const workoutLines = week.workouts
        .map((w) => {
          let line = `  - ${w.type} (${w.intensity}): "${w.name}"`
          if (w.targetDistance) line += ` | ${(w.targetDistance / 1000).toFixed(1)} km`
          if (w.targetDuration) line += ` ${Math.round(w.targetDuration / 60)} min`
          if (w.targetPace) line += ` @ ${w.targetPace}/km`
          return line
        })
        .join('\n')
      return `${header}\n${workoutLines}`
    })
    .join('\n\n')
}

function buildAdaptationPrompt(request: AdaptTrainingPlanRequest): {
  system: string
  user: string
} {
  const langName = getLanguageName(request.language)
  const raceDistance = getRaceDistance(request.raceType)
  const completedWeeksStr = formatCompletedWeeks(request.completedWeeks)
  const originalRemainingStr =
    request.originalRemainingWeeks && request.originalRemainingWeeks.length > 0
      ? formatOriginalRemainingWeeks(request.originalRemainingWeeks)
      : ''

  const dayNames: Record<number, string> = {
    1: 'Sunday',
    2: 'Monday',
    3: 'Tuesday',
    4: 'Wednesday',
    5: 'Thursday',
    6: 'Friday',
    7: 'Saturday',
  }

  const contextParts: string[] = []
  contextParts.push(`Race: ${raceDistance}`)
  contextParts.push(`Target date: ${request.targetDate}`)
  contextParts.push(`Fitness level: ${request.fitnessLevel}`)
  contextParts.push(`Training days per week: ${request.trainingDaysPerWeek}`)
  if (request.preferredDays.length > 0) {
    const names = request.preferredDays.map((d) => dayNames[d] || `Day ${d}`).join(', ')
    contextParts.push(`Preferred training days: ${names}`)
  }
  if (request.injury) {
    contextParts.push(`Injury/constraint: ${request.injury}`)
  }
  if (request.targetTimeSeconds) {
    const hours = Math.floor(request.targetTimeSeconds / 3600)
    const minutes = Math.floor((request.targetTimeSeconds % 3600) / 60)
    const timeStr = hours > 0 ? `${hours}h${minutes.toString().padStart(2, '0')}` : `${minutes}min`
    contextParts.push(`Target finish time: ${timeStr}`)
  }
  contextParts.push(`Current week: ${request.currentWeekNumber}`)
  contextParts.push(`Remaining weeks to generate: ${request.remainingWeeksCount}`)
  const contextStr = contextParts.map((p) => `- ${p}`).join('\n')

  const systemPrompt = `You are an expert running coach AI adapting an existing training plan based on actual performance data.

LANGUAGE: All text fields (name, goal, notes, descriptions, workout names, assessment, adjustments) MUST be 100% in ${langName}. Zero English words.

TASK: Analyze the runner's completed weeks (planned vs actual performance) and generate adapted remaining weeks.

CRITICAL RULES:
- Output ONLY valid JSON. No markdown, no code blocks, no explanation text.
- You are adapting an existing plan "${request.originalPlanName}" with goal "${request.originalPlanGoal}".
- Keep the SAME race goal and target date. Do NOT change the objective.
- Analyze actual vs planned performance to determine if the runner is ahead, on track, or behind.
- Adjust difficulty accordingly: increase if ahead, maintain if on track, decrease if behind.
- Generate exactly ${request.trainingDaysPerWeek} workouts per week.
- You MUST output exactly ${request.remainingWeeksCount} week(s) — no more, no less. The LAST of those weeks is the race week and MUST include the race itself as a workout.
- In the LAST week, the race workout MUST be the FIRST entry of the "workouts" array (index 0). The client uses array order to schedule the race on race day.
- DO NOT assign days of the week. The client app handles day scheduling.
- Distances in meters, durations in seconds.
- Weekly volume (weeklyVolume) MUST be in kilometers (not meters).
- Gradually adjust weekly volume (no more than 10% change per week).
- Maintain proper phase progression for the remaining weeks.${request.injury ? `\n- IMPORTANT: The runner has an injury/constraint: "${request.injury}". Adapt accordingly.` : ''}
${originalRemainingStr ? `- The "ORIGINAL REMAINING PLAN" section below shows the previously planned weeks. PRESERVE the phase sequence and pedagogical intent (key sessions, long runs, taper structure) — adjust volume/intensity/pace, not the overall blueprint, unless performance data clearly demands a structural change.` : ''}

SKIPPED vs MISSED:
- "SKIPPED (intentional — user opted out)" → user deliberately removed this session. Treat as a deliberate de-load, not a failure. Do not penalize completion rate aggressively.
- "MISSED (no recorded workout)" → likely fatigue, life event, or sync issue. Treat as a real signal of overload or scheduling stress.

ADAPTATION GUIDELINES:
- If completion rate < 60%: reduce volume and intensity, add more recovery
- If completion rate 60-80%: maintain similar difficulty, minor adjustments
- If completion rate > 80% and actual pace better than planned: increase intensity progressively
- If actual heart rate consistently high: reduce intensity even if pace is good
- Always assess if the target time is still achievable given current performance

WORKOUT TYPES: easy_run, tempo, intervals, long_run, recovery, hill_repeats, fartlek, cross_training
INTENSITIES: easy, moderate, hard, very_hard
PHASES: base, build, peak, taper, recovery

OUTPUT FORMAT:
{
  "weeks": [
    {
      "weekNumber": ${request.currentWeekNumber + 1},
      "phase": "build",
      "workouts": [
        {
          "type": "tempo",
          "name": "Workout name",
          "description": "Description",
          "targetDuration": 3600,
          "targetDistance": 8000,
          "targetPace": "5:30",
          "intensity": "moderate",
          "steps": [
            { "type": "warmup", "duration": 300, "description": "Warmup" },
            { "type": "work", "duration": 3000, "distance": 7000, "targetPace": "5:30", "description": "Main set" },
            { "type": "cooldown", "duration": 300, "description": "Cooldown" }
          ]
        }
      ],
      "weeklyVolume": 30.0,
      "notes": "Week focus"
    }
  ],
  "adaptation": {
    "assessment": "Analysis of runner's progress...",
    "adjustments": "What was changed and why...",
    "goalAchievable": true,
    "confidenceLevel": "high"
  }
}

RUNNER CONTEXT:
${contextStr}

COMPLETED WEEKS (planned vs actual):
${completedWeeksStr}${originalRemainingStr ? `\n\nORIGINAL REMAINING PLAN (the weeks you are adapting — preserve phase intent, adjust load):\n${originalRemainingStr}` : ''}`

  const userPrompt = `Adapt the remaining ${request.remainingWeeksCount} weeks of the training plan for a ${raceDistance} race. The runner is at week ${request.currentWeekNumber} of the plan. Analyze their performance data and generate optimized remaining weeks.`

  return { system: systemPrompt, user: userPrompt }
}

function validateAdaptedPlanJSON(data: unknown): data is AdaptedTrainingPlan {
  if (typeof data !== 'object' || data === null) return false

  const plan = data as AdaptedTrainingPlan

  if (!Array.isArray(plan.weeks) || plan.weeks.length === 0) return false
  if (!plan.adaptation || typeof plan.adaptation !== 'object') return false
  if (typeof plan.adaptation.assessment !== 'string') return false
  if (typeof plan.adaptation.goalAchievable !== 'boolean') return false

  // Optional fields — validated only when present, kept lenient for older model outputs.
  if (plan.adaptation.adjustments != null && typeof plan.adaptation.adjustments !== 'string')
    return false
  if (
    plan.adaptation.confidenceLevel != null &&
    !['high', 'medium', 'low'].includes(plan.adaptation.confidenceLevel)
  )
    return false

  for (const week of plan.weeks) {
    if (typeof week.weekNumber !== 'number') return false
    if (!['base', 'build', 'peak', 'taper', 'recovery'].includes(week.phase)) return false
    if (!Array.isArray(week.workouts) || week.workouts.length === 0) return false

    for (const workout of week.workouts) {
      if (!workout.type || !workout.name) return false
      if (
        ![
          'easy_run',
          'tempo',
          'intervals',
          'long_run',
          'recovery',
          'hill_repeats',
          'fartlek',
          'cross_training',
        ].includes(workout.type)
      )
        return false
      if (!['easy', 'moderate', 'hard', 'very_hard'].includes(workout.intensity)) return false

      if (workout.targetDuration != null) {
        if (
          typeof workout.targetDuration !== 'number' ||
          !Number.isFinite(workout.targetDuration) ||
          workout.targetDuration < 0
        )
          return false
      }
      if (workout.targetDistance != null) {
        if (
          typeof workout.targetDistance !== 'number' ||
          !Number.isFinite(workout.targetDistance) ||
          workout.targetDistance < 0
        )
          return false
      }

      if (Array.isArray(workout.steps)) {
        for (const step of workout.steps) {
          if (
            step.type != null &&
            !['warmup', 'work', 'recovery', 'cooldown', 'interval', 'rest'].includes(step.type)
          )
            return false

          if (step.duration != null) {
            if (
              typeof step.duration !== 'number' ||
              !Number.isFinite(step.duration) ||
              step.duration < 0
            )
              return false
          }
          if (step.distance != null) {
            if (
              typeof step.distance !== 'number' ||
              !Number.isFinite(step.distance) ||
              step.distance < 0
            )
              return false
          }

          if (
            step.repetitions != null &&
            (typeof step.repetitions !== 'number' ||
              step.repetitions < 1 ||
              !Number.isInteger(step.repetitions))
          )
            return false
        }
      }
    }
  }

  return true
}

// POST /api/adapt-training-plan
app.post('/', async (c) => {
  const startTime = Date.now()

  try {
    const body = (await c.req.json()) as AdaptTrainingPlanRequest

    // Validate request
    if (
      !body.raceType ||
      !body.targetDate ||
      !body.fitnessLevel ||
      !body.language ||
      !body.completedWeeks ||
      !body.remainingWeeksCount
    ) {
      return c.json(
        {
          error: 'Bad Request',
          message:
            'Missing required fields: raceType, targetDate, fitnessLevel, language, completedWeeks, remainingWeeksCount',
        },
        400
      )
    }

    if (body.remainingWeeksCount < 1) {
      return c.json(
        { error: 'Bad Request', message: 'At least 1 remaining week required for adaptation' },
        400
      )
    }

    const userId = c.req.header('X-User-ID') || c.req.header('CF-Connecting-IP') || 'unknown'
    const ip = c.req.header('CF-Connecting-IP') || 'unknown'
    const traceId = crypto.randomUUID()

    // Build prompt
    const { system: systemPrompt, user: userPrompt } = buildAdaptationPrompt(body)

    // Select model
    const { modelId: finalModel, modelConfig } = await selectModelFromRequest(
      'COMPLEX',
      undefined,
      c.env.RATE_LIMITER,
      userId,
      RequestType.COMPLEX
    )

    console.log(
      `📋 Adapting training plan with ${finalModel} — week ${body.currentWeekNumber}, ${body.remainingWeeksCount} weeks remaining`
    )

    // Call OpenRouter with retry logic
    let adaptedPlan: AdaptedTrainingPlan | null = null
    let attempts = 0
    const maxAttempts = 2

    while (attempts < maxAttempts && !adaptedPlan) {
      attempts++

      const controller = new AbortController()
      const timer = setTimeout(() => controller.abort(), OPENROUTER_TIMEOUT_MS)

      try {
        const response = await fetch(OPENROUTER_API_URL, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${c.env.OPENROUTER_API_KEY}`,
            'HTTP-Referer': 'https://insightrun.ai',
            'X-Title': 'insightRun.ai',
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            model: finalModel,
            messages: [
              { role: 'system', content: systemPrompt },
              { role: 'user', content: userPrompt },
            ],
            max_tokens: MAX_TOKENS,
            temperature: AI_TEMPERATURE,
            stream: false,
            response_format: { type: 'json_object' },
          }),
          signal: controller.signal,
        })

        if (!response.ok) {
          const errorText = await response.text()
          throw new Error(`OpenRouter API error: ${response.status} - ${errorText}`)
        }

        const data = (await response.json()) as {
          choices: Array<{ message: { content: string } }>
        }

        const rawResponse = data.choices[0]?.message?.content || ''
        console.log(`📝 Attempt ${attempts} - Raw response length: ${rawResponse.length}`)

        const cleanedResponse = cleanJSONResponse(rawResponse)
        const parsedData = JSON.parse(cleanedResponse) as unknown

        if (validateAdaptedPlanJSON(parsedData)) {
          adaptedPlan = parsedData
          console.log(
            `Adapted plan generated: ${adaptedPlan.weeks.length} weeks, goal achievable: ${adaptedPlan.adaptation.goalAchievable}`
          )
        } else {
          console.warn(`Invalid adapted plan structure on attempt ${attempts}`)
          if (attempts >= maxAttempts) {
            throw new Error('Generated adapted plan failed validation')
          }
        }
      } catch (parseError) {
        console.error(`Attempt ${attempts} failed:`, parseError)
        if (attempts >= maxAttempts) {
          throw parseError
        }
      } finally {
        clearTimeout(timer)
      }
    }

    if (!adaptedPlan) {
      throw new Error('Failed to generate valid adapted plan after retries')
    }

    const generationTime = Date.now() - startTime

    // Increment quota
    if (modelConfig) {
      await afterModelUsage(modelConfig, c.env.RATE_LIMITER, userId)
    }

    // PostHog analytics
    if (c.env.POSTHOG_API_KEY && c.env.POSTHOG_HOST) {
      const posthog = createPostHogClient({
        apiKey: c.env.POSTHOG_API_KEY,
        host: c.env.POSTHOG_HOST,
      })

      c.executionCtx.waitUntil(
        (async () => {
          try {
            const inputTokenCount = estimateTokenCount(systemPrompt + userPrompt)
            const outputTokenCount = estimateTokenCount(JSON.stringify(adaptedPlan))
            await captureLLMEvent(posthog, userId, traceId, {
              model: finalModel,
              input: userPrompt,
              systemPrompt,
              output: JSON.stringify(adaptedPlan),
              inputTokens: inputTokenCount,
              outputTokens: outputTokenCount,
              latency: generationTime / 1000,
              cost: undefined,
              ip,
            })
            await posthog.shutdown()
          } catch (error) {
            console.error('PostHog capture error:', error)
          }
        })()
      )
    }

    console.log(`Adapted training plan generated in ${generationTime}ms`)

    return c.json({
      plan: adaptedPlan,
      metadata: {
        generationTimeMs: generationTime,
        modelUsed: finalModel,
        attempts,
        weeksGenerated: adaptedPlan.weeks.length,
      },
    })
  } catch (error) {
    console.error('Training plan adaptation error:', error)

    return c.json(
      {
        error: 'Training Plan Adaptation Failed',
        message: error instanceof Error ? error.message : 'Unknown error occurred',
      },
      500
    )
  }
})

export default app
