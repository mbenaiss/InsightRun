import { PostHog } from 'posthog-node'

export interface PostHogConfig {
  apiKey: string
  host: string
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
      trace_id: traceId,
      app: 'healthapp',
      environment: 'production',
      prompt_length: properties.input.length,
      error: properties.error,
    },
  })
}
