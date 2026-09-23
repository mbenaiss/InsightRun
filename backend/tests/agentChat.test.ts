import { afterEach, describe, expect, mock, spyOn, test } from 'bun:test'
import { RequestType, selectModel } from '../src/modelRouter'
import app from '../src/routes/agentChat'

afterEach(() => mock.restore())

async function chat(upstream: string | ((models: string[]) => string), data = {}) {
  const put = mock(async () => {})
  const fetchMock = spyOn(globalThis, 'fetch').mockImplementationOnce(
    async (_input, init) =>
      new Response(
        typeof upstream === 'string' ? upstream : upstream(JSON.parse(String(init?.body)).models)
      )
  )
  const response = await app.request(
    '/chat',
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-User-ID': 'test-user' },
      body: JSON.stringify({ userQuestion: 'Hello', language: 'en', data }),
    },
    {
      OPENROUTER_API_KEY: 'test-key',
      APP_SECRET: 'test-secret',
      POSTHOG_API_KEY: '',
      POSTHOG_HOST: '',
      RATE_LIMITER: { get: async () => null, put } as unknown as KVNamespace,
    },
    { waitUntil: () => {}, passThroughOnException: () => {} }
  )
  return { output: await response.text(), put, fetchMock }
}

describe('workout analysis context', () => {
  test('passes treadmill effort to the model without fabricated intensity or ideal ranges', async () => {
    const { output, fetchMock } = await chat(
      'data: {"choices":[{"delta":{"content":"Completed analysis."}}]}\n\ndata: [DONE]\n\n',
      {
        profile: { age: 39 },
        workout: {
          date: '2026-09-22',
          duration: 1360,
          distance: 3030,
          pace: 7.5,
          heartRate: { avg: 140, max: 152 },
          cadence: 163,
          effort: 4,
          effortSource: 'apple_estimated',
          isIndoor: true,
          temperatureCelsius: 11.8,
          splits: ['7:35', '7:23', '7:27'].map((pace, index) => ({
            kilometer: index + 1,
            distanceMeters: 1000,
            pace,
            time: pace,
          })),
        },
      }
    )
    expect(output).toContain('[DONE]')
    const prompt = JSON.parse(String(fetchMock.mock.calls[0][1]?.body)).messages[0].content
    expect(prompt).toContain('140 bpm')
    expect(prompt).toContain('**Duration:** 22m 40s')
    expect(prompt).toContain('Cadence: 163 spm')
    expect(prompt).toContain('"effort":4')
    expect(prompt).toContain('"effortSource":"apple_estimated"')
    expect(prompt).toContain('"isIndoor":true')
    expect(prompt).toContain('1.1% (descriptive variability')
    expect(prompt).toContain('Age-based maximum heart rate estimate: 181 bpm')
    expect(prompt).toContain('Do not override that effort from an age formula')
    expect(prompt).toContain('attached outdoor weather does not measure the room')
    expect(prompt).toContain('one continuous paragraph of plain text')
    expect(prompt).toContain('no headings, lists, separate sections or line breaks')
    expect(prompt).toContain('one concrete recommendation and why it follows')
    expect(prompt).not.toContain('organize the answer as observed facts')
    expect(prompt).not.toContain('Estimated Intensity:')
    expect(prompt).not.toContain('77%')
    expect(prompt).not.toContain('160-170')
    expect(prompt).not.toContain('Excellent (<3%)')
  })
})

describe('agent streaming failures', () => {
  test('does not charge quota for an empty completed answer', async () => {
    const { output, put } = await chat('data: [DONE]\n\n')
    expect(output).toContain('"type":"error"')
    expect(output).not.toContain('[DONE]')
    expect(put).not.toHaveBeenCalled()
  })

  test('surfaces an upstream error instead of a successful completion', async () => {
    const { output, put } = await chat(
      'data: {"error":{"message":"Provider failed"}}\n\ndata: [DONE]\n\n'
    )
    expect(output).toContain('"type":"error"')
    expect(output).not.toContain('[DONE]')
    expect(put).not.toHaveBeenCalled()
  })

  test('rejects a connection closed without the completion marker', async () => {
    const { output, put } = await chat('data: {"choices":[{"delta":{"content":"Partial"}}]}\n\n')
    expect(output).toContain('"type":"error"')
    expect(put).not.toHaveBeenCalled()
  })

  test('forwards a completed answer', async () => {
    const { output } = await chat(
      'data: {"choices":[{"delta":{"content":"Hello."}}]}\n\ndata: [DONE]\n\n'
    )
    expect(output).toContain('"content":"Hello."')
    expect(output).toContain('[DONE]')
    expect(output).not.toContain('"type":"error"')
  })
})

describe('agent premium quota', () => {
  test.each([
    ['the premium model', ([premium]: string[]) => premium, 1],
    ['a dated premium slug', ([premium]: string[]) => `${premium}-20251117`, 1],
    ['the fallback model', ([, fallback]: string[]) => fallback, 0],
    ['an unidentified model', () => undefined, 1],
  ])('is charged only when %s answered', async (_case, answeredBy, charges) => {
    const premium = await selectModel(
      RequestType.COMPLEX,
      { get: async () => null } as unknown as KVNamespace,
      'test-user',
      'chat'
    )
    expect(premium.model.requiresQuota).toBe(true)

    const { output, put, fetchMock } = await chat((models) => {
      const chunk = { model: answeredBy(models), choices: [{ delta: { content: 'Hello.' } }] }
      return `data: ${JSON.stringify(chunk)}\n\ndata: [DONE]\n\n`
    })

    const { models } = JSON.parse(String(fetchMock.mock.calls[0][1]?.body))
    expect(models[0]).toBe(premium.model.modelId)
    expect(models[1]).not.toBe(models[0])
    expect(output).toContain('[DONE]')
    expect(put).toHaveBeenCalledTimes(charges)
  })
})
