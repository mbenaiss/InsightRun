import { afterEach, describe, expect, mock, spyOn, test } from 'bun:test'
import app from '../src/routes/agentChat'

afterEach(() => mock.restore())

async function chat(upstream: string) {
  const put = mock(async () => {})
  spyOn(globalThis, 'fetch').mockResolvedValueOnce(new Response(upstream))
  const response = await app.request(
    '/chat',
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-User-ID': 'test-user' },
      body: JSON.stringify({ userQuestion: 'Hello', language: 'en', data: {} }),
    },
    {
      OPENROUTER_API_KEY: 'test-key',
      APP_SECRET: 'test-secret',
      POSTHOG_API_KEY: '',
      POSTHOG_HOST: '',
      RATE_LIMITER: { get: async () => null, put } as unknown as KVNamespace,
    },
    { waitUntil: () => {}, passThroughOnException: () => {} }
  )
  return { output: await response.text(), put }
}

describe('agent streaming failures', () => {
  test('does not charge quota for an empty completed answer', async () => {
    const { output, put } = await chat('data: [DONE]\n\n')
    expect(output).toContain('"type":"error"')
    expect(output).not.toContain('[DONE]')
    expect(put).not.toHaveBeenCalled()
  })

  test('surfaces an upstream error instead of a successful completion', async () => {
    const { output, put } = await chat(
      'data: {"error":{"message":"Provider failed"}}\n\ndata: [DONE]\n\n'
    )
    expect(output).toContain('"type":"error"')
    expect(output).not.toContain('[DONE]')
    expect(put).not.toHaveBeenCalled()
  })

  test('rejects a connection closed without the completion marker', async () => {
    const { output, put } = await chat('data: {"choices":[{"delta":{"content":"Partial"}}]}\n\n')
    expect(output).toContain('"type":"error"')
    expect(put).not.toHaveBeenCalled()
  })

  test('forwards a completed answer', async () => {
    const { output } = await chat(
      'data: {"choices":[{"delta":{"content":"Hello."}}]}\n\ndata: [DONE]\n\n'
    )
    expect(output).toContain('"content":"Hello."')
    expect(output).toContain('[DONE]')
    expect(output).not.toContain('"type":"error"')
  })
})
