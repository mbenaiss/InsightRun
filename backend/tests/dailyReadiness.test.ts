import { afterEach, describe, expect, spyOn, test } from 'bun:test'
import app, { calculateReadinessScore } from '../src/routes/dailyReadiness'
import fixtures from './fixtures/recovery-scores.json'

let fetchMock: ReturnType<typeof spyOn<typeof globalThis, 'fetch'>> | undefined
const env = {
  OPENROUTER_API_KEY: 'test-key',
  APP_SECRET: 'test-secret',
  RATE_LIMITER: { get: async () => null, put: async () => {} } as KVNamespace,
}
afterEach(() => fetchMock?.mockRestore())

async function request(body: unknown) {
  fetchMock = spyOn(globalThis, 'fetch').mockResolvedValue(
    Response.json({
      choices: [
        {
          message: {
            content: JSON.stringify({
              summary: 'Take an easy day.',
              detail: 'Take an easy day and review your recovery tomorrow.',
            }),
          },
        },
      ],
    })
  )
  return app.request(
    '/',
    { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) },
    env
  )
}

describe('readiness numerical contract shared with iOS', () => {
  for (const fixture of fixtures) {
    test(fixture.name, () => {
      expect(
        calculateReadinessScore(fixture.recovery, fixture.baseline, fixture.noSleepMode).score
      ).toBe(fixture.expected)
    })
  }
})

describe('readiness endpoint', () => {
  test.each([
    undefined,
    61,
  ])('RMSSD changes coaching context without changing the legacy response or score: %p', async (cachedScore) => {
    const body = { ...fixtures[0], cachedScore, language: 'fr' }
    const oldResponse = await request(body)
    const oldResult = await oldResponse.json()
    fetchMock?.mockRestore()
    const response = await request({
      ...body,
      recovery: {
        ...body.recovery,
        date: '2026-09-21T00:00:00+02:00',
        rmssd: {
          metric: 'RMSSD',
          context: 'asleep',
          source: 'com.apple.health/Watch8,3/27.0',
          sourceChanged: false,
          latestSampleAt: '2026-09-21T05:00:00Z',
          measuredAt: '2026-09-21T12:00:00Z',
          currentNight: { date: '2026-09-21T00:00:00+02:00', median: 92, sampleCount: 50 },
          baselineMedian: 95,
          baselineNights: 7,
          recentMedian: 92,
          recentNights: 1,
          nights: [{ date: '2026-09-21T00:00:00+02:00', median: 92, sampleCount: 50 }],
        },
      },
    })
    expect(oldResponse.status).toBe(200)
    expect(response.status).toBe(200)
    expect(await response.json()).toEqual(oldResult)
    const prompt = JSON.parse(String(fetchMock?.mock.calls[0]?.[1]?.body))
    expect(prompt.messages[1].content).toContain('Night-time RMSSD')
    expect(prompt.messages[1].content).toContain('HRV SDNN: 60 ms')
  })

  test('preserves decimal measurements in the calculation and insights', async () => {
    const recovery = {
      hrv: 75.4,
      restingHeartRate: 50.6,
      respiratoryRate: 12.5,
      oxygenSaturation: 98.7,
    }
    const response = await request({ recovery, language: 'fr' })
    const result = await response.json()
    expect(response.status).toBe(200)
    expect(result.score).toBe(calculateReadinessScore(recovery).score)
    expect(
      result.insights.find((insight: { metric: string }) => insight.metric === 'HRV').value
    ).toBe(75.4)
  })

  test.each([
    {},
    { walkingHeartRate: 80 },
  ])('does not invent a score without scoring measurements %p', async (recovery) => {
    const response = await request({ recovery })
    expect(response.status).toBe(422)
    expect(fetchMock).not.toHaveBeenCalled()
  })

  test('excludes an isolated sleep record in no-sleep mode', async () => {
    const response = await request({
      recovery: { sleepData: { totalDuration: 28800, efficiency: 90 } },
      noSleepMode: true,
    })
    expect(response.status).toBe(422)
    expect(fetchMock).not.toHaveBeenCalled()
  })

  test.each([
    { recovery: { hrv: -2 } },
    { recovery: { hrv: '75' } },
    { recovery: { oxygenSaturation: 101 } },
    { recovery: { sleepData: { totalDuration: -1, efficiency: 90 } } },
    { recovery: { hrv: 60 }, cachedScore: 200 },
    { recovery: { hrv: 60 }, cachedScore: 50.5 },
    {
      recovery: { hrv: 60 },
      recentWorkouts: [
        { date: '2026-09-16', distanceMeters: 42000, durationSeconds: 14400, hoursAgo: -4 },
      ],
    },
  ])('rejects invalid numerical inputs before coaching %p', async (body) => {
    expect((await request(body)).status).toBe(400)
    expect(fetchMock).not.toHaveBeenCalled()
  })

  test('keeps a frozen score but derives its matching status', async () => {
    const response = await request({
      recovery: { hrv: 60 },
      cachedScore: 20,
      cachedStatus: 'excellent',
    })
    const result = await response.json()
    expect(result.score).toBe(20)
    expect(result.status).toBe('poor')
  })

  test('preserves recovery measurements when older clients send conflicting sleep stages', async () => {
    const fixture = fixtures.find(
      (item) => item.name === 'conflicting-stages-preserve-other-signals'
    )
    expect(fixture).toBeDefined()
    const response = await request(fixture)
    const result = await response.json()
    expect(response.status).toBe(200)
    expect(result.score).toBe(61)
    expect(
      result.insights.find((insight: { metric: string }) => insight.metric === 'HRV').value
    ).toBe(60)
    expect(fetchMock).toHaveBeenCalledTimes(1)
  })

  test('preserves other signals when older clients send a zero-duration sleep record', async () => {
    const fixture = fixtures.find((item) => item.name === 'zero-duration-sleep-is-unavailable')
    expect(fixture).toBeDefined()
    const response = await request(fixture)
    expect(response.status).toBe(200)
    expect((await response.json()).score).toBe(58)
  })

  test('does not invent a score from an isolated zero-duration sleep record', async () => {
    const response = await request({ recovery: { sleepData: { totalDuration: 0, efficiency: 0 } } })
    expect(response.status).toBe(422)
    expect(fetchMock).not.toHaveBeenCalled()
  })

  test('applies only the largest recent-effort penalty, including a fourth workout', async () => {
    const easy = { date: '2026-09-15', distanceMeters: 5000, durationSeconds: 1800, hoursAgo: 12 }
    const race = { ...easy, distanceMeters: 42000, durationSeconds: 14400, hoursAgo: 84 }
    const response = await request({ ...fixtures[0], recentWorkouts: [easy, easy, easy, race] })
    expect((await response.json()).score).toBe(51)
  })

  test('does not apply the race penalty twice to a frozen score', async () => {
    const response = await request({
      ...fixtures[0],
      cachedScore: 51,
      recentWorkouts: [
        { date: '2026-09-13', distanceMeters: 42000, durationSeconds: 14400, hoursAgo: 84 },
      ],
    })
    expect((await response.json()).score).toBe(51)
  })
})

async function requestWithMock(body: unknown, payload: unknown, status = 200) {
  fetchMock = spyOn(globalThis, 'fetch').mockResolvedValue(Response.json(payload, { status }))
  return app.request(
    '/',
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    },
    env
  )
}

describe('dashboard coaching resilience', () => {
  test('returns validated AI text and a concise prompt with a consistent training ceiling', async () => {
    const response = await request({
      recovery: { hrv: 75 },
      language: 'fr',
      noSleepMode: true,
      cardiacLoad: { score: 18, status: 'overreaching' },
    })
    const result = await response.json()
    expect(result.coachingSource).toBe('ai')
    expect(result.suggestedWorkoutType).toBe('rest')
    const body = JSON.parse(String(fetchMock?.mock.calls[0]?.[1]?.body))
    expect(body.messages[0].content).toContain('training ceiling is rest')
    expect(body.messages[0].content).toContain('do not mention sleep')
    expect(body.messages[0].content.length).toBeLessThan(1800)
    expect(body.reasoning).toEqual({ effort: 'low', exclude: true })
  })

  test.each([
    '{"summary":"Go run","detail":"An unfinished',
    '{"summary":"","detail":""}',
    '{"summary":12,"detail":null}',
    'Plain text instead of structured analysis',
    'null',
  ])('uses a safe fallback for malformed or incomplete analysis %s', async (content) => {
    const response = await requestWithMock(
      { recovery: { hrv: 75 }, language: 'fr' },
      {
        choices: [{ message: { content }, finish_reason: 'stop' }],
      }
    )
    const result = await response.json()
    expect(response.status).toBe(200)
    expect(result.coachingSource).toBe('fallback')
    expect(result.summary.length).toBeGreaterThan(0)
    expect(result.detail).not.toContain('{')
    expect(fetchMock).toHaveBeenCalledTimes(1)
  })

  test('rejects a token-limited response even if its JSON happens to be valid', async () => {
    const response = await requestWithMock(
      { recovery: { hrv: 75 } },
      {
        choices: [
          {
            message: {
              content: JSON.stringify({ summary: 'AI text', detail: 'Incomplete reasoning' }),
            },
            finish_reason: 'length',
          },
        ],
      }
    )
    expect((await response.json()).coachingSource).toBe('fallback')
  })

  test('does not retry an unavailable provider and preserves the score', async () => {
    const response = await requestWithMock(
      { recovery: { hrv: 75 }, cachedScore: 80 },
      { error: 'Unavailable' },
      503
    )
    const result = await response.json()
    expect(result.score).toBe(80)
    expect(result.coachingSource).toBe('fallback')
    expect(fetchMock).toHaveBeenCalledTimes(1)
  })

  test('fallback and workout type respect a recent race even with a frozen high score', async () => {
    const response = await requestWithMock(
      {
        recovery: { hrv: 75 },
        cachedScore: 95,
        language: 'fr',
        recentWorkouts: [
          { date: '2026-09-13', distanceMeters: 42000, durationSeconds: 14400, hoursAgo: 72 },
        ],
      },
      { error: 'Unavailable' },
      503
    )
    const result = await response.json()
    expect(result.suggestedWorkoutType).toBe('rest')
    expect(result.detail).toContain('effort long récent')
    expect(result.detail).not.toContain('séance de qualité')
  })

  test('caps hard-effort advice without overriding a stricter cardiac-load recommendation', async () => {
    const response = await request({
      recovery: { hrv: 75 },
      cachedScore: 40,
      cardiacLoad: { score: 12, status: 'increasing' },
      recentWorkouts: [
        { date: '2026-09-16', distanceMeters: 22000, durationSeconds: 7200, hoursAgo: 6 },
      ],
    })
    expect((await response.json()).suggestedWorkoutType).toBe('rest')
  })

  test('keeps the timeout active after headers until the response body completes', async () => {
    const originalSetTimeout = globalThis.setTimeout
    const timer = spyOn(globalThis, 'setTimeout').mockImplementation(((
      handler: TimerHandler,
      timeout?: number
    ) => originalSetTimeout(handler, timeout === 12000 ? 10 : timeout)) as typeof setTimeout)
    let aborted = false
    fetchMock = spyOn(globalThis, 'fetch').mockImplementation(async (_url, init) => {
      const body = new ReadableStream<Uint8Array>({
        start(controller) {
          init?.signal?.addEventListener(
            'abort',
            () => {
              aborted = true
              controller.error(new DOMException('Aborted', 'AbortError'))
            },
            { once: true }
          )
          controller.enqueue(new TextEncoder().encode('{"choices":['))
        },
      })
      return new Response(body, { headers: { 'Content-Type': 'application/json' } })
    })
    try {
      const response = await app.request(
        '/',
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ recovery: { hrv: 75 } }),
        },
        env
      )
      expect(aborted).toBe(true)
      expect((await response.json()).coachingSource).toBe('fallback')
      expect(fetchMock).toHaveBeenCalledTimes(1)
    } finally {
      timer.mockRestore()
    }
  })
})
