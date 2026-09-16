import { afterEach, describe, expect, mock, spyOn, test } from 'bun:test'
import { PLAN_FALLBACK_MODEL_ID } from '../src/modelRouter'
import adaptPlan from '../src/routes/adaptTrainingPlan'
import generatePlan from '../src/routes/generateTrainingPlan'

afterEach(() => mock.restore())

const env = {
  OPENROUTER_API_KEY: 'test-key',
  APP_SECRET: 'test-secret',
  POSTHOG_API_KEY: '',
  POSTHOG_HOST: '',
  RATE_LIMITER: { get: async () => null, put: async () => undefined } as unknown as KVNamespace,
}

function requestBody() {
  const now = Date.now()
  return {
    raceType: '10k',
    targetDate: new Date(now + 29 * 86400000).toISOString(),
    startDate: new Date(now + 86400000).toISOString(),
    fitnessLevel: 'intermediate',
    language: 'fr',
    weeksCount: 4,
    trainingDaysPerWeek: 3,
    preferredDays: [2, 4, 6],
    currentWeekNumber: 2,
    remainingWeeksCount: 4,
    completedWeeks: [],
    originalPlanName: 'QA',
    originalPlanGoal: 'QA',
  }
}

function plan(firstWeek = 1) {
  return {
    name: 'QA',
    goal: 'QA',
    weeks: Array.from({ length: 4 }, (_, index) => ({
      weekNumber: firstWeek + index,
      phase: index === 3 ? 'taper' : 'base',
      weeklyVolume: 15,
      workouts: [
        {
          type: index === 3 ? 'tempo' : 'easy_run',
          name: 'QA',
          description: 'QA',
          intensity: 'easy',
          targetDistance: 10000,
          steps: [] as Array<{ type: string; repetitions?: number; description: string }>,
        },
      ],
    })),
    adaptation: {
      assessment: 'QA',
      goalAchievable: true,
      adjustments: 'QA',
      confidenceLevel: 'medium',
    },
  }
}

function modelResponse(output: unknown, finishReason = 'stop') {
  return Response.json({
    choices: [{ message: { content: JSON.stringify(output) }, finish_reason: finishReason }],
  })
}

function send(route: 'generate' | 'adapt', body = requestBody()) {
  return (route === 'generate' ? generatePlan : adaptPlan).request(
    '/',
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    },
    env
  )
}

function fastForwardTimeouts() {
  const realSetTimeout = globalThis.setTimeout
  const now = Date.now()
  let elapsed = 0
  spyOn(Date, 'now').mockImplementation(() => now + elapsed)
  spyOn(globalThis, 'setTimeout').mockImplementation((callback, delay, ...args) =>
    realSetTimeout(() => {
      elapsed += delay ?? 0
      callback(...args)
    }, 0)
  )
  return () => elapsed
}

function waitForAbort(_input: unknown, init?: RequestInit): Promise<Response> {
  return new Promise((_resolve, reject) => {
    init?.signal?.addEventListener('abort', () => reject(new DOMException('Aborted', 'AbortError')))
  })
}

for (const route of ['generate', 'adapt'] as const) {
  describe(`${route} training plan`, () => {
    const firstWeek = route === 'generate' ? 1 : 3

    test('bounds reasoning while preserving all weeks in a successful response', async () => {
      const output = plan(firstWeek)
      const fetchMock = spyOn(globalThis, 'fetch').mockResolvedValue(modelResponse(output))
      const response = await send(route)
      expect(response.status).toBe(200)
      expect((await response.json()).plan.weeks).toEqual(output.weeks)
      const body = JSON.parse(String(fetchMock.mock.calls[0][1]?.body))
      expect(body.reasoning).toEqual({ effort: 'low', exclude: true })
      expect(fetchMock).toHaveBeenCalledTimes(1)
    })

    test('switches to the fallback after one stalled call and returns before iOS expires', async () => {
      const elapsed = fastForwardTimeouts()
      const fetchMock = spyOn(globalThis, 'fetch')
        .mockImplementationOnce(waitForAbort)
        .mockResolvedValueOnce(modelResponse(plan(firstWeek)))
      const response = await send(route)
      expect(response.status).toBe(200)
      expect(fetchMock).toHaveBeenCalledTimes(2)
      expect(elapsed()).toBe(75000)
      const retry = JSON.parse(String(fetchMock.mock.calls[1][1]?.body))
      expect(retry.model).toBe(PLAN_FALLBACK_MODEL_ID)
      expect((await response.json()).metadata.modelUsed).toBe(PLAN_FALLBACK_MODEL_ID)
    })

    test('returns a timeout within the total budget instead of nesting four attempts', async () => {
      const elapsed = fastForwardTimeouts()
      const fetchMock = spyOn(globalThis, 'fetch').mockImplementation(waitForAbort)
      const response = await send(route)
      expect(response.status).toBe(504)
      expect(fetchMock).toHaveBeenCalledTimes(2)
      expect(elapsed()).toBeLessThanOrEqual(150000)
    })

    test('retries truncated JSON once on the fallback model', async () => {
      const fetchMock = spyOn(globalThis, 'fetch')
        .mockResolvedValueOnce(modelResponse(plan(firstWeek), 'length'))
        .mockResolvedValueOnce(modelResponse(plan(firstWeek)))
      const response = await send(route)
      expect(response.status).toBe(200)
      expect(fetchMock).toHaveBeenCalledTimes(2)
      const retry = JSON.parse(String(fetchMock.mock.calls[1][1]?.body))
      expect(retry.model).toBe(PLAN_FALLBACK_MODEL_ID)
      expect(retry.messages[1].content).toContain('cut off')
    })

    test('rejects duplicate week numbers instead of silently losing weeks in iOS', async () => {
      const output = plan(firstWeek)
      output.weeks.forEach((week) => {
        week.weekNumber = firstWeek
      })
      const fetchMock = spyOn(globalThis, 'fetch').mockImplementation(async () =>
        modelResponse(output)
      )
      const response = await send(route)
      expect(response.status).toBe(500)
      expect(fetchMock).toHaveBeenCalledTimes(2)
    })
  })
}

describe('plan schedule validation', () => {
  test.each([
    'targetDate',
    'startDate',
  ] as const)('rejects an invalid %s before calling the model', async (key) => {
    const body = requestBody()
    body[key] = 'not-a-date'
    const fetchMock = spyOn(globalThis, 'fetch')
    const response = await send('generate', body)
    expect(response.status).toBe(400)
    expect(fetchMock).not.toHaveBeenCalled()
  })

  test('rejects a race in three days even when the client claims four weeks', async () => {
    const body = requestBody()
    body.targetDate = new Date(Date.now() + 3 * 86400000).toISOString()
    const fetchMock = spyOn(globalThis, 'fetch')
    expect((await send('generate', body)).status).toBe(400)
    expect(fetchMock).not.toHaveBeenCalled()
  })

  test('computes the number of weeks from the actual dates', async () => {
    const body = requestBody()
    body.weeksCount = 18
    const fetchMock = spyOn(globalThis, 'fetch').mockResolvedValue(modelResponse(plan()))
    const response = await send('generate', body)
    expect(response.status).toBe(200)
    expect((await response.json()).metadata.weeksGenerated).toBe(4)
    expect(fetchMock).toHaveBeenCalledTimes(1)
  })
})

describe('long training plans', () => {
  test('assembles every week in order from bounded concurrent blocks', async () => {
    const body = requestBody()
    body.targetDate = new Date(new Date(body.startDate).getTime() + 126 * 86400000).toISOString()
    body.weeksCount = 18
    let calls = 0
    const fetchMock = spyOn(globalThis, 'fetch').mockImplementation(async (_input, init) => {
      const request = JSON.parse(String(init?.body))
      const firstWeek = calls++ * 4 + 1
      const count = Math.min(4, 19 - firstWeek)
      expect(request.messages[0].content).toContain(
        `ONLY weeks ${firstWeek} through ${firstWeek + count - 1}`
      )
      const output = plan(firstWeek)
      output.weeks = output.weeks.slice(0, count)
      if (firstWeek === 17) output.weeks[1].workouts[0].type = 'tempo'
      await new Promise((resolve) => setTimeout(resolve, 19 - firstWeek))
      return modelResponse(output)
    })
    const response = await send('generate', body)
    expect(response.status).toBe(200)
    expect(fetchMock).toHaveBeenCalledTimes(5)
    const result = await response.json()
    expect(result.plan.weeks.map((week: { weekNumber: number }) => week.weekNumber)).toEqual(
      Array.from({ length: 18 }, (_, index) => index + 1)
    )
    expect(result.plan.weeks[17].workouts[0].type).toBe('tempo')
  })

  test('does not return a partial plan when a block fails both attempts', async () => {
    const body = requestBody()
    body.targetDate = new Date(new Date(body.startDate).getTime() + 35 * 86400000).toISOString()
    let calls = 0
    spyOn(globalThis, 'fetch').mockImplementation(async () => {
      calls++
      return modelResponse(calls === 1 ? plan() : { weeks: [] })
    })
    const response = await send('generate', body)
    expect(response.status).toBe(500)
    expect((await response.json()).plan).toBeUndefined()
  })
})

describe('long plan adaptation', () => {
  test('preserves absolute week numbers and completed history across blocks', async () => {
    const body = requestBody()
    body.remainingWeeksCount = 16
    let calls = 0
    const fetchMock = spyOn(globalThis, 'fetch').mockImplementation(async (_input, init) => {
      const request = JSON.parse(String(init?.body))
      const firstWeek = 3 + calls++ * 4
      expect(request.messages[0].content).toContain(
        `ONLY weeks ${firstWeek} through ${firstWeek + 3}`
      )
      return modelResponse(plan(firstWeek))
    })
    const response = await send('adapt', body)
    expect(response.status).toBe(200)
    expect(fetchMock).toHaveBeenCalledTimes(4)
    const result = await response.json()
    expect(result.plan.weeks.map((week: { weekNumber: number }) => week.weekNumber)).toEqual(
      Array.from({ length: 16 }, (_, index) => index + 3)
    )
    expect(result.plan.adaptation.goalAchievable).toBe(true)
  })

  test.each([
    -1, 0.5, 25,
  ])('rejects invalid remaining week count %s before generation', async (count) => {
    const body = requestBody()
    body.remainingWeeksCount = count
    const fetchMock = spyOn(globalThis, 'fetch')
    expect((await send('adapt', body)).status).toBe(400)
    expect(fetchMock).not.toHaveBeenCalled()
  })
})

test('tells the adaptation fallback which field must be corrected', async () => {
  const invalid = plan(3)
  invalid.weeks[0].workouts[0].steps = [{ type: 'work', repetitions: 0, description: 'QA' }]
  const fetchMock = spyOn(globalThis, 'fetch')
    .mockResolvedValueOnce(modelResponse(invalid))
    .mockResolvedValueOnce(modelResponse(plan(3)))
  const response = await send('adapt')
  expect(response.status).toBe(200)
  const retry = JSON.parse(String(fetchMock.mock.calls[1][1]?.body))
  expect(retry.messages[1].content).toContain(
    'week 3, workout 0, step 0: repetitions must be an integer from 1 to 30 or omitted'
  )
})
