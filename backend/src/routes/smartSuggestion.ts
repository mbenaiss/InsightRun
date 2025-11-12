import { Hono } from 'hono'
import { createPostHogClient } from '../posthog'
import type { ChatRequestV2 } from '../types'

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

const app = new Hono<{ Bindings: Bindings; Variables: Variables }>()

const OPENROUTER_API_URL = 'https://openrouter.ai/api/v1/chat/completions'
const MAX_TOKENS = 1000 // Allow detailed suggestions
const AI_TEMPERATURE = 0.7

function buildSmartSuggestionPrompt(payload: ChatRequestV2): { system: string; user: string } {
  const { data, language } = payload
  const { recentWorkouts, historicalSummary } = data

  if (!recentWorkouts) {
    throw new Error('recentWorkouts data is required for smart suggestions')
  }

  const { workouts, totalDistance, totalDuration, avgPace } = recentWorkouts

  // Calculate stats
  const totalDistanceKm = (totalDistance / 1000).toFixed(1)
  const totalDurationMin = Math.round(totalDuration / 60)
  const avgPaceFormatted = avgPace
    ? `${Math.floor(avgPace)}:${String(Math.round((avgPace % 1) * 60)).padStart(2, '0')}/km`
    : 'N/A'

  // Get recent workout dates
  const sortedWorkouts = [...workouts].sort(
    (a, b) => new Date(b.date).getTime() - new Date(a.date).getTime()
  )
  const lastWorkoutDate = sortedWorkouts[0]?.date
  const daysSinceLastWorkout = lastWorkoutDate
    ? Math.floor((Date.now() - new Date(lastWorkoutDate).getTime()) / (1000 * 60 * 60 * 24))
    : null

  const systemPrompt = `You are an elite running coach AI. Analyze the runner's data deeply and create ONE highly personalized workout.

RUNNER PROFILE:
- Avg pace: ${avgPaceFormatted} (use this as baseline)
- Recent volume: ${totalDistanceKm}km over ${workouts.length} workouts (${totalDurationMin}min total)
- Days since last run: ${daysSinceLastWorkout !== null ? daysSinceLastWorkout : 'unknown'}
${historicalSummary ? `\nLONG-TERM PATTERN:\n${historicalSummary}` : ''}

LAST ${Math.min(5, workouts.length)} WORKOUTS (analyze progression/fatigue):
${workouts
  .slice(0, 5)
  .map(
    (w, i) =>
      `${i + 1}. ${new Date(w.date).toLocaleDateString()} - ${(w.distance / 1000).toFixed(1)}km, ${Math.round(w.duration / 60)}min, pace ${w.pace ? `${Math.floor(w.pace)}:${String(Math.round((w.pace % 1) * 60)).padStart(2, '0')}/km` : 'N/A'}${w.heartRate?.avg ? `, HR ${w.heartRate.avg}bpm` : ''}`
  )
  .join('\n')}

ANALYSIS FRAMEWORK (think, don't output):
1. Training load trend: increasing/stable/decreasing?
2. Workout variety: all easy runs? need intensity?
3. Recovery status: adequate rest days? signs of fatigue?
4. Next logical step: recovery/endurance/speed/threshold work?

OUTPUT FORMAT (strict):
[Short Workout Title]

- [Phase]: [duration] at [exact pace]
- [Phase]: [duration] at [exact pace]
...

EXAMPLE:
"Threshold Development Run

- Warm-up: 10 min at 6:00/km
- Tempo 1: 12 min at 5:30/km
- Recovery: 3 min at 6:15/km
- Tempo 2: 10 min at 5:25/km
- Cool-down: 10 min at 6:00/km"

STRICT RULES:
- Title + blocks ONLY (NO explanations, NO descriptions, NO markdown)
- Each block = ONE exact pace (e.g., "8 min at 5:42/km")
- NO ranges/progressive (FORBIDDEN: "5:15→4:30/km")
- Calculate paces from runner's ${avgPaceFormatted} avg:
  * Easy: +15-30 sec/km slower
  * Tempo: -10 to -20 sec/km faster
  * Speed: -30 to -45 sec/km faster
- Adapt blocks to runner's current fitness (use actual data)
- NO generic tips (hydration/monitoring/equipment/purpose)
- Language: ${language}

OUTPUT: Title + blank line + blocks. NOTHING ELSE.`

  const userPrompt = `Based on my recent training history, suggest a detailed workout for my next run.`

  return { system: systemPrompt, user: userPrompt }
}

async function callGrokForSuggestion(
  apiKey: string,
  systemPrompt: string,
  userPrompt: string
): Promise<string> {
  const requestBody = {
    model: 'x-ai/grok-4-fast', // xAI Grok 4 Fast model
    messages: [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: userPrompt },
    ],
    max_tokens: MAX_TOKENS,
    temperature: AI_TEMPERATURE,
    stream: false,
  }

  const response = await fetch(OPENROUTER_API_URL, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'HTTP-Referer': 'https://insightrun.ai',
      'X-Title': 'InsightRun Smart Suggestion',
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

  return data.choices[0].message.content.trim()
}

// POST /api/workout/smart-suggestion
app.post('/', async (c) => {
  const startTime = Date.now()

  try {
    const body = (await c.req.json()) as ChatRequestV2

    // Validate request (same as /api/chat/v2)
    if (!body.promptType || !body.model || !body.language || !body.data) {
      return c.json(
        {
          error: 'Bad Request',
          message: 'Missing required fields: promptType, model, language, data',
        },
        400
      )
    }

    if (!body.data.recentWorkouts) {
      return c.json(
        {
          error: 'Bad Request',
          message: 'recentWorkouts data is required for smart suggestions',
        },
        400
      )
    }

    // Get user ID for analytics
    const userId = c.req.header('X-User-ID') || c.req.header('CF-Connecting-IP') || 'unknown'

    console.log(
      `✨ Generating smart suggestion for user ${userId} (${body.data.recentWorkouts.workouts.length} recent workouts)`
    )

    // Build prompt (specific to smart suggestion)
    const { system: systemPrompt, user: userPrompt } = buildSmartSuggestionPrompt(body)

    // Call Grok (same model as other endpoints)
    const suggestion = await callGrokForSuggestion(
      c.env.OPENROUTER_API_KEY,
      systemPrompt,
      userPrompt
    )

    const generationTime = Date.now() - startTime

    console.log(`✅ Smart suggestion generated in ${generationTime}ms (${suggestion.length} chars)`)

    // Track analytics
    const posthog = createPostHogClient({
      apiKey: c.env.POSTHOG_API_KEY,
      host: c.env.POSTHOG_HOST,
    })
    posthog.capture({
      distinctId: userId,
      event: 'smart_suggestion_generated',
      properties: {
        workout_count: body.data.recentWorkouts.workouts.length,
        total_distance: body.data.recentWorkouts.totalDistance,
        avg_pace: body.data.recentWorkouts.avgPace,
        has_historical_summary: !!body.data.historicalSummary,
        suggestion_length: suggestion.length,
        generation_time_ms: generationTime,
        language: body.language,
        model_used: body.model,
      },
    })
    await posthog.shutdown()

    return c.json({
      suggestion: suggestion,
    })
  } catch (error) {
    const generationTime = Date.now() - startTime
    console.error('❌ Smart suggestion error:', error)

    const userId = c.req.header('X-User-ID') || c.req.header('CF-Connecting-IP') || 'unknown'

    // Track error
    const posthog = createPostHogClient({
      apiKey: c.env.POSTHOG_API_KEY,
      host: c.env.POSTHOG_HOST,
    })
    posthog.capture({
      distinctId: userId,
      event: 'smart_suggestion_failed',
      properties: {
        error_type: 'generation_error',
        error_message: error instanceof Error ? error.message : String(error),
        generation_time_ms: generationTime,
      },
    })
    await posthog.shutdown()

    return c.json(
      {
        error: 'Smart Suggestion Failed',
        message: error instanceof Error ? error.message : 'Unknown error occurred',
        details: String(error),
      },
      500
    )
  }
})

export default app
