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

async function send(
  path: string,
  body: unknown,
  upstream: Response | Error | (() => Response),
  userId = 'user-1'
) {
  const capture = mock(async (_event: CapturedEvent) => {})
  spyOn(analytics, 'createPostHogClient').mockReturnValue({
    captureImmediate: capture,
    shutdown: mock(async () => {}),
  } as unknown as ReturnType<typeof analytics.createPostHogClient>)
  const fetchMock = spyOn(globalThis, 'fetch')
  if (upstream instanceof Error) fetchMock.mockRejectedValue(upstream)
  else if (upstream instanceof Response) fetchMock.mockResolvedValue(upstream)
  else fetchMock.mockImplementation(async () => upstream())
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
  const text = await response.text()
  await Promise.all(pending)
  const generations = capture.mock.calls
    .map(([event]) => event)
    .filter((event) => event.event === '$ai_generation')
  return { response, text, generations, fetchMock }
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

describe('structured AI routes $ai_generation usage', () => {
  const usage = { prompt_tokens: 321, completion_tokens: 54, cost: 0.0007 }
  const completion = (content: string) =>
    Response.json({
      model: 'vendor/answering-model',
      choices: [{ message: { content }, finish_reason: 'stop' }],
      usage,
    })
  const workout = {
    name: 'Easy run',
    description: 'Easy 30 minutes.',
    sport: 'running',
    steps: [{ type: 'work', goal: { type: 'duration', value: 1800 } }],
  }
  const recentWorkouts = {
    workouts: [{ date: '2026-09-16', distance: 5000, duration: 1800, pace: 6 }],
    totalDistance: 5000,
    totalDuration: 1800,
    totalCalories: 300,
    avgPace: 6,
  }
  const suggestion =
    'Easy return\n\n- Warm up: 5 min at 6:00/km\n- Run: 20 min at 5:40/km\n- Cool down: 5 min at 6:10/km'
  const readiness = { recovery: { hrv: 60, restingHeartRate: 50 }, language: 'en' }

  test.each([
    [
      '/api/generate-workout',
      { userQuestion: 'Easy 30 min run', language: 'en' },
      JSON.stringify(workout),
    ],
    [
      '/api/workout/smart-suggestion',
      { promptType: 'workout_suggestion', language: 'en', data: { recentWorkouts } },
      suggestion,
    ],
    [
      '/api/analyze-history/batch',
      {
        workouts: [{ date: '2026-09-13', duration: 1800, distance: 5000 }],
        batchIndex: 0,
        language: 'en',
      },
      'One 5 km run.',
    ],
    [
      '/api/analyze-history/consolidate',
      { batchSummaries: ['One 5 km run.'], totalWorkouts: 1, language: 'en' },
      'One 5 km run.',
    ],
    [
      '/api/daily-readiness',
      readiness,
      JSON.stringify({ summary: 'Easy day.', detail: 'Keep today easy.' }),
    ],
  ])('%s reports the usage, cost and model returned by OpenRouter', async (path, body, content) => {
    const { response, generations } = await send(path, body, completion(content))
    expect(response.status).toBe(200)
    expect(generations).toHaveLength(1)
    expect(generations[0].properties).toMatchObject({
      $ai_model: 'vendor/answering-model',
      $ai_input_tokens: 321,
      $ai_output_tokens: 54,
      $ai_total_cost_usd: 0.0007,
      route: path,
    })
  })

  test('workout generation adds up the usage of every attempt', async () => {
    let call = 0
    const { response, generations } = await send(
      '/api/generate-workout',
      { userQuestion: 'Easy 30 min run', language: 'en' },
      () =>
        completion(
          call++ === 0 ? JSON.stringify({ ...workout, steps: [] }) : JSON.stringify(workout)
        )
    )
    expect(response.status).toBe(200)
    expect(generations[0].properties).toMatchObject({
      $ai_input_tokens: 642,
      $ai_output_tokens: 108,
    })
    expect(generations[0].properties.$ai_total_cost_usd).toBeCloseTo(0.0014)
  })

  test('daily readiness reports an unusable coaching output as an AI error', async () => {
    const { response, text, generations } = await send(
      '/api/daily-readiness',
      readiness,
      completion('Not JSON')
    )
    expect(response.status).toBe(200)
    expect(JSON.parse(text).coachingSource).toBe('fallback')
    expect(generations).toHaveLength(1)
    expect(generations[0].properties).toMatchObject({
      $ai_is_error: true,
      $ai_error: 'Invalid coaching output',
      $ai_total_cost_usd: 0.0007,
      route: '/api/daily-readiness',
    })
  })
})
