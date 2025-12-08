-- Migration: 0002
-- Description: Fix strava_activities PRIMARY KEY to be composite (id, user_id)
-- Reason: Prevent activity ID collisions between different users
-- Date: 2025-01-24

-- SQLite doesn't support ALTER TABLE to change PRIMARY KEY
-- So we need to recreate the table

-- Step 1: Rename old table
ALTER TABLE strava_activities RENAME TO strava_activities_old;

-- Step 2: Create new table with composite PRIMARY KEY
CREATE TABLE strava_activities (
  id INTEGER NOT NULL,                       -- Strava activity ID
  user_id TEXT NOT NULL,                     -- iOS User ID (from HealthKit or device ID)
  athlete_id INTEGER NOT NULL,               -- Strava athlete ID
  data TEXT NOT NULL,                        -- Full JSON of activity (from Strava API)
  synced_at INTEGER NOT NULL,                -- Unix timestamp when cached
  activity_date INTEGER NOT NULL,            -- Unix timestamp of activity start date
  activity_type TEXT NOT NULL,               -- Run, Ride, Swim, etc.
  distance REAL NOT NULL,                    -- Distance in meters
  moving_time INTEGER NOT NULL,              -- Moving time in seconds
  PRIMARY KEY (id, user_id)                  -- Composite key to prevent cross-user collisions
);

-- Step 3: Copy data from old table
INSERT INTO strava_activities
  SELECT id, user_id, athlete_id, data, synced_at, activity_date, activity_type, distance, moving_time
  FROM strava_activities_old;

-- Step 4: Drop old table
DROP TABLE strava_activities_old;

-- Step 5: Recreate indexes (optimized for query patterns)
-- Composite index for main query: fetch user activities sorted by date
CREATE INDEX idx_activities_user_date ON strava_activities(user_id, activity_date DESC);

-- Index for webhook lookup: find user by athlete_id
CREATE INDEX idx_activities_athlete ON strava_activities(athlete_id);
