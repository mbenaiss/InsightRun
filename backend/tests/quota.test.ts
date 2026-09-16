import { afterEach, describe, expect, mock, spyOn, test } from 'bun:test'
import { checkQuota, getQuotaHeaders, incrementQuota } from '../src/quota'

afterEach(() => mock.restore())

const config = { ipLimit: 100, ipWindow: 3600, userLimit: 2000, userWindow: 2592000 }
const ipKey = 'ratelimit:ip:192.0.2.1'
const userKey = 'ratelimit:user:test-user'

function setup() {
  let now = 1_800_000_000
  spyOn(Date, 'now').mockImplementation(() => now * 1000)
  const stored = new Map<
    string,
    { value: string; expiration?: number; metadata?: { resetAt: number } }
  >()
  const put = mock(async (key: string, value: string, options: KVNamespacePutOptions) => {
    const expiration = options.expiration ?? now + (options.expirationTtl ?? 0)
    if (expiration < now + 60) throw new Error('KV expiration must be at least 60 seconds away')
    stored.set(key, {
      value,
      expiration,
      metadata: options.metadata as { resetAt: number } | undefined,
    })
  })
  const list = mock(async ({ prefix }: { prefix: string }) => ({
    keys: [...stored.entries()]
      .filter(([key]) => key.startsWith(prefix))
      .map(([name, entry]) => ({ name, expiration: entry.expiration })),
    list_complete: true,
    cacheStatus: null,
  }))
  const kv = {
    get: async (key: string) => stored.get(key)?.value ?? null,
    getWithMetadata: async (key: string) => ({
      value: stored.get(key)?.value ?? null,
      metadata: stored.get(key)?.metadata ?? null,
      cacheStatus: null,
    }),
    list,
    put,
  } as unknown as KVNamespace
  return {
    kv,
    stored,
    put,
    list,
    now: () => now,
    advance: (seconds: number) => {
      now += seconds
    },
    check: () => checkQuota(kv, '192.0.2.1', 'test-user', config),
    increment: () => incrementQuota(kv, '192.0.2.1', 'test-user', config),
  }
}

describe('quota windows', () => {
  test('requests keep the original user deadline while expired IP windows restart', async () => {
    const { stored, now, advance, check, increment } = setup()
    const start = now()
    await increment()
    advance(86400)
    await increment()

    const quota = await check()
    expect(quota.user?.remaining).toBe(1998)
    expect(quota.user?.resetAt).toBe(start + config.userWindow)
    expect(quota.user?.resetIn).toBe(config.userWindow - 86400)
    expect(quota.ip.remaining).toBe(99)
    expect(quota.ip.resetAt).toBe(now() + config.ipWindow)
    expect(stored.get(userKey)?.expiration).toBe(start + config.userWindow)
  })

  test('expired counters restart even if the old value is still in KV', async () => {
    const { stored, now, check, increment } = setup()
    stored.set(userKey, { value: '2000', metadata: { resetAt: now() - 1 } })

    expect((await check()).allowed).toBe(true)
    await increment()
    expect(stored.get(userKey)?.value).toBe('1')
    expect(stored.get(userKey)?.metadata?.resetAt).toBe(now() + config.userWindow)
  })

  test('legacy exhausted counters report their actual existing expiry', async () => {
    const { stored, now, check, put } = setup()
    stored.set(userKey, { value: '2000', expiration: now() + 120 })

    const quota = await check()
    expect(quota.allowed).toBe(false)
    expect(quota.restrictedBy).toBe('user')
    expect(quota.user?.resetIn).toBe(120)
    expect(put).not.toHaveBeenCalled()
  })

  test('legacy counters retain usage and expiry when migrated to metadata', async () => {
    const { stored, now, advance, increment, list } = setup()
    const resetAt = now() + 600
    stored.set(userKey, { value: '1998', expiration: resetAt })
    await increment()
    advance(100)
    await increment()

    expect(stored.get(userKey)).toEqual({
      value: '2000',
      expiration: resetAt,
      metadata: { resetAt },
    })
    expect(list).toHaveBeenCalledTimes(1)
  })

  test('the KV minimum retention does not extend the logical quota window', async () => {
    const { stored, now, advance, check, increment } = setup()
    const resetAt = now() + 5
    stored.set(userKey, { value: '1999', metadata: { resetAt } })
    await increment()

    expect(stored.get(userKey)?.expiration).toBe(now() + 60)
    expect(stored.get(userKey)?.metadata?.resetAt).toBe(resetAt)
    expect((await check()).allowed).toBe(false)
    advance(5)
    expect((await check()).allowed).toBe(true)
  })

  test.each([
    'user',
    'ip',
  ] as const)('429 headers identify the actual %s retry deadline', async (bucket) => {
    const { stored, now, advance, check } = setup()
    stored.set(bucket === 'user' ? userKey : ipKey, {
      value: bucket === 'user' ? '2000' : '100',
      metadata: { resetAt: now() + 300 },
    })
    advance(120)

    const headers = getQuotaHeaders(await check())
    expect(headers['Retry-After']).toBe('180')
    expect(headers['X-RateLimit-Reset']).toBe(String(now() + 180))
  })

  test('retry waits for both exhausted buckets to become available', async () => {
    const { stored, now, check } = setup()
    stored.set(userKey, { value: '2000', metadata: { resetAt: now() + 60 } })
    stored.set(ipKey, { value: '100', metadata: { resetAt: now() + 300 } })

    const quota = await check()
    expect(quota.allowed).toBe(false)
    expect(quota.restrictedBy).toBe('ip')
    expect(getQuotaHeaders(quota)['Retry-After']).toBe('300')
  })
})

describe('quota write resilience', () => {
  test('a rejected IP write does not prevent user accounting', async () => {
    const { kv, put, stored } = setup()
    put.mockImplementation(async (key, value) => {
      if (key === ipKey) throw new Error('KV PUT failed: 503')
      stored.set(key, { value })
    })
    await expect(incrementQuota(kv, '192.0.2.1', 'test-user', config)).rejects.toThrow(
      'Quota accounting failed'
    )
    expect(stored.get(userKey)?.value).toBe('1')
    expect(put).toHaveBeenCalledTimes(2)
  })

  test('a 429 write is retried using a fresh counter without extending its deadline', async () => {
    const { kv, put, stored, now } = setup()
    const resetAt = now() + 300
    stored.set(ipKey, { value: '3', metadata: { resetAt } })
    let attempts = 0
    put.mockImplementation(async (key, value, options) => {
      attempts++
      if (attempts === 1) {
        stored.set(key, { value: '4', metadata: { resetAt } })
        throw new Error('KV PUT failed: 429 Too Many Requests')
      }
      stored.set(key, { value, metadata: options.metadata as { resetAt: number } })
    })
    await incrementQuota(kv, '192.0.2.1', undefined, config)
    expect(put).toHaveBeenCalledTimes(2)
    expect(stored.get(ipKey)).toEqual({ value: '5', metadata: { resetAt } })
  })
})
