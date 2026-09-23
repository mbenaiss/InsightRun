import { afterEach, describe, expect, mock, spyOn, test } from 'bun:test'
import app from '../src/index'
import * as analytics from '../src/posthog'

afterEach(() => mock.restore())

type CapturedEvent = { distinctId: string; event: string; properties: Record<string, unknown> }

const agentRequest = { userQuestion: 'Hello', language: 'en', data: {} }

function sse(...chunks: unknown[]) {
  const events = chunks.map((chunk) => `data: ${JSON.stringify(chunk)}\n\n`).join('')
  return new Response(`${events}data: [DONE]\n\n`)
}

async function send(path: string, body: unknown, upstream: Response | Error, userId = 'user-1') {
  const capture = mock(async (_event: CapturedEvent) => {})
  spyOn(analytics, 'createPostHogClient').mockReturnValue({
    captureImmediate: capture,
    shutdown: mock(async () => {}),
  } as unknown as ReturnType<typeof analytics.createPostHogClient>)
  const fetchMock = spyOn(globalThis, 'fetch')
  if (upstream instanceof Error) fetchMock.mockRejectedValue(upstream)
  else fetchMock.mockResolvedValue(upstream)
  spyOn(console, 'error').mockImplementation(() => {})
  const pending: Promise<unknown>[] = []
  const response = await app.request(
    path,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-App-Key': 'test-secret',
        'X-User-ID': userId,
        'CF-Connecting-IP': '192.0.2.20',
      },
      body: JSON.stringify(body),
    },
    {
      APP_SECRET: 'test-secret',
      OPENROUTER_API_KEY: 'test-key',
      POSTHOG_API_KEY: 'test-key',
      POSTHOG_HOST: 'https://example.invalid',
      RATE_LIMITER: {
        get: async () => null,
        getWithMetadata: async () => ({ value: null, metadata: null }),
        put: async () => {},
      } as unknown as KVNamespace,
    },
    {
      waitUntil: (promise: Promise<unknown>) => {
        pending.push(promise)
      },
      passThroughOnException: () => {},
    }
  )
  await response.text()
  await Promise.all(pending)
  const generations = capture.mock.calls
    .map(([event]) => event)
    .filter((event) => event.event === '$ai_generation')
  return { response, generations, fetchMock }
}

describe('agent chat $ai_generation', () => {
  test('reports the answering fallback model with OpenRouter usage and cost', async () => {
    const { response, generations, fetchMock } = await send(
      '/api/agent/chat',
      agentRequest,
      sse(
        { model: 'google/gemini-2.5-flash', choices: [{ delta: { content: 'Hi.' } }] },
        {
          model: 'google/gemini-2.5-flash',
          choices: [{ delta: {}, finish_reason: 'stop' }],
          usage: { prompt_tokens: 1200, completion_tokens: 40, total_tokens: 1240, cost: 0.00042 },
        }
      )
    )
    expect(response.status).toBe(200)
    const requested = JSON.parse(String(fetchMock.mock.calls[0][1]?.body)).model
    expect(requested).not.toBe('google/gemini-2.5-flash')
    expect(generations).toHaveLength(1)
    expect(generations[0].properties).toMatchObject({
      $ai_model: 'google/gemini-2.5-flash',
      $ai_input_tokens: 1200,
      $ai_output_tokens: 40,
      $ai_total_cost_usd: 0.00042,
      route: '/api/agent/chat',
      is_internal: false,
    })
    expect(generations[0].properties).not.toHaveProperty('$ai_is_error')
  })

  test.each([
    [
      'an upstream HTTP failure',
      new Response('Unavailable', { status: 503 }),
      'OpenRouter HTTP 503',
    ],
    ['a network failure', new TypeError('fetch failed'), 'OpenRouter request failed'],
    [
      'a stream error',
      sse({ error: { code: 502, message: 'Provider error' } }),
      'OpenRouter stream error 502',
    ],
    ['an empty answer', sse(), 'The AI response was empty'],
    [
      'a malformed chunk',
      new Response('data: {"choices":\n\ndata: [DONE]\n\n'),
      'Malformed stream chunk',
    ],
  ])('reports %s as an AI error', async (_case, upstream, error) => {
    const { generations } = await send('/api/agent/chat', agentRequest, upstream)
    expect(generations).toHaveLength(1)
    expect(generations[0].properties).toMatchObject({
      $ai_is_error: true,
      $ai_error: error,
      route: '/api/agent/chat',
    })
  })

  test('marks QA traffic as internal', async () => {
    const { generations } = await send(
      '/api/agent/chat',
      agentRequest,
      sse({ choices: [{ delta: { content: 'Hi.' } }] }),
      'qa-simulator'
    )
    expect(generations[0].properties.is_internal).toBe(true)
  })
})

describe('legacy chat $ai_generation cost', () => {
  const usage = { prompt_tokens: 100, completion_tokens: 5, total_tokens: 105 }

  test.each([
    [
      '/api/chat',
      { prompt: 'Q', systemPrompt: 'Coach', requestType: 'MODERATE' },
      () => sse({ choices: [{ delta: { content: 'A.' } }], usage: { ...usage, cost: 0.0003 } }),
      0.0003,
    ],
    [
      '/api/chat',
      { prompt: 'Q', systemPrompt: 'Classifier', requestType: 'CLASSIFICATION', stream: false },
      () => Response.json({ choices: [{ message: { content: 'SIMPLE' } }], usage }),
      undefined,
    ],
    [
      '/api/chat/v2',
      {
        promptType: 'workout_coach',
        requestType: 'MODERATE',
        userQuestion: 'Q',
        language: 'en',
        data: {},
      },
      () => sse({ choices: [{ delta: { content: 'A.' } }], usage }),
      undefined,
    ],
  ])('%s reports the OpenRouter cost, never a token estimate', async (path, body, upstream, cost) => {
    const { response, generations } = await send(path, body, upstream())
    expect(response.status).toBe(200)
    expect(generations).toHaveLength(1)
    expect(generations[0].properties).toMatchObject({ $ai_input_tokens: 100, route: path })
    expect(generations[0].properties.$ai_total_cost_usd).toBe(cost)
  })
})
