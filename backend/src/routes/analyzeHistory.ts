import type { Context } from 'hono'
import { Hono } from 'hono'
import { afterModelUsage, RequestType, selectModelFromRequest } from '../modelRouter'
import { captureLLMEvent, createPostHogClient } from '../posthog'
import type { QuotaCheck } from '../quota'
import type {
  BatchAnalysisResponse,
  ConsolidateResponse,
  HealthProfileData,
  WorkoutData,
} from '../types'
import { batchAnalysisRequestSchema, consolidateRequestSchema } from '../types'
import {
  estimateTokenCount,
  formatDistance,
  formatDuration,
  formatPace,
  getLanguageName,
  truncateToTokenLimit,
  validateTokenCount,
} from '../utils'

type Bindings = {
  OPENROUTER_API_KEY: string
  APP_SECRET: string
  RATE_LIMITER: KVNamespace
  POSTHOG_API_KEY: string
  POSTHOG_HOST: string
}

type Variables = {
  rateLimitKey: string
  quotaCheck: QuotaCheck
}

const OPENROUTER_API_URL = 'https://openrouter.ai/api/v1/chat/completions'
const AI_TEMPERATURE = 0.3 // Lower temperature for more consistent summaries
const BATCH_TIMEOUT = 30000 // 30s timeout for batch analysis
const CONSOLIDATE_TIMEOUT = 60000 // 60s timeout for consolidation
const MAX_BATCH_TOKENS = 1000 // Max tokens for batch summary (concise)
const MAX_CONSOLIDATE_TOKENS = 3000 // Max tokens for final consolidated summary

// Helper to build health profile context
function buildHealthProfileContext(profile: HealthProfileData): string {
  let context = 'Runner Profile:\n'

  if (profile.age) {
    context += `- Age: ${profile.age} years\n`
  }

  if (profile.sex) {
    context += `- Sex: ${profile.sex}\n`
  }

  if (profile.bodyMass) {
    context += `- Weight: ${profile.bodyMass.toFixed(1)} kg\n`
  }

  if (profile.bodyFatPercentage) {
    context += `- Body Fat: ${profile.bodyFatPercentage.toFixed(1)}%\n`
  }

  if (profile.exerciseTime !== undefined) {
    context += `- Today's Exercise Minutes: ${Math.round(profile.exerciseTime)} min\n`
  }

  const crossTraining: string[] = []
  if (profile.cyclingDistance) {
    crossTraining.push(`Cycling (7d): ${(profile.cyclingDistance / 1000).toFixed(1)} km`)
  }
  if (profile.swimmingDistance) {
    crossTraining.push(`Swimming (7d): ${(profile.swimmingDistance / 1000).toFixed(1)} km`)
  }

  if (crossTraining.length > 0) {
    context += `- Cross-Training: ${crossTraining.join(' | ')}\n`
  }

  return context
}

// Build batch analysis prompt (for 50 workouts max)
function buildBatchAnalysisPrompt(
  workouts: WorkoutData[],
  profile: HealthProfileData | undefined,
  language: string
): { system: string; user: string } {
  const langName = getLanguageName(language)

  const system = `You are an expert running coach analyzing workout data. Generate concise, factual summaries.

**LANGUAGE: Respond entirely in ${langName}.**
**DATA INTEGRITY: Only reference metrics present in the data. Never invent values.**

This is a PARTIAL batch summary that will be combined with other batches later. Keep it concise and under 1000 tokens.
${profile ? `\n${buildHealthProfileContext(profile)}` : ''}`

  let user = `Analyze these ${workouts.length} workouts and create a compact summary covering:

1. **Key Statistics**: date range, total workouts/distance/duration, averages
2. **Performance Highlights**: best performances, improvements or declines
3. **Physiological Insights**: HR trends, cadence, VO2 max patterns (if available)
4. **Training Patterns**: frequency, volume progression, hard/easy distribution
5. **Concerns**: injury risks, overtraining signals

Use bullet points. Be factual and data-driven.

# Workouts (${workouts.length} total)
`

  for (let i = 0; i < workouts.length; i++) {
    const w = workouts[i]
    user += `\n${i + 1}. ${w.date} | ${formatDuration(w.duration)} | ${formatDistance(w.distance)}`

    if (w.pace) {
      user += ` | Pace: ${formatPace(w.pace)}`
    }

    if (w.heartRate?.avg) {
      user += ` | HR: ${Math.round(w.heartRate.avg)} bpm`
    }

    if (w.cadence) {
      user += ` | Cadence: ${Math.round(w.cadence)} spm`
    }

    if (w.vo2Max) {
      user += ` | VO2: ${w.vo2Max.toFixed(1)}`
    }
  }

  return { system, user }
}

// Build consolidation prompt (for all batch summaries)
function buildConsolidationPrompt(
  batchSummaries: string[],
  language: string,
  profile?: HealthProfileData
): { system: string; user: string } {
  const langName = getLanguageName(language)

  let system = `You are an expert running coach consolidating partial training summaries into ONE comprehensive analysis.

**LANGUAGE: Respond entirely in ${langName}.**
**DATA INTEGRITY: Only reference data from the provided summaries. Never invent metrics.**

This summary will be used as context for future coaching conversations. Keep it under 3000 tokens but be detailed and quantitative.`

  if (profile) {
    system += `\n\n${buildHealthProfileContext(profile)}`
    system += `\nUse this profile to calibrate training load, recovery expectations, and physiological baselines.`
  }

  let user = `Consolidate these ${batchSummaries.length} batch summaries (ordered from oldest to most recent) into ONE comprehensive analysis with these sections:

1. **OVERALL PERFORMANCE TRENDS**: pace progression, volume progression, HR efficiency, PRs
2. **PHYSIOLOGICAL PROFILE**: HR zones, aerobic base, biomechanics baseline, VO2 max trends
3. **TRAINING PATTERNS**: frequency, consistency, hard/easy distribution, recovery patterns
4. **STRENGTHS & ACHIEVEMENTS**: personal records, consistent periods, technical strengths
5. **WEAKNESSES & RISKS**: injury indicators, overtraining signals, recovery deficits
6. **STATISTICAL BASELINE**: totals, averages, intensity distribution

Be factual, quantitative, and actionable. Use specific numbers.

# Batch Summaries (oldest first)
`

  for (let i = 0; i < batchSummaries.length; i++) {
    user += `\n## Batch ${i + 1}\n\n${batchSummaries[i]}\n\n---\n`
  }

  return { system, user }
}

// Call OpenRouter (non-streaming)
async function callOpenRouterNonStreaming(
  apiKey: string,
  model: string,
  systemPrompt: string,
  prompt: string,
  maxTokens: number,
  timeout: number
): Promise<string> {
  const requestBody = {
    model,
    messages: [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: prompt },
    ],
    max_tokens: maxTokens,
    temperature: AI_TEMPERATURE,
    stream: false,
  }

  const controller = new AbortController()
  const timeoutId = setTimeout(() => controller.abort(), timeout)

  try {
    const response = await fetch(OPENROUTER_API_URL, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'HTTP-Referer': 'https://insightrun.ai',
        'X-Title': 'insightRun.ai',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(requestBody),
      signal: controller.signal,
    })

    clearTimeout(timeoutId)

    if (!response.ok) {
      const errorText = await response.text()
      throw new Error(`OpenRouter API error: ${response.status} - ${errorText}`)
    }

    const data = (await response.json()) as {
      choices: Array<{ message: { content: string } }>
    }

    return data.choices[0].message.content
  } catch (error) {
    clearTimeout(timeoutId)
    if ((error as Error).name === 'AbortError') {
      throw new Error(`Request timeout after ${timeout}ms`)
    }
    throw error
  }
}

const app = new Hono<{ Bindings: Bindings; Variables: Variables }>()

// POST /batch - Analyze a batch of up to 50 workouts
app.post('/batch', async (c: Context<{ Bindings: Bindings; Variables: Variables }>) => {
  const startTime = Date.now()

  try {
    const body = await c.req.json()

    // Validate request with Zod
    const validationResult = batchAnalysisRequestSchema.safeParse(body)

    if (!validationResult.success) {
      const errorMessages = validationResult.error.issues.map((err) => {
        const path = err.path.join('.')
        return `${path}: ${err.message}`
      })

      return c.json(
        {
          error: 'Bad Request',
          message: 'Invalid batch analysis request',
          details: errorMessages,
        },
        400
      )
    }

    const {
      workouts,
      batchIndex,
      language,
      requestType,
      model: manualModel,
    } = validationResult.data

    // Get user ID for quota management
    const userId = c.req.header('X-User-ID') || c.req.header('CF-Connecting-IP') || 'unknown'

    // Select model using helper
    const { modelId: finalModel, modelConfig } = await selectModelFromRequest(
      requestType,
      manualModel,
      c.env.RATE_LIMITER,
      userId,
      RequestType.BATCH_PROCESSING
    )

    console.log(
      `📦 Batch analysis requested: batch ${batchIndex}, ${workouts.length} workouts, model: ${finalModel}, language: ${language}`
    )

    // Build batch analysis prompt
    const { system: systemPrompt, user: prompt } = buildBatchAnalysisPrompt(
      workouts,
      undefined,
      language
    )

    // Call OpenRouter with batch timeout
    let summary = await callOpenRouterNonStreaming(
      c.env.OPENROUTER_API_KEY,
      finalModel,
      systemPrompt,
      prompt,
      MAX_BATCH_TOKENS,
      BATCH_TIMEOUT
    )

    // Increment quota if model requires it
    if (modelConfig) {
      await afterModelUsage(modelConfig, c.env.RATE_LIMITER, userId)
    }

    // Validate and truncate if needed
    const tokenCount = validateTokenCount(summary, MAX_BATCH_TOKENS, 'Batch summary')

    if (tokenCount > MAX_BATCH_TOKENS) {
      console.warn(
        `⚠️ Batch summary exceeds ${MAX_BATCH_TOKENS} tokens (${tokenCount}). Truncating...`
      )
      summary = truncateToTokenLimit(summary, MAX_BATCH_TOKENS - 50) // Leave margin
    }

    const finalTokenCount = estimateTokenCount(summary)
    const latency = (Date.now() - startTime) / 1000

    console.log(
      `✅ Batch summary generated: ${finalTokenCount} tokens, ${workouts.length} workouts, ${latency.toFixed(2)}s`
    )

    // Log to PostHog (optional, async)
    if (c.env.POSTHOG_API_KEY && c.env.POSTHOG_HOST) {
      const userId = c.req.header('X-User-ID') || c.req.header('CF-Connecting-IP') || 'unknown'
      const ip = c.req.header('CF-Connecting-IP') || 'unknown'
      const traceId = crypto.randomUUID()

      const posthog = createPostHogClient({
        apiKey: c.env.POSTHOG_API_KEY,
        host: c.env.POSTHOG_HOST,
      })

      c.executionCtx.waitUntil(
        (async () => {
          try {
            const inputTokenCount = estimateTokenCount(prompt)
            await captureLLMEvent(posthog, userId, traceId, {
              model: finalModel,
              input: `Batch analysis: ${workouts.length} workouts (${inputTokenCount} tokens)`,
              systemPrompt,
              output: summary,
              inputTokens: inputTokenCount,
              outputTokens: finalTokenCount,
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

    const response: BatchAnalysisResponse = {
      batchIndex,
      partialSummary: summary,
      workoutCount: workouts.length,
      tokenCount: finalTokenCount,
    }

    return c.json(response)
  } catch (error) {
    console.error('Batch analysis error:', error)

    return c.json(
      {
        error: 'Internal Server Error',
        message: error instanceof Error ? error.message : 'Unknown error',
      },
      500
    )
  }
})

// POST /consolidate - Consolidate all batch summaries into one final summary
app.post('/consolidate', async (c: Context<{ Bindings: Bindings; Variables: Variables }>) => {
  const startTime = Date.now()

  try {
    const body = await c.req.json()

    // Validate request with Zod
    const validationResult = consolidateRequestSchema.safeParse(body)

    if (!validationResult.success) {
      const errorMessages = validationResult.error.issues.map((err) => {
        const path = err.path.join('.')
        return `${path}: ${err.message}`
      })

      return c.json(
        {
          error: 'Bad Request',
          message: 'Invalid consolidation request',
          details: errorMessages,
        },
        400
      )
    }

    const {
      batchSummaries,
      totalWorkouts,
      profile,
      language,
      requestType,
      model: manualModel,
    } = validationResult.data

    // Get user ID for quota management
    const userId = c.req.header('X-User-ID') || c.req.header('CF-Connecting-IP') || 'unknown'

    // Select model using helper
    const { modelId: finalModel, modelConfig } = await selectModelFromRequest(
      requestType,
      manualModel,
      c.env.RATE_LIMITER,
      userId,
      RequestType.MODERATE
    )

    const profileInfo = profile
      ? `with profile (age: ${profile.age || 'N/A'}, sex: ${profile.sex || 'N/A'})`
      : 'no profile'
    console.log(
      `🔄 Consolidation requested: ${batchSummaries.length} batches, ${totalWorkouts} workouts, ${profileInfo}, model: ${finalModel}, language: ${language}`
    )

    // Build consolidation prompt with optional profile context
    const { system: systemPrompt, user: prompt } = buildConsolidationPrompt(
      batchSummaries,
      language,
      profile
    )

    // Call OpenRouter with consolidation timeout
    let summary = await callOpenRouterNonStreaming(
      c.env.OPENROUTER_API_KEY,
      finalModel,
      systemPrompt,
      prompt,
      MAX_CONSOLIDATE_TOKENS,
      CONSOLIDATE_TIMEOUT
    )

    // Increment quota if model requires it
    if (modelConfig) {
      await afterModelUsage(modelConfig, c.env.RATE_LIMITER, userId)
    }

    // Validate and truncate if needed
    const tokenCount = validateTokenCount(summary, MAX_CONSOLIDATE_TOKENS, 'Consolidated summary')

    if (tokenCount > MAX_CONSOLIDATE_TOKENS) {
      console.warn(
        `⚠️ Consolidated summary exceeds ${MAX_CONSOLIDATE_TOKENS} tokens (${tokenCount}). Truncating...`
      )
      summary = truncateToTokenLimit(summary, MAX_CONSOLIDATE_TOKENS - 50) // Leave margin
    }

    const finalTokenCount = estimateTokenCount(summary)
    const latency = (Date.now() - startTime) / 1000

    console.log(
      `✅ Consolidated summary generated: ${finalTokenCount} tokens, ${batchSummaries.length} batches, ${latency.toFixed(2)}s`
    )

    // Log to PostHog (optional, async)
    if (c.env.POSTHOG_API_KEY && c.env.POSTHOG_HOST) {
      const userId = c.req.header('X-User-ID') || c.req.header('CF-Connecting-IP') || 'unknown'
      const ip = c.req.header('CF-Connecting-IP') || 'unknown'
      const traceId = crypto.randomUUID()

      const posthog = createPostHogClient({
        apiKey: c.env.POSTHOG_API_KEY,
        host: c.env.POSTHOG_HOST,
      })

      c.executionCtx.waitUntil(
        (async () => {
          try {
            const inputTokenCount = estimateTokenCount(prompt)
            await captureLLMEvent(posthog, userId, traceId, {
              model: finalModel,
              input: `Consolidation: ${batchSummaries.length} batches (${inputTokenCount} tokens)`,
              systemPrompt,
              output: summary,
              inputTokens: inputTokenCount,
              outputTokens: finalTokenCount,
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

    const response: ConsolidateResponse = {
      summary,
      workoutCount: totalWorkouts,
      tokenCount: finalTokenCount,
    }

    return c.json(response)
  } catch (error) {
    console.error('Consolidation error:', error)

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
