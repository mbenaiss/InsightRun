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
        headers: {
          'X-App-Key': 'test-secret',
          'X-User-ID': 'quota-test-user',
          'CF-Connecting-IP': '192.0.2.1',
        },
      },
      {
        APP_SECRET: 'test-secret',
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

test('an accounting failure preserves a response already produced by the route', async () => {
  const pending: Promise<unknown>[] = []
  const errors = spyOn(console, 'error').mockImplementation(() => {})
  const put = mock(async () => {
    throw new Error('KV PUT failed: 503')
  })
  const response = await app.request(
    '/api/config',
    { headers: { 'X-App-Key': 'test-secret' } },
    {
      APP_SECRET: 'test-secret',
      RATE_LIMITER: {
        get: async () => null,
        getWithMetadata: async () => ({ value: null, metadata: null }),
        put,
      } as unknown as KVNamespace,
    },
    {
      waitUntil: (promise: Promise<unknown>) => {
        pending.push(promise)
      },
      passThroughOnException: () => {},
    }
  )
  expect(response.status).toBe(200)
  expect(response.headers.get('X-RateLimit-IP-Limit')).toBe('100')
  await Promise.all(pending)
  expect(put).toHaveBeenCalled()
  expect(errors).toHaveBeenCalledWith('quota_accounting_failed', {
    route: '/api/config',
    failures: [{ status: '503' }],
  })
})

describe('quota accounting requires a valid app key', () => {
  function environment() {
    const kv = {
      get: mock(async () => null),
      getWithMetadata: mock(async () => ({ value: null, metadata: null })),
      list: mock(async () => ({ keys: [] })),
      put: mock(async () => {}),
    }
    const pending: Promise<unknown>[] = []
    return {
      kv,
      pending,
      env: {
        APP_SECRET: 'test-secret',
        ADMIN_SECRET: 'admin-secret',
        STRAVA_WEBHOOK_VERIFY_TOKEN: 'verify-token',
        RATE_LIMITER: kv as unknown as KVNamespace,
      },
      execution: {
        waitUntil: (promise: Promise<unknown>) => {
          pending.push(promise)
        },
        passThroughOnException: () => {},
      },
    }
  }

  test.each([
    ['POST', '/api/chat'],
    ['POST', '/api/chat/v2'],
    ['GET', '/api/config'],
    ['POST', '/api/agent/chat'],
    ['POST', '/api/daily-readiness'],
    ['POST', '/api/analyze-history/batch'],
    ['POST', '/api/analyze-history/consolidate'],
    ['POST', '/api/generate-workout'],
    ['POST', '/api/workout/smart-suggestion'],
    ['POST', '/api/generate-training-plan'],
    ['POST', '/api/adapt-training-plan'],
    ['POST', '/api/strava/exchange-token'],
    ['POST', '/api/strava/refresh-token'],
    ['GET', '/api/strava/activities'],
    ['GET', '/api/strava/activities/1'],
    ['POST', '/api/strava/sync'],
    ['GET', '/api/strava/stats'],
    ['DELETE', '/api/strava/disconnect'],
  ])('%s %s rejects a missing or wrong key before reading or charging quota', async (method, path) => {
    const fetchMock = spyOn(globalThis, 'fetch').mockRejectedValue(new Error('Unexpected call'))
    for (const key of [undefined, 'wrong-key']) {
      const { kv, env, execution, pending } = environment()
      const response = await app.request(
        path,
        {
          method,
          headers: {
            'X-User-ID': 'victim-user',
            'CF-Connecting-IP': '192.0.2.1',
            ...(key ? { 'X-App-Key': key } : {}),
          },
        },
        env,
        execution
      )
      await Promise.all(pending)
      expect(response.status).toBe(401)
      expect(await response.json()).toEqual({ error: 'Unauthorized', message: 'Invalid app key' })
      for (const operation of Object.values(kv)) expect(operation).not.toHaveBeenCalled()
    }
    expect(fetchMock).not.toHaveBeenCalled()
  })

  test('public stats stay public and only a keyed call is metered', async () => {
    for (const key of [undefined, 'test-secret']) {
      const { kv, env, execution, pending } = environment()
      const response = await app.request(
        '/api/stats',
        {
          headers: {
            'X-User-ID': 'victim-user',
            'CF-Connecting-IP': '192.0.2.1',
            ...(key ? { 'X-App-Key': key } : {}),
          },
        },
        env,
        execution
      )
      await Promise.all(pending)
      expect(response.status).toBe(200)
      expect((await response.json()).requestsRemaining).toBe(100)
      expect(kv.put).toHaveBeenCalledTimes(key ? 2 : 0)
      expect(response.headers.has('X-RateLimit-IP-Limit')).toBe(key !== undefined)
    }
  })

  test('Strava webhooks and admin routes keep their own authentication without quota', async () => {
    const { kv, env, execution, pending } = environment()
    const webhook = await app.request(
      '/api/strava/webhooks/callback?hub.mode=subscribe&hub.verify_token=verify-token&hub.challenge=abc',
      {},
      env,
      execution
    )
    expect(webhook.status).toBe(200)
    expect(await webhook.json()).toEqual({ 'hub.challenge': 'abc' })

    const admin = await app.request('/api/admin/config', {}, env, execution)
    expect(admin.status).toBe(401)
    expect((await admin.json()).message).toBe('Invalid admin key')

    await Promise.all(pending)
    for (const operation of Object.values(kv)) expect(operation).not.toHaveBeenCalled()
  })
})
