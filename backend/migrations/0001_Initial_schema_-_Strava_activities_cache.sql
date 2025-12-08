-- Migration number: 0001 	 2025-11-24T09:36:00.089Z
-- Strava Activities Cache Schema
-- This database stores cached Strava activities to minimize API calls

CREATE TABLE IF NOT EXISTS strava_activities (
  id INTEGER PRIMARY KEY,                    -- Strava activity ID
  user_id TEXT NOT NULL,                     -- iOS User ID (from HealthKit or device ID)
  athlete_id INTEGER NOT NULL,               -- Strava athlete ID
  data TEXT NOT NULL,                        -- Full JSON of activity (from Strava API)
  synced_at INTEGER NOT NULL,                -- Unix timestamp when cached
  activity_date INTEGER NOT NULL,            -- Unix timestamp of activity start date
  activity_type TEXT NOT NULL,               -- Run, Ride, Swim, etc.
  distance REAL NOT NULL,                    -- Distance in meters
  moving_time INTEGER NOT NULL               -- Moving time in seconds
);

-- Index for user queries (most common: get activities for a user)
CREATE INDEX IF NOT EXISTS idx_user_date
  ON strava_activities(user_id, activity_date DESC);

-- Index for athlete queries
CREATE INDEX IF NOT EXISTS idx_athlete_date
  ON strava_activities(athlete_id, activity_date DESC);

-- Index for sync status (find activities that need refresh)
CREATE INDEX IF NOT EXISTS idx_sync
  ON strava_activities(user_id, synced_at);

-- Metadata table to track sync state per user
CREATE TABLE IF NOT EXISTS strava_sync_state (
  user_id TEXT PRIMARY KEY,
  last_sync_at INTEGER NOT NULL,             -- When we last synced
  last_activity_date INTEGER,                -- Date of most recent activity
  total_activities INTEGER DEFAULT 0,        -- Total activities cached
  sync_status TEXT DEFAULT 'idle',           -- idle, syncing, error
  error_message TEXT,                        -- Last error if any
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

-- Stats table for rate limiting monitoring
CREATE TABLE IF NOT EXISTS strava_api_stats (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  timestamp INTEGER NOT NULL,
  user_id TEXT,
  endpoint TEXT NOT NULL,                    -- activities, athlete, activity/:id
  cache_hit BOOLEAN NOT NULL DEFAULT 0,      -- 1 if served from cache, 0 if hit Strava
  response_time_ms INTEGER,                  -- Response time
  rate_limit_15min INTEGER,                  -- Strava 15min rate limit usage
  rate_limit_daily INTEGER                   -- Strava daily rate limit usage
);

CREATE INDEX IF NOT EXISTS idx_stats_timestamp
  ON strava_api_stats(timestamp DESC);
