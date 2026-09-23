import { afterEach, describe, expect, mock, spyOn, test } from 'bun:test'
import * as analytics from '../src/posthog'
import app from '../src/routes/strava'
import { StravaCache } from '../src/services/stravaCache'

afterEach(() => mock.restore())

function setup() {
  const stored = {
    accessToken: 'expired-access',
    refreshToken: 'current-refresh',
    expiresAt: 1,
    athleteId: 42,
    athleteName: 'Test Runner',
    createdAt: 123,
  }
  const put = mock(async (_key: string, _value: string) => {})
  const env = {
    STRAVA_CLIENT_ID: 'test-client',
    STRAVA_CLIENT_SECRET: 'test-secret',
    STRAVA_TOKENS: { get: mock(async () => stored), put } as unknown as KVNamespace,
    STRAVA_CACHE: {} as D1Database,
    POSTHOG_API_KEY: '',
    POSTHOG_HOST: '',
  }
  const execution = { waitUntil: () => {}, passThroughOnException: () => {} }
  const fetchMock = spyOn(globalThis, 'fetch')
  const refreshed = {
    access_token: 'new-access',
    refresh_token: 'new-refresh',
    expires_at: Math.floor(Date.now() / 1000) + 21600,
  }
  return { env, execution, stored, put, fetchMock, refreshed }
}

describe('Strava token refresh', () => {
  test('does not disclose server tokens based only on a user ID', async () => {
    const { env, execution, fetchMock, put } = setup()
    const response = await app.request(
      '/refresh-token',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ userId: 'test-user', refreshToken: 'wrong-token' }),
      },
      env,
      execution
    )
    expect(response.status).toBe(401)
    expect(fetchMock).not.toHaveBeenCalled()
    expect(put).not.toHaveBeenCalled()
  })

  test('preserves athlete metadata when the OAuth refresh response has no athlete', async () => {
    const { env, execution, stored, put, fetchMock, refreshed } = setup()
    fetchMock.mockResolvedValueOnce(Response.json(refreshed))
    const response = await app.request(
      '/refresh-token',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ userId: 'test-user', refreshToken: 'current-refresh' }),
      },
      env,
      execution
    )
    expect(response.status).toBe(200)
    expect((await response.json()).athlete.id).toBe(42)
    const saved = JSON.parse(put.mock.calls[0][1])
    expect(saved).toMatchObject({
      ...stored,
      accessToken: refreshed.access_token,
      refreshToken: refreshed.refresh_token,
      expiresAt: refreshed.expires_at,
    })
    const requestBody = JSON.parse(fetchMock.mock.calls[0][1]?.body as string)
    expect(requestBody.refresh_token).toBe('current-refresh')
  })

  test('refreshes a detail request without losing the rotated refresh token', async () => {
    const { env, execution, put, fetchMock, refreshed } = setup()
    spyOn(StravaCache.prototype, 'getActivity').mockResolvedValue(null)
    spyOn(StravaCache.prototype, 'saveActivities').mockResolvedValue()
    spyOn(StravaCache.prototype, 'trackApiCall').mockResolvedValue()
    const activity = {
      id: 1,
      name: 'Test run',
      distance: 5000,
      moving_time: 1800,
      elapsed_time: 1800,
      total_elevation_gain: 20,
      type: 'Run',
      start_date: '2026-09-13T08:00:00Z',
      start_date_local: '2026-09-13T10:00:00Z',
      splits_metric: [],
    }
    fetchMock.mockResolvedValueOnce(Response.json({}, { status: 401 }))
    fetchMock.mockResolvedValueOnce(Response.json(refreshed))
    fetchMock.mockResolvedValueOnce(Response.json(activity))
    const response = await app.request(
      '/activities/1',
      { headers: { 'X-User-ID': 'test-user' } },
      env,
      execution
    )
    expect(response.status).toBe(200)
    expect((await response.json()).activity).toEqual(activity)
    expect(JSON.parse(put.mock.calls[0][1]).refreshToken).toBe('new-refresh')
  })

  test.each([
    [400, 401],
    [401, 401],
    [429, 429],
    [503, 502],
  ])('maps refresh HTTP %i to HTTP %i without replacing stored tokens', async (upstreamStatus, expectedStatus) => {
    const { env, execution, put, fetchMock } = setup()
    spyOn(StravaCache.prototype, 'needsSync').mockResolvedValue(true)
    spyOn(StravaCache.prototype, 'getLastActivityDate').mockResolvedValue(null)
    fetchMock.mockResolvedValueOnce(Response.json({}, { status: 401 }))
    fetchMock.mockResolvedValueOnce(
      Response.json({ message: 'Refresh failed' }, { status: upstreamStatus })
    )
    const response = await app.request(
      '/activities',
      { headers: { 'X-User-ID': 'test-user' } },
      env,
      execution
    )
    expect(response.status).toBe(expectedStatus)
    expect(put).not.toHaveBeenCalled()
  })
})

describe('Strava activity detail failures', () => {
  function requestDetail(env: ReturnType<typeof setup>['env']) {
    const pending: Promise<unknown>[] = []
    const response = app.request(
      '/activities/7',
      { headers: { 'X-User-ID': 'test-user' } },
      { ...env, POSTHOG_API_KEY: 'test-key', POSTHOG_HOST: 'https://example.invalid' },
      {
        waitUntil: (promise: Promise<unknown>) => {
          pending.push(promise)
        },
        passThroughOnException: () => {},
      }
    )
    return { response, pending }
  }

  test.each([
    [401, 401],
    [404, 404],
    [429, 429],
    [503, 502],
  ])('maps Strava HTTP %i to HTTP %i and reports its status', async (upstreamStatus, expectedStatus) => {
    const { env, fetchMock, refreshed } = setup()
    const capture = mock(async () => {})
    spyOn(analytics, 'createPostHogClient').mockReturnValue({
      captureImmediate: capture,
      shutdown: mock(async () => {}),
    } as unknown as ReturnType<typeof analytics.createPostHogClient>)
    const errors = spyOn(console, 'error').mockImplementation(() => {})
    spyOn(StravaCache.prototype, 'getActivity').mockResolvedValue(null)
    if (upstreamStatus === 401) {
      fetchMock.mockResolvedValueOnce(Response.json({}, { status: 401 }))
      fetchMock.mockResolvedValueOnce(Response.json(refreshed))
    }
    fetchMock.mockResolvedValueOnce(
      Response.json({ message: 'Failure' }, { status: upstreamStatus })
    )

    const { response, pending } = requestDetail(env)
    const result = await response
    await Promise.all(pending)

    const message = `Strava API error: ${upstreamStatus} - Failed to fetch activity from Strava`
    expect(result.status).toBe(expectedStatus)
    expect(await result.json()).toEqual({
      error: 'Strava API error',
      strava_status: upstreamStatus,
      message,
    })
    expect(errors).toHaveBeenCalledWith(`strava_activity_detail_failed_backend: ${message}`)
    expect(capture).toHaveBeenCalledWith({
      distinctId: 'test-user',
      event: 'strava_activity_detail_failed_backend',
      properties: {
        error_type: 'StravaApiError',
        error_message: message,
        strava_status: upstreamStatus,
        timestamp: expect.any(Number),
      },
    })
  })

  test('keeps the error field for an internal failure', async () => {
    const { env } = setup()
    spyOn(analytics, 'createPostHogClient').mockReturnValue({
      captureImmediate: mock(async () => {}),
      shutdown: mock(async () => {}),
    } as unknown as ReturnType<typeof analytics.createPostHogClient>)
    spyOn(console, 'error').mockImplementation(() => {})
    spyOn(StravaCache.prototype, 'getActivity').mockRejectedValue(new Error('D1 unavailable'))

    const { response, pending } = requestDetail(env)
    const result = await response
    await Promise.all(pending)

    expect(result.status).toBe(500)
    expect((await result.json()).error).toBe('Failed to fetch activity')
  })
})
