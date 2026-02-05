import { Hono } from 'hono'
import { streamSSE } from 'hono/streaming'
import { afterModelUsage, RequestType, selectModel } from '../modelRouter'
import { captureLLMEvent, createPostHogClient } from '../posthog'
import { buildPrompt } from '../prompts'
import type { ChatDataPayload } from '../types'

type Bindings = {
  OPENROUTER_API_KEY: string
  APP_SECRET: string
  RATE_LIMITER: KVNamespace
  POSTHOG_API_KEY: string
  POSTHOG_HOST: string
}

// Function definitions for agentic AI
const AGENT_FUNCTIONS = [
  {
    name: 'generate_workout',
    description:
      'Generate a structured workout plan based on user goals and fitness level. Use this when the user asks to create, generate, or plan a workout.',
    parameters: {
      type: 'object',
      properties: {
        workoutType: {
          type: 'string',
          enum: [
            'easy_run',
            'tempo',
            'intervals',
            'long_run',
            'recovery',
            'hill_repeats',
            'fartlek',
          ],
          description: 'The type of workout to generate',
        },
        duration: {
          type: 'number',
          description: 'Target duration in minutes',
        },
        distance: {
          type: 'number',
          description: 'Target distance in kilometers (optional)',
        },
        targetPace: {
          type: 'string',
          description: 'Target pace in format "5:30" for min/km',
        },
        notes: {
          type: 'string',
          description: 'Additional instructions or notes for the workout',
        },
      },
      required: ['workoutType', 'duration'],
    },
  },
]

interface AgentChatRequest {
  userQuestion: string
  language: string
  data: ChatDataPayload
  conversationHistory?: Array<{
    role: 'user' | 'assistant'
    content: string
  }>
}

interface FunctionCall {
  name: string
  arguments: string
}

interface OpenRouterResponse {
  choices: Array<{
    message?: {
      content?: string
      tool_calls?: Array<{
        function: FunctionCall
      }>
    }
    delta?: {
      content?: string
      tool_calls?: Array<{
        function?: {
          name?: string
          arguments?: string
        }
      }>
    }
  }>
  usage?: {
    prompt_tokens: number
    completion_tokens: number
    total_tokens: number
  }
}

const app = new Hono<{ Bindings: Bindings }>()

const OPENROUTER_API_URL = 'https://openrouter.ai/api/v1/chat/completions'
const MAX_TOKENS = 2000
const AI_TEMPERATURE = 0.7
const MAX_PROMPT_LENGTH = 5000

// Build the agentic system prompt
function buildAgentSystemPrompt(data: ChatDataPayload, language: string): string {
  const basePrompt = buildPrompt('workout_coach', data, language)

  const agentInstructions = `
# Agent Mode

You are now operating in AGENT MODE. In addition to providing advice, you can take actions using the available functions.

## Available Actions

1. **generate_workout** - Create a structured workout when the user asks for a specific training session

## When to Use Functions

- User asks to "create", "generate", "plan", or "build" a workout → use generate_workout

## Response Guidelines for Agent Mode

1. If a function is appropriate, call it with the right parameters
2. Always explain what action you're taking and why
3. After a function result, interpret it for the user
4. Maintain a conversational tone while being action-oriented

`

  return basePrompt + agentInstructions
}

// Process function call results
function processFunctionCall(functionCall: FunctionCall): {
  result: unknown
  displayMessage: string
} {
  let args: Record<string, unknown>
  try {
    args = JSON.parse(functionCall.arguments)
  } catch {
    return {
      result: { error: 'Failed to parse function arguments' },
      displayMessage: `Error processing ${functionCall.name}: invalid arguments`,
    }
  }

  switch (functionCall.name) {
    case 'generate_workout': {
      const workoutArgs = args as {
        workoutType: string
        duration: number
        distance?: number
        targetPace?: string
        notes?: string
      }
      const workout = {
        type: workoutArgs.workoutType,
        duration: workoutArgs.duration,
        distance: workoutArgs.distance,
        targetPace: workoutArgs.targetPace,
        notes: workoutArgs.notes,
        steps: generateWorkoutSteps(workoutArgs),
      }
      return {
        result: workout,
        displayMessage: `Generated a ${workoutArgs.workoutType.replace('_', ' ')} workout (${workoutArgs.duration} min)`,
      }
    }

    default:
      return {
        result: { error: 'Unknown function' },
        displayMessage: 'Unknown action requested',
      }
  }
}

// Generate workout steps based on type
function generateWorkoutSteps(args: {
  workoutType: string
  duration: number
  targetPace?: string
}) {
  const steps = []

  // Warmup (10% of duration, min 5 min)
  const warmupDuration = Math.max(5, Math.round(args.duration * 0.1))
  steps.push({
    type: 'warmup',
    duration: warmupDuration,
    description: 'Easy jog to warm up',
  })

  const mainDuration = Math.max(1, args.duration - warmupDuration - 5) // 5 min cooldown

  switch (args.workoutType) {
    case 'intervals':
      steps.push({
        type: 'intervals',
        duration: mainDuration,
        description: `${Math.floor(mainDuration / 5)} x 400m fast with 90s recovery`,
        targetPace: args.targetPace,
      })
      break

    case 'tempo':
      steps.push({
        type: 'tempo',
        duration: mainDuration,
        description: 'Sustained effort at tempo pace',
        targetPace: args.targetPace,
      })
      break

    case 'long_run':
      steps.push({
        type: 'steady',
        duration: mainDuration,
        description: 'Easy to moderate pace, focus on time on feet',
      })
      break

    default:
      steps.push({
        type: 'main',
        duration: mainDuration,
        description: 'Main workout segment',
        targetPace: args.targetPace,
      })
  }

  // Cooldown
  steps.push({
    type: 'cooldown',
    duration: 5,
    description: 'Easy jog and stretching',
  })

  return steps
}

// POST /api/agent/chat
app.post('/chat', async (c) => {
  const startTime = Date.now()

  try {
    const body = (await c.req.json()) as AgentChatRequest

    if (!body.userQuestion || !body.language || !body.data) {
      return c.json(
        {
          error: 'Bad Request',
          message: 'Missing required fields: userQuestion, language, data',
        },
        400
      )
    }

    if (typeof body.data !== 'object' || body.data === null || Array.isArray(body.data)) {
      return c.json({ error: 'Bad Request', message: 'Invalid data format' }, 400)
    }

    if (body.userQuestion.length > MAX_PROMPT_LENGTH) {
      return c.json(
        {
          error: 'Bad Request',
          message: `Question too long (max ${MAX_PROMPT_LENGTH} characters)`,
        },
        400
      )
    }

    const userId = c.req.header('X-User-ID') || c.req.header('CF-Connecting-IP') || 'unknown'
    const ip = c.req.header('CF-Connecting-IP') || 'unknown'
    const traceId = crypto.randomUUID()

    // Select model for complex requests
    const selection = await selectModel(RequestType.COMPLEX, c.env.RATE_LIMITER, userId)
    const model = selection.model.modelId

    // Build agentic system prompt
    const systemPrompt = buildAgentSystemPrompt(body.data, body.language)

    // Build messages
    const messages: Array<{ role: string; content: string }> = [
      { role: 'system', content: systemPrompt },
    ]

    // Add conversation history if provided
    if (body.conversationHistory) {
      let totalChars = 0
      const MAX_HISTORY_CHARS = 20_000
      const validHistory = body.conversationHistory
        .slice(-20)
        .filter((msg) => msg.role === 'user')
        .map((msg) => ({
          ...msg,
          content: typeof msg.content === 'string' ? msg.content.slice(0, MAX_PROMPT_LENGTH) : '',
        }))
        .filter((msg) => {
          totalChars += msg.content.length
          return totalChars <= MAX_HISTORY_CHARS
        })
      messages.push(...validHistory)
    }

    messages.push({ role: 'user', content: body.userQuestion })

    // Call OpenRouter with function calling
    const openRouterResponse = await fetch(OPENROUTER_API_URL, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${c.env.OPENROUTER_API_KEY}`,
        'HTTP-Referer': 'https://insightrun.ai',
        'X-Title': 'insightRun.ai',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model,
        messages,
        max_tokens: MAX_TOKENS,
        temperature: AI_TEMPERATURE,
        tools: AGENT_FUNCTIONS.map((fn) => ({ type: 'function' as const, function: fn })),
        tool_choice: 'auto',
        stream: true,
      }),
    })

    if (!openRouterResponse.ok) {
      const errorText = await openRouterResponse.text()
      console.error('OpenRouter error:', errorText)
      return c.json(
        {
          error: 'AI Service Error',
          message: 'Failed to get response from AI service',
        },
        500
      )
    }

    // Stream the response
    let fullOutput = ''
    let functionCall: { name: string; arguments: string } | null = null

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
          buffer = lines.pop() || ''

          for (const line of lines) {
            if (line.startsWith('data: ')) {
              const dataStr = line.slice(6).trim()

              if (dataStr === '[DONE]') {
                // If we had a function call, process it
                if (functionCall) {
                  const result = processFunctionCall(functionCall)
                  await stream.writeSSE({
                    data: JSON.stringify({
                      type: 'function_result',
                      function: functionCall.name,
                      result: result.result,
                      message: result.displayMessage,
                    }),
                  })
                }

                await stream.writeSSE({ data: '[DONE]' })

                // Capture analytics
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
                          input: body.userQuestion,
                          systemPrompt,
                          output: fullOutput,
                          latency,
                          ip,
                        })
                        await posthog.shutdown()
                      } catch (error) {
                        console.error('PostHog capture error:', error)
                      }
                    })()
                  )
                }

                await afterModelUsage(selection.model, c.env.RATE_LIMITER, userId)
                return
              }

              if (dataStr) {
                try {
                  const json: OpenRouterResponse = JSON.parse(dataStr)
                  const choice = json.choices?.[0]

                  // Handle tool calls
                  const toolCall = choice?.delta?.tool_calls?.[0]
                  if (toolCall?.function) {
                    if (toolCall.function.name) {
                      functionCall = { name: toolCall.function.name, arguments: '' }
                    }
                    if (toolCall.function.arguments && functionCall) {
                      functionCall.arguments += toolCall.function.arguments
                    }
                  }

                  // Handle regular content
                  const content = choice?.delta?.content
                  if (content) {
                    fullOutput += content
                    await stream.writeSSE({
                      data: JSON.stringify({ type: 'content', content }),
                    })
                  }
                } catch (parseError) {
                  console.warn('JSON parse error:', parseError)
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
    console.error('Agent chat endpoint error:', error)
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
