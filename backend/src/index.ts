import type { Context } from 'hono'
import { Hono } from 'hono'
import { cors } from 'hono/cors'
import { logger } from 'hono/logger'
import { streamSSE } from 'hono/streaming'
import { captureLLMEvent, createPostHogClient } from './posthog'
import { buildHistoricalAnalysisPrompt, buildPrompt } from './prompts'
import type { QuotaCheck } from './quota'
import { checkQuota, getQuotaConfig, getQuotaHeaders, incrementQuota } from './quota'
import type { ChatRequestV2, HistoricalAnalysisResponse } from './types'
import { historicalAnalysisRequestSchema } from './types'
import { estimateTokenCount, truncateToTokenLimit, validateTokenCount } from './utils'

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

interface ChatRequest {
  prompt: string
  systemPrompt: string
  model: string
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
  return !!(req.prompt && req.systemPrompt && req.model)
}

function validateChatRequestV2(body: unknown): body is ChatRequestV2 {
  const req = body as ChatRequestV2
  return !!(req.promptType && req.model && req.userQuestion && req.language && req.data)
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

async function callOpenRouterNonStreaming(
  apiKey: string,
  model: string,
  systemPrompt: string,
  prompt: string,
  maxTokens: number = 3000
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
    throw new Error(`OpenRouter API error: ${response.status}`)
  }

  const data = (await response.json()) as {
    choices: Array<{ message: { content: string } }>
  }
  return data.choices[0].message.content
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
          message: 'Missing required fields: prompt, systemPrompt, model',
        },
        400
      )
    }

    const { prompt, systemPrompt, model } = body

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

    const openRouterResponse = await callOpenRouter(
      c.env.OPENROUTER_API_KEY,
      model,
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
                          model,
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

    const { prompt, systemPrompt, model } = body

    // Get user ID from X-User-ID header (from iOS app) or fallback to IP
    const userId = c.req.header('X-User-ID') || c.req.header('CF-Connecting-IP') || 'unknown'
    const ip = c.req.header('CF-Connecting-IP') || 'unknown'
    const traceId = crypto.randomUUID()

    const openRouterResponse = await callOpenRouter(
      c.env.OPENROUTER_API_KEY,
      model,
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
                        model,
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
          message: 'Missing required fields: promptType, model, userQuestion, language, data',
        },
        400
      )
    }

    const { promptType, model, userQuestion, language, data } = body

    if (userQuestion.length > MAX_PROMPT_LENGTH) {
      return c.json(
        {
          error: 'Bad Request',
          message: `Question too long (max ${MAX_PROMPT_LENGTH} characters)`,
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

    // Get user ID from X-User-ID header (from iOS app) or fallback to IP
    const userId = c.req.header('X-User-ID') || c.req.header('CF-Connecting-IP') || 'unknown'
    const ip = c.req.header('CF-Connecting-IP') || 'unknown'
    const traceId = crypto.randomUUID()

    const openRouterResponse = await callOpenRouter(
      c.env.OPENROUTER_API_KEY,
      model,
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

                if (c.env.POSTHOG_API_KEY && c.env.POSTHOG_HOST) {
                  const posthog = createPostHogClient({
                    apiKey: c.env.POSTHOG_API_KEY,
                    host: c.env.POSTHOG_HOST,
                  })

                  c.executionCtx.waitUntil(
                    (async () => {
                      try {
                        await captureLLMEvent(posthog, userId, traceId, {
                          model,
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

app.post('/api/analyze-history', async (c) => {
  const startTime = Date.now()

  try {
    if (!validateAppAuth(c)) {
      return c.json({ error: 'Unauthorized', message: 'Invalid app key' }, 401)
    }

    const body = await c.req.json()

    // Validate request body with Zod
    const validationResult = historicalAnalysisRequestSchema.safeParse(body)

    if (!validationResult.success) {
      const errorMessages = validationResult.error.issues.map((err) => {
        const path = err.path.join('.')
        return `${path}: ${err.message}`
      })

      return c.json(
        {
          error: 'Bad Request',
          message: 'Invalid workout data',
          details: errorMessages,
        },
        400
      )
    }

    const { workouts, profile, language } = validationResult.data
    // Force Grok 4 Fast for historical analysis (ignore client model)
    const model = 'x-ai/grok-4-fast'

    // Get user ID for tracking
    const userId = c.req.header('X-User-ID') || c.req.header('CF-Connecting-IP') || 'unknown'
    const ip = c.req.header('CF-Connecting-IP') || 'unknown'
    const traceId = crypto.randomUUID()

    const profileInfo = profile
      ? `with profile (age: ${profile.age || 'N/A'}, sex: ${profile.sex || 'N/A'})`
      : 'no profile'
    console.log(
      `📊 Historical analysis requested: ${workouts.length} workouts, ${profileInfo}, model: ${model}, user: ${userId}`
    )

    // Build the analysis prompt
    const systemPrompt = ''
    const prompt = buildHistoricalAnalysisPrompt(workouts, profile, language)

    // Call OpenRouter (non-streaming) with higher token limit for summary generation
    let summary = await callOpenRouterNonStreaming(
      c.env.OPENROUTER_API_KEY,
      model,
      systemPrompt,
      prompt,
      5000 // Max tokens for generation (will truncate if needed)
    )

    // Validate and truncate summary if it exceeds 5000 tokens
    const tokenCount = validateTokenCount(summary, 5000, 'Historical summary')

    if (tokenCount > 5000) {
      console.warn(`⚠️ Summary exceeds 5000 tokens (${tokenCount}). Truncating intelligently...`)
      summary = truncateToTokenLimit(summary, 4800) // Truncate to 4800 to leave margin
      const finalTokenCount = estimateTokenCount(summary)
      console.log(`✅ Summary truncated to ${finalTokenCount} tokens`)
    } else if (tokenCount > 4000) {
      console.log(`⚠️ Summary is large (${tokenCount} tokens) but within 5000 limit`)
    }

    const finalTokenCount = estimateTokenCount(summary)
    const latency = (Date.now() - startTime) / 1000

    // Estimate input token count for logging
    const inputTokenCount = estimateTokenCount(prompt)

    console.log(
      `✅ Historical summary generated: ${finalTokenCount} tokens, ${workouts.length} workouts, ${latency.toFixed(2)}s, input: ${inputTokenCount} tokens`
    )

    // Log to PostHog
    if (c.env.POSTHOG_API_KEY && c.env.POSTHOG_HOST) {
      const posthog = createPostHogClient({
        apiKey: c.env.POSTHOG_API_KEY,
        host: c.env.POSTHOG_HOST,
      })

      c.executionCtx.waitUntil(
        (async () => {
          try {
            // Log with a summary + size info instead of full prompt to save space
            // The full prompt with all workout data IS sent to the AI API
            const inputSummary = `Historical analysis: ${workouts.length} workouts (${inputTokenCount} tokens input)\n\nSample of data sent:\n${prompt.substring(0, 500)}...\n\n[Full workout details sent to AI - truncated here for logging]`

            await captureLLMEvent(posthog, userId, traceId, {
              model,
              input: inputSummary,
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

    const response: HistoricalAnalysisResponse = {
      summary,
      workoutCount: workouts.length,
      tokenCount: finalTokenCount,
      generatedAt: new Date().toISOString(),
    }

    return c.json(response)
  } catch (error) {
    console.error('Historical analysis endpoint error:', error)

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
