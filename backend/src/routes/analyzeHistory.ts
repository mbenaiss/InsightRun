import type { Context } from 'hono'
import { Hono } from 'hono'
import { captureLLMEvent, createPostHogClient } from '../posthog'
import type { QuotaCheck } from '../quota'
import type {
  BatchAnalysisResponse,
  ConsolidateResponse,
  HealthProfileData,
  WorkoutData,
} from '../types'
import { batchAnalysisRequestSchema, consolidateRequestSchema } from '../types'
import { estimateTokenCount, truncateToTokenLimit, validateTokenCount } from '../utils'
import { RequestType, selectModel, afterModelUsage } from '../modelRouter'

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

// Helper to format duration
function formatDuration(seconds: number): string {
  const hours = Math.floor(seconds / 3600)
  const minutes = Math.floor((seconds % 3600) / 60)
  if (hours > 0) {
    return `${hours}h ${minutes.toString().padStart(2, '0')}m`
  }
  return `${minutes}m`
}

// Helper to format distance
function formatDistance(meters: number): string {
  return `${(meters / 1000).toFixed(2)} km`
}

// Helper to format pace
function formatPace(pace: number): string {
  const minutes = Math.floor(pace)
  const seconds = Math.floor((pace - minutes) * 60)
  return `${minutes}'${seconds.toString().padStart(2, '0')}"/km`
}

// Helper to get language name
function getLanguageName(langCode: string): string {
  const languages: Record<string, string> = {
    fr: 'French',
    en: 'English',
    es: 'Spanish',
    de: 'German',
    it: 'Italian',
    pt: 'Portuguese',
    nl: 'Dutch',
    ja: 'Japanese',
    zh: 'Chinese',
    ko: 'Korean',
    ar: 'Arabic',
  }
  return languages[langCode.toLowerCase()] || 'English'
}

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
): string {
  let prompt = `You are an expert running coach analyzing a batch of ${workouts.length} workouts.

CRITICAL: Generate a CONCISE summary under 800 tokens (strict limit: 1000 tokens).
This is a PARTIAL summary that will be combined with other batches later.

**IMPORTANT: You MUST respond in ${getLanguageName(language)} language.**

`

  if (profile) {
    prompt += `\n${buildHealthProfileContext(profile)}\n\n`
  }

  prompt += `Your task: Create a compact summary focusing on:

1. **Key Statistics** (100 tokens):
   - Date range covered
   - Total workouts, distance, duration
   - Average pace, speed, HR (if available)

2. **Performance Highlights** (200 tokens):
   - Best performances (fastest pace, longest distance)
   - Notable improvements or declines
   - Consistency patterns

3. **Physiological Insights** (200 tokens):
   - HR trends (zones, efficiency)
   - Cadence, VO2 max patterns (if available)
   - Biomechanics observations (GCT, vertical oscillation if available)

4. **Training Patterns** (200 tokens):
   - Frequency, volume progression
   - Hard/easy distribution
   - Recovery patterns observed

5. **Concerns** (100 tokens):
   - Injury risks detected (volume spikes, inadequate recovery)
   - Overtraining signals
   - Technical issues

Keep it FACTUAL and DATA-DRIVEN. Use bullet points. Be concise.

---

# Workouts (${workouts.length} total)

`

  for (let i = 0; i < workouts.length; i++) {
    const w = workouts[i]
    prompt += `\n${i + 1}. ${w.date} | ${formatDuration(w.duration)} | ${formatDistance(w.distance)}`

    if (w.pace) {
      prompt += ` | Pace: ${formatPace(w.pace)}`
    }

    if (w.heartRate?.avg) {
      prompt += ` | HR: ${Math.round(w.heartRate.avg)} bpm`
    }

    if (w.cadence) {
      prompt += ` | Cadence: ${Math.round(w.cadence)} spm`
    }

    if (w.vo2Max) {
      prompt += ` | VO2: ${w.vo2Max.toFixed(1)}`
    }

    prompt += `\n`
  }

  prompt += `\n\nGenerate the concise batch summary now (target: 800 tokens, max: 1000 tokens).`

  return prompt
}

// Build consolidation prompt (for all batch summaries)
function buildConsolidationPrompt(
  batchSummaries: string[],
  language: string,
  profile?: HealthProfileData
): string {
  let prompt = `You are an expert running coach consolidating ${batchSummaries.length} partial training summaries into ONE comprehensive analysis.

CRITICAL: Generate a DETAILED final summary under 2500 tokens (strict limit: 3000 tokens).
This will be used as context for future coaching conversations.

**IMPORTANT: You MUST respond in ${getLanguageName(language)} language.**

`

  // Add runner profile context if available
  if (profile) {
    prompt += `${buildHealthProfileContext(profile)}\n`
    prompt += `Use this runner profile to calibrate training load, recovery expectations, and physiological baselines when consolidating the summaries.\n\n`
  }

  prompt += `Your task: Create a comprehensive summary with these sections:

1. **OVERALL PERFORMANCE TRENDS** (400 tokens):
   - Pace progression over time
   - Volume progression (km/week)
   - Speed evolution
   - Heart rate efficiency trends
   - Best performances and PRs

2. **PHYSIOLOGICAL PROFILE** (500 tokens):
   - HR zones distribution
   - Aerobic base strength
   - Cardiovascular efficiency
   - Running biomechanics baseline (cadence, GCT, etc.)
   - VO2 max trends (if available)

3. **TRAINING PATTERNS** (400 tokens):
   - Frequency and consistency
   - Optimal training volume
   - Hard/easy distribution
   - Long run patterns
   - Recovery patterns

4. **STRENGTHS & ACHIEVEMENTS** (300 tokens):
   - Top personal records
   - Most consistent periods
   - Performance highlights
   - Technical strengths

5. **WEAKNESSES & RISKS** (300 tokens):
   - Injury risk indicators
   - Overtraining signals
   - Technical weaknesses
   - Recovery deficits

6. **STATISTICAL BASELINE** (400 tokens):
   - Total distance, time, workouts
   - Average pace, speed, HR, cadence
   - Intensity distribution (easy/moderate/hard %)
   - Consistency metrics

Be FACTUAL, QUANTITATIVE, and ACTIONABLE. Use specific numbers and trends.

---

# Batch Summaries to Consolidate

`

  for (let i = 0; i < batchSummaries.length; i++) {
    prompt += `\n## Batch ${i + 1}\n\n${batchSummaries[i]}\n\n---\n`
  }

  prompt += `\n\nGenerate the comprehensive consolidated summary now (target: 2500 tokens, max: 3000 tokens).`

  return prompt
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

    const { workouts, batchIndex, language, requestType, model: manualModel } = validationResult.data

    // Get user ID for quota management
    const userId = c.req.header('X-User-ID') || c.req.header('CF-Connecting-IP') || 'unknown'

    // Determine which model to use
    let finalModel: string
    const modelType = requestType || RequestType.BATCH_PROCESSING // Default to BATCH_PROCESSING

    if (Object.values(RequestType).includes(modelType as RequestType)) {
      const selection = await selectModel(
        modelType as RequestType,
        c.env.RATE_LIMITER,
        userId
      )
      finalModel = selection.model.modelId
      console.log(
        `📦 Batch analysis requested: batch ${batchIndex}, ${workouts.length} workouts, type: ${modelType}, model: ${selection.model.displayName}, language: ${language}`
      )
    } else if (manualModel) {
      finalModel = manualModel
      console.log(
        `📦 Batch analysis requested: batch ${batchIndex}, ${workouts.length} workouts, manual model: ${finalModel}, language: ${language}`
      )
    } else {
      // Default fallback
      finalModel = 'google/gemini-2.5-flash-lite'
      console.log(
        `📦 Batch analysis requested: batch ${batchIndex}, ${workouts.length} workouts, default model: ${finalModel}, language: ${language}`
      )
    }

    // Build batch analysis prompt
    const systemPrompt = ''
    const prompt = buildBatchAnalysisPrompt(workouts, undefined, language)

    // Call OpenRouter with batch timeout
    let summary = await callOpenRouterNonStreaming(
      c.env.OPENROUTER_API_KEY,
      finalModel,
      systemPrompt,
      prompt,
      MAX_BATCH_TOKENS,
      BATCH_TIMEOUT
    )

    // Increment quota if needed
    if (requestType && Object.values(RequestType).includes(requestType as RequestType)) {
      const selection = await selectModel(requestType as RequestType, c.env.RATE_LIMITER, userId)
      await afterModelUsage(selection.model, c.env.RATE_LIMITER, userId)
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

    const { batchSummaries, totalWorkouts, profile, language, requestType, model: manualModel } = validationResult.data

    // Get user ID for quota management
    const userId = c.req.header('X-User-ID') || c.req.header('CF-Connecting-IP') || 'unknown'

    // Determine which model to use
    let finalModel: string
    const modelType = requestType || RequestType.MODERATE // Default to MODERATE for consolidation

    if (Object.values(RequestType).includes(modelType as RequestType)) {
      const selection = await selectModel(
        modelType as RequestType,
        c.env.RATE_LIMITER,
        userId
      )
      finalModel = selection.model.modelId
    } else if (manualModel) {
      finalModel = manualModel
    } else {
      // Default fallback to Haiku for consolidation
      finalModel = 'anthropic/claude-haiku-4.5'
    }

    const profileInfo = profile
      ? `with profile (age: ${profile.age || 'N/A'}, sex: ${profile.sex || 'N/A'})`
      : 'no profile'
    console.log(
      `🔄 Consolidation requested: ${batchSummaries.length} batches, ${totalWorkouts} workouts, ${profileInfo}, type: ${modelType}, model: ${finalModel}, language: ${language}`
    )

    // Build consolidation prompt with optional profile context
    const systemPrompt = ''
    const prompt = buildConsolidationPrompt(batchSummaries, language, profile)

    // Call OpenRouter with consolidation timeout
    let summary = await callOpenRouterNonStreaming(
      c.env.OPENROUTER_API_KEY,
      finalModel,
      systemPrompt,
      prompt,
      MAX_CONSOLIDATE_TOKENS,
      CONSOLIDATE_TIMEOUT
    )

    // Increment quota if needed
    if (requestType && Object.values(RequestType).includes(requestType as RequestType)) {
      const selection = await selectModel(requestType as RequestType, c.env.RATE_LIMITER, userId)
      await afterModelUsage(selection.model, c.env.RATE_LIMITER, userId)
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
