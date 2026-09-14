import { afterEach, describe, expect, mock, spyOn, test } from 'bun:test'
import app from '../src/routes/analyzeHistory'

afterEach(() => mock.restore())

async function analyze(content: unknown, cached: string | null = null, finishReason = 'stop') {
  const put = mock(async () => {})
  const fetchMock = spyOn(globalThis, 'fetch').mockResolvedValueOnce(
    Response.json({ choices: [{ message: { content }, finish_reason: finishReason }] })
  )
  const response = await app.request(
    '/batch',
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-User-ID': 'test-user' },
      body: JSON.stringify({
        batchIndex: 0,
        language: 'en',
        model: 'test-model',
        workouts: [{ date: '2026-09-13', duration: 1800, distance: 5000 }],
      }),
    },
    {
      OPENROUTER_API_KEY: 'test-key',
      APP_SECRET: 'test-secret',
      POSTHOG_API_KEY: '',
      POSTHOG_HOST: '',
      RATE_LIMITER: { get: async () => cached, put } as unknown as KVNamespace,
    },
    { waitUntil: () => {}, passThroughOnException: () => {} }
  )
  return { response, put, fetchMock }
}

describe('history analysis summaries', () => {
  test.each([
    '',
    '  \n\t',
    null,
  ])('rejects empty output %p without caching it as successful', async (content) => {
    const { response, put } = await analyze(content)
    expect(response.status).toBe(500)
    expect(put).not.toHaveBeenCalled()
  })

  test('does not cache output cut off by the token limit', async () => {
    const { response, put } = await analyze('Partial analysis', null, 'length')
    expect(response.status).toBe(500)
    expect(put).not.toHaveBeenCalled()
  })

  test('regenerates an empty summary persisted by an earlier version', async () => {
    const { response, fetchMock } = await analyze(
      'One 5 km run.',
      JSON.stringify({ partialSummary: '', workoutCount: 1 })
    )
    expect(response.status).toBe(200)
    expect((await response.json()).partialSummary).toBe('One 5 km run.')
    expect(fetchMock).toHaveBeenCalledTimes(1)
  })

  test('reuses a valid summary without calling the model', async () => {
    const { response, fetchMock } = await analyze(
      'Unused',
      JSON.stringify({ partialSummary: 'One 5 km run.', workoutCount: 1 })
    )
    expect(response.status).toBe(200)
    expect((await response.json()).partialSummary).toBe('One 5 km run.')
    expect(fetchMock).not.toHaveBeenCalled()
  })
})
