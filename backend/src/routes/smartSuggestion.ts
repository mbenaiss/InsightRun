import { Hono } from 'hono'
import { afterModelUsage, RequestType, selectModelFromRequest } from '../modelRouter'
import { captureLLMEvent, createPostHogClient } from '../posthog'
import type { ChatRequestV2 } from '../types'
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

const app = new Hono<{ Bindings: Bindings; Variables: Variables }>()

const OPENROUTER_API_URL = 'https://openrouter.ai/api/v1/chat/completions'
const MAX_TOKENS = 4000 // Increased for full workout generation
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

  const langName = getLanguageName(language)

  const systemPrompt = `You are an elite running coach AI. Analyze the runner's data and create ONE highly personalized workout.

**LANGUAGE: Respond entirely in ${langName}. Use phase names appropriate for ${langName}.**

RUNNER PROFILE:
- Avg pace: ${avgPaceFormatted} (use this as baseline for pace calculations)
- Recent volume: ${totalDistanceKm}km over ${workouts.length} workouts (${totalDurationMin}min total)
${daysSinceLastWorkout !== null ? `- Days since last run: ${daysSinceLastWorkout}` : ''}
${historicalSummary ? `\nLONG-TERM PATTERN:\n${historicalSummary}` : ''}

LAST ${Math.min(5, workouts.length)} WORKOUTS:
${workouts
  .slice(0, 5)
  .map(
    (w, i) =>
      `${i + 1}. ${new Date(w.date).toLocaleDateString()} - ${(w.distance / 1000).toFixed(1)}km, ${Math.round(w.duration / 60)}min, pace ${w.pace ? `${Math.floor(w.pace)}:${String(Math.round((w.pace % 1) * 60)).padStart(2, '0')}/km` : 'N/A'}${w.heartRate?.avg ? `, HR ${w.heartRate.avg}bpm` : ''}`
  )
  .join('\n')}

INTERNAL ANALYSIS (reason about these, don't output them):
1. Training load trend: increasing/stable/decreasing?
2. Workout variety: all easy runs? need intensity?
3. Recovery status: adequate rest days? signs of fatigue?
4. Next logical step: recovery/endurance/speed/threshold work?

OUTPUT FORMAT (strict):
[Short Workout Title]

- [Phase name]: [duration] at [exact single pace]
- [Phase name]: [duration] at [exact single pace]
...

RULES:
- Title + blank line + phases list. Nothing else.
- Each phase MUST have exact duration (min or km) and ONE exact pace value (e.g., "5:30/km").
- Each pace must be a single fixed value. Never use ranges or progressive paces.
- Calculate paces relative to runner's ${avgPaceFormatted} baseline:
  * Easy/Recovery: +15-30 sec/km
  * Endurance: +0-15 sec/km
  * Tempo: -10 to -20 sec/km
  * Speed intervals: -30 to -45 sec/km
- Adapt to runner's current fitness, fatigue, and recent training.
- Total workout: 40-90 minutes based on runner's recent volume.
- The user will edit this before generating the structured workout.`

  const userPrompt = `Based on my recent training history, suggest a detailed workout for my next run.`

  return { system: systemPrompt, user: userPrompt }
}

async function callModelForSuggestion(
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

  return (data.choices[0]?.message?.content || '').trim()
}

// POST /api/workout/smart-suggestion
app.post('/', async (c) => {
  const startTime = Date.now()

  try {
    const body = (await c.req.json()) as ChatRequestV2

    // Validate request
    if (!body.promptType || !body.language || !body.data) {
      return c.json(
        {
          error: 'Bad Request',
          message: 'Missing required fields: promptType, language, data',
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
    const ip = c.req.header('CF-Connecting-IP') || 'unknown'
    const traceId = crypto.randomUUID()

    // Select model using helper
    const { modelId: finalModel, modelConfig } = await selectModelFromRequest(
      body.requestType,
      body.model,
      c.env.RATE_LIMITER,
      userId,
      RequestType.SMART_SUGGESTION
    )

    console.log(
      `✨ Generating smart suggestion with ${finalModel} for user ${userId} (${body.data.recentWorkouts.workouts.length} recent workouts)`
    )

    // Build prompt (specific to smart suggestion)
    const { system: systemPrompt, user: userPrompt } = buildSmartSuggestionPrompt(body)

    // Call selected model
    const suggestion = await callModelForSuggestion(
      c.env.OPENROUTER_API_KEY,
      systemPrompt,
      userPrompt,
      finalModel
    )

    const generationTime = Date.now() - startTime
    const latency = generationTime / 1000

    // Increment quota if model requires it
    if (modelConfig) {
      await afterModelUsage(modelConfig, c.env.RATE_LIMITER, userId)
    }

    console.log(`✅ Smart suggestion generated in ${generationTime}ms (${suggestion.length} chars)`)

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
            const outputTokenCount = estimateTokenCount(suggestion)
            await captureLLMEvent(posthog, userId, traceId, {
              model: finalModel,
              input: userPrompt,
              systemPrompt,
              output: suggestion,
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

    return c.json({
      suggestion: suggestion,
    })
  } catch (error) {
    console.error('Smart suggestion error:', error)

    return c.json(
      {
        error: 'Smart Suggestion Failed',
        message: error instanceof Error ? error.message : 'Unknown error occurred',
      },
      500
    )
  }
})

export default app
