import { afterEach, describe, expect, mock, spyOn, test } from 'bun:test'
import app from '../src/routes/analyzeHistory'

afterEach(() => mock.restore())

async function requestAnalysis(route: 'batch' | 'consolidate', cached: string | null = null) {
  const put = mock(async () => {})
  const response = await app.request(
    `/${route}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-User-ID': 'test-user' },
      body: JSON.stringify({
        language: 'en',
        model: 'test-model',
        ...(route === 'batch'
          ? {
              batchIndex: 0,
              workouts: [{ date: '2026-09-13', duration: 1800, distance: 5000 }],
            }
          : { batchSummaries: ['One 5 km run.'], totalWorkouts: 1 }),
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
  return { response, put }
}

async function analyze(content: unknown, cached: string | null = null, finishReason = 'stop') {
  const fetchMock = spyOn(globalThis, 'fetch').mockResolvedValueOnce(
    Response.json({ choices: [{ message: { content }, finish_reason: finishReason }] })
  )
  return { ...(await requestAnalysis('batch', cached)), fetchMock }
}

function fastForwardTimers() {
  const realSetTimeout = globalThis.setTimeout
  let elapsedMs = 0
  spyOn(globalThis, 'setTimeout').mockImplementation((callback, delay, ...args) =>
    realSetTimeout(() => {
      elapsedMs += delay ?? 0
      callback(...args)
    }, 0)
  )
  return () => elapsedMs
}

function waitForAbort(_input: unknown, init?: RequestInit): Promise<Response> {
  return new Promise((_resolve, reject) => {
    init?.signal?.addEventListener('abort', () => reject(new DOMException('Aborted', 'AbortError')))
  })
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

describe('history analysis retries', () => {
  test.each([
    ['batch', 429],
    ['batch', 503],
    ['consolidate', 429],
    ['consolidate', 503],
  ] as const)('%s recovers from HTTP %s with one retry', async (route, status) => {
    fastForwardTimers()
    const fetchMock = spyOn(globalThis, 'fetch')
      .mockResolvedValueOnce(new Response('Unavailable', { status }))
      .mockResolvedValueOnce(
        Response.json({ choices: [{ message: { content: 'One 5 km run.' } }] })
      )

    const { response, put } = await requestAnalysis(route)

    expect(response.status).toBe(200)
    expect(fetchMock).toHaveBeenCalledTimes(2)
    expect(put).toHaveBeenCalledTimes(1)
  })

  test('consolidation leaves at least 5 seconds before the client timeout after two timeouts', async () => {
    const elapsedMs = fastForwardTimers()
    const fetchMock = spyOn(globalThis, 'fetch').mockImplementation(waitForAbort)

    const { response, put } = await requestAnalysis('consolidate')

    expect(response.status).toBe(504)
    expect(fetchMock).toHaveBeenCalledTimes(2)
    expect(put).not.toHaveBeenCalled()
    expect(elapsedMs()).toBeGreaterThan(0)
    expect(elapsedMs()).toBeLessThanOrEqual(120_000 - 5_000)
  })

  test('consolidation can still succeed after the first attempt times out', async () => {
    fastForwardTimers()
    const fetchMock = spyOn(globalThis, 'fetch')
      .mockImplementationOnce(waitForAbort)
      .mockResolvedValueOnce(
        Response.json({ choices: [{ message: { content: 'One 5 km run.' } }] })
      )

    const { response, put } = await requestAnalysis('consolidate')

    expect(response.status).toBe(200)
    expect((await response.json()).summary).toBe('One 5 km run.')
    expect(fetchMock).toHaveBeenCalledTimes(2)
    expect(put).toHaveBeenCalledTimes(1)
  })
})
