interface StravaActivity {
  id: number
  name: string
  distance: number
  moving_time: number
  elapsed_time: number
  total_elevation_gain: number
  type: string
  start_date: string
  start_date_local: string
  average_speed?: number
  max_speed?: number
  average_heartrate?: number
  max_heartrate?: number
  calories?: number
}

interface CachedActivity {
  id: number
  userId: string
  athleteId: number
  data: StravaActivity
  syncedAt: number
  activityDate: number
  activityType: string
  distance: number
  movingTime: number
}

interface SyncState {
  userId: string
  lastSyncAt: number
  lastActivityDate?: number
  totalActivities: number
  syncStatus: 'idle' | 'syncing' | 'error'
  errorMessage?: string
  createdAt: number
  updatedAt: number
}

export class StravaCache {
  constructor(private db: D1Database) {}

  async saveActivities(
    userId: string,
    athleteId: number,
    activities: StravaActivity[]
  ): Promise<void> {
    if (activities.length === 0) return

    const now = Date.now()

    const stmt = this.db.prepare(`
      INSERT OR REPLACE INTO strava_activities
      (id, user_id, athlete_id, data, synced_at, activity_date, activity_type, distance, moving_time)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `)

    const batch = activities.map((activity) => {
      const activityDate = new Date(activity.start_date).getTime()
      return stmt.bind(
        activity.id,
        userId,
        athleteId,
        JSON.stringify(activity),
        now,
        activityDate,
        activity.type,
        activity.distance,
        activity.moving_time
      )
    })

    await this.db.batch(batch)

    await this.updateSyncState(userId, activities)
  }

  async getActivities(userId: string, limit = 100, offset = 0): Promise<CachedActivity[]> {
    const result = await this.db
      .prepare(`
      SELECT id, user_id, athlete_id, data, synced_at, activity_date, activity_type, distance, moving_time
      FROM strava_activities
      WHERE user_id = ?
      ORDER BY activity_date DESC
      LIMIT ? OFFSET ?
    `)
      .bind(userId, limit, offset)
      .all<{
        id: number
        user_id: string
        athlete_id: number
        data: string
        synced_at: number
        activity_date: number
        activity_type: string
        distance: number
        moving_time: number
      }>()

    return result.results.map((row) => ({
      id: row.id,
      userId: row.user_id,
      athleteId: row.athlete_id,
      data: JSON.parse(row.data) as StravaActivity,
      syncedAt: row.synced_at,
      activityDate: row.activity_date,
      activityType: row.activity_type,
      distance: row.distance,
      movingTime: row.moving_time,
    }))
  }

  async getActivity(userId: string, activityId: number): Promise<CachedActivity | null> {
    const result = await this.db
      .prepare(`
      SELECT id, user_id, athlete_id, data, synced_at, activity_date, activity_type, distance, moving_time
      FROM strava_activities
      WHERE user_id = ? AND id = ?
    `)
      .bind(userId, activityId)
      .first<{
        id: number
        user_id: string
        athlete_id: number
        data: string
        synced_at: number
        activity_date: number
        activity_type: string
        distance: number
        moving_time: number
      }>()

    if (!result) return null

    return {
      id: result.id,
      userId: result.user_id,
      athleteId: result.athlete_id,
      data: JSON.parse(result.data) as StravaActivity,
      syncedAt: result.synced_at,
      activityDate: result.activity_date,
      activityType: result.activity_type,
      distance: result.distance,
      movingTime: result.moving_time,
    }
  }

  async getSyncState(userId: string): Promise<SyncState | null> {
    const result = await this.db
      .prepare(`
      SELECT user_id, last_sync_at, last_activity_date, total_activities,
             sync_status, error_message, created_at, updated_at
      FROM strava_sync_state
      WHERE user_id = ?
    `)
      .bind(userId)
      .first<{
        user_id: string
        last_sync_at: number
        last_activity_date?: number
        total_activities: number
        sync_status: string
        error_message?: string
        created_at: number
        updated_at: number
      }>()

    if (!result) return null

    return {
      userId: result.user_id,
      lastSyncAt: result.last_sync_at,
      lastActivityDate: result.last_activity_date,
      totalActivities: result.total_activities,
      syncStatus: result.sync_status as 'idle' | 'syncing' | 'error',
      errorMessage: result.error_message,
      createdAt: result.created_at,
      updatedAt: result.updated_at,
    }
  }

  async getLastActivityDate(userId: string): Promise<number | null> {
    const result = await this.db
      .prepare(`
      SELECT MAX(activity_date) as last_date
      FROM strava_activities
      WHERE user_id = ?
    `)
      .bind(userId)
      .first<{ last_date: number | null }>()

    return result?.last_date || null
  }

  async needsSync(userId: string, maxCacheAge = 3600000): Promise<boolean> {
    const syncState = await this.getSyncState(userId)

    if (!syncState) return true

    const now = Date.now()
    const cacheAge = now - syncState.lastSyncAt

    return cacheAge > maxCacheAge
  }

  private async updateSyncState(userId: string, activities: StravaActivity[]): Promise<void> {
    const now = Date.now()
    const lastActivity = activities[0]
    const lastActivityDate = lastActivity ? new Date(lastActivity.start_date).getTime() : undefined

    const count = await this.db
      .prepare(`
      SELECT COUNT(*) as total FROM strava_activities WHERE user_id = ?
    `)
      .bind(userId)
      .first<{ total: number }>()

    const totalActivities = count?.total || 0

    await this.db
      .prepare(`
      INSERT OR REPLACE INTO strava_sync_state
      (user_id, last_sync_at, last_activity_date, total_activities, sync_status, created_at, updated_at)
      VALUES (?, ?, ?, ?, 'idle', COALESCE((SELECT created_at FROM strava_sync_state WHERE user_id = ?), ?), ?)
    `)
      .bind(userId, now, lastActivityDate, totalActivities, userId, now, now)
      .run()
  }

  async setSyncStatus(
    userId: string,
    status: 'idle' | 'syncing' | 'error',
    errorMessage?: string
  ): Promise<void> {
    const now = Date.now()
    await this.db
      .prepare(`
      UPDATE strava_sync_state
      SET sync_status = ?, error_message = ?, updated_at = ?
      WHERE user_id = ?
    `)
      .bind(status, errorMessage || null, now, userId)
      .run()
  }

  async trackApiCall(
    userId: string,
    endpoint: string,
    cacheHit: boolean,
    responseTimeMs: number,
    rateLimit15min?: number,
    rateLimitDaily?: number
  ): Promise<void> {
    const now = Date.now()
    await this.db
      .prepare(`
      INSERT INTO strava_api_stats
      (timestamp, user_id, endpoint, cache_hit, response_time_ms, rate_limit_15min, rate_limit_daily)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `)
      .bind(
        now,
        userId,
        endpoint,
        cacheHit ? 1 : 0,
        responseTimeMs,
        rateLimit15min ?? null,
        rateLimitDaily ?? null
      )
      .run()
  }

  async getCacheStats(userId: string): Promise<{
    totalActivities: number
    lastSyncAt: number | null
    cacheHitRate: number
  }> {
    const syncState = await this.getSyncState(userId)

    const stats = await this.db
      .prepare(`
      SELECT
        COUNT(*) as total_calls,
        SUM(CASE WHEN cache_hit = 1 THEN 1 ELSE 0 END) as cache_hits
      FROM strava_api_stats
      WHERE user_id = ? AND timestamp > ?
    `)
      .bind(userId, Date.now() - 86400000)
      .first<{ total_calls: number; cache_hits: number }>()

    const cacheHitRate = stats?.total_calls ? (stats.cache_hits / stats.total_calls) * 100 : 0

    return {
      totalActivities: syncState?.totalActivities || 0,
      lastSyncAt: syncState?.lastSyncAt || null,
      cacheHitRate,
    }
  }
}
