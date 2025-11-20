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
  costPer1MTokens: number // in USD
  requiresQuota: boolean
}

/**
 * Available AI models
 */
const MODELS: Record<string, ModelConfig> = {
  GROK_4_FAST: {
    modelId: 'x-ai/grok-4-fast',
    displayName: 'Grok 4 Fast',
    description: 'Fast and cheap for simple queries',
    costPer1MTokens: 0.4,
    requiresQuota: false,
  },
  CLAUDE_HAIKU_4_5: {
    modelId: 'anthropic/claude-haiku-4.5',
    displayName: 'Claude Haiku 4.5',
    description: 'Balanced model for moderate complexity',
    costPer1MTokens: 15.0,
    requiresQuota: false,
  },
  CLAUDE_SONNET_4_5: {
    modelId: 'anthropic/claude-sonnet-4.5',
    displayName: 'Claude Sonnet 4.5',
    description: 'Premium model for complex analysis',
    costPer1MTokens: 34.6,
    requiresQuota: true, // Limited quota for cost control
  },
  GEMINI_FLASH_LITE: {
    modelId: 'google/gemini-2.5-flash-lite',
    displayName: 'Gemini 2.5 Flash Lite',
    description: 'Fast and cost-effective for structured generation',
    costPer1MTokens: 1.5,
    requiresQuota: false,
  },
}

/**
 * Sonnet quota configuration
 * Limits Sonnet usage to maintain profitability
 */
export const SONNET_QUOTA_CONFIG = {
  maxRequestsPerMonth: 10,
  quotaKeyPrefix: 'sonnet_quota:',
}

/**
 * Map request type to appropriate AI model
 * This is the core routing logic - change models here without touching iOS
 */
function selectModelForRequestType(requestType: RequestType, hasSonnetQuota: boolean): ModelConfig {
  switch (requestType) {
    case RequestType.SIMPLE:
    case RequestType.SMART_SUGGESTION:
    case RequestType.CLASSIFICATION:
      // Cheap and fast for simple queries
      return MODELS.GROK_4_FAST

    case RequestType.MODERATE:
      // Balanced model for most queries
      return MODELS.CLAUDE_HAIKU_4_5

    case RequestType.COMPLEX:
      // Use Sonnet if quota available, fallback to Haiku
      if (hasSonnetQuota) {
        return MODELS.CLAUDE_SONNET_4_5
      } else {
        console.log('⚠️ ModelRouter: Sonnet quota exceeded, falling back to Haiku')
        return MODELS.CLAUDE_HAIKU_4_5
      }

    case RequestType.WORKOUT_GENERATION:
    case RequestType.BATCH_PROCESSING:
      // Gemini is excellent for structured JSON generation
      return MODELS.GEMINI_FLASH_LITE

    default:
      // Safe default
      console.warn(`⚠️ ModelRouter: Unknown request type "${requestType}", defaulting to Haiku`)
      return MODELS.CLAUDE_HAIKU_4_5
  }
}

/**
 * Sonnet Quota Management
 */

interface SonnetQuotaStatus {
  used: number
  limit: number
  remaining: number
  resetAt: number // Unix timestamp
  hasQuota: boolean
}

/**
 * Check if user has Sonnet quota remaining
 */
export async function checkSonnetQuota(
  kv: KVNamespace,
  userId: string
): Promise<SonnetQuotaStatus> {
  const now = Date.now()
  const currentMonth = new Date(now).toISOString().slice(0, 7) // YYYY-MM
  const quotaKey = `${SONNET_QUOTA_CONFIG.quotaKeyPrefix}${userId}:${currentMonth}`

  const value = await kv.get(quotaKey)
  const used = value ? Number.parseInt(value, 10) : 0
  const remaining = Math.max(0, SONNET_QUOTA_CONFIG.maxRequestsPerMonth - used)

  // Calculate reset date (first day of next month)
  const resetDate = new Date(now)
  resetDate.setMonth(resetDate.getMonth() + 1)
  resetDate.setDate(1)
  resetDate.setHours(0, 0, 0, 0)
  const resetAt = Math.floor(resetDate.getTime() / 1000)

  return {
    used,
    limit: SONNET_QUOTA_CONFIG.maxRequestsPerMonth,
    remaining,
    resetAt,
    hasQuota: remaining > 0,
  }
}

/**
 * Increment Sonnet usage counter
 */
export async function incrementSonnetQuota(
  kv: KVNamespace,
  userId: string
): Promise<void> {
  const now = Date.now()
  const currentMonth = new Date(now).toISOString().slice(0, 7) // YYYY-MM
  const quotaKey = `${SONNET_QUOTA_CONFIG.quotaKeyPrefix}${userId}:${currentMonth}`

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

  console.log(`💰 ModelRouter: Sonnet usage for ${userId}: ${newUsed}/${SONNET_QUOTA_CONFIG.maxRequestsPerMonth}`)
}

/**
 * Main model selection function
 * Returns the optimal model for a given request type and user
 */
export async function selectModel(
  requestType: RequestType,
  kv: KVNamespace,
  userId?: string
): Promise<{ model: ModelConfig; sonnetQuotaStatus?: SonnetQuotaStatus }> {
  // Check Sonnet quota if user ID provided
  let sonnetQuotaStatus: SonnetQuotaStatus | undefined
  let hasSonnetQuota = false

  if (userId) {
    sonnetQuotaStatus = await checkSonnetQuota(kv, userId)
    hasSonnetQuota = sonnetQuotaStatus.hasQuota
  }

  // Select appropriate model
  const model = selectModelForRequestType(requestType, hasSonnetQuota)

  console.log(`🎯 ModelRouter: ${requestType} → ${model.displayName} (${model.modelId})`)

  return {
    model,
    sonnetQuotaStatus,
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
  // Increment Sonnet quota if Sonnet was used
  if (modelConfig.requiresQuota && userId) {
    await incrementSonnetQuota(kv, userId)
  }
}

/**
 * Classify prompt complexity using Grok
 * Returns a RequestType enum value
 */
export async function classifyPromptComplexity(
  apiKey: string,
  prompt: string,
  contextDescription: string
): Promise<RequestType> {
  const classificationPrompt = `
Classify this running/fitness user question into ONE of three complexity levels:

**SIMPLE** - Basic queries that need quick factual answers:
- Statistics and metrics (pace, distance, time, calories, heart rate)
- Simple comparisons (was this workout better than last?)
- Motivational questions
- Basic data retrieval and clarifications

**MODERATE** - Questions requiring analysis and personalized advice:
- Training plan creation or adjustment
- Recovery recommendations based on metrics
- Nutrition and hydration advice
- Performance trend analysis over multiple workouts
- Race strategy suggestions
- Technique improvement tips

**COMPLEX** - Critical health/medical questions requiring expert analysis:
- Injury risk assessment or pain analysis
- HRV interpretation and overtraining detection
- Biomechanical issues (asymmetry, ground contact time)
- Performance prediction using ML models
- Medical contraindications or health concerns
- Advanced physiological analysis

Context: ${contextDescription}

User Question: "${prompt}"

Respond with ONLY ONE WORD: SIMPLE, MODERATE, or COMPLEX
`.trim()

  try {
    const response = await fetch('https://openrouter.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'HTTP-Referer': 'https://insightrun.ai',
        'X-Title': 'insightRun.ai',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: MODELS.GROK_4_FAST.modelId,
        messages: [
          {
            role: 'system',
            content: 'You are a query complexity classifier. Respond with ONLY one word: SIMPLE, MODERATE, or COMPLEX.',
          },
          { role: 'user', content: classificationPrompt },
        ],
        max_tokens: 10,
        temperature: 0.3,
        stream: false,
      }),
    })

    if (!response.ok) {
      console.error('❌ Classification failed, defaulting to MODERATE')
      return RequestType.MODERATE
    }

    const data: any = await response.json()
    const result = data.choices?.[0]?.message?.content?.trim().toUpperCase() || 'MODERATE'

    if (result.includes('SIMPLE')) {
      console.log('✅ Classified as SIMPLE')
      return RequestType.SIMPLE
    } else if (result.includes('COMPLEX')) {
      console.log('✅ Classified as COMPLEX')
      return RequestType.COMPLEX
    } else {
      console.log('✅ Classified as MODERATE')
      return RequestType.MODERATE
    }
  } catch (error) {
    console.error('❌ Classification error:', error)
    return RequestType.MODERATE // Safe default
  }
}
