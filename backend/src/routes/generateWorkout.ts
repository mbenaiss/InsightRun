import { Hono } from 'hono'
import { afterModelUsage, RequestType, selectModelFromRequest } from '../modelRouter'
import { callOpenRouterWithRetry, TruncatedResponseError } from '../openrouter'
import { captureLLMEvent, createPostHogClient } from '../posthog'
import { estimateTokenCount, getLanguageName } from '../utils'

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

interface WorkoutGenerationRequest {
  userQuestion: string
  language: string
  userContext?: {
    avgPace?: number // minutes per km
    vo2Max?: number
    recentWorkouts?: number // count
    fitnessLevel?: 'beginner' | 'intermediate' | 'advanced'
  }
  requestType?: string // e.g., 'WORKOUT_GENERATION'
  model?: string // Fallback for backward compatibility
}

interface WorkoutStep {
  type: 'warmup' | 'work' | 'recovery' | 'cooldown' | 'interval'
  goal: {
    type: 'distance' | 'duration' | 'open'
    value: number // meters for distance, seconds for duration
  }
  targetPace?: string // "4:30" format (single value)
  targetPaceMin?: string // "4:30" format (for ranges)
  targetPaceMax?: string // "4:45" format (for ranges)
  targetHeartRateZone?: number // 1-5
  repetitions?: number
  instructions?: string
}

interface AIGeneratedWorkout {
  name: string
  description: string
  sport: 'running' | 'cycling' | 'swimming'
  steps: WorkoutStep[]
  totalDistance?: number // meters
  estimatedDuration?: number // seconds
}

const app = new Hono<{ Bindings: Bindings; Variables: Variables }>()

const MAX_TOKENS = 4000
const AI_TEMPERATURE = 0.4
// iOS aborts this request at 60s; keep two attempts inside that budget (2×25s + margin).
const OPENROUTER_TIMEOUT_MS = 25_000
const WORKOUT_FALLBACK_MODEL = 'google/gemini-2.5-flash-lite'
// Canonical M:SS pace (minutes:seconds, seconds 00-59) after stripping a "/km" suffix.
const PACE_REGEX = /^\d+:[0-5]\d$/

// Strip an optional "/km" (or "/mi") suffix and validate the remainder is M:SS.
// Returns the cleaned "M:SS" string, or null when the value is not a valid pace.
function validatePaceFormat(pace: string): string | null {
  const cleaned = pace.trim().replace(/\s*\/(km|mi)\s*$/i, '')
  return PACE_REGEX.test(cleaned) ? cleaned : null
}

function buildWorkoutGenerationPrompt(
  userQuestion: string,
  language: string,
  userContext?: WorkoutGenerationRequest['userContext']
): { system: string; user: string } {
  const langName = getLanguageName(language)

  // Build user context only with available data
  let userContextStr = ''
  if (userContext) {
    const parts: string[] = []
    if (userContext.avgPace) parts.push(`Average pace: ${userContext.avgPace.toFixed(2)} min/km`)
    if (userContext.vo2Max) parts.push(`VO2 Max: ${userContext.vo2Max}`)
    if (userContext.recentWorkouts) parts.push(`Recent workouts: ${userContext.recentWorkouts}`)
    parts.push(`Fitness level: ${userContext.fitnessLevel || 'intermediate'}`)
    userContextStr = parts.map((p) => `- ${p}`).join('\n')
  } else {
    userContextStr = '- No context available, use general recommendations'
  }

  const systemPrompt = `You are a professional running coach AI. Generate structured workout plans as valid JSON.

LANGUAGE: All text fields (name, description, instructions) MUST be 100% in ${langName}. Zero English words — translate phase names, workout types, and instructions entirely.

CRITICAL RULES:
- Output ONLY valid JSON. No markdown, no code blocks, no explanation text.
- Respect the user's request exactly: simple continuous run = ONE step only.
- Only add warm-up/cool-down for high-intensity workouts (intervals, speed work, tempo).
- If the user specifies exact pace values, use those EXACT values. Never modify user-specified paces, distances, or durations.
- If no pace is specified, suggest paces based on user's fitness level.
- Max 50 steps. Distances in meters, durations in seconds.

PHASE PARSING:
If the user provides a pre-formatted workout with phases, parse it exactly:
- Map phase names to types: warmup/warm-up → "warmup", tempo/seuil/threshold → "work", intervals/répétitions → "interval", recovery/récupération → "recovery", cooldown/retour au calme → "cooldown", endurance/easy → "work"
- Convert: "10 min" → 600 seconds, "5 km" → 5000 meters
- Keep phases in the exact order provided.

REPETITIONS RULE (CRITICAL — never multiply distances):
- For "N × distance" workouts (e.g. "6×800m récup 400m"), generate ONE "interval"/"work" step with the unit value (800m) and "repetitions": N. NEVER output a single step with the multiplied distance (4800m is wrong).
- The "recovery" step that immediately follows is implicitly repeated the same number of times — do NOT duplicate it, do NOT set "repetitions" on the recovery step.
- Omit "repetitions" (or set to 1) for non-repeated steps.
- Example "6×800m at 3:30/km récup 400m at 5:30/km":
  { "type": "interval", "goal": { "type": "distance", "value": 800 }, "repetitions": 6, "targetPace": "3:30" },
  { "type": "recovery", "goal": { "type": "distance", "value": 400 }, "targetPace": "5:30" }

PACE RULES:
- Exact pace (e.g., "5:30/km") → use "targetPace": "5:30"
- Pace range (e.g., "6:00-6:30/km") → use "targetPaceMin": "6:00", "targetPaceMax": "6:30"
- Never mix targetPace and targetPaceMin/Max in the same step.
- Pace values MUST be exactly "M:SS" (minutes:seconds, seconds 00-59). No "/km" suffix, no apostrophes ("4'30"), no decimals ("4.5").

OUTPUT FORMAT:
{
  "name": "Concise workout name",
  "description": "Brief description (1-2 sentences)",
  "sport": "running",
  "steps": [
    {
      "type": "warmup",
      "goal": { "type": "duration", "value": 600 },
      "targetPaceMin": "6:30",
      "targetPaceMax": "7:00",
      "instructions": "Easy warm-up"
    }
  ],
  "totalDistance": 7600,
  "estimatedDuration": 2700
}

Step types: "warmup", "work", "recovery", "cooldown", "interval"
Goal types: "distance" (meters), "duration" (seconds), "open". For "open" steps, still include "value": 0.

USER CONTEXT:
${userContextStr}`

  const userPrompt = `Generate a running workout based on this request: ${userQuestion}`

  return { system: systemPrompt, user: userPrompt }
}

function validateWorkoutJSON(data: unknown): data is AIGeneratedWorkout {
  if (typeof data !== 'object' || data === null) return false

  const workout = data as AIGeneratedWorkout

  // Validate required fields
  if (!workout.name || typeof workout.name !== 'string') return false
  if (!workout.description || typeof workout.description !== 'string') return false
  if (!workout.sport || !['running', 'cycling', 'swimming'].includes(workout.sport)) return false
  if (!Array.isArray(workout.steps) || workout.steps.length === 0) return false
  if (workout.steps.length > 50) return false

  // Validate optional fields
  if (workout.totalDistance !== undefined && typeof workout.totalDistance !== 'number') return false
  if (workout.estimatedDuration !== undefined && typeof workout.estimatedDuration !== 'number')
    return false

  // Validate each step
  for (const step of workout.steps) {
    if (!['warmup', 'work', 'recovery', 'cooldown', 'interval'].includes(step.type)) return false
    if (!step.goal || !step.goal.type || !['distance', 'duration', 'open'].includes(step.goal.type))
      return false
    if (step.goal.type !== 'open' && (typeof step.goal.value !== 'number' || step.goal.value <= 0))
      return false
    if (step.targetHeartRateZone && (step.targetHeartRateZone < 1 || step.targetHeartRateZone > 5))
      return false
    if (
      step.repetitions !== undefined &&
      (typeof step.repetitions !== 'number' ||
        step.repetitions < 1 ||
        !Number.isInteger(step.repetitions))
    )
      return false

    // Pace fields must be canonical M:SS — the watch cannot interpret "4'30" or "4.5".
    // Reject (don't silently skip) so a malformed pace triggers a retry, not a bad workout.
    for (const key of ['targetPace', 'targetPaceMin', 'targetPaceMax'] as const) {
      const value = step[key]
      if (value != null) {
        if (typeof value !== 'string') return false
        const cleaned = validatePaceFormat(value)
        if (cleaned === null) return false
        step[key] = cleaned
      }
    }
  }

  return true
}

// The iOS StepGoal.value is a non-optional Double; an "open" step the model emits without
// a value would crash the strict decoder. Fill 0 so the response is always decodable.
function fillWorkoutDefaults(workout: AIGeneratedWorkout): void {
  for (const step of workout.steps) {
    if (step.goal.type === 'open' && typeof step.goal.value !== 'number') {
      step.goal.value = 0
    }
  }
}

function paceToSeconds(pace: string): number | null {
  const match = pace.match(/^(\d+):([0-5]?\d)$/)
  if (!match) return null
  return parseInt(match[1], 10) * 60 + parseInt(match[2], 10)
}

// The model occasionally emits a pace range with min/max swapped. The faster
// (smaller) pace must stay in targetPaceMin so the watch never gets an inverted range.
function normalizeWorkoutPaces(workout: AIGeneratedWorkout): void {
  for (const step of workout.steps) {
    if (!step.targetPaceMin || !step.targetPaceMax) continue
    const minSec = paceToSeconds(step.targetPaceMin)
    const maxSec = paceToSeconds(step.targetPaceMax)
    if (minSec === null || maxSec === null) continue
    if (minSec === maxSec) {
      // A zero-width range is a single pace; collapse it so the watch gets a threshold, not an unsupported range.
      if (!step.targetPace) step.targetPace = step.targetPaceMin
      step.targetPaceMin = undefined
      step.targetPaceMax = undefined
      continue
    }
    if (minSec > maxSec) {
      const tmp = step.targetPaceMin
      step.targetPaceMin = step.targetPaceMax
      step.targetPaceMax = tmp
    }
  }
}

async function callOpenRouterForWorkout(
  apiKey: string,
  systemPrompt: string,
  userPrompt: string,
  model: string
): Promise<string> {
  const { content } = await callOpenRouterWithRetry({
    apiKey,
    model,
    fallbackModel: WORKOUT_FALLBACK_MODEL,
    body: {
      messages: [
        { role: 'system', content: systemPrompt },
        { role: 'user', content: userPrompt },
      ],
      max_tokens: MAX_TOKENS,
      temperature: AI_TEMPERATURE,
      stream: false,
      response_format: { type: 'json_object' }, // Force JSON response (supported by some models)
    },
    timeoutMs: OPENROUTER_TIMEOUT_MS,
    title: 'insightRun.ai',
    throwOnTruncation: true,
  })
  return content
}

function cleanJSONResponse(text: string): string {
  // Remove markdown code blocks if present
  let cleaned = text.trim()

  // Remove ```json and ``` markers
  cleaned = cleaned.replace(/^```json\s*/i, '')
  cleaned = cleaned.replace(/^```\s*/, '')
  cleaned = cleaned.replace(/\s*```$/, '')

  // Remove any leading/trailing whitespace
  cleaned = cleaned.trim()

  return cleaned
}

// POST /api/generate-workout
app.post('/', async (c) => {
  const startTime = Date.now()

  try {
    const body = (await c.req.json()) as WorkoutGenerationRequest

    // Validate request
    if (!body.userQuestion || !body.language) {
      return c.json(
        {
          error: 'Bad Request',
          message: 'Missing required fields: userQuestion, language',
        },
        400
      )
    }

    if (body.userQuestion.length > 2000) {
      return c.json(
        {
          error: 'Bad Request',
          message: 'User question too long (max 2000 characters)',
        },
        400
      )
    }

    // Get user ID for analytics
    const userId = c.req.header('X-User-ID') || c.req.header('CF-Connecting-IP') || 'unknown'
    const ip = c.req.header('CF-Connecting-IP') || 'unknown'
    const traceId = crypto.randomUUID()

    // Build prompt
    const { system: systemPrompt, user: userPrompt } = buildWorkoutGenerationPrompt(
      body.userQuestion,
      body.language,
      body.userContext
    )

    // Select model using helper
    const { modelId: finalModel, modelConfig } = await selectModelFromRequest(
      body.requestType,
      body.model,
      c.env.RATE_LIMITER,
      userId,
      RequestType.WORKOUT_GENERATION
    )

    console.log(`🏃 Generating workout with ${finalModel} for "${body.userQuestion}"`)

    // Call OpenRouter with retry logic
    let workoutJSON: AIGeneratedWorkout | null = null
    let attempts = 0
    const maxAttempts = 2
    // Carries the previous failure into the next attempt so the model corrects it
    // instead of re-emitting the exact same broken output.
    let retryFeedback = ''

    while (attempts < maxAttempts && !workoutJSON) {
      attempts++

      try {
        const attemptUserPrompt = retryFeedback
          ? `${userPrompt}\n\nYour previous output was invalid: ${retryFeedback}\nReturn corrected, complete JSON only.`
          : userPrompt

        const rawResponse = await callOpenRouterForWorkout(
          c.env.OPENROUTER_API_KEY,
          systemPrompt,
          attemptUserPrompt,
          finalModel
        )

        console.log(`📝 Attempt ${attempts} - Raw response length: ${rawResponse.length}`)

        // Clean JSON response
        const cleanedResponse = cleanJSONResponse(rawResponse)

        // Parse JSON
        const parsedData = JSON.parse(cleanedResponse) as unknown

        // Validate structure
        if (validateWorkoutJSON(parsedData)) {
          fillWorkoutDefaults(parsedData)
          normalizeWorkoutPaces(parsedData)
          workoutJSON = parsedData
          console.log(
            `✅ Valid workout generated: "${workoutJSON.name}" with ${workoutJSON.steps.length} steps`
          )
        } else {
          console.warn(`⚠️ Invalid workout structure on attempt ${attempts}`)
          retryFeedback =
            'the JSON did not match the schema. Every step needs a valid "type" and "goal" {type, value}; every pace must be exact "M:SS" format (e.g. "5:30", no "/km", no apostrophes, no decimals).'
          if (attempts >= maxAttempts) {
            throw new Error('Generated workout failed validation')
          }
        }
      } catch (parseError) {
        console.error(`❌ Attempt ${attempts} failed:`, parseError)
        if (parseError instanceof TruncatedResponseError) {
          retryFeedback = 'the JSON was cut off. Use fewer steps / shorter instructions.'
        } else if (parseError instanceof SyntaxError) {
          retryFeedback = `the response was not valid JSON (${parseError.message}).`
        }
        if (attempts >= maxAttempts) {
          throw parseError
        }
      }
    }

    if (!workoutJSON) {
      throw new Error('Failed to generate valid workout after retries')
    }

    const generationTime = Date.now() - startTime
    const latency = generationTime / 1000

    // Increment quota if model requires it
    if (modelConfig) {
      await afterModelUsage(modelConfig, c.env.RATE_LIMITER, userId)
    }

    // Log to PostHog (optional, async)
    if (c.env.POSTHOG_API_KEY && c.env.POSTHOG_HOST) {
      const posthog = createPostHogClient({
        apiKey: c.env.POSTHOG_API_KEY,
        host: c.env.POSTHOG_HOST,
      })

      c.executionCtx.waitUntil(
        (async () => {
          try {
            const inputTokenCount = estimateTokenCount(systemPrompt + userPrompt)
            const outputTokenCount = estimateTokenCount(JSON.stringify(workoutJSON))
            await captureLLMEvent(posthog, userId, traceId, {
              model: finalModel,
              input: userPrompt,
              systemPrompt,
              output: JSON.stringify(workoutJSON),
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

    console.log(`✅ Workout generated successfully in ${generationTime}ms`)

    return c.json({
      workout: workoutJSON,
      metadata: {
        generationTimeMs: generationTime,
        modelUsed: finalModel,
        attempts: attempts,
      },
    })
  } catch (error) {
    console.error('Workout generation error:', error)

    return c.json(
      {
        error: 'Workout Generation Failed',
        message: error instanceof Error ? error.message : 'Unknown error occurred',
      },
      500
    )
  }
})

export default app
