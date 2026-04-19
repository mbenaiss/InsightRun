import type { Context } from 'hono'
import { Hono } from 'hono'
import { cors } from 'hono/cors'
import { logger } from 'hono/logger'
import { streamSSE } from 'hono/streaming'
import {
  afterModelUsage,
  deleteModel,
  getCurrentModelConfig,
  type ModelConfig,
  RequestType,
  selectModel,
  selectModelFromRequest,
  setModelMapping,
  upsertModel,
} from './modelRouter'
import { captureLLMEvent, createPostHogClient } from './posthog'
import { buildPrompt } from './prompts'
import type { QuotaCheck, QuotaConfig } from './quota'
import {
  checkQuota,
  getDefaultQuotaConfig,
  getQuotaConfigFromKV,
  getQuotaHeaders,
  incrementQuota,
  setQuotaConfig,
} from './quota'
import adaptTrainingPlanRoutes from './routes/adaptTrainingPlan'
import agentChatRoutes from './routes/agentChat'
import analyzeHistoryRoutes from './routes/analyzeHistory'
import dailyReadinessRoutes from './routes/dailyReadiness'
import generateTrainingPlanRoutes from './routes/generateTrainingPlan'
import generateWorkoutRoutes from './routes/generateWorkout'
import smartSuggestionRoutes from './routes/smartSuggestion'
import stravaRoutes from './routes/strava'
import type { ChatRequestV2 } from './types'

type Bindings = {
  OPENROUTER_API_KEY: string
  APP_SECRET: string
  ADMIN_SECRET: string // Admin API authentication
  RATE_LIMITER: KVNamespace
  POSTHOG_API_KEY: string
  POSTHOG_HOST: string
  // Strava integration
  STRAVA_CLIENT_ID: string
  STRAVA_CLIENT_SECRET: string
  STRAVA_WEBHOOK_VERIFY_TOKEN: string
  STRAVA_TOKENS: KVNamespace
  STRAVA_CACHE: D1Database
}

type Variables = {
  rateLimitKey: string
  quotaCheck: QuotaCheck
  quotaConfig: QuotaConfig
}

interface ChatRequest {
  prompt: string
  systemPrompt: string
  model?: string
  requestType?: string
  stream?: boolean // Optional: default true for backward compatibility
}

interface OpenRouterMessage {
  role: 'system' | 'user' | 'assistant'
  content: string
}

interface OpenRouterRequest {
  model: string
  messages: OpenRouterMessage[]
  max_tokens: number
  temperature: number
  stream: boolean
}

interface StreamChunk {
  choices?: Array<{
    delta?: {
      content?: string
    }
  }>
  usage?: {
    prompt_tokens?: number
    completion_tokens?: number
    total_tokens?: number
  }
}

const MAX_PROMPT_LENGTH = 5000 // Increased to support classification prompts with long user questions
const MAX_TOKENS = 2000
const AI_TEMPERATURE = 0.7
const OPENROUTER_API_URL = 'https://openrouter.ai/api/v1/chat/completions'
type AppContext = Context<{ Bindings: Bindings; Variables: Variables }>

function validateAppAuth(c: AppContext): boolean {
  if (!c.env.APP_SECRET) {
    console.error('⚠️ APP_SECRET not configured')
    return false
  }
  const appKey = c.req.header('X-App-Key')
  return appKey === c.env.APP_SECRET
}

function validateAdminAuth(c: AppContext): boolean {
  const adminKey = c.req.header('X-Admin-Key')
  // Admin secret is required - no default fallback for security
  if (!c.env.ADMIN_SECRET) {
    console.error('⚠️ ADMIN_SECRET not configured')
    return false
  }
  return adminKey === c.env.ADMIN_SECRET
}

// KV keys for admin configuration
const KV_FEATURE_FLAGS_KEY = 'admin:config:features'
const KV_BLOCKED_USER_PREFIX = 'admin:blocked:user:'
const KV_BLOCKED_IP_PREFIX = 'admin:blocked:ip:'

// Default feature flags (only used if KV is empty)
const DEFAULT_FEATURE_FLAGS: Record<string, boolean> = {
  strava_enabled: false, // Disabled until Strava API validation
}

async function getFeatureFlags(kv: KVNamespace): Promise<Record<string, boolean>> {
  try {
    const configJson = await kv.get(KV_FEATURE_FLAGS_KEY)
    if (configJson) {
      const config = JSON.parse(configJson) as Record<string, boolean>
      return { ...DEFAULT_FEATURE_FLAGS, ...config }
    }
  } catch (error) {
    console.warn('Failed to read feature flags from KV, using defaults', error)
  }
  return DEFAULT_FEATURE_FLAGS
}

async function setFeatureFlags(kv: KVNamespace, flags: Record<string, boolean>): Promise<void> {
  const currentFlags = await getFeatureFlags(kv)
  const newFlags = { ...currentFlags, ...flags }
  await kv.put(KV_FEATURE_FLAGS_KEY, JSON.stringify(newFlags))
}

interface BlockedEntity {
  reason: string
  blocked_at: number
  blocked_by: string
  expires_at: number | null
}

async function isUserBlocked(kv: KVNamespace, userId: string): Promise<BlockedEntity | null> {
  try {
    const blockJson = await kv.get(`${KV_BLOCKED_USER_PREFIX}${userId}`)
    if (blockJson) {
      const block = JSON.parse(blockJson) as BlockedEntity
      // Check if block has expired
      if (block.expires_at && Date.now() > block.expires_at) {
        await kv.delete(`${KV_BLOCKED_USER_PREFIX}${userId}`)
        return null
      }
      return block
    }
  } catch (error) {
    console.warn('⚠️ Failed to check user block status', error)
  }
  return null
}

async function isIPBlocked(kv: KVNamespace, ip: string): Promise<BlockedEntity | null> {
  try {
    const blockJson = await kv.get(`${KV_BLOCKED_IP_PREFIX}${ip}`)
    if (blockJson) {
      const block = JSON.parse(blockJson) as BlockedEntity
      // Check if block has expired
      if (block.expires_at && Date.now() > block.expires_at) {
        await kv.delete(`${KV_BLOCKED_IP_PREFIX}${ip}`)
        return null
      }
      return block
    }
  } catch (error) {
    console.warn('⚠️ Failed to check IP block status', error)
  }
  return null
}

function validateChatRequest(body: unknown): body is ChatRequest {
  const req = body as ChatRequest
  // Either model or requestType must be provided
  return !!(req.prompt && req.systemPrompt && (req.model || req.requestType))
}

function validateChatRequestV2(body: unknown): body is ChatRequestV2 {
  const req = body as ChatRequestV2
  // Either requestType or model must be provided (requestType takes priority)
  return !!(
    req.promptType &&
    (req.requestType || req.model) &&
    req.userQuestion &&
    req.language &&
    req.data
  )
}

async function callOpenRouter(
  apiKey: string,
  model: string,
  systemPrompt: string,
  prompt: string
): Promise<Response> {
  const requestBody: OpenRouterRequest = {
    model,
    messages: [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: prompt },
    ],
    max_tokens: MAX_TOKENS,
    temperature: AI_TEMPERATURE,
    stream: true,
  }

  return fetch(OPENROUTER_API_URL, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'HTTP-Referer': 'https://insightrun.ai',
      'X-Title': 'insightRun.ai',
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(requestBody),
  })
}

const app = new Hono<{ Bindings: Bindings; Variables: Variables }>()

app.use('*', logger())
app.use(
  '*',
  cors({
    origin: '*',
    allowMethods: ['POST', 'GET', 'PUT', 'DELETE', 'OPTIONS'],
    allowHeaders: ['Content-Type', 'Authorization', 'X-App-Key', 'X-User-ID', 'X-Admin-Key'],
    maxAge: 86400,
  })
)

app.use('/api/*', async (c, next) => {
  // Skip rate limiting and blocking for admin routes (they have their own auth)
  const path = new URL(c.req.url).pathname
  if (path.startsWith('/api/admin')) {
    await next()
    return
  }

  // Extract user ID and IP from headers
  const userId = c.req.header('X-User-ID')
  const ip = c.req.header('CF-Connecting-IP') || 'unknown'
  const identifier = userId || ip
  const rateLimitKey = `ratelimit:${identifier}`

  c.set('rateLimitKey', rateLimitKey)

  // Check if user or IP is blocked
  if (userId) {
    const userBlock = await isUserBlocked(c.env.RATE_LIMITER, userId)
    if (userBlock) {
      return c.json(
        {
          error: 'Blocked',
          message: 'Your account has been blocked',
          reason: userBlock.reason,
          blocked_at: userBlock.blocked_at,
          expires_at: userBlock.expires_at,
        },
        403
      )
    }
  }

  const ipBlock = await isIPBlocked(c.env.RATE_LIMITER, ip)
  if (ipBlock) {
    return c.json(
      {
        error: 'Blocked',
        message: 'Your IP has been blocked',
        reason: ipBlock.reason,
        blocked_at: ipBlock.blocked_at,
        expires_at: ipBlock.expires_at,
      },
      403
    )
  }

  // Get quota config from KV (or use defaults)
  const config = await getQuotaConfigFromKV(c.env.RATE_LIMITER)
  c.set('quotaConfig', config)

  // Check both IP and User quotas
  const quotaCheck = await checkQuota(c.env.RATE_LIMITER, ip, userId, config)

  // Store quota check for adding headers to response
  c.set('quotaCheck', quotaCheck)

  // If quota exceeded, return 429 with detailed error
  if (!quotaCheck.allowed) {
    const quotaHeaders = getQuotaHeaders(quotaCheck)
    return c.json(
      {
        error: 'Quota exceeded',
        message: quotaCheck.message,
        restrictedBy: quotaCheck.restrictedBy,
        quotas: {
          ip: {
            limit: quotaCheck.ip.limit,
            remaining: quotaCheck.ip.remaining,
            resetAt: quotaCheck.ip.resetAt,
          },
          ...(quotaCheck.user && {
            user: {
              limit: quotaCheck.user.limit,
              remaining: quotaCheck.user.remaining,
              resetAt: quotaCheck.user.resetAt,
            },
          }),
        },
      },
      429,
      quotaHeaders
    )
  }

  // Process request
  await next()

  // Increment both IP and User quotas after successful request
  await incrementQuota(c.env.RATE_LIMITER, ip, userId, config)

  // Add quota headers to successful responses (if response is a JSON response)
  const quotaHeaders = getQuotaHeaders(quotaCheck)
  for (const [key, value] of Object.entries(quotaHeaders)) {
    c.res.headers.set(key, value)
  }
})

// Auth middleware for /api/analyze-history routes
app.use('/api/analyze-history/*', async (c, next) => {
  if (!validateAppAuth(c)) {
    return c.json({ error: 'Unauthorized', message: 'Invalid app key' }, 401)
  }
  await next()
})

// Auth middleware for /api/generate-training-plan route
app.use('/api/generate-training-plan/*', async (c, next) => {
  if (!validateAppAuth(c)) {
    return c.json({ error: 'Unauthorized', message: 'Invalid app key' }, 401)
  }
  await next()
})

// Auth middleware for /api/adapt-training-plan route
app.use('/api/adapt-training-plan/*', async (c, next) => {
  if (!validateAppAuth(c)) {
    return c.json({ error: 'Unauthorized', message: 'Invalid app key' }, 401)
  }
  await next()
})

// Auth middleware for /api/generate-workout route
app.use('/api/generate-workout/*', async (c, next) => {
  if (!validateAppAuth(c)) {
    return c.json({ error: 'Unauthorized', message: 'Invalid app key' }, 401)
  }
  await next()
})

// Auth middleware for /api/workout/smart-suggestion route
app.use('/api/workout/smart-suggestion/*', async (c, next) => {
  if (!validateAppAuth(c)) {
    return c.json({ error: 'Unauthorized', message: 'Invalid app key' }, 401)
  }
  await next()
})

// Auth middleware for /api/daily-readiness route
app.use('/api/daily-readiness/*', async (c, next) => {
  if (!validateAppAuth(c)) {
    return c.json({ error: 'Unauthorized', message: 'Invalid app key' }, 401)
  }
  await next()
})

// Auth middleware for /api/agent/* routes
app.use('/api/agent/*', async (c, next) => {
  if (!validateAppAuth(c)) {
    return c.json({ error: 'Unauthorized', message: 'Invalid app key' }, 401)
  }
  await next()
})

// Auth middleware for /api/strava/* routes (except webhooks)
app.use('/api/strava/*', async (c, next) => {
  // Skip auth for webhook endpoints (Strava calls them)
  const path = new URL(c.req.url).pathname
  if (path.includes('/webhooks/')) {
    await next()
    return
  }

  // Require X-App-Key for all other Strava endpoints
  if (!validateAppAuth(c)) {
    return c.json({ error: 'Unauthorized', message: 'Invalid app key' }, 401)
  }
  await next()
})

// Mount analyze-history routes
app.route('/api/analyze-history', analyzeHistoryRoutes)

// Mount generate-training-plan route
app.route('/api/generate-training-plan', generateTrainingPlanRoutes)

// Mount adapt-training-plan route
app.route('/api/adapt-training-plan', adaptTrainingPlanRoutes)

// Mount generate-workout route
app.route('/api/generate-workout', generateWorkoutRoutes)

// Mount smart-suggestion route
app.route('/api/workout/smart-suggestion', smartSuggestionRoutes)

// Mount daily-readiness route
app.route('/api/daily-readiness', dailyReadinessRoutes)

// Mount agent chat routes
app.route('/api/agent', agentChatRoutes)

// Mount Strava routes
app.route('/api/strava', stravaRoutes)

app.get('/', (c) => {
  return c.json({
    status: 'ok',
    service: 'InsightRun Backend API',
    version: '1.0.0',
    timestamp: new Date().toISOString(),
  })
})

app.get('/health', (c) => {
  return c.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
  })
})

app.post('/api/chat', async (c) => {
  const startTime = Date.now()

  try {
    if (!validateAppAuth(c)) {
      return c.json({ error: 'Unauthorized', message: 'Invalid app key' }, 401)
    }

    const body = await c.req.json()

    if (!validateChatRequest(body)) {
      return c.json(
        {
          error: 'Bad Request',
          message: 'Missing required fields: prompt, systemPrompt, and (model or requestType)',
        },
        400
      )
    }

    const { prompt, systemPrompt, model, requestType, stream = true } = body

    if (prompt.length > MAX_PROMPT_LENGTH) {
      return c.json(
        {
          error: 'Bad Request',
          message: `Prompt too long (${prompt.length} chars, max ${MAX_PROMPT_LENGTH} characters)`,
        },
        400
      )
    }

    // Get user ID from X-User-ID header (from iOS app) or fallback to IP
    const userId = c.req.header('X-User-ID') || c.req.header('CF-Connecting-IP') || 'unknown'
    const ip = c.req.header('CF-Connecting-IP') || 'unknown'
    const traceId = crypto.randomUUID()

    // Select model using requestType or manual model
    const { modelId: finalModel, modelConfig } = await selectModelFromRequest(
      requestType,
      model,
      c.env.RATE_LIMITER,
      userId,
      RequestType.MODERATE
    )

    // Non-streaming mode (for classification)
    if (!stream) {
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
            { role: 'user', content: prompt },
          ],
          max_tokens: requestType === RequestType.CLASSIFICATION ? 10 : MAX_TOKENS,
          temperature: requestType === RequestType.CLASSIFICATION ? 0.3 : AI_TEMPERATURE,
          stream: false,
        }),
      })

      if (!response.ok) {
        const errorText = await response.text()
        console.error('OpenRouter error:', errorText)
        return c.json(
          {
            error: 'AI Service Error',
            message: 'Failed to get response from AI service',
            details: 'Check server logs for details',
          },
          500
        )
      }

      const data = (await response.json()) as {
        choices: Array<{ message: { content: string } }>
        usage?: {
          prompt_tokens?: number
          completion_tokens?: number
          total_tokens?: number
        }
      }

      const responseText = data.choices[0]?.message?.content || ''

      // Increment quota if model requires it
      if (modelConfig) {
        await afterModelUsage(modelConfig, c.env.RATE_LIMITER, userId)
      }

      // Capture LLM event with all collected data
      const latency = (Date.now() - startTime) / 1000

      if (c.env.POSTHOG_API_KEY && c.env.POSTHOG_HOST) {
        const posthog = createPostHogClient({
          apiKey: c.env.POSTHOG_API_KEY,
          host: c.env.POSTHOG_HOST,
        })

        c.executionCtx.waitUntil(
          (async () => {
            try {
              await captureLLMEvent(posthog, userId, traceId, {
                model: finalModel,
                input: prompt,
                systemPrompt,
                output: responseText,
                inputTokens: data.usage?.prompt_tokens,
                outputTokens: data.usage?.completion_tokens,
                latency,
                cost: data.usage?.total_tokens ? data.usage.total_tokens * 0.000001 : undefined,
                ip,
              })
              await posthog.shutdown()
            } catch (error) {
              console.error('PostHog capture error:', error)
            }
          })()
        )
      }

      return c.json({ response: responseText })
    }

    // Streaming mode (default, existing behavior)
    const openRouterResponse = await callOpenRouter(
      c.env.OPENROUTER_API_KEY,
      finalModel,
      systemPrompt,
      prompt
    )

    if (!openRouterResponse.ok) {
      const errorText = await openRouterResponse.text()
      console.error('OpenRouter error:', errorText)

      return c.json(
        {
          error: 'AI Service Error',
          message: 'Failed to get response from AI service',
          details: errorText,
        },
        500
      )
    }

    // Variables to capture during streaming
    let fullOutput = ''
    let inputTokens: number | undefined
    let outputTokens: number | undefined
    let totalTokens: number | undefined

    return streamSSE(c, async (stream) => {
      const reader = openRouterResponse.body?.getReader()
      if (!reader) {
        throw new Error('No response body')
      }

      const decoder = new TextDecoder()
      let buffer = ''

      try {
        while (true) {
          const { done, value } = await reader.read()
          if (done) break

          buffer += decoder.decode(value, { stream: true })
          const lines = buffer.split('\n')

          // Keep the last incomplete line in buffer
          buffer = lines.pop() || ''

          for (const line of lines) {
            if (line.startsWith('data: ')) {
              const data = line.slice(6).trim()

              if (data === '[DONE]') {
                await stream.writeSSE({
                  data: '[DONE]',
                })

                // Increment quota if model requires it
                if (modelConfig) {
                  await afterModelUsage(modelConfig, c.env.RATE_LIMITER, userId)
                }

                // Capture LLM event with all collected data
                const latency = (Date.now() - startTime) / 1000

                if (c.env.POSTHOG_API_KEY && c.env.POSTHOG_HOST) {
                  const posthog = createPostHogClient({
                    apiKey: c.env.POSTHOG_API_KEY,
                    host: c.env.POSTHOG_HOST,
                  })

                  c.executionCtx.waitUntil(
                    (async () => {
                      try {
                        await captureLLMEvent(posthog, userId, traceId, {
                          model: finalModel,
                          input: prompt,
                          systemPrompt,
                          output: fullOutput,
                          inputTokens,
                          outputTokens,
                          latency,
                          cost: totalTokens ? totalTokens * 0.000001 : undefined, // Rough estimation
                          ip,
                        })
                        await posthog.shutdown()
                      } catch (error) {
                        console.error('PostHog capture error:', error)
                      }
                    })()
                  )
                }

                return
              }

              if (data) {
                try {
                  const json: StreamChunk = JSON.parse(data)
                  const content = json.choices?.[0]?.delta?.content

                  if (content) {
                    fullOutput += content
                    await stream.writeSSE({
                      data: JSON.stringify({ content }),
                    })
                  }

                  // Capture usage data if present
                  if (json.usage) {
                    inputTokens = json.usage.prompt_tokens
                    outputTokens = json.usage.completion_tokens
                    totalTokens = json.usage.total_tokens
                  }
                } catch (parseError) {
                  console.warn('JSON parse error:', parseError, 'Data:', data)
                }
              }
            }
          }
        }
      } catch (error) {
        console.error('Streaming error:', error)
        throw error
      }
    })
  } catch (error) {
    console.error('Chat endpoint error:', error)

    return c.json(
      {
        error: 'Internal Server Error',
        message: error instanceof Error ? error.message : 'Unknown error',
      },
      500
    )
  }
})

app.post('/api/chat/stream', async (c) => {
  const startTime = Date.now()

  try {
    if (!validateAppAuth(c)) {
      return c.json({ error: 'Unauthorized' }, 401)
    }

    const body = await c.req.json()

    if (!validateChatRequest(body)) {
      return c.json({ error: 'Bad Request', message: 'Missing required fields' }, 400)
    }

    const { prompt, systemPrompt, model, requestType } = body

    // Get user ID from X-User-ID header (from iOS app) or fallback to IP
    const userId = c.req.header('X-User-ID') || c.req.header('CF-Connecting-IP') || 'unknown'
    const ip = c.req.header('CF-Connecting-IP') || 'unknown'
    const traceId = crypto.randomUUID()

    // Select model using requestType or manual model
    const { modelId: finalModel, modelConfig } = await selectModelFromRequest(
      requestType,
      model,
      c.env.RATE_LIMITER,
      userId,
      RequestType.MODERATE
    )

    console.log(
      `🎯 /api/chat/stream: Using model ${finalModel} for requestType ${requestType || 'none'}`
    )

    const openRouterResponse = await callOpenRouter(
      c.env.OPENROUTER_API_KEY,
      finalModel,
      systemPrompt,
      prompt
    )

    if (!openRouterResponse.ok) {
      const errorText = await openRouterResponse.text()
      console.error('OpenRouter error:', errorText)

      return c.json(
        {
          error: 'AI Service Error',
          message: 'Failed to get response from AI service',
          details: errorText,
        },
        500
      )
    }

    // Variables to capture during streaming
    let fullOutput = ''
    let inputTokens: number | undefined
    let outputTokens: number | undefined
    let totalTokens: number | undefined

    // Wrap the response body to capture tokens
    const reader = openRouterResponse.body?.getReader()
    if (!reader) {
      return c.json({ error: 'No response body' }, 500)
    }

    const decoder = new TextDecoder()
    let buffer = ''

    const readable = new ReadableStream({
      async start(controller) {
        try {
          while (true) {
            const { done, value } = await reader.read()
            if (done) {
              // Increment quota if model requires it
              if (modelConfig) {
                await afterModelUsage(modelConfig, c.env.RATE_LIMITER, userId)
              }

              // Capture LLM event with all collected data
              const latency = (Date.now() - startTime) / 1000

              if (c.env.POSTHOG_API_KEY && c.env.POSTHOG_HOST) {
                const posthog = createPostHogClient({
                  apiKey: c.env.POSTHOG_API_KEY,
                  host: c.env.POSTHOG_HOST,
                })

                c.executionCtx.waitUntil(
                  (async () => {
                    try {
                      await captureLLMEvent(posthog, userId, traceId, {
                        model: finalModel,
                        input: prompt,
                        systemPrompt,
                        output: fullOutput,
                        inputTokens,
                        outputTokens,
                        latency,
                        cost: totalTokens ? totalTokens * 0.000001 : undefined,
                        ip,
                      })
                      await posthog.shutdown()
                    } catch (error) {
                      console.error('PostHog capture error:', error)
                    }
                  })()
                )
              }

              controller.close()
              break
            }

            buffer += decoder.decode(value, { stream: true })
            const lines = buffer.split('\n')
            buffer = lines.pop() || ''

            for (const line of lines) {
              if (line.startsWith('data: ')) {
                const data = line.slice(6).trim()

                if (data && data !== '[DONE]') {
                  try {
                    const json: StreamChunk = JSON.parse(data)
                    const content = json.choices?.[0]?.delta?.content

                    if (content) {
                      fullOutput += content
                    }

                    // Capture usage data if present
                    if (json.usage) {
                      inputTokens = json.usage.prompt_tokens
                      outputTokens = json.usage.completion_tokens
                      totalTokens = json.usage.total_tokens
                    }
                  } catch (parseError) {
                    console.warn('JSON parse error:', parseError)
                  }
                }
              }
            }

            // Forward the chunk to the client
            controller.enqueue(value)
          }
        } catch (error) {
          console.error('Streaming error:', error)
          controller.error(error)
        }
      },
    })

    return new Response(readable, {
      headers: {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        Connection: 'keep-alive',
      },
    })
  } catch (error) {
    console.error('Streaming error:', error)
    return c.json({ error: 'Streaming failed' }, 500)
  }
})

app.post('/api/chat/v2', async (c) => {
  const startTime = Date.now()

  try {
    if (!validateAppAuth(c)) {
      return c.json({ error: 'Unauthorized', message: 'Invalid app key' }, 401)
    }

    const body = await c.req.json()

    if (!validateChatRequestV2(body)) {
      return c.json(
        {
          error: 'Bad Request',
          message:
            'Missing required fields: promptType, requestType or model, userQuestion, language, data',
        },
        400
      )
    }

    const { promptType, requestType, model: manualModel, userQuestion, language, data } = body

    if (userQuestion.length > MAX_PROMPT_LENGTH) {
      return c.json(
        {
          error: 'Bad Request',
          message: `Question too long (max ${MAX_PROMPT_LENGTH} characters)`,
        },
        400
      )
    }

    // Get user ID from X-User-ID header (from iOS app) or fallback to IP
    const userId = c.req.header('X-User-ID') || c.req.header('CF-Connecting-IP') || 'unknown'
    const ip = c.req.header('CF-Connecting-IP') || 'unknown'
    const traceId = crypto.randomUUID()

    // Determine which model to use
    let finalModel: string
    let selectedModelConfig: Awaited<ReturnType<typeof selectModel>>['model'] | undefined

    if (requestType) {
      // Use semantic requestType to select model (preferred)
      console.log(`🎯 Using requestType: ${requestType}`)

      // Validate requestType
      if (!Object.values(RequestType).includes(requestType as RequestType)) {
        return c.json(
          {
            error: 'Bad Request',
            message: `Invalid requestType. Valid values: ${Object.values(RequestType).join(', ')}`,
          },
          400
        )
      }

      // Select model based on requestType and user quota
      const selection = await selectModel(requestType as RequestType, c.env.RATE_LIMITER, userId)
      finalModel = selection.model.modelId
      selectedModelConfig = selection.model

      console.log(`✅ Selected model: ${selection.model.displayName} (${finalModel})`)
    } else if (manualModel) {
      // Fallback to manual model (backward compatibility)
      console.log(`⚠️ Using legacy manual model: ${manualModel}`)
      finalModel = manualModel
    } else {
      return c.json(
        {
          error: 'Bad Request',
          message: 'Either requestType or model must be provided',
        },
        400
      )
    }

    // Build system prompt from data using templates
    let systemPrompt: string
    try {
      systemPrompt = buildPrompt(promptType, data, language || 'en')
    } catch (error) {
      return c.json(
        {
          error: 'Bad Request',
          message: error instanceof Error ? error.message : 'Invalid prompt type',
        },
        400
      )
    }

    const openRouterResponse = await callOpenRouter(
      c.env.OPENROUTER_API_KEY,
      finalModel,
      systemPrompt,
      userQuestion
    )

    if (!openRouterResponse.ok) {
      const errorText = await openRouterResponse.text()
      console.error('OpenRouter error:', errorText)

      return c.json(
        {
          error: 'AI Service Error',
          message: 'Failed to get response from AI service',
          details: errorText,
        },
        500
      )
    }

    // Variables to capture during streaming
    let fullOutput = ''
    let inputTokens: number | undefined
    let outputTokens: number | undefined
    let totalTokens: number | undefined

    return streamSSE(c, async (stream) => {
      const reader = openRouterResponse.body?.getReader()
      if (!reader) {
        throw new Error('No response body')
      }

      const decoder = new TextDecoder()
      let buffer = ''

      try {
        while (true) {
          const { done, value } = await reader.read()
          if (done) break

          buffer += decoder.decode(value, { stream: true })
          const lines = buffer.split('\n')

          // Keep the last incomplete line in buffer
          buffer = lines.pop() || ''

          for (const line of lines) {
            if (line.startsWith('data: ')) {
              const dataStr = line.slice(6).trim()

              if (dataStr === '[DONE]') {
                await stream.writeSSE({
                  data: '[DONE]',
                })

                // Capture LLM event with all collected data
                const latency = (Date.now() - startTime) / 1000

                // Increment quotas if needed (e.g., Sonnet usage)
                if (selectedModelConfig) {
                  c.executionCtx.waitUntil(
                    (async () => {
                      try {
                        await afterModelUsage(selectedModelConfig, c.env.RATE_LIMITER, userId)
                      } catch (error) {
                        console.error('Quota increment error:', error)
                      }
                    })()
                  )
                }

                if (c.env.POSTHOG_API_KEY && c.env.POSTHOG_HOST) {
                  const posthog = createPostHogClient({
                    apiKey: c.env.POSTHOG_API_KEY,
                    host: c.env.POSTHOG_HOST,
                  })

                  c.executionCtx.waitUntil(
                    (async () => {
                      try {
                        await captureLLMEvent(posthog, userId, traceId, {
                          model: finalModel,
                          input: userQuestion,
                          systemPrompt,
                          output: fullOutput,
                          inputTokens,
                          outputTokens,
                          latency,
                          cost: totalTokens ? totalTokens * 0.000001 : undefined,
                          ip,
                        })
                        await posthog.shutdown()
                      } catch (error) {
                        console.error('PostHog capture error:', error)
                      }
                    })()
                  )
                }

                return
              }

              if (dataStr) {
                try {
                  const json: StreamChunk = JSON.parse(dataStr)
                  const content = json.choices?.[0]?.delta?.content

                  if (content) {
                    fullOutput += content
                    await stream.writeSSE({
                      data: JSON.stringify({ content }),
                    })
                  }

                  // Capture usage data if present
                  if (json.usage) {
                    inputTokens = json.usage.prompt_tokens
                    outputTokens = json.usage.completion_tokens
                    totalTokens = json.usage.total_tokens
                  }
                } catch (parseError) {
                  console.warn('JSON parse error:', parseError, 'Data:', dataStr)
                }
              }
            }
          }
        }
      } catch (error) {
        console.error('Streaming error:', error)
        throw error
      }
    })
  } catch (error) {
    console.error('Chat v2 endpoint error:', error)

    return c.json(
      {
        error: 'Internal Server Error',
        message: error instanceof Error ? error.message : 'Unknown error',
      },
      500
    )
  }
})

app.get('/api/stats', async (c) => {
  // Use X-User-ID header if available, fallback to IP
  const userId = c.req.header('X-User-ID')
  const ip = c.req.header('CF-Connecting-IP') || 'unknown'

  // Get quota config from KV (dynamic)
  const config = await getQuotaConfigFromKV(c.env.RATE_LIMITER)
  const quotaCheck = await checkQuota(c.env.RATE_LIMITER, ip, userId, config)

  return c.json({
    identifier: userId || ip,
    ip,
    userId: userId || null,
    quotas: {
      ip: {
        limit: quotaCheck.ip.limit,
        remaining: quotaCheck.ip.remaining,
        resetAt: quotaCheck.ip.resetAt,
        resetIn: quotaCheck.ip.resetIn,
        window: config.ipWindow,
      },
      ...(quotaCheck.user && {
        user: {
          limit: quotaCheck.user.limit,
          remaining: quotaCheck.user.remaining,
          resetAt: quotaCheck.user.resetAt,
          resetIn: quotaCheck.user.resetIn,
          window: config.userWindow,
        },
      }),
    },
    allowed: quotaCheck.allowed,
    restrictedBy: quotaCheck.restrictedBy || null,
  })
})

// ============================================================
// iOS Configuration Endpoint (Feature Flags)
// ============================================================

app.get('/api/config', async (c) => {
  if (!validateAppAuth(c)) {
    return c.json({ error: 'Unauthorized', message: 'Invalid app key' }, 401)
  }

  const features = await getFeatureFlags(c.env.RATE_LIMITER)

  // Return all features dynamically - no hardcoded structure
  return c.json({ features })
})

// ============================================================
// Admin API Endpoints
// ============================================================

// Admin auth middleware
app.use('/api/admin/*', async (c, next) => {
  if (!validateAdminAuth(c)) {
    return c.json({ error: 'Unauthorized', message: 'Invalid admin key' }, 401)
  }
  await next()
})

// Get all admin configuration
app.get('/api/admin/config', async (c) => {
  const [features, modelConfig, quotaConfig] = await Promise.all([
    getFeatureFlags(c.env.RATE_LIMITER),
    getCurrentModelConfig(c.env.RATE_LIMITER),
    getQuotaConfigFromKV(c.env.RATE_LIMITER),
  ])

  return c.json({
    features,
    models: {
      current: modelConfig.mapping,
      available: modelConfig.models,
      defaults: modelConfig.defaults,
    },
    rate_limits: {
      current: quotaConfig,
      defaults: getDefaultQuotaConfig(),
    },
  })
})

// Update model mapping
app.put('/api/admin/config/models', async (c) => {
  try {
    const body = await c.req.json()

    if (!body || typeof body !== 'object') {
      return c.json({ error: 'Bad Request', message: 'Invalid model mapping' }, 400)
    }

    await setModelMapping(c.env.RATE_LIMITER, body)

    return c.json({
      success: true,
      message: 'Model mapping updated',
      mapping: body,
    })
  } catch (error) {
    console.error('Error updating model config:', error)
    return c.json({ error: 'Internal Server Error', message: 'Failed to update model config' }, 500)
  }
})

// Add or update a model definition
app.put('/api/admin/models/:key', async (c) => {
  try {
    const key = c.req.param('key')
    const body = (await c.req.json()) as ModelConfig

    if (!body.modelId || !body.displayName) {
      return c.json({ error: 'Bad Request', message: 'modelId and displayName are required' }, 400)
    }

    const config: ModelConfig = {
      modelId: body.modelId,
      displayName: body.displayName,
      description: body.description || '',
      requiresQuota: body.requiresQuota ?? false,
    }

    await upsertModel(c.env.RATE_LIMITER, key, config)

    return c.json({
      success: true,
      message: `Model ${key} saved`,
      model: { key, ...config },
    })
  } catch (error) {
    console.error('Error upserting model:', error)
    return c.json({ error: 'Internal Server Error', message: 'Failed to save model' }, 500)
  }
})

// Delete a custom model
app.delete('/api/admin/models/:key', async (c) => {
  try {
    const key = c.req.param('key')

    const deleted = await deleteModel(c.env.RATE_LIMITER, key)

    if (!deleted) {
      return c.json(
        { error: 'Bad Request', message: 'Cannot delete default model or model not found' },
        400
      )
    }

    return c.json({
      success: true,
      message: `Model ${key} deleted`,
    })
  } catch (error) {
    console.error('Error deleting model:', error)
    return c.json({ error: 'Internal Server Error', message: 'Failed to delete model' }, 500)
  }
})

// Update feature flags
app.put('/api/admin/config/features', async (c) => {
  try {
    const body = await c.req.json()

    if (!body || typeof body !== 'object') {
      return c.json({ error: 'Bad Request', message: 'Invalid feature flags' }, 400)
    }

    // Check if this is a full replacement or a partial update
    const { _replace_all, ...flags } = body
    if (_replace_all) {
      // Full replacement - directly set the KV
      await c.env.RATE_LIMITER.put(KV_FEATURE_FLAGS_KEY, JSON.stringify(flags))
    } else {
      // Partial update - merge with existing
      await setFeatureFlags(c.env.RATE_LIMITER, flags)
    }
    const updated = await getFeatureFlags(c.env.RATE_LIMITER)

    return c.json({
      success: true,
      message: 'Feature flags updated',
      features: updated,
    })
  } catch (error) {
    console.error('Error updating feature flags:', error)
    return c.json(
      { error: 'Internal Server Error', message: 'Failed to update feature flags' },
      500
    )
  }
})

// Update rate limits
app.put('/api/admin/config/rate-limits', async (c) => {
  try {
    const body = await c.req.json()

    if (!body || typeof body !== 'object') {
      return c.json({ error: 'Bad Request', message: 'Invalid rate limits' }, 400)
    }

    await setQuotaConfig(c.env.RATE_LIMITER, body)
    const updated = await getQuotaConfigFromKV(c.env.RATE_LIMITER)

    return c.json({
      success: true,
      message: 'Rate limits updated',
      rate_limits: updated,
    })
  } catch (error) {
    console.error('Error updating rate limits:', error)
    return c.json({ error: 'Internal Server Error', message: 'Failed to update rate limits' }, 500)
  }
})

// Block a user
app.post('/api/admin/users/:userId/block', async (c) => {
  try {
    const userId = c.req.param('userId')
    const body = await c.req.json()

    const block: BlockedEntity = {
      reason: body.reason || 'No reason provided',
      blocked_at: Date.now(),
      blocked_by: 'admin',
      expires_at: body.expires_at || null,
    }

    await c.env.RATE_LIMITER.put(`${KV_BLOCKED_USER_PREFIX}${userId}`, JSON.stringify(block))

    return c.json({
      success: true,
      message: `User ${userId} has been blocked`,
      block,
    })
  } catch (error) {
    console.error('Error blocking user:', error)
    return c.json({ error: 'Internal Server Error', message: 'Failed to block user' }, 500)
  }
})

// Unblock a user
app.delete('/api/admin/users/:userId/block', async (c) => {
  try {
    const userId = c.req.param('userId')

    await c.env.RATE_LIMITER.delete(`${KV_BLOCKED_USER_PREFIX}${userId}`)

    return c.json({
      success: true,
      message: `User ${userId} has been unblocked`,
    })
  } catch (error) {
    console.error('Error unblocking user:', error)
    return c.json({ error: 'Internal Server Error', message: 'Failed to unblock user' }, 500)
  }
})

// Block an IP
app.post('/api/admin/ip/:ip/block', async (c) => {
  try {
    const ip = c.req.param('ip')
    const body = await c.req.json()

    const block: BlockedEntity = {
      reason: body.reason || 'No reason provided',
      blocked_at: Date.now(),
      blocked_by: 'admin',
      expires_at: body.expires_at || null,
    }

    await c.env.RATE_LIMITER.put(`${KV_BLOCKED_IP_PREFIX}${ip}`, JSON.stringify(block))

    return c.json({
      success: true,
      message: `IP ${ip} has been blocked`,
      block,
    })
  } catch (error) {
    console.error('Error blocking IP:', error)
    return c.json({ error: 'Internal Server Error', message: 'Failed to block IP' }, 500)
  }
})

// Unblock an IP
app.delete('/api/admin/ip/:ip/block', async (c) => {
  try {
    const ip = c.req.param('ip')

    await c.env.RATE_LIMITER.delete(`${KV_BLOCKED_IP_PREFIX}${ip}`)

    return c.json({
      success: true,
      message: `IP ${ip} has been unblocked`,
    })
  } catch (error) {
    console.error('Error unblocking IP:', error)
    return c.json({ error: 'Internal Server Error', message: 'Failed to unblock IP' }, 500)
  }
})

// List all blocked entities (users and IPs)
app.get('/api/admin/blocked', async (c) => {
  try {
    // List blocked users
    const usersList = await c.env.RATE_LIMITER.list({ prefix: KV_BLOCKED_USER_PREFIX })
    const ipsList = await c.env.RATE_LIMITER.list({ prefix: KV_BLOCKED_IP_PREFIX })

    const blockedUsers: Array<{ id: string; block: BlockedEntity }> = []
    const blockedIPs: Array<{ ip: string; block: BlockedEntity }> = []

    for (const key of usersList.keys) {
      const userId = key.name.replace(KV_BLOCKED_USER_PREFIX, '')
      const blockJson = await c.env.RATE_LIMITER.get(key.name)
      if (blockJson) {
        blockedUsers.push({ id: userId, block: JSON.parse(blockJson) })
      }
    }

    for (const key of ipsList.keys) {
      const ip = key.name.replace(KV_BLOCKED_IP_PREFIX, '')
      const blockJson = await c.env.RATE_LIMITER.get(key.name)
      if (blockJson) {
        blockedIPs.push({ ip, block: JSON.parse(blockJson) })
      }
    }

    return c.json({
      users: blockedUsers,
      ips: blockedIPs,
      total: blockedUsers.length + blockedIPs.length,
    })
  } catch (error) {
    console.error('Error listing blocked entities:', error)
    return c.json(
      { error: 'Internal Server Error', message: 'Failed to list blocked entities' },
      500
    )
  }
})

export default app
