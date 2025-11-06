// Quota management for IP-based and User-based rate limiting

export interface QuotaConfig {
  ipLimit: number
  ipWindow: number // seconds
  userLimit: number
  userWindow: number // seconds
}

export interface QuotaStatus {
  remaining: number
  limit: number
  resetAt: number // Unix timestamp
  resetIn: number // seconds
}

export interface QuotaCheck {
  allowed: boolean
  ip: QuotaStatus
  user?: QuotaStatus
  restrictedBy?: 'ip' | 'user'
  message?: string
}

const DEFAULT_QUOTA_CONFIG: QuotaConfig = {
  // IP-based: 100 requests per hour
  ipLimit: 100,
  ipWindow: 3600, // 1 hour

  // User-based: 1000 requests per month
  userLimit: 1000,
  userWindow: 2592000, // 30 days (30 * 24 * 60 * 60)
}

/**
 * Get current quota status from KV store
 */
async function getQuotaStatus(
  kv: KVNamespace,
  key: string,
  limit: number,
  window: number
): Promise<QuotaStatus> {
  const value = await kv.get(key)
  const count = value ? Number.parseInt(value, 10) : 0

  const now = Math.floor(Date.now() / 1000)
  const resetIn = window // Default to full window if we can't determine exact reset time

  return {
    remaining: Math.max(0, limit - count),
    limit,
    resetAt: now + resetIn,
    resetIn,
  }
}

/**
 * Check if request is allowed based on both IP and User quotas
 */
export async function checkQuota(
  kv: KVNamespace,
  ip: string,
  userId?: string,
  config: QuotaConfig = DEFAULT_QUOTA_CONFIG
): Promise<QuotaCheck> {
  // Check IP quota
  const ipKey = `ratelimit:ip:${ip}`
  const ipStatus = await getQuotaStatus(kv, ipKey, config.ipLimit, config.ipWindow)

  // Check User quota if userId provided
  let userStatus: QuotaStatus | undefined
  if (userId) {
    const userKey = `ratelimit:user:${userId}`
    userStatus = await getQuotaStatus(kv, userKey, config.userLimit, config.userWindow)
  }

  // Determine if request is allowed
  let allowed = ipStatus.remaining > 0
  let restrictedBy: 'ip' | 'user' | undefined

  if (userStatus && userStatus.remaining === 0) {
    allowed = false
    restrictedBy = 'user'
  } else if (ipStatus.remaining === 0) {
    restrictedBy = 'ip'
  }

  const message = !allowed
    ? `${restrictedBy === 'user' ? 'User' : 'IP'} quota exceeded. Resets in ${restrictedBy === 'user' ? userStatus?.resetIn : ipStatus.resetIn} seconds.`
    : undefined

  return {
    allowed,
    ip: ipStatus,
    user: userStatus,
    restrictedBy: !allowed ? restrictedBy : undefined,
    message,
  }
}

/**
 * Increment quota counters for IP and User
 */
export async function incrementQuota(
  kv: KVNamespace,
  ip: string,
  userId?: string,
  config: QuotaConfig = DEFAULT_QUOTA_CONFIG
): Promise<void> {
  // Increment IP counter
  const ipKey = `ratelimit:ip:${ip}`
  const ipCount = await kv.get(ipKey)
  const ipRequestCount = ipCount ? Number.parseInt(ipCount, 10) : 0
  await kv.put(ipKey, (ipRequestCount + 1).toString(), {
    expirationTtl: config.ipWindow,
  })

  // Increment User counter if userId provided
  if (userId) {
    const userKey = `ratelimit:user:${userId}`
    const userCount = await kv.get(userKey)
    const userRequestCount = userCount ? Number.parseInt(userCount, 10) : 0
    await kv.put(userKey, (userRequestCount + 1).toString(), {
      expirationTtl: config.userWindow,
    })
  }
}

/**
 * Get quota headers for HTTP response
 */
export function getQuotaHeaders(quotaCheck: QuotaCheck): Record<string, string> {
  const headers: Record<string, string> = {
    'X-RateLimit-IP-Limit': quotaCheck.ip.limit.toString(),
    'X-RateLimit-IP-Remaining': quotaCheck.ip.remaining.toString(),
    'X-RateLimit-IP-Reset': quotaCheck.ip.resetAt.toString(),
  }

  if (quotaCheck.user) {
    headers['X-RateLimit-User-Limit'] = quotaCheck.user.limit.toString()
    headers['X-RateLimit-User-Remaining'] = quotaCheck.user.remaining.toString()
    headers['X-RateLimit-User-Reset'] = quotaCheck.user.resetAt.toString()
  }

  return headers
}

/**
 * Get quota configuration (can be extended to support env variables)
 */
export function getQuotaConfig(): QuotaConfig {
  return DEFAULT_QUOTA_CONFIG
}
