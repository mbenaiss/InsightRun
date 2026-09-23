import type { Context } from 'hono'
import { Hono } from 'hono'
import { z } from 'zod'
import { createPostHogClient } from '../posthog'
import { StravaCache, stravaActivitySchema } from '../services/stravaCache'

type StravaBindings = {
  STRAVA_CLIENT_ID: string
  STRAVA_CLIENT_SECRET: string
  STRAVA_WEBHOOK_VERIFY_TOKEN: string
  STRAVA_TOKENS: KVNamespace
  STRAVA_CACHE: D1Database
  POSTHOG_API_KEY: string
  POSTHOG_HOST: string
}

type StravaContext = Context<{ Bindings: StravaBindings }>

interface StravaTokenResponse {
  access_token: string
  refresh_token: string
  expires_at: number
  athlete: {
    id: number
    username: string
    firstname: string
    lastname: string
  }
}

interface StoredUserTokens {
  accessToken: string
  refreshToken: string
  expiresAt: number
  athleteId: number
  athleteName: string
  createdAt: number
  lastRefreshedAt?: number
}

class StravaAuthenticationError extends Error {}

class StravaApiError extends Error {
  status: number
  body: string

  constructor(status: number, body: string) {
    super(`Strava API error: ${status}${body ? ` - ${body}` : ''}`)
    this.name = 'StravaApiError'
    this.status = status
    this.body = body
  }
}

// Cloudflare's log collector drops `error.message` when an Error object is logged,
// so the message is logged explicitly and mirrored to PostHog.
function reportStravaError(
  c: StravaContext,
  event: string,
  userId: string | undefined,
  error: unknown
) {
  const message = error instanceof Error ? error.message : String(error)
  const status = error instanceof StravaApiError ? error.status : undefined
  console.error(`${event}: ${message}`)

  if (!c.env.POSTHOG_API_KEY || !c.env.POSTHOG_HOST) return

  c.executionCtx.waitUntil(
    (async () => {
      try {
        const posthog = createPostHogClient({
          apiKey: c.env.POSTHOG_API_KEY,
          host: c.env.POSTHOG_HOST,
        })
        await posthog.captureImmediate({
          distinctId: userId || 'unknown',
          event,
          properties: {
            error_type: error instanceof Error ? error.name : 'Unknown',
            error_message: message,
            strava_status: status,
            timestamp: Date.now(),
          },
        })
        await posthog.shutdown()
      } catch (captureError) {
        console.error('PostHog capture error:', captureError)
      }
    })()
  )
}

function stravaErrorResponse(c: StravaContext, error: unknown, fallback: string) {
  if (error instanceof StravaAuthenticationError) {
    return c.json({ error: 'Strava authentication required', message: error.message }, 401)
  }
  if (error instanceof StravaApiError) {
    return c.json(
      { error: 'Strava API error', strava_status: error.status, message: error.message },
      ([401, 404, 429] as const).find((status) => status === error.status) ?? 502
    )
  }
  if (error instanceof Error && error.message.includes('not authenticated')) {
    return c.json({ error: error.message }, 401)
  }
  return c.json({ error: fallback, message: 'Unexpected server error' }, 500)
}

interface StravaWebhookEvent {
  object_type: string
  object_id: number
  aspect_type: string
  owner_id: number
  subscription_id: number
  event_time: number
}

const STRAVA_OAUTH_URL = 'https://www.strava.com/oauth/token'
const STRAVA_API_URL = 'https://www.strava.com/api/v3'
const CACHE_MAX_AGE = 3600000 // 1 hour

const refreshedTokensSchema = z.object({
  access_token: z.string().min(1),
  refresh_token: z.string().min(1),
  expires_at: z.number().int().positive(),
})

async function refreshUserTokens(
  c: StravaContext,
  userId: string,
  existing: StoredUserTokens
): Promise<StoredUserTokens> {
  const response = await fetch(STRAVA_OAUTH_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      client_id: c.env.STRAVA_CLIENT_ID,
      client_secret: c.env.STRAVA_CLIENT_SECRET,
      refresh_token: existing.refreshToken,
      grant_type: 'refresh_token',
    }),
  })
  if (response.status === 400 || response.status === 401) {
    throw new StravaAuthenticationError('Your Strava session expired. Please reconnect.')
  }
  if (!response.ok) throw new StravaApiError(response.status, 'Token refresh failed')

  const data = refreshedTokensSchema.parse(await response.json())
  // Refresh responses omit athlete data, and the rotated token must be saved immediately.
  const updated = {
    ...existing,
    accessToken: data.access_token,
    refreshToken: data.refresh_token,
    expiresAt: data.expires_at,
    lastRefreshedAt: Date.now(),
  }
  await c.env.STRAVA_TOKENS.put(`user:${userId}`, JSON.stringify(updated))
  return updated
}

const app = new Hono<{ Bindings: StravaBindings }>()

app.post('/exchange-token', async (c: StravaContext) => {
  try {
    const body = await c.req.json<{ code: string; userId: string }>()

    if (!body.code || !body.userId) {
      return c.json({ error: 'Missing code or userId' }, 400)
    }

    const { code, userId } = body

    const response = await fetch(STRAVA_OAUTH_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        client_id: c.env.STRAVA_CLIENT_ID,
        client_secret: c.env.STRAVA_CLIENT_SECRET,
        code,
        grant_type: 'authorization_code',
      }),
    })

    if (!response.ok) {
      const error = await response.text()
      return c.json(
        { error: 'Token exchange failed', details: error },
        response.status === 400 ? 400 : 502
      )
    }

    const data: StravaTokenResponse = await response.json()

    const userTokens: StoredUserTokens = {
      accessToken: data.access_token,
      refreshToken: data.refresh_token,
      expiresAt: data.expires_at,
      athleteId: data.athlete.id,
      athleteName: `${data.athlete.firstname} ${data.athlete.lastname}`,
      createdAt: Date.now(),
    }

    await c.env.STRAVA_TOKENS.put(`user:${userId}`, JSON.stringify(userTokens))

    c.executionCtx.waitUntil(
      (async () => {
        try {
          const posthog = createPostHogClient({
            apiKey: c.env.POSTHOG_API_KEY,
            host: c.env.POSTHOG_HOST,
          })

          await posthog.captureImmediate({
            distinctId: userId,
            event: 'strava_oauth_success',
            properties: {
              athleteId: data.athlete.id,
              athleteName: userTokens.athleteName,
              timestamp: Date.now(),
            },
          })

          await posthog.shutdown()
        } catch (error) {
          console.error('PostHog capture error:', error)
        }
      })()
    )

    return c.json({
      access_token: data.access_token,
      refresh_token: data.refresh_token,
      expires_at: data.expires_at,
      athlete: data.athlete,
    })
  } catch (error) {
    console.error('Exchange token error:', error)
    return c.json({ error: 'Internal server error' }, 500)
  }
})

app.post('/refresh-token', async (c: StravaContext) => {
  let userId: string | undefined
  try {
    const body = await c.req.json<{ refreshToken: string; userId: string }>()
    if (!body.refreshToken || !body.userId) {
      return c.json({ error: 'Missing refreshToken or userId' }, 400)
    }
    userId = body.userId
    const existing = await c.env.STRAVA_TOKENS.get<StoredUserTokens>(`user:${body.userId}`, 'json')
    if (!existing || existing.refreshToken !== body.refreshToken) {
      throw new StravaAuthenticationError('Please reconnect to Strava.')
    }

    const tokens =
      existing.expiresAt > Date.now() / 1000 + 300
        ? existing
        : await refreshUserTokens(c, body.userId, existing)
    if (c.env.POSTHOG_API_KEY && c.env.POSTHOG_HOST) {
      c.executionCtx.waitUntil(
        (async () => {
          try {
            const posthog = createPostHogClient({
              apiKey: c.env.POSTHOG_API_KEY,
              host: c.env.POSTHOG_HOST,
            })
            await posthog.captureImmediate({
              distinctId: body.userId,
              event: 'strava_token_refresh',
              properties: { athleteId: tokens.athleteId, timestamp: Date.now() },
            })
            await posthog.shutdown()
          } catch (error) {
            console.error('PostHog capture error:', error)
          }
        })()
      )
    }
    return c.json({
      access_token: tokens.accessToken,
      refresh_token: tokens.refreshToken,
      expires_at: tokens.expiresAt,
      athlete: { id: tokens.athleteId },
    })
  } catch (error) {
    reportStravaError(c, 'strava_token_refresh_failed_backend', userId, error)
    return stravaErrorResponse(c, error, 'Failed to refresh Strava token')
  }
})

app.get('/webhooks/callback', async (c: StravaContext) => {
  const mode = c.req.query('hub.mode')
  const token = c.req.query('hub.verify_token')
  const challenge = c.req.query('hub.challenge')

  const verifyToken = c.env.STRAVA_WEBHOOK_VERIFY_TOKEN

  if (mode === 'subscribe' && token === verifyToken) {
    return c.json({ 'hub.challenge': challenge })
  }

  return c.json({ error: 'Forbidden' }, 403)
})

app.post('/webhooks/callback', async (c: StravaContext) => {
  try {
    // Verify webhook authenticity (basic check - in production, verify subscription ID)
    // Note: Strava doesn't send HMAC signatures on webhook POSTs, only on subscription validation
    // We rely on the subscription setup with verify_token to ensure only valid webhooks reach us
    const event: StravaWebhookEvent = await c.req.json()

    console.log(
      `[WEBHOOK] Received event: ${event.aspect_type} for ${event.object_type} ${event.object_id}`
    )

    if (event.object_type !== 'activity') {
      console.log('[WEBHOOK] Ignoring non-activity event')
      return c.text('EVENT_RECEIVED', 200)
    }

    // Validate event structure
    if (!event.owner_id || !event.object_id || !event.aspect_type) {
      console.error('[WEBHOOK] Invalid event structure:', event)
      return c.json({ error: 'Invalid event structure' }, 400)
    }

    c.executionCtx.waitUntil(processWebhookEvent(c, event))

    return c.text('EVENT_RECEIVED', 200)
  } catch (error) {
    console.error('[WEBHOOK] Error:', error)
    return c.json({ error: 'Internal server error' }, 500)
  }
})

async function processWebhookEvent(c: StravaContext, event: StravaWebhookEvent) {
  try {
    const athleteId = event.owner_id
    const activityId = event.object_id
    const aspectType = event.aspect_type

    console.log(`📥 Webhook: ${aspectType} for activity ${activityId} (athlete ${athleteId})`)

    // Find App User ID from athlete ID via D1
    const userResult = await c.env.STRAVA_CACHE.prepare(`
      SELECT DISTINCT user_id FROM strava_activities WHERE athlete_id = ? LIMIT 1
    `)
      .bind(athleteId)
      .first<{ user_id: string }>()

    if (!userResult) {
      console.warn(`⚠️ No user found for athlete ${athleteId}`)
      return
    }

    const userId = userResult.user_id

    // Get user tokens
    const userTokensData = await c.env.STRAVA_TOKENS.get(`user:${userId}`, 'json')
    const userTokens = userTokensData as StoredUserTokens | null

    if (!userTokens || !userTokens.accessToken) {
      console.warn(`⚠️ No tokens for user ${userId}`)
      return
    }

    // Handle different aspect types
    if (aspectType === 'create' || aspectType === 'update') {
      // Fetch the activity from Strava
      let response = await fetch(`${STRAVA_API_URL}/activities/${activityId}`, {
        headers: {
          Authorization: `Bearer ${userTokens.accessToken}`,
        },
      })

      // Refresh token if needed
      if (response.status === 401) {
        console.log('⚠️ Token expired, refreshing for webhook...')

        const updatedTokens = await refreshUserTokens(c, userId, userTokens)
        response = await fetch(`${STRAVA_API_URL}/activities/${activityId}`, {
          headers: { Authorization: `Bearer ${updatedTokens.accessToken}` },
        })
      }

      if (response.ok) {
        const activity = stravaActivitySchema.parse(await response.json())
        const cache = new StravaCache(c.env.STRAVA_CACHE)
        await cache.saveActivities(userId, athleteId, [activity])

        console.log(`✅ Webhook: ${aspectType}d activity ${activityId}`)
      } else {
        console.error(`❌ Failed to fetch activity ${activityId}: ${response.status}`)
      }
    } else if (aspectType === 'delete') {
      const cache = new StravaCache(c.env.STRAVA_CACHE)

      // Delete activity from cache
      const deleteResult = await c.env.STRAVA_CACHE.prepare(`
        DELETE FROM strava_activities WHERE id = ? AND user_id = ?
      `)
        .bind(activityId, userId)
        .run()

      // Update sync state to decrement totalActivities
      if (deleteResult.meta.changes > 0) {
        const syncState = await cache.getSyncState(userId)
        if (syncState && syncState.totalActivities > 0) {
          await c.env.STRAVA_CACHE.prepare(`
            UPDATE strava_sync_state
            SET total_activities = total_activities - 1,
                last_sync_at = ?
            WHERE user_id = ?
          `)
            .bind(Date.now(), userId)
            .run()

          console.log(`✅ Webhook: deleted activity ${activityId}, updated sync state`)
        } else {
          console.log(`✅ Webhook: deleted activity ${activityId}`)
        }
      } else {
        console.log(`⚠️ Webhook: activity ${activityId} not found in cache`)
      }
    }

    // Track in PostHog
    const posthog = createPostHogClient({
      apiKey: c.env.POSTHOG_API_KEY,
      host: c.env.POSTHOG_HOST,
    })

    await posthog.captureImmediate({
      distinctId: userId,
      event: 'strava_webhook_processed',
      properties: {
        objectType: event.object_type,
        aspectType: event.aspect_type,
        activityId: event.object_id,
        athleteId,
        eventTime: event.event_time,
        timestamp: Date.now(),
      },
    })

    await posthog.shutdown()
  } catch (error) {
    console.error('Webhook processing error:', error)
  }
}

app.get('/activities', async (c: StravaContext) => {
  const startTime = Date.now()

  try {
    const userId = c.req.header('X-User-ID')
    if (!userId) {
      return c.json({ error: 'Missing X-User-ID header' }, 400)
    }

    // Support both pagination styles:
    // - page/per_page (traditional): ?page=1&per_page=30
    // - limit/offset (REST standard): ?limit=100&offset=0
    let limit: number
    let offset: number
    let page: number | undefined
    let perPage: number | undefined

    if (c.req.query('limit') || c.req.query('offset')) {
      // iOS app style: limit/offset
      limit = Math.min(Number(c.req.query('limit')) || 100, 200)
      offset = Number(c.req.query('offset')) || 0
      page = undefined
      perPage = undefined
    } else {
      // Traditional pagination: page/per_page
      page = Number(c.req.query('page')) || 1
      perPage = Math.min(Number(c.req.query('per_page')) || 30, 200)
      limit = perPage
      offset = (page - 1) * perPage
    }

    const cache = new StravaCache(c.env.STRAVA_CACHE)

    const needsSync = await cache.needsSync(userId, CACHE_MAX_AGE)

    if (needsSync) {
      // Check if user has tokens before attempting sync
      const userTokensData = await c.env.STRAVA_TOKENS.get(`user:${userId}`, 'json')
      const userTokens = userTokensData as StoredUserTokens | null

      if (!userTokens || !userTokens.accessToken) {
        return c.json({ error: 'User not authenticated with Strava' }, 401)
      }

      await syncUserActivities(c, userId, cache)
    }

    const activities = await cache.getActivities(userId, limit, offset)

    // Get total count from sync state
    const syncState = await cache.getSyncState(userId)
    const totalActivities = syncState?.totalActivities || 0

    const responseTime = Date.now() - startTime

    await cache.trackApiCall(userId, 'activities', !needsSync, responseTime)

    // Build response with appropriate pagination fields
    const response: Record<string, unknown> = {
      activities: activities.map((a) => ({
        id: a.id,
        user_id: a.userId,
        athlete_id: a.athleteId,
        activity_id: a.id,
        name: a.data.name,
        type: a.data.type,
        distance: a.data.distance,
        moving_time: a.data.moving_time,
        elapsed_time: a.data.elapsed_time,
        total_elevation_gain: a.data.total_elevation_gain,
        start_date: a.data.start_date,
        start_date_local: a.data.start_date_local,
        average_speed: a.data.average_speed,
        max_speed: a.data.max_speed,
        average_heartrate: a.data.average_heartrate,
        max_heartrate: a.data.max_heartrate,
        calories: a.data.calories,
      })),
      cached: !needsSync,
      syncedAt: syncState?.lastSyncAt,
    }

    // Include appropriate pagination fields based on request style
    if (page !== undefined && perPage !== undefined) {
      // page/per_page style (for StravaAPIClient)
      response.page = page
      response.perPage = perPage
    } else {
      // limit/offset style (for StravaBackendClient)
      response.limit = limit
      response.offset = offset
      response.total = totalActivities
    }

    return c.json(response)
  } catch (error) {
    reportStravaError(c, 'strava_activities_failed_backend', c.req.header('X-User-ID'), error)
    return stravaErrorResponse(c, error, 'Failed to fetch activities')
  }
})

app.get('/activities/:id', async (c: StravaContext) => {
  const startTime = Date.now()

  try {
    const userId = c.req.header('X-User-ID')
    if (!userId) {
      return c.json({ error: 'Missing X-User-ID header' }, 400)
    }

    const activityId = Number(c.req.param('id'))

    const cache = new StravaCache(c.env.STRAVA_CACHE)

    const cachedActivity = await cache.getActivity(userId, activityId)

    // Check if cached activity has detailed data (splits_metric)
    // If not, we need to fetch from Strava API to get full details
    const hasDetailedData = cachedActivity?.data && 'splits_metric' in cachedActivity.data

    if (cachedActivity && hasDetailedData) {
      const responseTime = Date.now() - startTime
      await cache.trackApiCall(userId, `activity/${activityId}`, true, responseTime)

      return c.json({
        activity: cachedActivity.data,
        cached: true,
        syncedAt: cachedActivity.syncedAt,
      })
    }

    const userTokensData = await c.env.STRAVA_TOKENS.get(`user:${userId}`, 'json')
    let userTokens = userTokensData as StoredUserTokens | null

    if (!userTokens || !userTokens.accessToken) {
      return c.json({ error: 'User not authenticated with Strava' }, 401)
    }

    let response = await fetch(`${STRAVA_API_URL}/activities/${activityId}`, {
      headers: {
        Authorization: `Bearer ${userTokens.accessToken}`,
      },
    })

    // If 401 Unauthorized, try to refresh token and retry
    if (response.status === 401) {
      console.log('⚠️ Access token expired, refreshing...')

      userTokens = await refreshUserTokens(c, userId, userTokens)
      response = await fetch(`${STRAVA_API_URL}/activities/${activityId}`, {
        headers: { Authorization: `Bearer ${userTokens.accessToken}` },
      })
    }

    if (!response.ok) {
      throw new StravaApiError(response.status, 'Failed to fetch activity from Strava')
    }

    const activity = stravaActivitySchema.parse(await response.json())

    await cache.saveActivities(userId, userTokens.athleteId, [activity])

    const responseTime = Date.now() - startTime
    await cache.trackApiCall(userId, `activity/${activityId}`, false, responseTime)

    return c.json({
      activity,
      cached: false,
      syncedAt: Date.now(),
    })
  } catch (error) {
    reportStravaError(c, 'strava_activity_detail_failed_backend', c.req.header('X-User-ID'), error)
    return stravaErrorResponse(c, error, 'Failed to fetch activity')
  }
})

app.post('/sync', async (c: StravaContext) => {
  try {
    const userId = c.req.header('X-User-ID')
    if (!userId) {
      return c.json({ error: 'Missing X-User-ID header' }, 400)
    }

    // Read force flag from request body
    const body = await c.req.json<{ force?: boolean }>()
    const force = body.force ?? false

    const cache = new StravaCache(c.env.STRAVA_CACHE)

    await cache.setSyncStatus(userId, 'syncing')

    const result = await syncUserActivities(c, userId, cache, force)

    await cache.setSyncStatus(userId, 'idle')

    return c.json({
      success: true,
      new_activities: result.newActivities,
      total_activities: result.totalActivities,
    })
  } catch (error) {
    const userId = c.req.header('X-User-ID')
    reportStravaError(c, 'strava_sync_failed_backend', userId, error)

    if (userId) {
      const cache = new StravaCache(c.env.STRAVA_CACHE)
      await cache.setSyncStatus(
        userId,
        'error',
        error instanceof Error ? error.message : 'Unknown error'
      )
    }

    return stravaErrorResponse(c, error, 'Sync failed')
  }
})

app.get('/stats', async (c: StravaContext) => {
  try {
    const userId = c.req.header('X-User-ID')
    if (!userId) {
      return c.json({ error: 'Missing X-User-ID header' }, 400)
    }

    const cache = new StravaCache(c.env.STRAVA_CACHE)
    const stats = await cache.getCacheStats(userId)
    const syncState = await cache.getSyncState(userId)

    return c.json({
      ...stats,
      syncState,
    })
  } catch (error) {
    console.error('Stats error:', error)
    return c.json({ error: 'Failed to get stats' }, 500)
  }
})

app.delete('/disconnect', async (c: StravaContext) => {
  try {
    const userId = c.req.header('X-User-ID')
    if (!userId) {
      return c.json({ error: 'Missing X-User-ID header' }, 400)
    }

    console.log(`[DISCONNECT] Starting cleanup for user ${userId}`)

    // Delete KV tokens
    await c.env.STRAVA_TOKENS.delete(`user:${userId}`)
    console.log(`[DISCONNECT] Deleted KV tokens for user ${userId}`)

    // Delete D1 activities
    const deleteResult = await c.env.STRAVA_CACHE.prepare(
      'DELETE FROM strava_activities WHERE user_id = ?'
    )
      .bind(userId)
      .run()

    console.log(`[DISCONNECT] Deleted ${deleteResult.meta.changes} activities from D1`)

    // Delete D1 sync state
    await c.env.STRAVA_CACHE.prepare('DELETE FROM strava_sync_state WHERE user_id = ?')
      .bind(userId)
      .run()

    console.log(`[DISCONNECT] Deleted sync state for user ${userId}`)

    return c.json({
      success: true,
      deletedActivities: deleteResult.meta.changes,
      message: 'All Strava data deleted successfully',
    })
  } catch (error) {
    console.error('[DISCONNECT] Error:', error)
    return c.json({ error: 'Failed to disconnect and clean up data' }, 500)
  }
})

async function syncUserActivities(
  c: StravaContext,
  userId: string,
  cache: StravaCache,
  force = false
): Promise<{ newActivities: number; totalActivities: number }> {
  const userTokensData = await c.env.STRAVA_TOKENS.get(`user:${userId}`, 'json')
  let userTokens = userTokensData as StoredUserTokens | null

  if (!userTokens || !userTokens.accessToken) {
    throw new Error('User not authenticated with Strava')
  }

  const lastActivityDate = await cache.getLastActivityDate(userId)

  const perPage = 100
  const maxPages = 10 // Limit to 1000 activities to avoid timeout
  let page = 1
  let totalNewActivities = 0
  let hasMore = true

  while (hasMore && page <= maxPages) {
    let url = `${STRAVA_API_URL}/athlete/activities?per_page=${perPage}&page=${page}`

    if (lastActivityDate && !force) {
      const afterTimestamp = Math.floor(lastActivityDate / 1000) + 1
      url += `&after=${afterTimestamp}`
    }

    console.log(`📥 Fetching page ${page}...`)

    let response = await fetch(url, {
      headers: {
        Authorization: `Bearer ${userTokens.accessToken}`,
      },
    })

    // If 401 Unauthorized, try to refresh token and retry
    if (response.status === 401 && page === 1) {
      console.log('⚠️ Access token expired, refreshing...')

      userTokens = await refreshUserTokens(c, userId, userTokens)
      response = await fetch(url, {
        headers: { Authorization: `Bearer ${userTokens.accessToken}` },
      })
    }

    if (!response.ok) {
      const body = await response.text().catch(() => '')
      throw new StravaApiError(response.status, body.slice(0, 500))
    }

    const activities = z.array(stravaActivitySchema).parse(await response.json())

    if (activities.length === 0) {
      hasMore = false
      console.log(`✅ No more activities (page ${page})`)
    } else {
      await cache.saveActivities(userId, userTokens.athleteId, activities)
      totalNewActivities += activities.length
      console.log(`✅ Page ${page}: ${activities.length} activities`)

      // If we got less than perPage, it's the last page
      if (activities.length < perPage) {
        hasMore = false
        console.log(`✅ Last page (${activities.length} < ${perPage})`)
      }
    }

    page++
  }

  if (page > maxPages) {
    console.log(`⚠️ Reached max pages limit (${maxPages}). User may have more activities.`)
  }

  // Always update last_sync_at, even if no new activities
  if (totalNewActivities === 0) {
    const now = Date.now()
    const count = await c.env.STRAVA_CACHE.prepare(`
      SELECT COUNT(*) as total FROM strava_activities WHERE user_id = ?
    `)
      .bind(userId)
      .first<{ total: number }>()

    const totalActivities = count?.total || 0
    const lastActivityDate = await cache.getLastActivityDate(userId)

    await c.env.STRAVA_CACHE.prepare(`
      INSERT OR REPLACE INTO strava_sync_state
      (user_id, last_sync_at, last_activity_date, total_activities, sync_status, created_at, updated_at)
      VALUES (?, ?, ?, ?, 'idle', COALESCE((SELECT created_at FROM strava_sync_state WHERE user_id = ?), ?), ?)
    `)
      .bind(userId, now, lastActivityDate, totalActivities, userId, now, now)
      .run()

    console.log('✅ Updated last_sync_at (no new activities)')
  }

  const syncState = await cache.getSyncState(userId)

  return {
    newActivities: totalNewActivities,
    totalActivities: syncState?.totalActivities || 0,
  }
}

export default app
