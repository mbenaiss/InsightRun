import { describe, expect, spyOn, test } from 'bun:test'
import { afterModelUsage, checkPremiumModelQuota } from '../src/modelRouter'

describe('premium model quota', () => {
  test('records an accounting failure without discarding a completed model response', async () => {
    const kv = {
      async get() {
        return '3'
      },
      async put() {
        throw new Error('KV PUT failed: 503')
      },
    } as unknown as KVNamespace
    const log = spyOn(console, 'error').mockImplementation(() => {})
    try {
      await expect(
        afterModelUsage(
          {
            modelId: 'test-model',
            displayName: 'Test',
            description: '',
            requiresQuota: true,
          },
          kv,
          'test-user'
        )
      ).resolves.toBeUndefined()
      expect(log).toHaveBeenCalledWith('premium_quota_accounting_failed', {
        category: 'shared',
        status: '503',
      })
    } finally {
      log.mockRestore()
    }
  })

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
