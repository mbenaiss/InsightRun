import { describe, expect, test } from 'bun:test'
import { checkPremiumModelQuota } from '../src/modelRouter'

describe('premium model quota', () => {
  test('reads the quota with a cache TTL accepted by Workers KV', async () => {
    const kv = {
      async get(_key: string, options: { cacheTtl: number }) {
        if (options.cacheTtl < 60) throw new Error('Workers KV requires cacheTtl >= 60')
        return '3'
      },
    } as unknown as KVNamespace

    const quota = await checkPremiumModelQuota(kv, 'workout-test-user')
    expect(quota.used).toBe(3)
    expect(quota.hasQuota).toBe(true)
    expect(quota.remaining).toBe(quota.limit - 3)
  })
})
