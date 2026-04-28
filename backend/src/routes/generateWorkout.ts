import { Hono } from 'hono'
import { afterModelUsage, RequestType, selectModelFromRequest } from '../modelRouter'
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

const OPENROUTER_API_URL = 'https://openrouter.ai/api/v1/chat/completions'
const MAX_TOKENS = 4000
const AI_TEMPERATURE = 0.4

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
Goal types: "distance" (meters), "duration" (seconds), "open"

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
  }

  return true
}

async function callOpenRouterForWorkout(
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
    response_format: { type: 'json_object' }, // Force JSON response (supported by some models)
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
    usage?: {
      prompt_tokens?: number
      completion_tokens?: number
      total_tokens?: number
    }
  }

  return data.choices[0]?.message?.content || ''
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

    while (attempts < maxAttempts && !workoutJSON) {
      attempts++

      try {
        const rawResponse = await callOpenRouterForWorkout(
          c.env.OPENROUTER_API_KEY,
          systemPrompt,
          userPrompt,
          finalModel
        )

        console.log(`📝 Attempt ${attempts} - Raw response length: ${rawResponse.length}`)

        // Clean JSON response
        const cleanedResponse = cleanJSONResponse(rawResponse)

        // Parse JSON
        const parsedData = JSON.parse(cleanedResponse) as unknown

        // Validate structure
        if (validateWorkoutJSON(parsedData)) {
          workoutJSON = parsedData
          console.log(
            `✅ Valid workout generated: "${workoutJSON.name}" with ${workoutJSON.steps.length} steps`
          )
        } else {
          console.warn(`⚠️ Invalid workout structure on attempt ${attempts}`)
          if (attempts >= maxAttempts) {
            throw new Error('Generated workout failed validation')
          }
        }
      } catch (parseError) {
        console.error(`❌ Attempt ${attempts} failed:`, parseError)
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
