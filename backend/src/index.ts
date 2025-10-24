import type { Context } from 'hono'
import { Hono } from 'hono'
import { cors } from 'hono/cors'
import { logger } from 'hono/logger'
import { streamSSE } from 'hono/streaming'
import { captureLLMEvent, createPostHogClient } from './posthog'

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

const RATE_LIMIT = 100
const RATE_LIMIT_WINDOW = 3600
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
  // Use X-User-ID header if available (from iOS app), fallback to IP for backward compatibility
  const userId = c.req.header('X-User-ID')
  const ip = c.req.header('CF-Connecting-IP') || 'unknown'
  const identifier = userId || ip
  const rateLimitKey = `ratelimit:${identifier}`

  c.set('rateLimitKey', rateLimitKey)

  const count = await c.env.RATE_LIMITER.get(rateLimitKey)
  const requestCount = count ? Number.parseInt(count, 10) : 0

  if (requestCount >= RATE_LIMIT) {
    return c.json(
      {
        error: 'Rate limit exceeded',
        message: 'Too many requests. Please try again later.',
        limit: RATE_LIMIT,
        retryAfter: RATE_LIMIT_WINDOW,
      },
      429
    )
  }

  await next()

  await c.env.RATE_LIMITER.put(rateLimitKey, (requestCount + 1).toString(), {
    expirationTtl: RATE_LIMIT_WINDOW,
  })
})

app.get('/', (c) => {
  return c.json({
    status: 'ok',
    service: 'HealthApp Backend API',
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

app.get('/api/stats', async (c) => {
  // Use X-User-ID header if available, fallback to IP
  const userId = c.req.header('X-User-ID')
  const ip = c.req.header('CF-Connecting-IP') || 'unknown'
  const identifier = userId || ip
  const rateLimitKey = `ratelimit:${identifier}`
  const count = await c.env.RATE_LIMITER.get(rateLimitKey)

  return c.json({
    requestsRemaining: RATE_LIMIT - (count ? Number.parseInt(count, 10) : 0),
    limit: RATE_LIMIT,
    resetIn: RATE_LIMIT_WINDOW,
    identifier,
    ip,
  })
})

export default app
