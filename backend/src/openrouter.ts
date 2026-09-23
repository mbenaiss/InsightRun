// Shared OpenRouter client: a single network call with one retry on transient
// upstream failures (408/429/5xx, network, timeout) and a per-call timeout. The
// application-level re-prompt loop (re-injecting parse/validation feedback) stays in
// each route — this only encapsulates the network fetch + retry + timeout.

const OPENROUTER_API_URL = 'https://openrouter.ai/api/v1/chat/completions'

// Thrown when the model stopped because it hit max_tokens — the JSON is truncated and
// retrying identically just burns budget. The caller surfaces this to the next attempt.
export class TruncatedResponseError extends Error {
  constructor() {
    super('Model response was truncated (finish_reason=length): output exceeds token budget')
    this.name = 'TruncatedResponseError'
  }
}

export class OpenRouterTimeoutError extends Error {
  constructor() {
    super('OpenRouter request timed out')
    this.name = 'OpenRouterTimeoutError'
  }
}

export class OpenRouterEmptyResponseError extends Error {
  constructor() {
    super('OpenRouter returned a response without choices')
    this.name = 'OpenRouterEmptyResponseError'
  }
}

export class OpenRouterHttpError extends Error {
  constructor(
    readonly status: number,
    body: string
  ) {
    super(`OpenRouter API error: ${status} - ${body}`)
    this.name = 'OpenRouterHttpError'
  }
}

const isRetryableStatus = (status: number) => status === 408 || status === 429 || status >= 500

export interface OpenRouterUsage {
  prompt_tokens?: number
  completion_tokens?: number
  cost?: number
}

export function addUsage(
  total: OpenRouterUsage | undefined,
  usage: OpenRouterUsage | undefined
): OpenRouterUsage | undefined {
  if (!total || !usage) return total ?? usage
  const sum = (a?: number, b?: number) =>
    a === undefined && b === undefined ? undefined : (a ?? 0) + (b ?? 0)
  return {
    prompt_tokens: sum(total.prompt_tokens, usage.prompt_tokens),
    completion_tokens: sum(total.completion_tokens, usage.completion_tokens),
    cost: sum(total.cost, usage.cost),
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
  networkAttempts?: 1 | 2
  // OpenRouter "X-Title" attribution header (varies per route).
  title: string
  // When true, throw TruncatedResponseError on finish_reason === 'length'. Routes
  // that don't parse strict JSON (e.g. free-text suggestions) leave this off.
  throwOnTruncation?: boolean
}

export async function callOpenRouterWithRetry(opts: CallOpenRouterOptions): Promise<{
  content: string
  finishReason: string
  usage?: OpenRouterUsage
  model?: string
}> {
  const requestBody = {
    ...opts.body,
    model: opts.model,
    models: [opts.model, opts.fallbackModel],
  }

  let lastError: unknown
  for (let networkAttempt = 0; networkAttempt < (opts.networkAttempts ?? 2); networkAttempt++) {
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
        const error = new OpenRouterHttpError(response.status, await response.text())
        if (!isRetryableStatus(response.status)) throw error
        lastError = error
        continue
      }

      const data = (await response.json().catch(() => null)) as {
        model?: string
        choices?: Array<{ message?: { content?: string }; finish_reason?: string }>
        usage?: OpenRouterUsage
      } | null

      // A 200 can still carry an upstream error body instead of a completion.
      const choice = data?.choices?.[0]
      if (!choice) {
        lastError = controller.signal.aborted
          ? new OpenRouterTimeoutError()
          : new OpenRouterEmptyResponseError()
        continue
      }

      const finishReason = choice.finish_reason || ''
      if (opts.throwOnTruncation && finishReason === 'length') {
        throw new TruncatedResponseError()
      }

      return {
        content: choice.message?.content || '',
        finishReason,
        usage: data?.usage,
        model: data?.model,
      }
    } catch (error) {
      if (error instanceof TruncatedResponseError || error instanceof OpenRouterHttpError)
        throw error
      lastError = controller.signal.aborted ? new OpenRouterTimeoutError() : error
    } finally {
      clearTimeout(timer)
    }
  }

  throw lastError instanceof Error ? lastError : new Error('OpenRouter request failed')
}
