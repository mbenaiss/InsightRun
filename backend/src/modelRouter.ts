// Model routing and selection logic
// Maps semantic request types to specific AI models

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
}

/**
 * Premium model quota configuration
 * Limits premium model usage to maintain profitability
 */
export const PREMIUM_MODEL_QUOTA_CONFIG = {
  maxRequestsPerMonth: 20,
  quotaKeyPrefix: 'premium_quota:',
}

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
 * Get custom models from KV
 */
async function getCustomModels(kv: KVNamespace): Promise<Record<string, ModelConfig>> {
  try {
    const json = await kv.get(KV_CUSTOM_MODELS_KEY)
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
  console.log('✅ ModelRouter: Updated custom models in KV')
}

/**
 * Get all models (default + custom merged)
 */
export async function getAllModels(kv: KVNamespace): Promise<Record<string, ModelConfig>> {
  const customModels = await getCustomModels(kv)
  return { ...DEFAULT_MODELS, ...customModels }
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
 */
export async function getModelMapping(kv: KVNamespace): Promise<Record<RequestType, string>> {
  try {
    const [configJson, allModels] = await Promise.all([
      kv.get(KV_MODEL_CONFIG_KEY),
      getAllModels(kv),
    ])
    if (configJson) {
      const config = JSON.parse(configJson) as Record<string, string>
      const mapping: Record<string, string> = { ...DEFAULT_MODEL_MAPPING }
      for (const [requestType, modelKey] of Object.entries(config)) {
        if (
          Object.values(RequestType).includes(requestType as RequestType) &&
          modelKey in allModels
        ) {
          mapping[requestType as RequestType] = modelKey
        }
      }
      console.log('📊 ModelRouter: Using KV config')
      return mapping as Record<RequestType, string>
    }
  } catch (error) {
    console.warn('⚠️ ModelRouter: Failed to read KV config, using defaults', error)
  }
  return DEFAULT_MODEL_MAPPING as Record<RequestType, string>
}

/**
 * Update model mapping in KV store
 */
export async function setModelMapping(
  kv: KVNamespace,
  mapping: Record<string, string>
): Promise<void> {
  await kv.put(KV_MODEL_CONFIG_KEY, JSON.stringify(mapping))
  console.log('✅ ModelRouter: Updated model config in KV')
}

/**
 * Get available models (for admin UI)
 */
export function getAvailableModels(): Record<string, ModelConfig> {
  return MODELS
}

/**
 * Fallback model when premium quota is exceeded
 */
const PREMIUM_MODEL_FALLBACK: keyof typeof MODELS = 'GROK_4_FAST'

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
    const fallback = allModels[PREMIUM_MODEL_FALLBACK] || MODELS[PREMIUM_MODEL_FALLBACK]
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
 */
export async function checkPremiumModelQuota(
  kv: KVNamespace,
  userId: string
): Promise<PremiumModelQuotaStatus> {
  const now = Date.now()
  const currentMonth = new Date(now).toISOString().slice(0, 7) // YYYY-MM
  const quotaKey = `${PREMIUM_MODEL_QUOTA_CONFIG.quotaKeyPrefix}${userId}:${currentMonth}`

  const value = await kv.get(quotaKey)
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
export async function incrementPremiumModelQuota(kv: KVNamespace, userId: string): Promise<void> {
  const now = Date.now()
  const currentMonth = new Date(now).toISOString().slice(0, 7) // YYYY-MM
  const quotaKey = `${PREMIUM_MODEL_QUOTA_CONFIG.quotaKeyPrefix}${userId}:${currentMonth}`

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
  userId?: string
): Promise<{ model: ModelConfig; premiumQuotaStatus?: PremiumModelQuotaStatus }> {
  const [modelMapping, allModels] = await Promise.all([getModelMapping(kv), getAllModels(kv)])

  let premiumQuotaStatus: PremiumModelQuotaStatus | undefined
  let hasPremiumQuota = false

  if (userId) {
    premiumQuotaStatus = await checkPremiumModelQuota(kv, userId)
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
  userId?: string
): Promise<void> {
  // Increment premium model quota if premium model was used
  if (modelConfig.requiresQuota && userId) {
    await incrementPremiumModelQuota(kv, userId)
  }
}

/**
 * Helper to select model from request parameters
 * Handles requestType, manual model override, and defaults
 * Returns modelId and modelConfig for quota tracking
 */
export async function selectModelFromRequest(
  requestType: string | undefined,
  manualModel: string | undefined,
  kv: KVNamespace,
  userId: string,
  defaultRequestType: RequestType = RequestType.MODERATE
): Promise<{ modelId: string; modelConfig: ModelConfig | null }> {
  const modelType = requestType || defaultRequestType

  // Validate and use requestType (uses dynamic mapping from KV)
  if (Object.values(RequestType).includes(modelType as RequestType)) {
    const selection = await selectModel(modelType as RequestType, kv, userId)
    return {
      modelId: selection.model.modelId,
      modelConfig: selection.model,
    }
  }

  // Fallback to manual model if provided
  if (manualModel) {
    console.log(`⚠️ Using manual model override: ${manualModel}`)
    return {
      modelId: manualModel,
      modelConfig: null, // No quota tracking for manual models
    }
  }

  // Final fallback to default (uses dynamic mapping from KV)
  console.warn(`⚠️ Invalid requestType "${modelType}", using default: ${defaultRequestType}`)
  const selection = await selectModel(defaultRequestType, kv, userId)
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
  const [mapping, allModels] = await Promise.all([getModelMapping(kv), getAllModels(kv)])
  return {
    mapping: mapping as Record<string, string>,
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
