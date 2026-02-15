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

  const system = `You are an expert running coach analyzing workout data. Generate concise, quantitative summaries focused on trends and actionable patterns.

**LANGUAGE: Respond 100% in ${langName}. Zero English words in non-English responses. Translate ALL running terms (no "pacing", "splits", "cross-training", "overstriding", "drills", "HR", "HRV", "GCT" etc.).**
**DATA INTEGRITY: ONLY reference metrics explicitly present in the workout data below. NEVER invent, estimate, or fabricate any value (VO2 Max, cadence, power, etc.) that is not explicitly provided. If a metric is absent, skip it entirely.**

This is a PARTIAL batch summary that will be combined with other batches later. Focus on QUANTITATIVE facts and TRENDS, not generic observations.
${profile ? `\n${buildHealthProfileContext(profile)}` : ''}`

  let user = `Analyze these ${workouts.length} workouts. Prioritize quantitative trends over generic observations:

1. **Statistics**: date range, total workouts/distance/duration, pace range (fastest to slowest)
2. **Pace Trend**: Is pace improving, stable, or declining across this batch? Quantify the change
3. **HR Efficiency**: At similar paces, is HR trending lower (improvement) or higher (fatigue)?
4. **Volume Pattern**: Distance per workout trend, longest vs shortest run, rest day frequency
5. **Technical Metrics**: Average cadence, stride, GCT, VO2 max if available — note any trends
6. **Concerns**: Volume spikes >10%/week, too many consecutive hard sessions, cadence drops

Use bullet points with specific numbers. Skip sections where no relevant data exists.

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

  let system = `You are an expert running coach consolidating partial training summaries into ONE comprehensive athlete profile.

**LANGUAGE: Respond 100% in ${langName}. Zero English words in non-English responses. Translate ALL running terms.**
**DATA INTEGRITY: ONLY reference data from the provided summaries. NEVER invent, estimate, or fabricate any metric value. If a metric was not mentioned in any batch summary, do NOT include it in the consolidated profile.**

This summary will be used as long-term context for future coaching conversations. It must be a complete athlete profile that enables personalized coaching. Be detailed, quantitative, and specific.`

  if (profile) {
    system += `\n\n${buildHealthProfileContext(profile)}`
    system += `\nUse this profile to calibrate training zones, recovery expectations, and physiological baselines.`
  }

  let user = `Consolidate these ${batchSummaries.length} batch summaries (oldest → most recent) into ONE comprehensive athlete profile:

1. **PERFORMANCE TRAJECTORY**: Pace evolution over time (specific numbers), best performances, current fitness level estimate
2. **TRAINING IDENTITY**: Typical weekly volume/frequency, preferred distances, training variety (easy/hard ratio), consistency score
3. **PHYSIOLOGICAL PROFILE**: Typical HR ranges at different paces, cadence baseline, VO2 max trend, biomechanics baseline (GCT, stride, asymmetry)
4. **STRENGTHS**: What this runner does well (backed by data — e.g., "consistent 175 spm cadence", "good negative split tendency")
5. **AREAS TO DEVELOP**: Specific weaknesses with quantified gaps (e.g., "GCT averaging 285ms vs optimal 220-250ms", "no runs >10km in dataset")
6. **RISK FACTORS**: Injury indicators, overtraining patterns, recovery deficits observed
7. **KEY NUMBERS**: Total distance/time, PR paces, average metrics across all workouts

Focus on patterns that persist across batches. Short-term fluctuations matter less than long-term trends.

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

    return data.choices[0]?.message?.content || ''
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
