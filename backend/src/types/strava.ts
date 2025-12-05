/**
 * Strava API Types
 * Comprehensive type definitions for Strava integration
 */

// OAuth & Authentication
export interface StravaTokenResponse {
  access_token: string
  refresh_token: string
  expires_at: number
  expires_in: number
  token_type: string
  athlete: StravaAthlete
}

export interface StravaAthlete {
  id: number
  username: string | null
  resource_state: number
  firstname: string
  lastname: string
  bio: string | null
  city: string | null
  state: string | null
  country: string | null
  sex: 'M' | 'F' | null
  premium: boolean
  summit: boolean
  created_at: string
  updated_at: string
  badge_type_id: number
  weight: number | null
  profile_medium: string
  profile: string
  friend: null | string
  follower: null | string
}

// Activity Types
export interface StravaActivity {
  id: number
  resource_state: number
  upload_id: number | null
  athlete: {
    id: number
    resource_state: number
  }
  name: string
  distance: number // meters
  moving_time: number // seconds
  elapsed_time: number // seconds
  total_elevation_gain: number // meters
  type: StravaActivityType
  sport_type: StravaSportType
  workout_type: number | null
  start_date: string // ISO 8601
  start_date_local: string // ISO 8601
  timezone: string
  utc_offset: number
  location_city: string | null
  location_state: string | null
  location_country: string | null
  achievement_count: number
  kudos_count: number
  comment_count: number
  athlete_count: number
  photo_count: number
  map: StravaMap
  trainer: boolean
  commute: boolean
  manual: boolean
  private: boolean
  visibility: 'everyone' | 'followers_only' | 'only_me'
  flagged: boolean
  gear_id: string | null
  start_latlng: [number, number] | null
  end_latlng: [number, number] | null
  average_speed: number // m/s
  max_speed: number // m/s
  average_cadence?: number
  average_temp?: number
  average_watts?: number
  weighted_average_watts?: number
  kilojoules?: number
  device_watts?: boolean
  has_heartrate: boolean
  average_heartrate?: number
  max_heartrate?: number
  heartrate_opt_out?: boolean
  display_hide_heartrate_option?: boolean
  elev_high?: number
  elev_low?: number
  upload_id_str?: string
  external_id?: string
  from_accepted_tag?: boolean
  pr_count?: number
  total_photo_count?: number
  has_kudoed: boolean
}

export interface StravaDetailedActivity extends StravaActivity {
  description: string | null
  calories: number
  device_name: string
  embed_token: string
  segment_leaderboard_opt_out: boolean
  leaderboard_opt_out: boolean
  photos: StravaPhotos
  gear: StravaGear | null
  laps: StravaLap[]
  splits_metric: StravaSplit[]
  splits_standard: StravaSplit[]
  best_efforts?: StravaBestEffort[]
}

export interface StravaMap {
  id: string
  summary_polyline: string | null
  resource_state: number
  polyline?: string | null
}

export interface StravaPhotos {
  primary: StravaPhoto | null
  use_primary_photo: boolean
  count: number
}

export interface StravaPhoto {
  id: number | null
  unique_id: string
  urls: {
    [key: string]: string
  }
  source: number
  upload_id: number | null
  activity_id: number | null
  resource_state: number
  caption: string | null
  created_at: string
  created_at_local: string
  type: string
  location: [number, number] | null
  athlete_id: number | null
}

export interface StravaGear {
  id: string
  primary: boolean
  name: string
  nickname: string | null
  retired: boolean
  distance: number
  converted_distance: number
  resource_state: number
}

export interface StravaLap {
  id: number
  resource_state: number
  name: string
  activity: {
    id: number
    resource_state: number
  }
  athlete: {
    id: number
    resource_state: number
  }
  elapsed_time: number
  moving_time: number
  start_date: string
  start_date_local: string
  distance: number
  start_index: number
  end_index: number
  total_elevation_gain: number
  average_speed: number
  max_speed: number
  average_cadence?: number
  device_watts?: boolean
  average_watts?: number
  lap_index: number
  split: number
  average_heartrate?: number
  max_heartrate?: number
  pace_zone?: number
}

export interface StravaSplit {
  distance: number
  elapsed_time: number
  elevation_difference: number
  moving_time: number
  split: number
  average_speed: number
  average_grade_adjusted_speed?: number
  average_heartrate?: number
  pace_zone?: number
}

export interface StravaBestEffort {
  id: number
  resource_state: number
  name: string
  activity: {
    id: number
    resource_state: number
  }
  athlete: {
    id: number
    resource_state: number
  }
  elapsed_time: number
  moving_time: number
  start_date: string
  start_date_local: string
  distance: number
  start_index: number
  end_index: number
  pr_rank: number | null
  achievements: unknown[]
}

// Activity Type Enums
export type StravaActivityType =
  | 'Run'
  | 'Ride'
  | 'Swim'
  | 'Hike'
  | 'Walk'
  | 'AlpineSki'
  | 'BackcountrySki'
  | 'Canoeing'
  | 'Crossfit'
  | 'EBikeRide'
  | 'Elliptical'
  | 'Golf'
  | 'Handcycle'
  | 'IceSkate'
  | 'InlineSkate'
  | 'Kayaking'
  | 'Kitesurf'
  | 'NordicSki'
  | 'RockClimbing'
  | 'RollerSki'
  | 'Rowing'
  | 'Snowboard'
  | 'Snowshoe'
  | 'Soccer'
  | 'StairStepper'
  | 'StandUpPaddling'
  | 'Surfing'
  | 'VirtualRide'
  | 'VirtualRun'
  | 'WeightTraining'
  | 'Windsurf'
  | 'Workout'
  | 'Yoga'

export type StravaSportType =
  | 'AlpineSki'
  | 'BackcountrySki'
  | 'Canoeing'
  | 'Crossfit'
  | 'EBikeRide'
  | 'Elliptical'
  | 'Golf'
  | 'Handcycle'
  | 'Hike'
  | 'IceSkate'
  | 'InlineSkate'
  | 'Kayaking'
  | 'Kitesurf'
  | 'NordicSki'
  | 'Ride'
  | 'RockClimbing'
  | 'RollerSki'
  | 'Rowing'
  | 'Run'
  | 'Snowboard'
  | 'Snowshoe'
  | 'Soccer'
  | 'StairStepper'
  | 'StandUpPaddling'
  | 'Surfing'
  | 'Swim'
  | 'VirtualRide'
  | 'VirtualRun'
  | 'Walk'
  | 'WeightTraining'
  | 'Windsurf'
  | 'Workout'
  | 'Yoga'

// Webhook Types
export interface StravaWebhookEvent {
  object_type: 'activity' | 'athlete'
  object_id: number
  aspect_type: 'create' | 'update' | 'delete'
  owner_id: number
  subscription_id: number
  event_time: number
  updates?: {
    title?: string
    type?: StravaActivityType
    private?: boolean | string
    authorized?: string
  }
}

export interface StravaWebhookSubscription {
  id: number
  resource_state: number
  application_id: number
  callback_url: string
  created_at: string
  updated_at: string
}

// Rate Limit Types
export interface StravaRateLimits {
  usage15Min: number
  limit15Min: number
  usageDaily: number
  limitDaily: number
}

// Storage Types (for KV)
export interface StoredUserTokens {
  accessToken: string
  refreshToken: string
  expiresAt: number
  athleteId: number
  athleteName: string
  createdAt: number
  lastRefreshedAt?: number
}

export interface StravaWebhookEventStored {
  type: 'activity.create' | 'activity.update' | 'activity.delete'
  activityId: number
  activity?: StravaDetailedActivity
  timestamp: number
}

// API Request/Response Types
export interface ExchangeTokenRequest {
  code: string
  userId: string
}

export interface ExchangeTokenResponse {
  accessToken: string
  refreshToken: string
  expiresAt: number
  athlete: StravaAthlete
}

export interface RefreshTokenRequest {
  refreshToken: string
  userId: string
}

export interface RefreshTokenResponse {
  accessToken: string
  refreshToken: string
  expiresAt: number
}

export interface FetchActivitiesRequest {
  page?: number
  perPage?: number
  after?: number // Unix timestamp
  before?: number // Unix timestamp
}

export interface FetchActivitiesResponse {
  activities: StravaActivity[]
  pagination: {
    page: number
    perPage: number
    count: number
    hasMore: boolean
  }
  rateLimit: {
    usage: string | null
    limit: string | null
  }
}

export interface CreateWebhookSubscriptionRequest {
  callbackUrl?: string
}

export interface CreateWebhookSubscriptionResponse extends StravaWebhookSubscription {}

// Error Types
export interface StravaAPIError {
  message: string
  errors: Array<{
    resource: string
    field: string
    code: string
  }>
}
