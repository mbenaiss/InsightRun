/**
 * Utility functions for token management and text processing
 */

/**
 * Estimate token count for a given text
 * Uses a simple approximation: 1 token ≈ 4 characters
 * This is roughly accurate for English and European languages
 * For more accuracy, consider using tiktoken library
 *
 * @param text - The text to count tokens for
 * @returns Estimated token count
 */
export function estimateTokenCount(text: string): number {
  // Simple approximation: 1 token ≈ 4 characters
  // This is conservative and works well for English/French text
  return Math.ceil(text.length / 4)
}

/**
 * Truncate text to fit within a token limit while preserving structure
 * Attempts to cut at sentence or paragraph boundaries when possible
 *
 * Strategy:
 * 1. If already within limit, return as-is
 * 2. Calculate target character length (maxTokens * 4)
 * 3. Try to truncate at the last sentence boundary
 * 4. If no sentence boundary found, truncate at last word boundary
 * 5. Add ellipsis to indicate truncation
 *
 * @param text - The text to truncate
 * @param maxTokens - Maximum allowed tokens
 * @returns Truncated text
 */
export function truncateToTokenLimit(text: string, maxTokens: number): string {
  const currentTokens = estimateTokenCount(text)

  // Already within limit
  if (currentTokens <= maxTokens) {
    return text
  }

  // Calculate target character length
  const targetLength = maxTokens * 4

  // Try to find the last complete sentence before target
  const truncated = text.slice(0, targetLength)

  // Try sentence boundary first (. ! ?)
  const lastSentence = Math.max(
    truncated.lastIndexOf('. '),
    truncated.lastIndexOf('! '),
    truncated.lastIndexOf('? ')
  )

  if (lastSentence > targetLength * 0.8) {
    // Found a good sentence boundary (at least 80% of target)
    return `${truncated.slice(0, lastSentence + 1).trim()}\n\n[...]`
  }

  // Try paragraph boundary
  const lastParagraph = truncated.lastIndexOf('\n\n')
  if (lastParagraph > targetLength * 0.7) {
    // Found a good paragraph boundary (at least 70% of target)
    return `${truncated.slice(0, lastParagraph).trim()}\n\n[...]`
  }

  // Try line boundary
  const lastLine = truncated.lastIndexOf('\n')
  if (lastLine > targetLength * 0.7) {
    return `${truncated.slice(0, lastLine).trim()}\n\n[...]`
  }

  // Fallback: truncate at word boundary
  const lastSpace = truncated.lastIndexOf(' ')
  if (lastSpace > targetLength * 0.5) {
    return `${truncated.slice(0, lastSpace).trim()}...`
  }

  // Last resort: hard truncate
  return `${truncated.trim()}...`
}

/**
 * Validate token count and log warnings if exceeded
 *
 * @param text - Text to validate
 * @param maxTokens - Maximum allowed tokens
 * @param context - Context for logging (e.g., "Historical summary")
 * @returns Token count
 */
export function validateTokenCount(text: string, maxTokens: number, context: string): number {
  const tokenCount = estimateTokenCount(text)

  if (tokenCount > maxTokens) {
    console.warn(
      `⚠️ ${context} exceeds ${maxTokens} tokens (${tokenCount} tokens, ${text.length} chars)`
    )
  } else {
    console.log(
      `✅ ${context} within limits: ${tokenCount} tokens (${text.length} chars, target: ${maxTokens})`
    )
  }

  return tokenCount
}

export function formatDuration(seconds: number): string {
  const hours = Math.floor(seconds / 3600)
  const minutes = Math.floor((seconds % 3600) / 60)
  if (hours > 0) {
    return `${hours}h ${minutes.toString().padStart(2, '0')}m`
  }
  return `${minutes}m`
}

export function formatDistance(meters: number): string {
  return `${(meters / 1000).toFixed(2)} km`
}

export function formatPace(pace: number): string {
  const minutes = Math.floor(pace)
  const seconds = Math.floor((pace - minutes) * 60)
  return `${minutes}:${seconds.toString().padStart(2, '0')}/km`
}

// Normalize any inbound pace string (e.g. "4:30", "4'30\"", "4.5") to canonical
// M:SS/km so a single notation reaches the model. Returns the input untouched if
// it cannot be parsed.
export function normalizePaceString(raw: string): string {
  const trimmed = raw.trim()
  const colon = trimmed.match(/^(\d+):([0-5]?\d)/)
  if (colon) {
    return `${colon[1]}:${colon[2].padStart(2, '0')}/km`
  }
  const apostrophe = trimmed.match(/^(\d+)'(\d{1,2})/)
  if (apostrophe) {
    return `${apostrophe[1]}:${apostrophe[2].padStart(2, '0')}/km`
  }
  const decimal = trimmed.match(/^(\d+)(?:\.(\d+))?$/)
  if (decimal) {
    return formatPace(parseFloat(trimmed))
  }
  return raw
}

// Readiness score bands — single source of truth shared with the
// /api/daily-readiness endpoint (getStatusFromScore). Score is a linear 0-100
// scale where a neutral baseline day sits near 50.
export const READINESS_BANDS = {
  excellent: 67, // >= 67 → intense training OK
  good: 50, // >= 50 → moderate training
  fair: 33, // >= 33 → easy / recovery
  // below `fair` → rest required
} as const

export function readinessBandLine(): string {
  return `Score: >=${READINESS_BANDS.excellent} = intense training OK | >=${READINESS_BANDS.good} = moderate training | >=${READINESS_BANDS.fair} = easy/recovery | <${READINESS_BANDS.fair} = rest required`
}

// Maximum heart rate estimated from age (Fox formula). Returns null when age is
// unknown so callers never present a fabricated zone as fact.
export function estimateMaxHR(age?: number): number | null {
  if (!age || age <= 0) return null
  return 220 - age
}

// Five heart-rate training zones expressed as % of estimated max HR. Defined
// once so every prompt references the same reference table.
export const HR_ZONES_TABLE = [
  'Zone 1 (Recovery): 50-60% of max HR',
  'Zone 2 (Aerobic/Endurance): 60-70% of max HR',
  'Zone 3 (Tempo): 70-80% of max HR',
  'Zone 4 (Threshold): 80-90% of max HR',
  'Zone 5 (VO2max): 90-100% of max HR',
] as const

export function hrZonesReference(): string {
  return HR_ZONES_TABLE.map((z) => `- ${z}`).join('\n')
}

// Wrap untrusted, user-supplied free text so the model treats it strictly as
// data and never as instructions (prompt-injection guard). Works inline or as a
// block; a global instruction near the top of each prompt explains the tag.
export function wrapUserData(content: string): string {
  return `<user_data>${content}</user_data>`
}

export function cleanJSONResponse(text: string): string {
  let cleaned = text.trim()
  cleaned = cleaned.replace(/^```json\s*/i, '')
  cleaned = cleaned.replace(/^```\s*/, '')
  cleaned = cleaned.replace(/\s*```$/, '')
  return cleaned.trim()
}

export function getRaceDistance(raceType: string): string {
  const distances: Record<string, string> = {
    '5k': '5 km',
    '10k': '10 km',
    half_marathon: '21.1 km (Half Marathon)',
    marathon: '42.195 km (Marathon)',
    ultra: '50+ km (Ultra Marathon)',
  }
  return distances[raceType] || raceType
}

const LANGUAGE_NAMES: Record<string, string> = {
  fr: 'French',
  en: 'English',
  es: 'Spanish',
  de: 'German',
  it: 'Italian',
  pt: 'Portuguese',
  nl: 'Dutch',
  ja: 'Japanese',
  zh: 'Chinese',
  ko: 'Korean',
  ar: 'Arabic',
}

export function getLanguageName(langCode: string): string {
  const base = langCode.toLowerCase().split('-')[0]
  return LANGUAGE_NAMES[base] || 'English'
}
