import { afterEach, describe, expect, mock, spyOn, test } from 'bun:test'
import {
  afterModelUsage,
  checkPremiumModelQuota,
  deleteModel,
  RequestType,
  selectModel,
  selectModelFromRequest,
  upsertModel,
} from '../src/modelRouter'

function premiumQuotaKV(used: string | null) {
  return {
    get: async (key: string) => (key.startsWith('premium_quota:') ? used : null),
  } as unknown as KVNamespace
}

describe('client-selected model', () => {
  afterEach(() => mock.restore())

  test.each([
    'openai/o1-pro',
    42,
  ])('an id outside the catalog falls back to the route default: %p', async (model) => {
    const warn = spyOn(console, 'warn').mockImplementation(() => {})
    const kv = premiumQuotaKV(null)
    const selection = await selectModelFromRequest(
      undefined,
      model as string,
      kv,
      'test-user',
      RequestType.WORKOUT_GENERATION
    )
    const routeDefault = (await selectModel(RequestType.WORKOUT_GENERATION, kv, 'test-user')).model
    expect(selection).toEqual({ modelId: routeDefault.modelId, modelConfig: routeDefault })
    expect(String(warn.mock.calls[0]?.[0])).toContain(String(model))
  })

  test('a catalog model is honoured with its configuration', async () => {
    const selection = await selectModelFromRequest(
      undefined,
      'anthropic/claude-haiku-4.5',
      premiumQuotaKV(null),
      'test-user',
      RequestType.WORKOUT_GENERATION
    )
    expect(selection.modelId).toBe('anthropic/claude-haiku-4.5')
    expect(selection.modelConfig?.requiresQuota).toBe(false)
  })

  test('a custom model stored in the KV catalog is honoured', async () => {
    const stored = new Map<string, string>()
    const kv = {
      get: async (key: string) => stored.get(key) ?? null,
      put: async (key: string, value: string) => {
        stored.set(key, value)
      },
    } as unknown as KVNamespace
    const custom = {
      modelId: 'vendor/custom-model',
      displayName: 'Custom',
      description: '',
      requiresQuota: false,
    }
    await upsertModel(kv, 'CUSTOM_TEST_MODEL', custom)
    try {
      const selection = await selectModelFromRequest(
        undefined,
        custom.modelId,
        kv,
        'test-user',
        RequestType.SMART_SUGGESTION
      )
      expect(selection).toEqual({ modelId: custom.modelId, modelConfig: custom })
    } finally {
      await deleteModel(kv, 'CUSTOM_TEST_MODEL')
    }
  })

  test('a premium catalog model is only honoured while premium quota remains', async () => {
    spyOn(console, 'warn').mockImplementation(() => {})
    const premium = 'google/gemini-3-pro-preview'
    const withQuota = await selectModelFromRequest(
      undefined,
      premium,
      premiumQuotaKV('3'),
      'test-user',
      RequestType.SMART_SUGGESTION
    )
    expect(withQuota.modelId).toBe(premium)
    expect(withQuota.modelConfig?.requiresQuota).toBe(true)

    const exhausted = await selectModelFromRequest(
      undefined,
      premium,
      premiumQuotaKV('20'),
      'test-user',
      RequestType.SMART_SUGGESTION
    )
    expect(exhausted.modelId).not.toBe(premium)
    expect(exhausted.modelConfig?.requiresQuota).toBe(false)
  })
})

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

  test('reads the quota with a cache TTL accepted by Workers KV (minimum 30 seconds)', async () => {
    const kv = {
      async get(_key: string, options: { cacheTtl: number }) {
        if (options.cacheTtl < 30) throw new Error('Workers KV requires cacheTtl >= 30')
        return '3'
      },
    } as unknown as KVNamespace

    const quota = await checkPremiumModelQuota(kv, 'workout-test-user')
    expect(quota.used).toBe(3)
    expect(quota.hasQuota).toBe(true)
    expect(quota.remaining).toBe(quota.limit - 3)
  })
})
