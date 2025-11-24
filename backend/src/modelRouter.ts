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
interface ModelConfig {
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
 * Centralized mapping: RequestType → Model
 * This is the SINGLE SOURCE OF TRUTH for model selection
 * Change models here without touching any other code
 */
const REQUEST_TYPE_TO_MODEL: Record<RequestType, keyof typeof MODELS> = {
  [RequestType.SIMPLE]: 'GROK_4_FAST',
  [RequestType.MODERATE]: 'GROK_4_FAST',
  [RequestType.COMPLEX]: 'GEMINI_3_PRO_PREVIEW', // Premium model with quota
  [RequestType.WORKOUT_GENERATION]: 'GEMINI_FLASH',
  [RequestType.BATCH_PROCESSING]: 'GEMINI_FLASH_LITE',
  [RequestType.SMART_SUGGESTION]: 'GROK_4_FAST',
  [RequestType.CLASSIFICATION]: 'GEMINI_FLASH',
}

/**
 * Fallback model when premium quota is exceeded
 */
const PREMIUM_MODEL_FALLBACK: keyof typeof MODELS = 'GROK_4_FAST'

/**
 * Select model for request type
 * Uses centralized mapping and handles quota fallback
 */
function selectModelForRequestType(
  requestType: RequestType,
  hasPremiumQuota: boolean
): ModelConfig {
  // Get model from centralized mapping
  const modelKey = REQUEST_TYPE_TO_MODEL[requestType]

  if (!modelKey) {
    console.warn(`⚠️ ModelRouter: Unknown request type "${requestType}", defaulting to Haiku`)
    return MODELS.CLAUDE_HAIKU_4_5
  }

  const selectedModel = MODELS[modelKey]

  // Handle premium model quota fallback
  if (selectedModel.requiresQuota && !hasPremiumQuota) {
    console.log(
      `⚠️ ModelRouter: Premium model quota exceeded for ${selectedModel.displayName}, falling back to ${MODELS[PREMIUM_MODEL_FALLBACK].displayName}`
    )
    return MODELS[PREMIUM_MODEL_FALLBACK]
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
  // Check premium model quota if user ID provided
  let premiumQuotaStatus: PremiumModelQuotaStatus | undefined
  let hasPremiumQuota = false

  if (userId) {
    premiumQuotaStatus = await checkPremiumModelQuota(kv, userId)
    hasPremiumQuota = premiumQuotaStatus.hasQuota
  }

  // Select appropriate model
  const model = selectModelForRequestType(requestType, hasPremiumQuota)

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

  // Validate and use requestType
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

  // Final fallback to default
  console.warn(`⚠️ Invalid requestType "${modelType}", using default: ${defaultRequestType}`)
  const selection = await selectModel(defaultRequestType, kv, userId)
  return {
    modelId: selection.model.modelId,
    modelConfig: selection.model,
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
