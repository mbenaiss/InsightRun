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

interface TrainingPlanRequest {
  raceType: 'marathon' | 'half_marathon' | '10k' | '5k' | 'ultra'
  targetDate: string // ISO 8601
  startDate?: string // ISO 8601 — user-chosen plan start date; defaults to now when absent
  fitnessLevel: 'beginner' | 'intermediate' | 'advanced'
  currentWeeklyVolumeKm?: number
  avgPace?: number // min/km
  language: string
  trainingDaysPerWeek?: number // 3-6
  preferredDays?: number[] // 1=Sunday...7=Saturday
  injury?: string // injury or constraint description
  targetTimeSeconds?: number // target finish time in seconds
}

interface GeneratedTrainingWeek {
  weekNumber: number
  phase: 'base' | 'build' | 'peak' | 'taper' | 'recovery'
  workouts: GeneratedPlannedWorkout[]
  weeklyVolume?: number // km
  notes?: string
}

interface GeneratedPlannedWorkout {
  type:
    | 'easy_run'
    | 'tempo'
    | 'intervals'
    | 'long_run'
    | 'recovery'
    | 'hill_repeats'
    | 'fartlek'
    | 'cross_training'
  name: string
  description: string
  targetDuration?: number // seconds
  targetDistance?: number // meters
  targetPace?: string // "5:30/km"
  intensity: 'easy' | 'moderate' | 'hard' | 'very_hard'
  steps: GeneratedWorkoutStep[]
}

interface GeneratedWorkoutStep {
  type: 'warmup' | 'work' | 'recovery' | 'cooldown' | 'interval' | 'rest'
  duration?: number // seconds
  distance?: number // meters
  targetPace?: string
  repetitions?: number
  description: string
}

interface GeneratedTrainingPlan {
  name: string
  goal: string
  weeks: GeneratedTrainingWeek[]
}

const app = new Hono<{ Bindings: Bindings; Variables: Variables }>()

const OPENROUTER_API_URL = 'https://openrouter.ai/api/v1/chat/completions'
const MAX_TOKENS = 16000 // Training plans are large
const AI_TEMPERATURE = 0.3 // Lower temperature for more consistent plans

function buildTrainingPlanPrompt(
  request: TrainingPlanRequest,
  weeksAvailable: number
): { system: string; user: string } {
  const langName = getLanguageName(request.language)
  const raceDistance = getRaceDistance(request.raceType)

  // Calculate race day of week (1=Sunday...7=Saturday to match our format)
  const targetDate = new Date(request.targetDate)
  const jsDay = targetDate.getUTCDay() // 0=Sunday...6=Saturday
  const raceDayOfWeek = jsDay + 1 // Convert to 1=Sunday...7=Saturday

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
  contextParts.push(`Fitness level: ${request.fitnessLevel}`)
  if (request.currentWeeklyVolumeKm) {
    contextParts.push(`Current weekly volume: ${request.currentWeeklyVolumeKm} km`)
  }
  if (request.avgPace) {
    contextParts.push(`Average pace: ${request.avgPace.toFixed(2)} min/km`)
  }
  contextParts.push(`Weeks available: ${weeksAvailable}`)
  if (request.trainingDaysPerWeek) {
    contextParts.push(`Training days per week: ${request.trainingDaysPerWeek}`)
  }
  if (request.preferredDays && request.preferredDays.length > 0) {
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
    contextParts.push(`Target finish time: ${timeStr} — set paces accordingly to achieve this goal`)
  }
  contextParts.push(`Race day: ${dayNames[raceDayOfWeek]} (dayOfWeek=${raceDayOfWeek})`)
  const userContextStr = contextParts.map((p) => `- ${p}`).join('\n')

  const systemPrompt = `You are an expert running coach AI. Generate structured multi-week training plans as valid JSON.

LANGUAGE: All text fields (name, goal, notes, descriptions, workout names) MUST be 100% in ${langName}. Zero English words.

CRITICAL RULES:
- Output ONLY valid JSON. No markdown, no code blocks, no explanation text.
- Generate a realistic, periodized training plan with proper phase progression.
- Phases should follow: base → build → peak → taper (adjust duration based on available weeks).
- Generate exactly ${request.trainingDaysPerWeek || '3-5'} workouts per week (NOT 7 days — just the workouts).${request.injury ? `\n- IMPORTANT: The runner has an injury/constraint (see USER CONTEXT). Adapt the plan accordingly: reduce intensity, avoid aggravating exercises, include more recovery.` : ''}
- DO NOT assign days of the week. The client app handles day scheduling.
- Distances in meters, durations in seconds.
- Weekly volume (weeklyVolume) MUST be in kilometers (not meters). Example: 25.0 means 25 km.
- Gradually increase weekly volume (no more than 10% per week).
- Include a taper phase (1-3 weeks before race depending on distance).
- The LAST week must include the race itself as a workout (type matching the race distance).
- In the LAST week, the race workout MUST be the FIRST entry of the "workouts" array (index 0). The client uses array order to schedule the race on race day — getting this wrong puts the race on the wrong day of the week.
- Order workouts by importance: key session first, then secondary sessions, then easy/recovery last.

REPETITIONS RULE (CRITICAL — never multiply distances):
- For "N × distance" interval sessions (e.g. "6×800m récup 400m"), generate ONE step with type "interval" or "work" carrying the unit value (800m) and "repetitions": N. NEVER output a single step with the multiplied distance (4800m is wrong).
- The "recovery" step that immediately follows is implicitly repeated the same number of times — do NOT duplicate it, do NOT set "repetitions" on the recovery step.
- Omit "repetitions" (or set to 1) for non-repeated steps.
- Example for an intervals workout "6×800m at 3:30/km récup 400m at 5:30/km":
  { "type": "interval", "distance": 800, "targetPace": "3:30", "repetitions": 6, "description": "Effort 800m" },
  { "type": "recovery", "distance": 400, "targetPace": "5:30", "description": "Récupération active" }

PHASE ALLOCATION GUIDELINES:
- 5K (6-10 weeks): 40% base, 30% build, 20% peak, 10% taper
- 10K (8-12 weeks): 35% base, 30% build, 25% peak, 10% taper
- Half Marathon (10-16 weeks): 30% base, 35% build, 25% peak, 10% taper
- Marathon (16-20 weeks): 25% base, 35% build, 25% peak, 15% taper
- Ultra (20+ weeks): 25% base, 35% build, 25% peak, 15% taper

WORKOUT INTENSITY BY LEVEL:
- Beginner: 70% easy, 15% moderate, 10% hard, 5% very_hard
- Intermediate: 55% easy, 20% moderate, 15% hard, 10% very_hard
- Advanced: 45% easy, 20% moderate, 20% hard, 15% very_hard

WORKOUT TYPES:
- easy_run: Base aerobic runs
- tempo: Sustained threshold effort
- intervals: Speed work (track or road)
- long_run: Weekly long run (progressive distance)
- recovery: Very easy post-hard-day runs
- hill_repeats: Hill training sessions
- fartlek: Unstructured speed play
- cross_training: Non-running activity

OUTPUT FORMAT (workouts array = ONLY the workout sessions, no rest days):
{
  "name": "Plan name",
  "goal": "Description of the goal",
  "weeks": [
    {
      "weekNumber": 1,
      "phase": "base",
      "workouts": [
        {
          "type": "long_run",
          "name": "Sortie longue facile",
          "description": "Endurance fondamentale",
          "targetDuration": 3600,
          "targetDistance": 8000,
          "targetPace": "6:00",
          "intensity": "easy",
          "steps": [
            { "type": "warmup", "duration": 300, "description": "Echauffement" },
            { "type": "work", "duration": 3000, "distance": 7000, "targetPace": "5:30", "description": "Course principale" },
            { "type": "cooldown", "duration": 300, "description": "Retour au calme" }
          ]
        },
        {
          "type": "tempo",
          "name": "Tempo modéré",
          "description": "Seuil contrôlé",
          "targetDuration": 2400,
          "targetDistance": 5000,
          "intensity": "moderate",
          "steps": []
        }
      ],
      "weeklyVolume": 25.0,
      "notes": "Week focus note"
    }
  ]
}

USER CONTEXT:
${userContextStr}`

  const userPrompt = `Generate a ${weeksAvailable}-week training plan for a ${raceDistance} race. The runner is ${request.fitnessLevel} level.`

  return { system: systemPrompt, user: userPrompt }
}

function validateTrainingPlanJSON(data: unknown): data is GeneratedTrainingPlan {
  if (typeof data !== 'object' || data === null) return false

  const plan = data as GeneratedTrainingPlan

  if (!plan.name || typeof plan.name !== 'string') return false
  if (!plan.goal || typeof plan.goal !== 'string') return false
  if (!Array.isArray(plan.weeks) || plan.weeks.length === 0) return false

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
    }
  }

  return true
}

async function callOpenRouterForPlan(
  apiKey: string,
  systemPrompt: string,
  userPrompt: string,
  model: string
): Promise<string> {
  const requestBody = {
    model,
    messages: [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: userPrompt },
    ],
    max_tokens: MAX_TOKENS,
    temperature: AI_TEMPERATURE,
    stream: false,
    response_format: { type: 'json_object' },
  }

  const response = await fetch(OPENROUTER_API_URL, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'HTTP-Referer': 'https://insightrun.ai',
      'X-Title': 'insightRun.ai',
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(requestBody),
  })

  if (!response.ok) {
    const errorText = await response.text()
    throw new Error(`OpenRouter API error: ${response.status} - ${errorText}`)
  }

  const data = (await response.json()) as {
    choices: Array<{ message: { content: string } }>
  }

  return data.choices[0]?.message?.content || ''
}

// POST /api/generate-training-plan
app.post('/', async (c) => {
  const startTime = Date.now()

  try {
    const body = (await c.req.json()) as TrainingPlanRequest

    // Validate request
    if (!body.raceType || !body.targetDate || !body.fitnessLevel || !body.language) {
      return c.json(
        {
          error: 'Bad Request',
          message: 'Missing required fields: raceType, targetDate, fitnessLevel, language',
        },
        400
      )
    }

    const validRaceTypes = ['marathon', 'half_marathon', '10k', '5k', 'ultra']
    if (!validRaceTypes.includes(body.raceType)) {
      return c.json(
        {
          error: 'Bad Request',
          message: `Invalid raceType. Must be one of: ${validRaceTypes.join(', ')}`,
        },
        400
      )
    }

    // Calculate weeks available from the user-chosen start date (or now as fallback)
    const targetDate = new Date(body.targetDate)
    const now = new Date()
    const parsedStart = body.startDate ? new Date(body.startDate) : now
    // Guard against invalid ISO strings or start dates in the past
    const startDate =
      Number.isNaN(parsedStart.getTime()) || parsedStart.getTime() < now.getTime()
        ? now
        : parsedStart
    const msPerWeek = 7 * 24 * 60 * 60 * 1000
    const weeksAvailable = Math.floor((targetDate.getTime() - startDate.getTime()) / msPerWeek)

    if (weeksAvailable < 4) {
      return c.json(
        {
          error: 'Bad Request',
          message: 'Plan must span at least 4 weeks from start to race date',
        },
        400
      )
    }

    // Cap at reasonable plan length
    const maxWeeks = Math.min(weeksAvailable, 24)

    const userId = c.req.header('X-User-ID') || c.req.header('CF-Connecting-IP') || 'unknown'
    const ip = c.req.header('CF-Connecting-IP') || 'unknown'
    const traceId = crypto.randomUUID()

    // Build prompt
    const { system: systemPrompt, user: userPrompt } = buildTrainingPlanPrompt(body, maxWeeks)

    // Select model - use COMPLEX for training plans (large structured output)
    const { modelId: finalModel, modelConfig } = await selectModelFromRequest(
      'COMPLEX',
      undefined,
      c.env.RATE_LIMITER,
      userId,
      RequestType.COMPLEX
    )

    console.log(
      `📋 Generating ${maxWeeks}-week training plan with ${finalModel} for ${body.raceType}`
    )

    // Call OpenRouter with retry logic
    let planJSON: GeneratedTrainingPlan | null = null
    let attempts = 0
    const maxAttempts = 2

    while (attempts < maxAttempts && !planJSON) {
      attempts++

      try {
        const rawResponse = await callOpenRouterForPlan(
          c.env.OPENROUTER_API_KEY,
          systemPrompt,
          userPrompt,
          finalModel
        )

        console.log(`📝 Attempt ${attempts} - Raw response length: ${rawResponse.length}`)

        const cleanedResponse = cleanJSONResponse(rawResponse)
        const parsedData = JSON.parse(cleanedResponse) as unknown

        if (validateTrainingPlanJSON(parsedData)) {
          planJSON = parsedData
          console.log(
            `✅ Valid training plan generated: "${planJSON.name}" with ${planJSON.weeks.length} weeks`
          )
        } else {
          console.warn(`⚠️ Invalid training plan structure on attempt ${attempts}`)
          if (attempts >= maxAttempts) {
            throw new Error('Generated training plan failed validation')
          }
        }
      } catch (parseError) {
        console.error(`❌ Attempt ${attempts} failed:`, parseError)
        if (attempts >= maxAttempts) {
          throw parseError
        }
      }
    }

    if (!planJSON) {
      throw new Error('Failed to generate valid training plan after retries')
    }

    const generationTime = Date.now() - startTime
    const latency = generationTime / 1000

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
            const outputTokenCount = estimateTokenCount(JSON.stringify(planJSON))
            await captureLLMEvent(posthog, userId, traceId, {
              model: finalModel,
              input: userPrompt,
              systemPrompt,
              output: JSON.stringify(planJSON),
              inputTokens: inputTokenCount,
              outputTokens: outputTokenCount,
              latency,
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

    console.log(`✅ Training plan generated successfully in ${generationTime}ms`)

    return c.json({
      plan: planJSON,
      metadata: {
        generationTimeMs: generationTime,
        modelUsed: finalModel,
        attempts,
        weeksGenerated: planJSON.weeks.length,
      },
    })
  } catch (error) {
    console.error('Training plan generation error:', error)

    return c.json(
      {
        error: 'Training Plan Generation Failed',
        message: error instanceof Error ? error.message : 'Unknown error occurred',
      },
      500
    )
  }
})

export default app
