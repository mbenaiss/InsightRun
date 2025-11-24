import type { Context } from 'hono'
import { Hono } from 'hono'
import { cors } from 'hono/cors'
import { logger } from 'hono/logger'
import { streamSSE } from 'hono/streaming'
import { afterModelUsage, RequestType, selectModel, selectModelFromRequest } from './modelRouter'
import { captureLLMEvent, createPostHogClient } from './posthog'
import { buildPrompt } from './prompts'
import type { QuotaCheck } from './quota'
import { checkQuota, getQuotaConfig, getQuotaHeaders, incrementQuota } from './quota'
import analyzeHistoryRoutes from './routes/analyzeHistory'
import generateWorkoutRoutes from './routes/generateWorkout'
import smartSuggestionRoutes from './routes/smartSuggestion'
import stravaRoutes from './routes/strava'
import type { ChatRequestV2 } from './types'

type Bindings = {
  OPENROUTER_API_KEY: string
  APP_SECRET: string
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
}

interface ChatRequest {
  prompt: string
  systemPrompt: string
  model?: string
  requestType?: string
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

const MAX_PROMPT_LENGTH = 2000
const MAX_TOKENS = 2000
const AI_TEMPERATURE = 0.7
const OPENROUTER_API_URL = 'https://openrouter.ai/api/v1/chat/completions'
const DEFAULT_APP_SECRET = 'healthapp-ios-v1'

type AppContext = Context<{ Bindings: Bindings; Variables: Variables }>

function validateAppAuth(c: AppContext): boolean {
  const appKey = c.req.header('X-App-Key')
  const expectedKey = c.env.APP_SECRET || DEFAULT_APP_SECRET
  return appKey === expectedKey
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
    allowMethods: ['POST', 'GET', 'OPTIONS'],
    allowHeaders: ['Content-Type', 'Authorization', 'X-App-Key', 'X-User-ID'],
    maxAge: 86400,
  })
)

app.use('/api/*', async (c, next) => {
  // Extract user ID and IP from headers
  const userId = c.req.header('X-User-ID')
  const ip = c.req.header('CF-Connecting-IP') || 'unknown'
  const identifier = userId || ip
  const rateLimitKey = `ratelimit:${identifier}`

  c.set('rateLimitKey', rateLimitKey)

  // Check both IP and User quotas
  const config = getQuotaConfig()
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

// Mount generate-workout route
app.route('/api/generate-workout', generateWorkoutRoutes)

// Mount smart-suggestion route
app.route('/api/workout/smart-suggestion', smartSuggestionRoutes)

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

    const { prompt, systemPrompt, model, requestType } = body

    if (prompt.length > MAX_PROMPT_LENGTH) {
      return c.json(
        {
          error: 'Bad Request',
          message: `Prompt too long (max ${MAX_PROMPT_LENGTH} characters)`,
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

    console.log(`🎯 /api/chat: Using model ${finalModel} for requestType ${requestType || 'none'}`)

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
                if (requestType) {
                  c.executionCtx.waitUntil(
                    (async () => {
                      try {
                        const selection = await selectModel(
                          requestType as RequestType,
                          c.env.RATE_LIMITER,
                          userId
                        )
                        await afterModelUsage(selection.model, c.env.RATE_LIMITER, userId)
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

  // Get quota status for both IP and User
  const config = getQuotaConfig()
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

export default app
