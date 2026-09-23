import { afterEach, describe, expect, mock, spyOn, test } from 'bun:test'
import {
  callOpenRouterWithRetry,
  OpenRouterEmptyResponseError,
  OpenRouterHttpError,
} from '../src/openrouter'

afterEach(() => mock.restore())

const options = {
  apiKey: 'test-key',
  model: 'test-model',
  fallbackModel: 'fallback-model',
  body: { messages: [{ role: 'user', content: 'Hello' }] },
  timeoutMs: 1000,
  title: 'test',
}

const recovered = () =>
  Response.json({ choices: [{ message: { content: 'Recovered' }, finish_reason: 'stop' }] })

describe('OpenRouter success status without choices', () => {
  test.each([
    ['an error body', () => Response.json({ error: { message: 'Provider returned error' } })],
    ['an empty choice list', () => Response.json({ choices: [] })],
    ['a non-JSON body', () => new Response('<html>Bad gateway</html>')],
  ])('retries %s as an upstream failure', async (_name, upstream) => {
    const fetchMock = spyOn(globalThis, 'fetch')
      .mockResolvedValueOnce(upstream())
      .mockResolvedValueOnce(recovered())
    expect(await callOpenRouterWithRetry(options)).toMatchObject({
      content: 'Recovered',
      finishReason: 'stop',
    })
    expect(fetchMock).toHaveBeenCalledTimes(2)
  })

  test('fails with a clean message once the attempts are exhausted', async () => {
    const fetchMock = spyOn(globalThis, 'fetch').mockImplementation(async () => Response.json({}))
    const error = await callOpenRouterWithRetry(options).catch((failure: unknown) => failure)
    expect(error).toBeInstanceOf(OpenRouterEmptyResponseError)
    expect((error as Error).message).toBe('OpenRouter returned a response without choices')
    expect(fetchMock).toHaveBeenCalledTimes(2)
  })
})

describe('OpenRouter HTTP and network failures', () => {
  test.each([
    400, 401, 402, 403, 404, 413, 422,
  ])('does not retry the non-retryable HTTP %i', async (status) => {
    const fetchMock = spyOn(globalThis, 'fetch').mockImplementation(
      async () => new Response('Rejected', { status })
    )
    const error = await callOpenRouterWithRetry(options).catch((failure: unknown) => failure)
    expect(error).toBeInstanceOf(OpenRouterHttpError)
    expect((error as OpenRouterHttpError).status).toBe(status)
    expect((error as Error).message).toBe(`OpenRouter API error: ${status} - Rejected`)
    expect(fetchMock).toHaveBeenCalledTimes(1)
  })

  test.each([
    ['HTTP 408', () => new Response('Timeout', { status: 408 })],
    ['HTTP 429', () => new Response('Busy', { status: 429 })],
    ['HTTP 500', () => new Response('Failure', { status: 500 })],
    ['HTTP 503', () => new Response('Unavailable', { status: 503 })],
    [
      'a network error',
      () => {
        throw new TypeError('fetch failed')
      },
    ],
  ])('retries %s once', async (_name, failure) => {
    const fetchMock = spyOn(globalThis, 'fetch')
      .mockImplementationOnce(async () => failure())
      .mockResolvedValueOnce(recovered())
    expect(await callOpenRouterWithRetry(options)).toMatchObject({
      content: 'Recovered',
      finishReason: 'stop',
    })
    expect(fetchMock).toHaveBeenCalledTimes(2)
  })
})
