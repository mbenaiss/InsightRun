// Shared OpenRouter client: a single network call with one retry on transient
// upstream failures (429/5xx) and a per-call timeout. The application-level
// re-prompt loop (re-injecting parse/validation feedback) stays in each route —
// this only encapsulates the network fetch + retry + timeout.

const OPENROUTER_API_URL = 'https://openrouter.ai/api/v1/chat/completions'

// Thrown when the model stopped because it hit max_tokens — the JSON is truncated and
// retrying identically just burns budget. The caller surfaces this to the next attempt.
export class TruncatedResponseError extends Error {
  constructor() {
    super('Model response was truncated (finish_reason=length): output exceeds token budget')
    this.name = 'TruncatedResponseError'
  }
}

interface CallOpenRouterOptions {
  apiKey: string
  model: string
  // Native OpenRouter fallback: if `model` 429s/5xx, retry transparently on the next entry.
  fallbackModel: string
  // Per-message payload (system/user) plus any extra request fields (max_tokens,
  // temperature, response_format, …). `model`/`models` are set by this helper.
  body: Omit<Record<string, unknown>, 'model' | 'models'> & {
    messages: Array<{ role: string; content: string }>
  }
  timeoutMs: number
  // OpenRouter "X-Title" attribution header (varies per route).
  title: string
  // When true, throw TruncatedResponseError on finish_reason === 'length'. Routes
  // that don't parse strict JSON (e.g. free-text suggestions) leave this off.
  throwOnTruncation?: boolean
}

export async function callOpenRouterWithRetry(
  opts: CallOpenRouterOptions
): Promise<{ content: string; finishReason: string }> {
  const requestBody = {
    ...opts.body,
    model: opts.model,
    models: [opts.model, opts.fallbackModel],
  }

  let lastError: unknown
  for (let networkAttempt = 0; networkAttempt < 2; networkAttempt++) {
    const controller = new AbortController()
    const timer = setTimeout(() => controller.abort(), opts.timeoutMs)

    try {
      const response = await fetch(OPENROUTER_API_URL, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${opts.apiKey}`,
          'HTTP-Referer': 'https://insightrun.ai',
          'X-Title': opts.title,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(requestBody),
        signal: controller.signal,
      })

      if (!response.ok) {
        const errorText = await response.text()
        if (response.status === 429 || response.status >= 500) {
          lastError = new Error(`OpenRouter API error: ${response.status} - ${errorText}`)
          continue
        }
        throw new Error(`OpenRouter API error: ${response.status} - ${errorText}`)
      }

      const data = (await response.json()) as {
        choices: Array<{ message: { content: string }; finish_reason?: string }>
      }

      const finishReason = data.choices[0]?.finish_reason || ''
      if (opts.throwOnTruncation && finishReason === 'length') {
        throw new TruncatedResponseError()
      }

      return { content: data.choices[0]?.message?.content || '', finishReason }
    } catch (error) {
      if (error instanceof TruncatedResponseError) throw error
      lastError = error
    } finally {
      clearTimeout(timer)
    }
  }

  throw lastError instanceof Error ? lastError : new Error('OpenRouter request failed')
}
