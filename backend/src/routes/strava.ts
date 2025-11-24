import type { Context } from 'hono'
import { Hono } from 'hono'
import { createPostHogClient } from '../posthog'
import { StravaCache } from '../services/stravaCache'

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
      return c.json({ error: 'Token exchange failed', details: error }, response.status)
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
  try {
    const body = await c.req.json<{ refreshToken: string; userId: string }>()

    if (!body.refreshToken || !body.userId) {
      return c.json({ error: 'Missing refreshToken or userId' }, 400)
    }

    const { refreshToken, userId } = body

    const response = await fetch(STRAVA_OAUTH_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        client_id: c.env.STRAVA_CLIENT_ID,
        client_secret: c.env.STRAVA_CLIENT_SECRET,
        refresh_token: refreshToken,
        grant_type: 'refresh_token',
      }),
    })

    if (!response.ok) {
      const error = await response.text()
      return c.json({ error: 'Token refresh failed', details: error }, response.status)
    }

    const data: StravaTokenResponse = await response.json()

    const existingData = await c.env.STRAVA_TOKENS.get(`user:${userId}`, 'json')
    const existing = existingData as StoredUserTokens | null

    const userTokens: StoredUserTokens = {
      accessToken: data.access_token,
      refreshToken: data.refresh_token,
      expiresAt: data.expires_at,
      athleteId: data.athlete.id,
      athleteName: `${data.athlete.firstname} ${data.athlete.lastname}`,
      createdAt: existing?.createdAt || Date.now(),
      lastRefreshedAt: Date.now(),
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
            event: 'strava_token_refresh',
            properties: {
              athleteId: data.athlete.id,
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
    console.error('Refresh token error:', error)
    return c.json({ error: 'Internal server error' }, 500)
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
    const event: StravaWebhookEvent = await c.req.json()

    if (event.object_type !== 'activity') {
      return c.text('EVENT_RECEIVED', 200)
    }

    c.executionCtx.waitUntil(processWebhookEvent(c, event))

    return c.text('EVENT_RECEIVED', 200)
  } catch (error) {
    console.error('Webhook error:', error)
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

        const refreshResponse = await fetch(STRAVA_OAUTH_URL, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            client_id: c.env.STRAVA_CLIENT_ID,
            client_secret: c.env.STRAVA_CLIENT_SECRET,
            refresh_token: userTokens.refreshToken,
            grant_type: 'refresh_token',
          }),
        })

        if (refreshResponse.ok) {
          const refreshData: StravaTokenResponse = await refreshResponse.json()

          const updatedTokens: StoredUserTokens = {
            ...userTokens,
            accessToken: refreshData.access_token,
            refreshToken: refreshData.refresh_token,
            expiresAt: refreshData.expires_at,
            lastRefreshedAt: Date.now(),
          }

          await c.env.STRAVA_TOKENS.put(`user:${userId}`, JSON.stringify(updatedTokens))

          // Retry with new token
          response = await fetch(`${STRAVA_API_URL}/activities/${activityId}`, {
            headers: {
              Authorization: `Bearer ${updatedTokens.accessToken}`,
            },
          })
        }
      }

      if (response.ok) {
        const activity = await response.json()
        const cache = new StravaCache(c.env.STRAVA_CACHE)
        await cache.saveActivities(userId, athleteId, [activity])

        console.log(`✅ Webhook: ${aspectType}d activity ${activityId}`)
      } else {
        console.error(`❌ Failed to fetch activity ${activityId}: ${response.status}`)
      }
    } else if (aspectType === 'delete') {
      // Delete activity from cache
      await c.env.STRAVA_CACHE.prepare(`
        DELETE FROM strava_activities WHERE id = ? AND user_id = ?
      `)
        .bind(activityId, userId)
        .run()

      console.log(`✅ Webhook: deleted activity ${activityId}`)
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

    const page = Number(c.req.query('page')) || 1
    const perPage = Math.min(Number(c.req.query('per_page')) || 30, 200)
    const offset = (page - 1) * perPage

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

    const activities = await cache.getActivities(userId, perPage, offset)

    const responseTime = Date.now() - startTime

    await cache.trackApiCall(userId, 'activities', !needsSync, responseTime)

    return c.json({
      activities: activities.map((a) => a.data),
      page,
      perPage,
      cached: !needsSync,
      syncedAt: activities[0]?.syncedAt,
    })
  } catch (error) {
    console.error('Activities error:', error)

    // Check if it's an authentication error
    if (error instanceof Error && error.message.includes('not authenticated')) {
      return c.json({ error: error.message }, 401)
    }

    return c.json({ error: 'Failed to fetch activities' }, 500)
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

    if (cachedActivity) {
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

      try {
        const refreshResponse = await fetch(STRAVA_OAUTH_URL, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            client_id: c.env.STRAVA_CLIENT_ID,
            client_secret: c.env.STRAVA_CLIENT_SECRET,
            refresh_token: userTokens.refreshToken,
            grant_type: 'refresh_token',
          }),
        })

        if (!refreshResponse.ok) {
          return c.json({ error: 'Failed to refresh Strava token. Please re-authenticate.' }, 401)
        }

        const refreshData: StravaTokenResponse = await refreshResponse.json()

        const updatedTokens: StoredUserTokens = {
          accessToken: refreshData.access_token,
          refreshToken: refreshData.refresh_token,
          expiresAt: refreshData.expires_at,
          athleteId: refreshData.athlete.id,
          athleteName: `${refreshData.athlete.firstname} ${refreshData.athlete.lastname}`,
          createdAt: userTokens.createdAt,
          lastRefreshedAt: Date.now(),
        }

        await c.env.STRAVA_TOKENS.put(`user:${userId}`, JSON.stringify(updatedTokens))

        console.log('✅ Token refreshed successfully')

        // Retry with new token
        response = await fetch(`${STRAVA_API_URL}/activities/${activityId}`, {
          headers: {
            Authorization: `Bearer ${updatedTokens.accessToken}`,
          },
        })

        userTokens = updatedTokens
      } catch (error) {
        console.error('❌ Token refresh failed:', error)
        return c.json({ error: 'Failed to refresh Strava token. Please re-authenticate.' }, 401)
      }
    }

    if (!response.ok) {
      return c.json({ error: 'Failed to fetch activity from Strava' }, response.status)
    }

    const activity = await response.json()

    await cache.saveActivities(userId, userTokens.athleteId, [activity])

    const responseTime = Date.now() - startTime
    await cache.trackApiCall(userId, `activity/${activityId}`, false, responseTime)

    return c.json({
      activity,
      cached: false,
      syncedAt: Date.now(),
    })
  } catch (error) {
    console.error('Activity detail error:', error)
    return c.json({ error: 'Failed to fetch activity' }, 500)
  }
})

app.post('/sync', async (c: StravaContext) => {
  try {
    const userId = c.req.header('X-User-ID')
    if (!userId) {
      return c.json({ error: 'Missing X-User-ID header' }, 400)
    }

    const cache = new StravaCache(c.env.STRAVA_CACHE)

    await cache.setSyncStatus(userId, 'syncing')

    const result = await syncUserActivities(c, userId, cache, true)

    await cache.setSyncStatus(userId, 'idle')

    return c.json({
      success: true,
      activitiesAdded: result.newActivities,
      totalActivities: result.totalActivities,
    })
  } catch (error) {
    console.error('Sync error:', error)

    const userId = c.req.header('X-User-ID')
    if (userId) {
      const cache = new StravaCache(c.env.STRAVA_CACHE)
      await cache.setSyncStatus(
        userId,
        'error',
        error instanceof Error ? error.message : 'Unknown error'
      )
    }

    return c.json({ error: 'Sync failed' }, 500)
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

      try {
        const refreshResponse = await fetch(STRAVA_OAUTH_URL, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            client_id: c.env.STRAVA_CLIENT_ID,
            client_secret: c.env.STRAVA_CLIENT_SECRET,
            refresh_token: userTokens.refreshToken,
            grant_type: 'refresh_token',
          }),
        })

        if (!refreshResponse.ok) {
          throw new Error(`Token refresh failed: ${refreshResponse.status}`)
        }

        const refreshData: StravaTokenResponse = await refreshResponse.json()

        const updatedTokens: StoredUserTokens = {
          accessToken: refreshData.access_token,
          refreshToken: refreshData.refresh_token,
          expiresAt: refreshData.expires_at,
          athleteId: refreshData.athlete.id,
          athleteName: `${refreshData.athlete.firstname} ${refreshData.athlete.lastname}`,
          createdAt: userTokens.createdAt,
          lastRefreshedAt: Date.now(),
        }

        await c.env.STRAVA_TOKENS.put(`user:${userId}`, JSON.stringify(updatedTokens))

        console.log('✅ Token refreshed successfully')

        // Retry with new token
        response = await fetch(url, {
          headers: {
            Authorization: `Bearer ${updatedTokens.accessToken}`,
          },
        })

        userTokens = updatedTokens
      } catch (error) {
        console.error('❌ Token refresh failed:', error)
        throw new Error('Failed to refresh Strava token. Please re-authenticate.')
      }
    }

    if (!response.ok) {
      throw new Error(`Strava API error: ${response.status}`)
    }

    const activities = await response.json()

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
