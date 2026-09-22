import { afterEach, describe, expect, mock, spyOn, test } from 'bun:test'
import { z } from 'zod'
import app from '../src/index'
import legacy from './fixtures/legacy-clients.json'
import recoveryScores from './fixtures/recovery-scores.json'

afterEach(() => mock.restore())

const data116 = {
  workout: legacy.workout,
  recovery: legacy.recovery116,
  profile: legacy.profile,
  baseline: legacy.baseline,
  recentWorkouts: {
    workouts: [legacy.workout],
    totalDistance: 5000,
    totalDuration: 1800,
    totalCalories: 350,
    avgPace: 6,
  },
  historicalSummary: 'One 5 km run.',
}
const data2010 = {
  ...data116,
  workout: {
    ...legacy.workout,
    splits: legacy.workout.splits.map((split) => ({ ...split, distanceMeters: 1000 })),
  },
  recovery: legacy.recovery2010,
}
const answer = 'Séance régulière.'
const streamAnswer = `data: ${JSON.stringify({ choices: [{ delta: { content: answer } }] })}\n\ndata: [DONE]\n\n`

// Freeze the fields decoded by installed clients, independently of current server types.
const readinessResponse = z.object({
  score: z.number().int().min(0).max(100),
  status: z.enum(['excellent', 'good', 'fair', 'poor']),
  recommendation: z.string().min(1),
  suggestedWorkoutType: z.enum(['intense', 'moderate', 'easy', 'rest']),
  insights: z.array(
    z.object({
      metric: z.string(),
      value: z.number(),
      comparison: z.enum(['above', 'at', 'below']),
      deviation: z.number().optional(),
      message: z.string(),
    })
  ),
})
const batchResponse = z.object({
  batchIndex: z.number().int(),
  partialSummary: z.string().min(1),
  workoutCount: z.number().int(),
  tokenCount: z.number().int(),
})
const consolidateResponse = z.object({
  summary: z.string().min(1),
  workoutCount: z.number().int(),
  tokenCount: z.number().int(),
})

async function request(
  path: string,
  body: unknown,
  upstream = new Response(streamAnswer),
  options: { authenticated?: boolean; cached?: string; cacheKey?: string; userID?: boolean } = {}
) {
  const fetchMock = spyOn(globalThis, 'fetch').mockResolvedValue(upstream)
  const pending: Promise<unknown>[] = []
  const response = await app.request(
    path,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'CF-Connecting-IP': '192.0.2.10',
        ...(options.authenticated === false ? {} : { 'X-App-Key': 'test-secret' }),
        ...(options.userID === false ? {} : { 'X-User-ID': 'legacy-test-user' }),
      },
      body: JSON.stringify(body),
    },
    {
      APP_SECRET: 'test-secret',
      OPENROUTER_API_KEY: 'test-key',
      POSTHOG_API_KEY: '',
      POSTHOG_HOST: '',
      RATE_LIMITER: {
        get: async (key: string) => (key === options.cacheKey ? (options.cached ?? null) : null),
        getWithMetadata: async () => ({ value: null, metadata: null }),
        put: async () => {},
      } as unknown as KVNamespace,
    },
    {
      waitUntil: (promise: Promise<unknown>) => pending.push(promise),
      passThroughOnException: () => {},
    }
  )
  const text = await response.text()
  await Promise.all(pending)
  return { response, text, fetchMock }
}

function modelJSON(content: string) {
  return Response.json({ choices: [{ message: { content }, finish_reason: 'stop' }] })
}

function expectLegacyStream(text: string, agent = false) {
  const events = text
    .split('\n')
    .filter((line) => line.startsWith('data: '))
    .map((line) => line.slice(6))
  expect(events.at(-1)).toBe('[DONE]')
  const chunks = events.slice(0, -1).map((event) => JSON.parse(event))
  expect(chunks).toEqual([agent ? { type: 'content', content: answer } : { content: answer }])
}

describe('installed client HTTP contracts', () => {
  test.each([
    { model: 'legacy-model' },
    { requestType: 'MODERATE' },
  ])('v1 chat preserves default SSE and callers without a user ID: %p', async (selection) => {
    const { response, text } = await request(
      '/api/chat',
      { prompt: 'Analyse ma course', systemPrompt: 'Running coach', ...selection },
      new Response(streamAnswer),
      { userID: false }
    )
    expect(response.status).toBe(200)
    expect(response.headers.get('Content-Type')).toContain('text/event-stream')
    expectLegacyStream(text)
  })

  test('v1 classification preserves the response string JSON field', async () => {
    const { response, text } = await request(
      '/api/chat',
      {
        prompt: 'Classe ma question',
        systemPrompt: 'Classifier',
        requestType: 'CLASSIFICATION',
        stream: false,
      },
      modelJSON('SIMPLE')
    )
    expect(response.status).toBe(200)
    expect(JSON.parse(text)).toEqual({ response: 'SIMPLE' })
  })

  for (const [version, data] of [
    ['1.1.6', data116],
    ['2.0.10', data2010],
    ['minimal', { workout: { date: '2026-09-10', duration: 60, distance: 100 } }],
  ] as const) {
    test.each([
      { model: 'legacy-model' },
      { requestType: 'MODERATE' },
    ])(`${version} v2 chat preserves SSE without new measurements: %p`, async (selection) => {
      const { response, text, fetchMock } = await request('/api/chat/v2', {
        promptType: 'workout_coach',
        userQuestion: 'Analyse ma course',
        language: 'fr',
        data,
        ...selection,
      })
      expect(response.status).toBe(200)
      expectLegacyStream(text)
      expect(fetchMock).toHaveBeenCalledTimes(1)
      const prompt = JSON.parse(String(fetchMock.mock.calls[0][1]?.body)).messages[0].content
      expect(prompt).toContain('2026-09-10')
      expect(prompt).not.toContain('Recorded session evidence')
      expect(prompt).not.toContain('Night-time RMSSD')
      expect(prompt).not.toContain('failed validation')
      if (version !== 'minimal') {
        expect(prompt).toContain('140 bpm')
        expect(prompt).toContain('60 ms (SDNN)')
        expect(prompt).toContain('Age-based maximum heart rate estimate:')
        expect(prompt).not.toContain('Estimated Intensity:')
      }
    })
  }

  test.each([
    data116,
    data2010,
    {},
  ])('agent chat preserves its content event contract: %p', async (data) => {
    const { response, text } = await request('/api/agent/chat', {
      userQuestion: 'Analyse ma course',
      language: 'fr',
      data,
      conversationHistory: [{ role: 'user', content: 'Bonjour' }],
    })
    expect(response.status).toBe(200)
    expectLegacyStream(text, true)
  })

  test.each([
    data116.workout,
    data2010.workout,
  ])('history indexation accepts old split formats: %p', async (workout) => {
    const { response, text } = await request(
      '/api/analyze-history/batch',
      { workouts: [workout], batchIndex: 0, model: 'legacy-model', language: 'fr' },
      modelJSON(answer)
    )
    expect(response.status).toBe(200)
    expect(batchResponse.parse(JSON.parse(text))).toEqual({
      batchIndex: 0,
      partialSummary: answer,
      workoutCount: 1,
      tokenCount: expect.any(Number),
    })
  })

  test('history resumes an old cached batch without an AI request', async () => {
    const { response, text, fetchMock } = await request(
      '/api/analyze-history/batch',
      { workouts: [legacy.workout], batchIndex: 2, language: 'fr' },
      modelJSON('Unused'),
      {
        cacheKey:
          'idem:batch:legacy-test-user:5c18d7688b28ae7b6764d97cff0c1d81a71c9ec742603701f1fbd6b819cfa339',
        cached: JSON.stringify({ partialSummary: answer, workoutCount: 1 }),
      }
    )
    expect(response.status).toBe(200)
    expect(batchResponse.parse(JSON.parse(text)).batchIndex).toBe(2)
    expect(fetchMock).not.toHaveBeenCalled()
  })

  test('history consolidation preserves all fields decoded by old apps', async () => {
    const { response, text } = await request(
      '/api/analyze-history/consolidate',
      { batchSummaries: [answer], totalWorkouts: 1, profile: legacy.profile, language: 'fr' },
      modelJSON(answer)
    )
    expect(response.status).toBe(200)
    expect(consolidateResponse.parse(JSON.parse(text)).workoutCount).toBe(1)
  })

  test.each([
    false,
    true,
  ])('daily readiness keeps the legacy recommendation, including fallback=%p', async (fallback) => {
    const { response, text } = await request(
      '/api/daily-readiness',
      { recovery: legacy.recovery2010, cachedScore: 61, language: 'fr' },
      fallback
        ? Response.json({ error: 'Unavailable' }, { status: 503 })
        : modelJSON(
            JSON.stringify({ summary: 'Récupération.', detail: 'Privilégie une sortie facile.' })
          )
    )
    expect(response.status).toBe(200)
    const result = JSON.parse(text)
    expect(readinessResponse.parse(result).score).toBe(61)
    expect(result.recommendation).toBe(result.detail)
    expect(result.coachingSource).toBe(fallback ? 'fallback' : 'ai')
  })

  for (const fixture of recoveryScores) {
    test(`legacy readiness score remains unchanged: ${fixture.name}`, async () => {
      const { response, text } = await request(
        '/api/daily-readiness',
        fixture,
        modelJSON(JSON.stringify({ summary: 'Recovery.', detail: 'Review your sensations.' }))
      )
      expect(response.status).toBe(200)
      expect(readinessResponse.parse(JSON.parse(text)).score).toBe(fixture.expected)
    })
  }

  test.each([
    '/api/chat',
    '/api/chat/v2',
    '/api/agent/chat',
    '/api/daily-readiness',
    '/api/analyze-history/batch',
  ])('legacy access still requires the existing app key: %s', async (path) => {
    const { response, fetchMock } = await request(path, {}, new Response(), {
      authenticated: false,
    })
    expect(response.status).toBe(401)
    expect(fetchMock).not.toHaveBeenCalled()
  })
})
