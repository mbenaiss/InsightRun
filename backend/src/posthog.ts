import type { Context } from 'hono'
import { PostHog } from 'posthog-node'
import type { ZodError } from 'zod'

export interface PostHogConfig {
  apiKey: string
  host: string
}

type PostHogEnv = {
  POSTHOG_API_KEY: string
  POSTHOG_HOST: string
}

/**
 * Create PostHog client for Cloudflare Workers
 * Configured with flushAt: 1 and flushInterval: 0 for immediate flushing
 */
export function createPostHogClient(config: PostHogConfig): PostHog {
  return new PostHog(config.apiKey, {
    host: config.host,
    flushAt: 1, // Send events immediately in edge environment
    flushInterval: 0, // Don't wait for interval
  })
}

/**
 * Short, non-reversible fingerprint of a payload, used so we can correlate /
 * dedupe prompts in analytics without exporting their content.
 */
async function fingerprint(value: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value))
  const bytes = new Uint8Array(digest).slice(0, 8)
  return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('')
}

/**
 * Capture LLM generation event with PostHog.
 *
 * Privacy: the system prompt and user input embed sensitive health data (age,
 * weight, HRV, sleep, resting HR…). We never export their raw text — only
 * length + a salted-free hash for correlation. The model output is reduced to
 * its length for the same reason.
 */
export async function captureLLMEvent(
  posthog: PostHog,
  distinctId: string,
  traceId: string,
  properties: {
    model: string
    input: string
    systemPrompt: string
    output?: string
    inputTokens?: number
    outputTokens?: number
    latency?: number
    cost?: number
    error?: string
    ip?: string
  }
): Promise<void> {
  const [inputHash, systemPromptHash] = await Promise.all([
    fingerprint(properties.input),
    fingerprint(properties.systemPrompt),
  ])

  await posthog.captureImmediate({
    distinctId,
    event: '$ai_generation',
    properties: {
      $ai_model: properties.model,
      $ai_input_tokens: properties.inputTokens,
      $ai_output_tokens: properties.outputTokens,
      $ai_latency: properties.latency,
      $ai_total_cost_usd: properties.cost,
      $ai_trace_id: traceId,
      app: 'healthapp',
      environment: 'production',
      input_length: properties.input.length,
      input_hash: inputHash,
      system_prompt_length: properties.systemPrompt.length,
      system_prompt_hash: systemPromptHash,
      output_length: properties.output?.length,
      error: properties.error,
    },
  })
}

/**
 * Capture a Zod validation rejection (HTTP 400) so we can see *which* field
 * blocked the request without waiting for users to report opaque errors.
 * Safe to call unconditionally — no-ops if PostHog env vars are missing.
 */
export function captureZodRejection<B extends PostHogEnv, V extends object>(
  c: Context<{ Bindings: B; Variables: V }>,
  params: {
    event: string
    route: string
    error: ZodError
    extra?: Record<string, unknown>
  }
): void {
  if (!c.env.POSTHOG_API_KEY || !c.env.POSTHOG_HOST) return

  const userId = c.req.header('X-User-ID') || c.req.header('CF-Connecting-IP') || 'unknown'
  const posthog = createPostHogClient({
    apiKey: c.env.POSTHOG_API_KEY,
    host: c.env.POSTHOG_HOST,
  })

  const issues = params.error.issues
  const details = issues.slice(0, 10).map((err) => `${err.path.join('.')}: ${err.message}`)

  c.executionCtx.waitUntil(
    (async () => {
      try {
        await posthog.captureImmediate({
          distinctId: userId,
          event: params.event,
          properties: {
            route: params.route,
            issue_count: issues.length,
            first_path: issues[0]?.path.join('.') ?? null,
            first_code: issues[0]?.code ?? null,
            first_message: issues[0]?.message ?? null,
            details,
            app: 'healthapp',
            environment: 'production',
            ...params.extra,
          },
        })
        await posthog.shutdown()
      } catch (error) {
        console.error('PostHog capture error:', error)
      }
    })()
  )
}
