import { Hono } from 'hono'
import { createPostHogClient } from '../posthog'

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
  model?: string
}

interface WorkoutStep {
  type: 'warmup' | 'work' | 'recovery' | 'cooldown' | 'interval'
  goal: {
    type: 'distance' | 'duration' | 'open'
    value: number // meters for distance, seconds for duration
  }
  targetPace?: string // "4:30" format
  targetHeartRateZone?: number // 1-5
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
const MAX_TOKENS = 4000 // Increased for workout generation
const AI_TEMPERATURE = 0.7

function buildWorkoutGenerationPrompt(
  userQuestion: string,
  language: string,
  userContext?: WorkoutGenerationRequest['userContext']
): { system: string; user: string } {
  const systemPrompt = `You are a professional running coach AI. Generate structured workout plans in valid JSON format.

CRITICAL RULES:
- Output ONLY valid JSON, no markdown formatting, no code blocks, no explanation
- RESPECT the user's request exactly - if they ask for a simple continuous run, generate ONE step only
- Only add warm-up and cool-down phases if the workout is high-intensity (intervals, speed work, tempo)
- For easy/endurance/steady runs, generate a single step with the requested duration/distance
- Provide specific paces based on user's fitness level
- Recovery times should be appropriate to workout intensity
- Max 50 steps per workout
- Distances in meters, durations in seconds

OUTPUT FORMAT (MUST be valid JSON):
{
  "name": "Workout name (concise, descriptive)",
  "description": "Brief workout description (1-2 sentences)",
  "sport": "running",
  "steps": [
    {
      "type": "warmup",
      "goal": { "type": "distance", "value": 1000 },
      "targetPace": "5:30",
      "targetHeartRateZone": 2,
      "instructions": "Start slow and gradually increase pace"
    },
    {
      "type": "work",
      "goal": { "type": "distance", "value": 400 },
      "targetPace": "4:00",
      "targetHeartRateZone": 4,
      "instructions": "Fast but controlled"
    },
    {
      "type": "recovery",
      "goal": { "type": "duration", "value": 60 },
      "targetPace": "6:00",
      "instructions": "Slow jog to recover"
    },
    {
      "type": "cooldown",
      "goal": { "type": "distance", "value": 800 },
      "targetPace": "5:45",
      "instructions": "Easy pace to finish"
    }
  ],
  "totalDistance": 7600,
  "estimatedDuration": 2700
}

USER CONTEXT:
${
  userContext
    ? `- Average pace: ${userContext.avgPace ? `${userContext.avgPace.toFixed(2)} min/km` : 'unknown'}
- VO2 Max: ${userContext.vo2Max || 'unknown'}
- Recent workouts: ${userContext.recentWorkouts || 0}
- Fitness level: ${userContext.fitnessLevel || 'intermediate'}`
    : '- No context available, use general recommendations'
}

LANGUAGE: Respond in ${language} (name, description, instructions)

IMPORTANT: Return ONLY the JSON object, nothing else.`

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

  return data.choices[0].message.content
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

    // Build prompt
    const { system: systemPrompt, user: userPrompt } = buildWorkoutGenerationPrompt(
      body.userQuestion,
      body.language,
      body.userContext
    )

    // Default model: Gemini 2.5 Flash Lite (fast and cheap for workout generation)
    const model = body.model || 'google/gemini-2.5-flash-lite'

    console.log(`🏃 Generating workout for user ${userId}: "${body.userQuestion}"`)

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
          model
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

    // Track analytics
    const posthog = createPostHogClient({
      apiKey: c.env.POSTHOG_API_KEY,
      host: c.env.POSTHOG_HOST,
    })
    posthog.capture({
      distinctId: userId,
      event: 'workout_generated',
      properties: {
        workout_name: workoutJSON.name,
        sport: workoutJSON.sport,
        step_count: workoutJSON.steps.length,
        total_distance: workoutJSON.totalDistance,
        estimated_duration: workoutJSON.estimatedDuration,
        generation_time_ms: generationTime,
        model_used: model,
        user_question_length: body.userQuestion.length,
        language: body.language,
        attempts: attempts,
      },
    })
    await posthog.shutdown()

    console.log(`✅ Workout generated successfully in ${generationTime}ms`)

    return c.json({
      workout: workoutJSON,
      metadata: {
        generationTimeMs: generationTime,
        modelUsed: model,
        attempts: attempts,
      },
    })
  } catch (error) {
    const generationTime = Date.now() - startTime
    console.error('❌ Workout generation error:', error)

    const userId = c.req.header('X-User-ID') || c.req.header('CF-Connecting-IP') || 'unknown'

    // Track error
    const posthog = createPostHogClient({
      apiKey: c.env.POSTHOG_API_KEY,
      host: c.env.POSTHOG_HOST,
    })
    posthog.capture({
      distinctId: userId,
      event: 'workout_generation_failed',
      properties: {
        error_type: 'generation_error',
        error_message: error instanceof Error ? error.message : String(error),
        generation_time_ms: generationTime,
      },
    })
    await posthog.shutdown()

    return c.json(
      {
        error: 'Workout Generation Failed',
        message: error instanceof Error ? error.message : 'Unknown error occurred',
        details: String(error),
      },
      500
    )
  }
})

export default app
