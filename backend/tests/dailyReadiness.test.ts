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
