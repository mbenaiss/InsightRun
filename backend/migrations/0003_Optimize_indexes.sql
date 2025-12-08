-- Migration: 0003
-- Description: Optimize indexes for query patterns
-- Reason: Migration 0002 created suboptimal indexes, this adds composite indexes
-- Date: 2025-01-24

-- Drop old simple indexes if they exist
DROP INDEX IF EXISTS idx_activities_user;
DROP INDEX IF EXISTS idx_activities_date;
DROP INDEX IF EXISTS idx_activities_type;

-- Create optimized composite index for main query pattern
-- Query: SELECT * FROM strava_activities WHERE user_id = ? ORDER BY activity_date DESC
CREATE INDEX IF NOT EXISTS idx_activities_user_date
  ON strava_activities(user_id, activity_date DESC);

-- Create index for webhook lookup pattern
-- Query: SELECT user_id FROM strava_activities WHERE athlete_id = ?
CREATE INDEX IF NOT EXISTS idx_activities_athlete
  ON strava_activities(athlete_id);
