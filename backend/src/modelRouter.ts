// Model routing and selection logic
// Maps semantic request types to specific AI models

// === CACHE CONFIGURATION ===
const KV_CACHE_TTL = 60 // Edge cache TTL in seconds
const MEMORY_CACHE_TTL_MS = 30_000 // In-memory cache TTL (30 seconds)

// Module-level cache (persists within Worker isolate lifetime)
interface ModelConfigCache {
  mapping: Record<string, string>
  allModels: Record<string, ModelConfig>
  expiresAt: number
}

let configCache: ModelConfigCache | null = null

/**
 * Request types that describe the semantic intent
 * iOS sends these instead of specific model names
 */
export enum RequestType {
  // Simple queries - Basic stats, quick facts
  SIMPLE = 'SIMPLE',

  // Moderate queries - Training plans, analysis, advice
  MODERATE = 'MODERATE',

  // Complex queries - Medical analysis, injury risk, advanced insights
  COMPLEX = 'COMPLEX',

  // Specialized: Workout generation with structured JSON output
  WORKOUT_GENERATION = 'WORKOUT_GENERATION',

  // Specialized: Batch processing for historical analysis
  BATCH_PROCESSING = 'BATCH_PROCESSING',

  // Specialized: Smart workout suggestions
  SMART_SUGGESTION = 'SMART_SUGGESTION',

  // Specialized: Complexity classification (internal use)
  CLASSIFICATION = 'CLASSIFICATION',
}

/**
 * Model configuration
 */
export interface ModelConfig {
  modelId: string
  displayName: string
  description: string
  requiresQuota: boolean
}

/**
 * Available AI models
 */
const MODELS: Record<string, ModelConfig> = {
  GROK_4_FAST: {
    modelId: 'x-ai/grok-4.1-fast',
    displayName: 'Grok 4.1 Fast',
    description: 'Fast and cheap for simple queries',
    requiresQuota: false,
  },
  CLAUDE_HAIKU_4_5: {
    modelId: 'anthropic/claude-haiku-4.5',
    displayName: 'Claude Haiku 4.5',
    description: 'Balanced model for moderate complexity',
    requiresQuota: false,
  },
  CLAUDE_SONNET_4_5: {
    modelId: 'anthropic/claude-sonnet-4.5',
    displayName: 'Claude Sonnet 4.5',
    description: 'Premium model for complex analysis (available but not used)',
    requiresQuota: true,
  },
  GEMINI_3_PRO_PREVIEW: {
    modelId: 'google/gemini-3-pro-preview',
    displayName: 'Gemini 3 Pro Preview',
    description: 'Premium model for complex analysis',
    requiresQuota: true, // Limited quota for cost control
  },
  GEMINI_FLASH_LITE: {
    modelId: 'google/gemini-2.5-flash-lite',
    displayName: 'Gemini 2.5 Flash Lite',
    description: 'Fast and cost-effective for structured generation',
    requiresQuota: false,
  },
  GEMINI_FLASH: {
    modelId: 'google/gemini-2.5-flash',
    displayName: 'Gemini 2.5 Flash',
    description: 'Fast and cost-effective for structured generation',
    requiresQuota: false,
  },
  GPT_5_4_NANO: {
    modelId: 'openai/gpt-5.4-nano',
    displayName: 'GPT 5.4 nano',
    description: 'Fallback for structured plan generation',
    requiresQuota: false,
  },
}

export const PLAN_FALLBACK_MODEL_ID = MODELS.GPT_5_4_NANO.modelId

/**
 * Premium model quota configuration
 * Limits premium model usage to maintain profitability
 */
export const PREMIUM_MODEL_QUOTA_CONFIG = {
  maxRequestsPerMonth: 20,
  quotaKeyPrefix: 'premium_quota:',
}

/**
 * Premium quota buckets. Plans (large structured generations) and chat (agent
 * conversation) get independent monthly allowances so a chatty user cannot
 * starve plan generation and vice-versa.
 *
 * Both check (selectModel) and increment (afterModelUsage) MUST use the same
 * category, otherwise the counter and the gate drift apart. The plan/adapt
 * routes opt into 'plan' by passing the category to selectModelFromRequest /
 * afterModelUsage; everything else defaults to 'shared'.
 */
export type PremiumQuotaCategory = 'plan' | 'chat' | 'shared'
const DEFAULT_PREMIUM_QUOTA_CATEGORY: PremiumQuotaCategory = 'shared'

/**
 * Default mapping: RequestType → Model
 * Used as fallback when KV config is not available
 */
const DEFAULT_MODEL_MAPPING: Record<RequestType, keyof typeof MODELS> = {
  [RequestType.SIMPLE]: 'GROK_4_FAST',
  [RequestType.MODERATE]: 'GROK_4_FAST',
  [RequestType.COMPLEX]: 'GEMINI_3_PRO_PREVIEW', // Premium model with quota
  [RequestType.WORKOUT_GENERATION]: 'GEMINI_FLASH',
  [RequestType.BATCH_PROCESSING]: 'GEMINI_FLASH_LITE',
  [RequestType.SMART_SUGGESTION]: 'GROK_4_FAST',
  [RequestType.CLASSIFICATION]: 'GEMINI_FLASH',
}

/**
 * KV key for admin model configuration
 */
const KV_MODEL_CONFIG_KEY = 'admin:config:models'

/**
 * KV key for custom models (added via admin)
 */
const KV_CUSTOM_MODELS_KEY = 'admin:config:custom_models'

/**
 * Default models (hardcoded fallback)
 */
const DEFAULT_MODELS = MODELS

/**
 * Invalidate the in-memory cache (call after any config update)
 */
function invalidateCache(): void {
  configCache = null
}

/**
 * Get model configuration with multi-level caching
 * - Level 1: In-memory cache (same isolate, 30s TTL) → ~0ms
 * - Level 2: KV edge cache (60s TTL) → ~1-2ms
 * - Level 3: KV origin → ~3-10ms
 *
 * This replaces separate getModelMapping() + getAllModels() calls
 * to avoid duplicate KV reads.
 */
async function getModelConfigCached(kv: KVNamespace): Promise<{
  mapping: Record<string, string>
  allModels: Record<string, ModelConfig>
}> {
  // Level 1: Check in-memory cache
  if (configCache && Date.now() < configCache.expiresAt) {
    return { mapping: configCache.mapping, allModels: configCache.allModels }
  }

  // Level 2 & 3: KV with edge caching (parallel reads - only 2 KV calls)
  const [mappingJson, customModelsJson] = await Promise.all([
    kv.get(KV_MODEL_CONFIG_KEY, { cacheTtl: KV_CACHE_TTL }),
    kv.get(KV_CUSTOM_MODELS_KEY, { cacheTtl: KV_CACHE_TTL }),
  ])

  // Parse mapping with defaults
  const mapping: Record<string, string> = { ...(DEFAULT_MODEL_MAPPING as Record<string, string>) }
  if (mappingJson) {
    try {
      const config = JSON.parse(mappingJson) as Record<string, string>
      for (const [requestType, modelKey] of Object.entries(config)) {
        if (Object.values(RequestType).includes(requestType as RequestType)) {
          mapping[requestType] = modelKey
        }
      }
    } catch {
      console.warn('⚠️ ModelRouter: Failed to parse model mapping')
    }
  }

  // Parse custom models and merge with defaults
  let allModels: Record<string, ModelConfig> = { ...DEFAULT_MODELS }
  if (customModelsJson) {
    try {
      const customModels = JSON.parse(customModelsJson) as Record<string, ModelConfig>
      allModels = { ...DEFAULT_MODELS, ...customModels }
    } catch {
      console.warn('⚠️ ModelRouter: Failed to parse custom models')
    }
  }

  // Update in-memory cache
  configCache = {
    mapping,
    allModels,
    expiresAt: Date.now() + MEMORY_CACHE_TTL_MS,
  }

  return { mapping, allModels }
}

/**
 * Get custom models from KV (uncached - for admin operations)
 */
async function getCustomModels(kv: KVNamespace): Promise<Record<string, ModelConfig>> {
  try {
    const json = await kv.get(KV_CUSTOM_MODELS_KEY, { cacheTtl: KV_CACHE_TTL })
    if (json) {
      return JSON.parse(json) as Record<string, ModelConfig>
    }
  } catch (error) {
    console.warn('⚠️ ModelRouter: Failed to read custom models from KV', error)
  }
  return {}
}

/**
 * Save custom models to KV
 */
async function setCustomModels(
  kv: KVNamespace,
  models: Record<string, ModelConfig>
): Promise<void> {
  await kv.put(KV_CUSTOM_MODELS_KEY, JSON.stringify(models))
  invalidateCache()
  console.log('✅ ModelRouter: Updated custom models in KV')
}

/**
 * Get all models (default + custom merged)
 */
export async function getAllModels(kv: KVNamespace): Promise<Record<string, ModelConfig>> {
  const { allModels } = await getModelConfigCached(kv)
  return allModels
}

/**
 * Add or update a model
 */
export async function upsertModel(
  kv: KVNamespace,
  key: string,
  config: ModelConfig
): Promise<void> {
  const customModels = await getCustomModels(kv)
  customModels[key] = config
  await setCustomModels(kv, customModels)
  console.log(`✅ ModelRouter: Upserted model ${key}`)
}

/**
 * Delete a custom model (cannot delete default models)
 */
export async function deleteModel(kv: KVNamespace, key: string): Promise<boolean> {
  if (key in DEFAULT_MODELS) {
    console.warn(`⚠️ ModelRouter: Cannot delete default model ${key}`)
    return false
  }
  const customModels = await getCustomModels(kv)
  if (!(key in customModels)) {
    console.warn(`⚠️ ModelRouter: Model ${key} not found in custom models`)
    return false
  }
  delete customModels[key]
  await setCustomModels(kv, customModels)
  console.log(`✅ ModelRouter: Deleted custom model ${key}`)
  return true
}

/**
 * Get model mapping from KV store or use defaults
 * Now uses the cached version for performance
 */
export async function getModelMapping(kv: KVNamespace): Promise<Record<RequestType, string>> {
  const { mapping } = await getModelConfigCached(kv)
  return mapping as Record<RequestType, string>
}

/**
 * Update model mapping in KV store
 */
export async function setModelMapping(
  kv: KVNamespace,
  mapping: Record<string, string>
): Promise<void> {
  await kv.put(KV_MODEL_CONFIG_KEY, JSON.stringify(mapping))
  invalidateCache()
  console.log('✅ ModelRouter: Updated model config in KV')
}

/**
 * Get available models (for admin UI)
 */
export function getAvailableModels(): Record<string, ModelConfig> {
  return MODELS
}

/**
 * Default fallback model when premium quota is exceeded
 */
const PREMIUM_MODEL_FALLBACK: keyof typeof MODELS = 'GROK_4_FAST'

/**
 * Per-request-type fallback when premium quota is exhausted.
 * COMPLEX produces large structured JSON (16k-token training plans); Grok fast
 * truncates/mangles them, so it must degrade to a capable non-premium model.
 */
const PREMIUM_FALLBACK_BY_REQUEST_TYPE: Partial<Record<RequestType, keyof typeof MODELS>> = {
  [RequestType.COMPLEX]: 'GEMINI_FLASH',
}

/**
 * Select model for request type
 * Uses dynamic mapping from KV and handles quota fallback
 */
function selectModelForRequestType(
  requestType: RequestType,
  hasPremiumQuota: boolean,
  modelMapping: Record<RequestType, string>,
  allModels: Record<string, ModelConfig>
): ModelConfig {
  const modelKey = modelMapping[requestType]

  if (!modelKey || !(modelKey in allModels)) {
    console.warn(
      `⚠️ ModelRouter: Unknown request type or model "${requestType}:${modelKey}", defaulting to Haiku`
    )
    return MODELS.CLAUDE_HAIKU_4_5
  }

  const selectedModel = allModels[modelKey]

  if (selectedModel.requiresQuota && !hasPremiumQuota) {
    const fallbackKey = PREMIUM_FALLBACK_BY_REQUEST_TYPE[requestType] || PREMIUM_MODEL_FALLBACK
    const fallback = allModels[fallbackKey] || MODELS[fallbackKey]
    console.log(
      `⚠️ ModelRouter: Premium model quota exceeded for ${selectedModel.displayName}, falling back to ${fallback.displayName}`
    )
    return fallback
  }

  return selectedModel
}

/**
 * Premium Model Quota Management
 */

interface PremiumModelQuotaStatus {
  used: number
  limit: number
  remaining: number
  resetAt: number // Unix timestamp
  hasQuota: boolean
}

/**
 * Check if user has premium model quota remaining
 *
 * When `userId` is the literal `unknown` (no X-User-ID and no client IP), the
 * caller should pass a per-IP identifier upstream; here we still namespace by
 * category so the two premium buckets never collide.
 */
export async function checkPremiumModelQuota(
  kv: KVNamespace,
  userId: string,
  category: PremiumQuotaCategory = DEFAULT_PREMIUM_QUOTA_CATEGORY
): Promise<PremiumModelQuotaStatus> {
  const now = Date.now()
  const currentMonth = new Date(now).toISOString().slice(0, 7) // YYYY-MM
  const quotaKey = `${PREMIUM_MODEL_QUOTA_CONFIG.quotaKeyPrefix}${category}:${userId}:${currentMonth}`

  // Short cache TTL for quota (30s minimum for Cloudflare KV)
  const value = await kv.get(quotaKey, { cacheTtl: 30 })
  const used = value ? Number.parseInt(value, 10) : 0
  const remaining = Math.max(0, PREMIUM_MODEL_QUOTA_CONFIG.maxRequestsPerMonth - used)

  // Calculate reset date (first day of next month)
  const resetDate = new Date(now)
  resetDate.setMonth(resetDate.getMonth() + 1)
  resetDate.setDate(1)
  resetDate.setHours(0, 0, 0, 0)
  const resetAt = Math.floor(resetDate.getTime() / 1000)

  return {
    used,
    limit: PREMIUM_MODEL_QUOTA_CONFIG.maxRequestsPerMonth,
    remaining,
    resetAt,
    hasQuota: remaining > 0,
  }
}

/**
 * Increment premium model usage counter
 */
export async function incrementPremiumModelQuota(
  kv: KVNamespace,
  userId: string,
  category: PremiumQuotaCategory = DEFAULT_PREMIUM_QUOTA_CATEGORY
): Promise<void> {
  const now = Date.now()
  const currentMonth = new Date(now).toISOString().slice(0, 7) // YYYY-MM
  const quotaKey = `${PREMIUM_MODEL_QUOTA_CONFIG.quotaKeyPrefix}${category}:${userId}:${currentMonth}`

  const value = await kv.get(quotaKey)
  const used = value ? Number.parseInt(value, 10) : 0
  const newUsed = used + 1

  // Set expiration to end of next month to ensure cleanup
  const expirationDate = new Date(now)
  expirationDate.setMonth(expirationDate.getMonth() + 2)
  expirationDate.setDate(1)
  expirationDate.setHours(0, 0, 0, 0)
  const expirationTtl = Math.floor((expirationDate.getTime() - now) / 1000)

  await kv.put(quotaKey, newUsed.toString(), {
    expirationTtl,
  })

  console.log(
    `💰 ModelRouter: Premium model usage for ${userId}: ${newUsed}/${PREMIUM_MODEL_QUOTA_CONFIG.maxRequestsPerMonth}`
  )
}

/**
 * Main model selection function
 * Returns the optimal model for a given request type and user
 */
export async function selectModel(
  requestType: RequestType,
  kv: KVNamespace,
  userId?: string,
  quotaCategory: PremiumQuotaCategory = DEFAULT_PREMIUM_QUOTA_CATEGORY
): Promise<{ model: ModelConfig; premiumQuotaStatus?: PremiumModelQuotaStatus }> {
  // Single cached call instead of separate getModelMapping + getAllModels (was reading KV 3x, now 2x max)
  const { mapping: modelMapping, allModels } = await getModelConfigCached(kv)

  let premiumQuotaStatus: PremiumModelQuotaStatus | undefined
  let hasPremiumQuota = false

  if (userId) {
    premiumQuotaStatus = await checkPremiumModelQuota(kv, userId, quotaCategory)
    hasPremiumQuota = premiumQuotaStatus.hasQuota
  }

  const model = selectModelForRequestType(requestType, hasPremiumQuota, modelMapping, allModels)

  console.log(`🎯 ModelRouter: ${requestType} → ${model.displayName} (${model.modelId})`)

  return {
    model,
    premiumQuotaStatus,
  }
}

/**
 * Post-request handler to increment quotas if needed
 */
export async function afterModelUsage(
  modelConfig: ModelConfig,
  kv: KVNamespace,
  userId?: string,
  quotaCategory: PremiumQuotaCategory = DEFAULT_PREMIUM_QUOTA_CATEGORY
): Promise<void> {
  // Increment premium model quota if premium model was used
  if (modelConfig.requiresQuota && userId) {
    await incrementPremiumModelQuota(kv, userId, quotaCategory)
  }
}

/**
 * Helper to select model from request parameters
 * Handles requestType, manual model override, and defaults
 * Returns modelId and modelConfig for quota tracking
 *
 * `allowedRequestTypes` is the server-side whitelist of request types this route
 * may serve. A client-supplied requestType outside the whitelist is rejected and
 * the route default is used instead, so a client cannot force a premium tier
 * (e.g. COMPLEX) on a cheap endpoint to drain quota / inflate cost.
 */
export async function selectModelFromRequest(
  requestType: string | undefined,
  manualModel: string | undefined,
  kv: KVNamespace,
  userId: string,
  defaultRequestType: RequestType = RequestType.MODERATE,
  allowedRequestTypes?: RequestType[],
  quotaCategory: PremiumQuotaCategory = DEFAULT_PREMIUM_QUOTA_CATEGORY
): Promise<{ modelId: string; modelConfig: ModelConfig | null }> {
  const whitelist = allowedRequestTypes ?? [defaultRequestType]
  const requested = requestType as RequestType | undefined

  // Use the client requestType only if it is a valid enum AND allowed for this route
  if (requested && whitelist.includes(requested)) {
    const selection = await selectModel(requested, kv, userId, quotaCategory)
    return {
      modelId: selection.model.modelId,
      modelConfig: selection.model,
    }
  }

  if (requestType && requested !== defaultRequestType) {
    console.warn(
      `⚠️ ModelRouter: requestType "${requestType}" not allowed for this route, using ${defaultRequestType}`
    )
  }

  // Manual model override is only honoured when no requestType was supplied,
  // to keep an explicit escape hatch without letting clients bypass the whitelist.
  if (!requestType && manualModel) {
    console.log(`⚠️ Using manual model override: ${manualModel}`)
    return {
      modelId: manualModel,
      modelConfig: null, // No quota tracking for manual models
    }
  }

  const selection = await selectModel(defaultRequestType, kv, userId, quotaCategory)
  return {
    modelId: selection.model.modelId,
    modelConfig: selection.model,
  }
}

/**
 * Get current model configuration (for admin API)
 */
export async function getCurrentModelConfig(kv: KVNamespace): Promise<{
  mapping: Record<string, string>
  models: Record<string, ModelConfig>
  defaults: Record<string, string>
  defaultModels: Record<string, ModelConfig>
}> {
  // Single cached call
  const { mapping, allModels } = await getModelConfigCached(kv)
  return {
    mapping,
    models: allModels,
    defaults: DEFAULT_MODEL_MAPPING as Record<string, string>,
    defaultModels: DEFAULT_MODELS,
  }
}

/**
 * Validate that requestType is a valid enum value
 */
export function isValidRequestType(requestType: unknown): requestType is RequestType {
  return (
    typeof requestType === 'string' &&
    Object.values(RequestType).includes(requestType as RequestType)
  )
}
