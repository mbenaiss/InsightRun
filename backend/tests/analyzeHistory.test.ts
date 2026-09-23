import { afterEach, describe, expect, mock, spyOn, test } from 'bun:test'
import * as analytics from '../src/posthog'
import app from '../src/routes/analyzeHistory'

afterEach(() => mock.restore())

async function requestAnalysis(
  route: 'batch' | 'consolidate',
  cached: string | null = null,
  reportErrors = false
) {
  const put = mock(async () => {})
  const pending: Promise<unknown>[] = []
  const response = await app.request(
    `/${route}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-User-ID': 'test-user' },
      body: JSON.stringify({
        language: 'en',
        model: 'google/gemini-2.5-flash',
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
      POSTHOG_API_KEY: reportErrors ? 'test-key' : '',
      POSTHOG_HOST: reportErrors ? 'https://example.invalid' : '',
      RATE_LIMITER: { get: async () => cached, put } as unknown as KVNamespace,
    },
    {
      waitUntil: (promise: Promise<unknown>) => {
        pending.push(promise)
      },
      passThroughOnException: () => {},
    }
  )
  await Promise.all(pending)
  return { response, put }
}

async function analyze(content: unknown, cached: string | null = null, finishReason = 'stop') {
  const fetchMock = spyOn(globalThis, 'fetch').mockImplementation(async () =>
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
    ['batch', 4096],
    ['consolidate', 6000],
  ] as const)('%s reserves space for reasoning and completes in one call', async (route, budget) => {
    const fetchMock = spyOn(globalThis, 'fetch').mockResolvedValueOnce(
      Response.json({ choices: [{ message: { content: 'One 5 km run.' }, finish_reason: 'stop' }] })
    )

    const { response } = await requestAnalysis(route)

    expect(response.status).toBe(200)
    expect(fetchMock).toHaveBeenCalledTimes(1)
    const request = JSON.parse(String(fetchMock.mock.calls[0][1]?.body))
    expect(request.max_tokens).toBe(budget)
    expect(request.reasoning).toEqual({ effort: 'low', exclude: true })
  })

  test('a larger generation budget cannot overflow the consolidation input limit', async () => {
    const { response, put } = await analyze('One 5 km run with a steady pace. '.repeat(200))

    const result = await response.json()
    expect(response.status).toBe(200)
    expect(result.partialSummary.length).toBeGreaterThan(0)
    expect(result.partialSummary.length).toBeLessThanOrEqual(4000)
    expect(JSON.parse(String(put.mock.calls[0][1])).partialSummary).toBe(result.partialSummary)
  })

  test.each([
    '',
    '  \n\t',
    null,
  ])('rejects empty output %p without caching it as successful', async (content) => {
    fastForwardTimers()
    const { response, put, fetchMock } = await analyze(content)
    expect(response.status).toBe(502)
    expect(fetchMock).toHaveBeenCalledTimes(2)
    expect(put).not.toHaveBeenCalled()
  })

  test('does not cache output cut off by the token limit', async () => {
    fastForwardTimers()
    const { response, put, fetchMock } = await analyze('Partial analysis', null, 'length')
    expect(response.status).toBe(502)
    expect(fetchMock).toHaveBeenCalledTimes(2)
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
    ['batch', '', 'stop', 4096],
    ['batch', null, 'length', 8192],
    ['batch', 'Partial analysis', 'length', 8192],
    ['consolidate', '', 'stop', 6000],
    ['consolidate', null, 'length', 12000],
    ['consolidate', 'Partial analysis', 'length', 12000],
  ] as const)('%s recovers from output %p ending with %s', async (route, content, finishReason, budget) => {
    fastForwardTimers()
    const fetchMock = spyOn(globalThis, 'fetch')
      .mockResolvedValueOnce(
        Response.json({ choices: [{ message: { content }, finish_reason: finishReason }] })
      )
      .mockResolvedValueOnce(
        Response.json({
          choices: [{ message: { content: 'One 5 km run.' }, finish_reason: 'stop' }],
        })
      )

    const { response, put } = await requestAnalysis(route)

    expect(response.status).toBe(200)
    const result = await response.json()
    expect(route === 'batch' ? result.partialSummary : result.summary).toBe('One 5 km run.')
    expect(fetchMock).toHaveBeenCalledTimes(2)
    const firstRequest = JSON.parse(String(fetchMock.mock.calls[0][1]?.body))
    const secondRequest = JSON.parse(String(fetchMock.mock.calls[1][1]?.body))
    expect(secondRequest.max_tokens).toBe(budget)
    expect(secondRequest.messages[0].content).toContain(firstRequest.messages[0].content)
    expect(secondRequest.messages[1]).toEqual(firstRequest.messages[1])
    expect(put).toHaveBeenCalledTimes(1)
    expect(JSON.parse(String(put.mock.calls[0][1]))).toEqual(
      route === 'batch'
        ? { partialSummary: 'One 5 km run.', workoutCount: 1 }
        : { summary: 'One 5 km run.' }
    )
  })

  test('recovers when the provider omits the completion choice', async () => {
    fastForwardTimers()
    const fetchMock = spyOn(globalThis, 'fetch')
      .mockResolvedValueOnce(Response.json({ choices: [] }))
      .mockResolvedValueOnce(
        Response.json({ choices: [{ message: { content: 'One 5 km run.' } }] })
      )

    const { response, put } = await requestAnalysis('batch')

    expect(response.status).toBe(200)
    expect(fetchMock).toHaveBeenCalledTimes(2)
    expect(put).toHaveBeenCalledTimes(1)
  })

  test.each([
    { content: '', finishReason: 'content_filter', refusal: null },
    { content: 'Partial analysis', finishReason: 'content_filter', refusal: null },
    { content: '', finishReason: 'stop', refusal: 'Request refused.' },
    { content: '', finishReason: 'tool_calls', refusal: null },
  ])('does not retry or cache blocked or non-text completions: %p', async ({
    content,
    finishReason,
    refusal,
  }) => {
    const fetchMock = spyOn(globalThis, 'fetch').mockResolvedValueOnce(
      Response.json({ choices: [{ message: { content, refusal }, finish_reason: finishReason }] })
    )

    const { response, put } = await requestAnalysis('batch')

    expect(response.status).toBe(502)
    expect(fetchMock).toHaveBeenCalledTimes(1)
    expect(put).not.toHaveBeenCalled()
  })

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

  test('does not add a third attempt if the retry returns an incomplete summary', async () => {
    fastForwardTimers()
    const fetchMock = spyOn(globalThis, 'fetch')
      .mockResolvedValueOnce(new Response('Unavailable', { status: 503 }))
      .mockResolvedValueOnce(
        Response.json({ choices: [{ message: { content: 'Partial' }, finish_reason: 'length' }] })
      )

    const { response, put } = await requestAnalysis('consolidate')

    expect(response.status).toBe(502)
    expect(fetchMock).toHaveBeenCalledTimes(2)
    expect(put).not.toHaveBeenCalled()
  })

  test('reports incomplete output diagnostics without exporting summary or reasoning content', async () => {
    fastForwardTimers()
    const capture = mock(async () => {})
    spyOn(analytics, 'createPostHogClient').mockReturnValue({
      captureImmediate: capture,
      shutdown: mock(async () => {}),
    } as unknown as ReturnType<typeof analytics.createPostHogClient>)
    const fetchMock = spyOn(globalThis, 'fetch').mockImplementation(async () =>
      Response.json({
        choices: [
          { message: { content: null, reasoning: 'Private reasoning' }, finish_reason: 'length' },
        ],
        usage: { completion_tokens: 8192, completion_tokens_details: { reasoning_tokens: 8192 } },
      })
    )

    const { response, put } = await requestAnalysis('batch', null, true)

    expect(response.status).toBe(502)
    expect(fetchMock).toHaveBeenCalledTimes(2)
    expect(put).not.toHaveBeenCalled()
    expect(capture).toHaveBeenCalledTimes(1)
    expect(capture).toHaveBeenCalledWith({
      distinctId: 'test-user',
      event: 'indexation_failed_backend',
      properties: {
        route: 'batch',
        error_type: 'OpenRouterSummaryError',
        error_message: 'History analysis returned an empty or incomplete summary. Please retry.',
        openrouter_status: undefined,
        model: 'google/gemini-2.5-flash',
        finish_reason: 'length',
        max_tokens: 8192,
        output_length: 0,
        completion_tokens: 8192,
        reasoning_tokens: 8192,
        timestamp: expect.any(Number),
      },
    })
  })
})
