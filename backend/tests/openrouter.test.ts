import { afterEach, describe, expect, mock, spyOn, test } from 'bun:test'
import { callOpenRouterWithRetry, OpenRouterEmptyResponseError } from '../src/openrouter'

afterEach(() => mock.restore())

const options = {
  apiKey: 'test-key',
  model: 'test-model',
  fallbackModel: 'fallback-model',
  body: { messages: [{ role: 'user', content: 'Hello' }] },
  timeoutMs: 1000,
  title: 'test',
}

describe('OpenRouter success status without choices', () => {
  test.each([
    ['an error body', () => Response.json({ error: { message: 'Provider returned error' } })],
    ['an empty choice list', () => Response.json({ choices: [] })],
    ['a non-JSON body', () => new Response('<html>Bad gateway</html>')],
  ])('retries %s as an upstream failure', async (_name, upstream) => {
    const fetchMock = spyOn(globalThis, 'fetch')
      .mockResolvedValueOnce(upstream())
      .mockResolvedValueOnce(
        Response.json({ choices: [{ message: { content: 'Recovered' }, finish_reason: 'stop' }] })
      )
    expect(await callOpenRouterWithRetry(options)).toEqual({
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
