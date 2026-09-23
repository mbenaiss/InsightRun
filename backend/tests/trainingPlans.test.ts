import { afterEach, describe, expect, mock, spyOn, test } from 'bun:test'
import { PLAN_FALLBACK_MODEL_ID } from '../src/modelRouter'
import adaptPlan from '../src/routes/adaptTrainingPlan'
import generatePlan, { buildPlanSkeleton, taperWeekCount } from '../src/routes/generateTrainingPlan'

afterEach(() => mock.restore())

const env = {
  OPENROUTER_API_KEY: 'test-key',
  APP_SECRET: 'test-secret',
  POSTHOG_API_KEY: '',
  POSTHOG_HOST: '',
  RATE_LIMITER: {
    get: async () => null,
    put: async () => undefined,
    delete: async () => undefined,
  } as unknown as KVNamespace,
}

function memoryKV() {
  const store = new Map<string, string>()
  const kv = {
    get: async (key: string) => store.get(key) ?? null,
    put: async (key: string, value: string) => {
      store.set(key, value)
    },
    delete: async (key: string) => {
      store.delete(key)
    },
  } as unknown as KVNamespace
  const blockKeys = () => [...store.keys()].filter((key) => key.startsWith('plan-block:'))
  return { kv, blockKeys }
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
      phase: ['base', 'build', 'peak', 'taper'][index],
      weeklyVolume: 15 as number | undefined,
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

function send(
  route: 'generate' | 'adapt',
  body: Record<string, unknown> = requestBody(),
  options: { headers?: Record<string, string>; kv?: KVNamespace } = {}
) {
  return (route === 'generate' ? generatePlan : adaptPlan).request(
    '/',
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', ...options.headers },
      body: JSON.stringify(body),
    },
    { ...env, RATE_LIMITER: options.kv ?? env.RATE_LIMITER }
  )
}

function promptWeeks(init?: RequestInit): { system: string; from: number; through: number } {
  const system: string = JSON.parse(String(init?.body)).messages[0].content
  const [, from, through] = system.match(/ONLY weeks (\d+) through (\d+)/) ?? []
  return { system, from: Number(from), through: Number(through) }
}

function blockOutput(from: number, through: number, raceWeek?: number, raceType = 'tempo') {
  const output = plan(from)
  output.weeks = output.weeks.slice(0, through - from + 1)
  if (through === raceWeek) output.weeks[output.weeks.length - 1].workouts[0].type = raceType
  return output
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

describe('objective form validation and calendar boundaries', () => {
  test.each([
    { trainingDaysPerWeek: 0 },
    { trainingDaysPerWeek: 8 },
    { trainingDaysPerWeek: 2.5 },
    { preferredDays: [] },
    { preferredDays: [2, 2, 4] },
    { preferredDays: [0, 2, 4] },
    { trainingDaysPerWeek: 4, preferredDays: [2, 4, 6] },
    { fitnessLevel: 'unknown' },
    { targetTimeSeconds: -1 },
    { targetDate: '2027-02-30', startDate: '2027-01-01' },
  ])('rejects an invalid profile before spending quota: %j', async (invalid) => {
    const fetchMock = spyOn(globalThis, 'fetch')
    expect((await send('generate', { ...requestBody(), ...invalid })).status).toBe(400)
    expect(fetchMock).not.toHaveBeenCalled()
  })

  test.each([
    ['2027-03-01', '2027-03-28', 4],
    ['2027-03-01', '2027-03-29', 5],
    ['2027-10-01', '2027-10-29', 5],
    ['2027-01-01', '2027-06-17', 24],
    ['2027-01-01', '2027-12-31', 24],
  ])('includes race day in calendar %s → %s: %s weeks', async (start, target, weeks) => {
    const fetchMock = spyOn(globalThis, 'fetch').mockImplementation(async (_input, init) => {
      const request = JSON.parse(String(init?.body))
      const [, from, through] = request.messages[0].content.match(/ONLY weeks (\d+) through (\d+)/)
      const output = plan(Number(from))
      output.weeks = output.weeks.slice(0, Number(through) - Number(from) + 1)
      output.weeks[output.weeks.length - 1].workouts[0].type = 'tempo'
      return modelResponse(output)
    })
    const response = await send('generate', {
      ...requestBody(),
      startDate: String(start),
      targetDate: String(target),
    })
    expect(response.status).toBe(200)
    expect((await response.json()).metadata.weeksGenerated).toBe(weeks)
    expect(fetchMock).toHaveBeenCalledTimes(Math.ceil(Number(weeks) / 4))
  })

  for (const race of ['5k', '10k', 'half_marathon', 'marathon', 'ultra']) {
    for (const level of ['beginner', 'intermediate', 'advanced']) {
      test(`forwards ${race}/${level} profile and constraint`, async () => {
        const output = plan()
        output.weeks[3].workouts[0].type = ['5k', '10k'].includes(race) ? 'tempo' : 'long_run'
        const fetchMock = spyOn(globalThis, 'fetch').mockResolvedValue(modelResponse(output))
        const response = await send('generate', {
          ...requestBody(),
          raceType: race,
          fitnessLevel: level,
          ...{ targetTimeSeconds: 5400, injury: 'QA knee constraint' },
        })
        expect(response.status).toBe(200)
        const request = JSON.parse(String(fetchMock.mock.calls[0][1]?.body))
        const prompt = JSON.stringify(request.messages)
        expect(prompt).toContain(level)
        expect(prompt).toContain('1h30')
        expect(prompt).toContain('QA knee constraint')
        expect(prompt).toContain('Monday, Wednesday, Friday')
      })
    }
  }
})

describe('plan skeleton', () => {
  const races = ['5k', '10k', 'half_marathon', 'marathon', 'ultra'] as const
  const levels = ['beginner', 'intermediate', 'advanced'] as const
  const phaseOrder = ['base', 'build', 'peak', 'taper']
  const taperByDistance = { '5k': 1, '10k': 1, half_marathon: 2, marathon: 3, ultra: 3 }
  const raceKm = { '5k': 5, '10k': 10, half_marathon: 21.1, marathon: 42.2, ultra: 50 }

  test('orders phases, tapers by distance and never ramps more than 10% a week', () => {
    for (const race of races) {
      for (const level of levels) {
        for (let weeks = 4; weeks <= 24; weeks++) {
          for (const days of [1, 3, 5, 7]) {
            for (const reference of [undefined, 3, 30, 200]) {
              const skeleton = buildPlanSkeleton(race, level, weeks, days, reference)
              const taper = Math.min(taperByDistance[race], Math.max(1, Math.floor(weeks / 4)))
              expect(skeleton.map((week) => week.weekNumber)).toEqual(
                Array.from({ length: weeks }, (_, index) => index + 1)
              )
              const ranks = skeleton.map((week) => phaseOrder.indexOf(week.phase))
              expect(ranks).toEqual([...ranks].sort((a, b) => a - b))
              expect(skeleton.filter((week) => week.phase === 'taper')).toHaveLength(taper)
              expect(taperWeekCount(race, weeks)).toBe(taper)
              expect(skeleton.some((week) => week.phase === 'peak')).toBe(true)
              expect(skeleton.every((week) => week.volumeKm > 0)).toBe(true)
              expect(skeleton[weeks - 1].volumeKm).toBeGreaterThan(raceKm[race])
              const loading = skeleton.filter((week) => week.phase !== 'taper' && !week.cutback)
              for (let index = 1; index < loading.length; index++) {
                expect(loading[index].volumeKm).toBeLessThanOrEqual(
                  loading[index - 1].volumeKm * 1.1 + 1
                )
              }
            }
          }
        }
      }
    }
  })

  test('periodizes a marathon with cutbacks and a three-week taper', () => {
    const skeleton = buildPlanSkeleton('marathon', 'intermediate', 18, 4)
    expect(skeleton.map((week) => week.phase)).toEqual([
      ...Array(4).fill('base'),
      ...Array(7).fill('build'),
      ...Array(4).fill('peak'),
      ...Array(3).fill('taper'),
    ])
    expect(skeleton.filter((week) => week.cutback).map((week) => week.weekNumber)).toEqual([4, 8])
    const peak = Math.max(...skeleton.slice(0, 15).map((week) => week.volumeKm))
    expect(peak).toBe(56)
    expect(skeleton[15].volumeKm).toBeLessThan(peak)
    expect(skeleton[16].volumeKm).toBeLessThan(skeleton[15].volumeKm)
  })

  test('starts from the reference volume, capped by the training days', () => {
    expect(buildPlanSkeleton('half_marathon', 'advanced', 12, 5, 45)[0].volumeKm).toBe(45)
    const capped = buildPlanSkeleton('10k', 'intermediate', 8, 4, 80)
    expect(Math.max(...capped.map((week) => week.volumeKm))).toBe(56)
  })
})

describe('skeleton-driven generation prompts', () => {
  const marathon = {
    ...requestBody(),
    raceType: 'marathon',
    startDate: '2027-01-04',
    targetDate: '2027-05-09',
  }

  test('gives each block its skeleton slice, the race date and explicit taper weeks', async () => {
    const prompts = new Map<number, string>()
    spyOn(globalThis, 'fetch').mockImplementation(async (_input, init) => {
      const { system, from, through } = promptWeeks(init)
      prompts.set(from, system)
      return modelResponse(blockOutput(from, through, 18, 'long_run'))
    })
    const response = await send('generate', marathon)
    expect(response.status).toBe(200)
    expect([...prompts.keys()].sort((a, b) => a - b)).toEqual([1, 5, 9, 13, 17])
    for (const prompt of prompts.values()) {
      expect(prompt).toContain('race on 2027-05-09')
      expect(prompt).toContain(
        'weeks 1-4 base, weeks 5-11 build, weeks 12-15 peak, weeks 16-18 taper'
      )
      expect(prompt).not.toContain('taper prematurely')
      expect(prompt).not.toContain('Include a taper phase')
      expect(prompt).not.toContain('PHASE ALLOCATION')
    }
    expect(prompts.get(1)).toContain(
      'none of these weeks is a taper week (the taper covers weeks 16, 17, 18)'
    )
    expect(prompts.get(1)).toMatch(/- Week 4: phase "base", weeklyVolume ≈ \d+ km \(cutback week/)
    expect(prompts.get(1)).not.toContain('- Week 5:')
    expect(prompts.get(13)).toContain('week 16 of this block is a taper week')
    expect(prompts.get(17)).toContain('weeks 17, 18 of this block are taper weeks')
    expect(prompts.get(17)).toContain('RACE WEEK')
    const phases = (await response.json()).plan.weeks.map((week: { phase: string }) => week.phase)
    expect(phases).toEqual(buildPlanSkeleton('marathon', 'intermediate', 18, 3).map((w) => w.phase))
  })

  test('forwards the running history reference and ignores implausible values', async () => {
    const fetchMock = spyOn(globalThis, 'fetch').mockImplementation(async () =>
      modelResponse(plan())
    )
    const response = await send('generate', {
      ...requestBody(),
      currentWeeklyVolumeKm: 32,
      avgPace: 5.75,
    })
    expect(response.status).toBe(200)
    const prompt = promptWeeks(fetchMock.mock.calls[0][1]).system
    expect(prompt).toContain('Current weekly running volume (recent average): 32.0 km')
    expect(prompt).toContain('Typical easy pace (recent runs): 5:45/km')
    expect(prompt).toContain('- Week 1: phase "base", weeklyVolume ≈ 32 km')

    const implausible = await send('generate', {
      ...requestBody(),
      currentWeeklyVolumeKm: -4,
      avgPace: 40,
    })
    expect(implausible.status).toBe(200)
    const ignored = promptWeeks(fetchMock.mock.calls[1][1]).system
    expect(ignored).not.toContain('Current weekly running volume')
    expect(ignored).not.toContain('Typical easy pace')
  })

  test('labels weeks with the skeleton phases and fills a missing weekly volume', async () => {
    const output = plan()
    output.weeks.forEach((week) => {
      week.phase = 'recovery'
    })
    output.weeks[1].weeklyVolume = undefined
    spyOn(globalThis, 'fetch').mockResolvedValue(modelResponse(output))
    const response = await send('generate')
    expect(response.status).toBe(200)
    const skeleton = buildPlanSkeleton('10k', 'intermediate', 4, 3)
    const weeks = (await response.json()).plan.weeks
    expect(weeks.map((week: { phase: string }) => week.phase)).toEqual(skeleton.map((w) => w.phase))
    expect(weeks[1].weeklyVolume).toBe(skeleton[1].volumeKm)
    expect(weeks[0].weeklyVolume).toBe(15)
  })
})

describe('plan block cache and concurrency', () => {
  const longPlan = { ...requestBody(), startDate: '2027-01-01', targetDate: '2027-06-17' }

  function respond(calls: number[], failing: Set<number>, delayMs = (_from: number) => 0) {
    return async (_input: unknown, init?: RequestInit) => {
      const { from, through } = promptWeeks(init)
      calls.push(from)
      await new Promise((resolve) => setTimeout(resolve, delayMs(from)))
      return modelResponse(failing.has(from) ? { weeks: [] } : blockOutput(from, through))
    }
  }

  test.each([
    ['an Idempotency-Key', { 'X-User-ID': 'qa-user', 'Idempotency-Key': 'generate-plan:10k:QA' }],
    ['a request hash', { 'X-User-ID': 'qa-user' }],
  ])('retries only the failed blocks through %s, then clears the cache', async (_, headers) => {
    const { kv, blockKeys } = memoryKV()
    const calls: number[] = []
    const failing = new Set([1])
    spyOn(globalThis, 'fetch').mockImplementation(
      respond(calls, failing, (from) => (from === 1 ? 0 : 20))
    )
    const failed = await send('generate', longPlan, { headers, kv })
    expect(failed.status).toBe(500)
    expect((await failed.json()).plan).toBeUndefined()
    expect(calls.sort((a, b) => a - b)).toEqual([1, 1, 5, 9, 13])
    expect(blockKeys()).toHaveLength(3)

    failing.clear()
    calls.length = 0
    const retried = await send('generate', longPlan, { headers, kv })
    expect(retried.status).toBe(200)
    expect(calls.sort((a, b) => a - b)).toEqual([1, 17, 21])
    const result = await retried.json()
    expect(result.plan.weeks.map((week: { weekNumber: number }) => week.weekNumber)).toEqual(
      Array.from({ length: 24 }, (_, index) => index + 1)
    )
    expect(blockKeys()).toEqual([])
  })

  test('never reuses blocks for another user or a changed request', async () => {
    const { kv, blockKeys } = memoryKV()
    const calls: number[] = []
    const failing = new Set([1])
    spyOn(globalThis, 'fetch').mockImplementation(
      respond(calls, failing, (from) => (from === 1 ? 0 : 20))
    )
    const headers = { 'X-User-ID': 'qa-user', 'Idempotency-Key': 'generate-plan:10k:QA' }
    expect((await send('generate', longPlan, { headers, kv })).status).toBe(500)
    expect(blockKeys()).toHaveLength(3)
    failing.clear()
    for (const [body, userID] of [
      [longPlan, 'qa-other-user'],
      [{ ...longPlan, injury: 'QA ankle' }, 'qa-user'],
      [{ ...longPlan, startDate: '2027-01-02' }, 'qa-user'],
    ] as const) {
      calls.length = 0
      const response = await send('generate', body, {
        headers: { ...headers, 'X-User-ID': userID },
        kv,
      })
      expect(response.status).toBe(200)
      expect(calls).toHaveLength(Math.ceil((await response.json()).plan.weeks.length / 4))
    }
    expect(blockKeys()).toHaveLength(3)
  })

  test('runs at most four model calls at once', async () => {
    let active = 0
    let peak = 0
    const fetchMock = spyOn(globalThis, 'fetch').mockImplementation(async (_input, init) => {
      active++
      peak = Math.max(peak, active)
      await new Promise((resolve) => setTimeout(resolve, 5))
      active--
      const { from, through } = promptWeeks(init)
      return modelResponse(blockOutput(from, through))
    })
    const response = await send('generate', longPlan)
    expect(response.status).toBe(200)
    expect(fetchMock).toHaveBeenCalledTimes(6)
    expect(peak).toBe(4)
  })
})

describe('adaptation taper', () => {
  const adaptation = {
    ...requestBody(),
    raceType: 'marathon',
    currentWeekNumber: 1,
    remainingWeeksCount: 17,
  }

  test.each([
    [
      'the original plan',
      Array.from({ length: 17 }, (_, index) => ({
        weekNumber: index + 2,
        phase: index + 2 >= 16 ? 'taper' : 'build',
        workouts: [],
      })),
    ],
    ['the generation skeleton', undefined],
  ])('tells each block which of its weeks keep the taper from %s', async (_, original) => {
    const prompts = new Map<number, string>()
    spyOn(globalThis, 'fetch').mockImplementation(async (_input, init) => {
      const { system, from, through } = promptWeeks(init)
      prompts.set(from, system)
      return modelResponse(blockOutput(from, through, 18, 'long_run'))
    })
    const response = await send('adapt', { ...adaptation, originalRemainingWeeks: original })
    expect(response.status).toBe(200)
    expect([...prompts.keys()].sort((a, b) => a - b)).toEqual([2, 6, 10, 14, 18])
    expect(prompts.get(2)).toContain(
      'none of these weeks is a taper week (the taper covers weeks 16, 17, 18)'
    )
    expect(prompts.get(14)).toContain('weeks 16, 17 of this block are taper weeks')
    expect(prompts.get(18)).toContain('week 18 of this block is a taper week')
    for (const prompt of prompts.values()) expect(prompt).not.toContain('taper prematurely')
  })
})
