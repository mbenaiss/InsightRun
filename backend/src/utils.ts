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
  return `${minutes}'${seconds.toString().padStart(2, '0')}"/km`
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
  return LANGUAGE_NAMES[langCode.toLowerCase()] || 'English'
}
