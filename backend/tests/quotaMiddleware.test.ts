import { afterEach, describe, expect, mock, spyOn, test } from 'bun:test'
import app from '../src/index'
import * as analytics from '../src/posthog'

afterEach(() => mock.restore())

describe('quota rejection telemetry', () => {
  test.each([
    false,
    true,
  ])('reports a rejection without charging quota when analytics fails: %p', async (captureFails) => {
    const resetAt = Math.floor(Date.now() / 1000) + 300
    const capture = mock(async () => {
      if (captureFails) throw new Error('Analytics unavailable')
    })
    spyOn(analytics, 'createPostHogClient').mockReturnValue({
      captureImmediate: capture,
      shutdown: mock(async () => {}),
    } as unknown as ReturnType<typeof analytics.createPostHogClient>)
    const fetchMock = spyOn(globalThis, 'fetch').mockRejectedValue(new Error('Unexpected AI call'))
    const put = mock(async () => {})
    const pending: Promise<unknown>[] = []

    const response = await app.request(
      '/api/agent/chat',
      {
        method: 'POST',
        headers: { 'X-User-ID': 'quota-test-user', 'CF-Connecting-IP': '192.0.2.1' },
      },
      {
        RATE_LIMITER: {
          get: async () => null,
          getWithMetadata: async (key: string) =>
            key.startsWith('ratelimit:user:')
              ? { value: '1000', metadata: { resetAt } }
              : { value: null, metadata: null },
          put,
        } as unknown as KVNamespace,
        POSTHOG_API_KEY: 'test-key',
        POSTHOG_HOST: 'https://example.invalid',
      },
      {
        waitUntil: (promise: Promise<unknown>) => {
          pending.push(promise)
        },
        passThroughOnException: () => {},
      }
    )
    await Promise.all(pending)

    expect(response.status).toBe(429)
    expect(response.headers.get('Retry-After')).toBe('300')
    expect((await response.json()).restrictedBy).toBe('user')
    expect(put).not.toHaveBeenCalled()
    expect(fetchMock).not.toHaveBeenCalled()
    expect(capture).toHaveBeenCalledWith({
      distinctId: 'quota-test-user',
      event: 'api_quota_exceeded',
      properties: {
        route: '/api/agent/chat',
        restricted_by: 'user',
        limit: 1000,
        retry_after_seconds: 300,
        reset_at: resetAt,
        app: 'healthapp',
        environment: 'production',
      },
    })
  })
})
