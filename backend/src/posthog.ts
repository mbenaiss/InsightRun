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
 * Capture LLM generation event with PostHog
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
  await posthog.captureImmediate({
    distinctId,
    event: '$ai_generation',
    properties: {
      $ai_model: properties.model,
      $ai_input: [
        { role: 'system', content: properties.systemPrompt },
        { role: 'user', content: properties.input },
      ],
      $ai_output: properties.output,
      $ai_input_tokens: properties.inputTokens,
      $ai_output_tokens: properties.outputTokens,
      $ai_latency: properties.latency,
      $ai_total_cost_usd: properties.cost,
      $ai_trace_id: traceId,
      app: 'healthapp',
      environment: 'production',
      prompt_length: properties.input.length,
      error: properties.error,
      $ip: properties.ip,
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
