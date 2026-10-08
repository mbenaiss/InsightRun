import { afterEach, describe, expect, mock, spyOn, test } from 'bun:test'
import app from '../src/index'
import * as modelRouter from '../src/modelRouter'
import {
  type PlanJobParams,
  type PlanJobStep,
  planJobRoutes,
  runPlanJob,
} from '../src/routes/generateTrainingPlan'
import { memoryKV } from './helpers/memoryKV'

afterEach(() => mock.restore())

const longPlan = {
  raceType: '10k',
  targetDate: '2027-06-17',
  startDate: '2027-01-01',
  fitnessLevel: 'intermediate',
  language: 'fr',
  trainingDaysPerWeek: 3,
  preferredDays: [2, 4, 6],
}
const jobId = '6f1c2b9e-3d4a-4b8c-9e7f-1a2b3c4d5e6f'
const runInstanceId = 'plan-qa-instance'
const premiumModel = {
  modelId: 'vendor/plan-model',
  displayName: 'QA',
  description: 'QA',
  requiresQuota: true,
}

function env(kv: KVNamespace, workflow?: unknown) {
  return {
    OPENROUTER_API_KEY: 'test-key',
    APP_SECRET: 'test-secret',
    POSTHOG_API_KEY: '',
    POSTHOG_HOST: '',
    RATE_LIMITER: kv,
    PLAN_GENERATION: workflow as Workflow<PlanJobParams>,
  }
}

function modelCalls() {
  const calls: number[] = []
  spyOn(globalThis, 'fetch').mockImplementation(async (_input, init) => {
    const system: string = JSON.parse(String(init?.body)).messages[0].content
    const [, from, through] = (system.match(/ONLY weeks (\d+) through (\d+)/) ?? []).map(Number)
    calls.push(from)
    const weeks = Array.from({ length: through - from + 1 }, (_, index) => ({
      weekNumber: from + index,
      phase: 'base',
      weeklyVolume: 15,
      workouts: [
        {
          type: from + index === 24 ? 'tempo' : 'easy_run',
          name: 'QA',
          description: 'QA',
          intensity: 'easy',
          targetDistance: 10000,
          steps: [],
        },
      ],
    }))
    return Response.json({
      choices: [
        {
          message: { content: JSON.stringify({ name: 'QA', goal: 'QA', weeks }) },
          finish_reason: 'stop',
        },
      ],
    })
  })
  return calls
}

// Mirrors the Workflows engine: a finished step is never run again, it returns its saved result.
function workflowStep(saved = new Map<string, unknown>(), evictAfterSteps = Infinity) {
  const names: string[] = []
  let started = 0
  const step: PlanJobStep = {
    async do<T>(name: string, _config: unknown, callback: () => Promise<T>) {
      names.push(name)
      if (saved.has(name)) return saved.get(name) as T
      if (++started > evictAfterSteps) throw new Error('engine evicted')
      const result = await callback()
      saved.set(name, structuredClone(result))
      return result
    },
  }
  return { step, names, saved }
}

function params(): PlanJobParams {
  return {
    request: longPlan as PlanJobParams['request'],
    userId: 'qa-user',
    ip: '192.0.2.1',
    model: premiumModel.modelId,
    modelConfig: premiumModel,
  }
}

describe('training plan job', () => {
  test('generates every block in its own step and counts the plan once', async () => {
    const { kv, blockKeys, store } = memoryKV()
    const calls = modelCalls()
    const quota = spyOn(modelRouter, 'afterModelUsage')
    const { step, names } = workflowStep()

    const result = await runPlanJob(env(kv), params(), step, {
      instanceId: runInstanceId,
      createdAt: Date.now(),
    })

    expect(result.plan.weeks.map((week) => week.weekNumber)).toEqual(
      Array.from({ length: 24 }, (_, index) => index + 1)
    )
    expect(calls.sort((a, b) => a - b)).toEqual([1, 5, 9, 13, 17, 21])
    expect(names.sort()).toEqual([
      'deliver plan',
      'weeks 1-4',
      'weeks 13-16',
      'weeks 17-20',
      'weeks 21-24',
      'weeks 5-8',
      'weeks 9-12',
    ])
    expect(quota).toHaveBeenCalledTimes(1)
    expect(blockKeys()).toEqual([])
    expect(
      [0, 1, 2, 3, 4, 5].map((index) => store.get(`plan-job:${runInstanceId}:${index}`))
    ).toEqual(['1', '1', '1', '1', '1', '1'])
  })

  test('a run resumed after an interruption never pays again for a finished block', async () => {
    const { kv } = memoryKV()
    const calls = modelCalls()
    const quota = spyOn(modelRouter, 'afterModelUsage')
    const createdAt = Date.now()
    const interrupted = workflowStep(new Map(), 4)
    await expect(
      runPlanJob(env(kv), params(), interrupted.step, { instanceId: runInstanceId, createdAt })
    ).rejects.toThrow('engine evicted')
    expect(interrupted.saved.size).toBe(4)
    expect(calls).toHaveLength(4)
    expect(quota).not.toHaveBeenCalled()

    const resumed = workflowStep(interrupted.saved)
    const result = await runPlanJob(env(kv), params(), resumed.step, {
      instanceId: runInstanceId,
      createdAt,
    })

    expect(result.plan.weeks).toHaveLength(24)
    expect(calls.sort((a, b) => a - b)).toEqual([1, 5, 9, 13, 17, 21])
    expect(quota).toHaveBeenCalledTimes(1)
  })
})

function fakeWorkflow() {
  const instances = new Map<string, { params: PlanJobParams; status: Record<string, unknown> }>()
  const create = mock(async ({ id, params }: { id: string; params: PlanJobParams }) => {
    if (instances.has(id)) throw new Error('instance.already_exists')
    instances.set(id, { params, status: { status: 'queued' } })
    return { id }
  })
  const workflow = {
    create,
    get: async (id: string) => {
      const instance = instances.get(id)
      if (!instance) throw new Error('instance.not_found')
      return { id, status: async () => instance.status }
    },
    deleteBatch: async (ids: string[]) => ({
      deleted: ids.filter((id) => instances.delete(id)).map((id) => ({ id })),
      errors: [],
    }),
  }
  return { workflow, instances, create }
}

function startJob(
  routeEnv: ReturnType<typeof env>,
  headers: Record<string, string>,
  body: unknown = longPlan
) {
  return planJobRoutes.request(
    '/',
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-User-ID': 'qa-user', ...headers },
      body: JSON.stringify(body),
    },
    routeEnv
  )
}

function readJob(routeEnv: ReturnType<typeof env>, id: string, userId = 'qa-user') {
  return planJobRoutes.request(`/${id}`, { headers: { 'X-User-ID': userId } }, routeEnv)
}

function deleteJob(routeEnv: ReturnType<typeof env>, id: string, userId = 'qa-user') {
  return planJobRoutes.request(
    `/${id}`,
    { method: 'DELETE', headers: { 'X-User-ID': userId } },
    routeEnv
  )
}

describe('training plan job routes', () => {
  test('queues one generation per job and keeps the plan for its owner', async () => {
    const { workflow, instances } = fakeWorkflow()
    const { kv } = memoryKV()
    const routeEnv = env(kv, workflow)

    const created = await startJob(routeEnv, { 'Idempotency-Key': jobId.toUpperCase() })
    expect(created.status).toBe(202)
    expect(await created.json()).toEqual({ jobId, status: 'running' })
    expect((await startJob(routeEnv, { 'Idempotency-Key': jobId })).status).toBe(202)
    expect(instances.size).toBe(1)
    const [instanceId] = [...instances.keys()]
    expect(instanceId.endsWith(jobId)).toBe(true)
    expect(instances.get(instanceId)?.params).toMatchObject({
      request: longPlan,
      userId: 'qa-user',
    })

    expect(await (await readJob(routeEnv, jobId)).json()).toEqual({
      status: 'running',
      progress: { completed: 0, total: 6 },
    })
    await kv.put(`plan-job:${instanceId}:0`, '1')
    await kv.put(`plan-job:${instanceId}:3`, '1')
    expect((await (await readJob(routeEnv, jobId)).json()).progress).toEqual({
      completed: 2,
      total: 6,
    })
    const output = { plan: { name: 'QA', goal: 'QA', weeks: [] }, metadata: { attempts: 1 } }
    const instance = instances.get(instanceId)
    if (instance) instance.status = { status: 'complete', output }
    expect(await (await readJob(routeEnv, jobId)).json()).toEqual({ status: 'complete', ...output })
    expect((await readJob(routeEnv, jobId, 'qa-other-user')).status).toBe(404)

    if (instance) instance.status = { status: 'errored', error: { name: 'Error', message: 'QA' } }
    expect(await (await readJob(routeEnv, jobId)).json()).toEqual({
      status: 'failed',
      message: 'QA',
    })
  })

  test('deletes an imported plan for its owner only', async () => {
    const { workflow, instances } = fakeWorkflow()
    const routeEnv = env(memoryKV().kv, workflow)
    await startJob(routeEnv, { 'Idempotency-Key': jobId })

    expect((await deleteJob(routeEnv, jobId, 'qa-other-user')).status).toBe(404)
    expect(instances.size).toBe(1)
    expect((await deleteJob(routeEnv, jobId)).status).toBe(204)
    expect(instances.size).toBe(0)
    expect((await readJob(routeEnv, jobId)).status).toBe(404)
    expect((await deleteJob(routeEnv, jobId)).status).toBe(404)
  })

  test('rejects a job without a UUID or with an invalid plan before queuing anything', async () => {
    const { workflow, create } = fakeWorkflow()
    const routeEnv = env(memoryKV().kv, workflow)

    expect((await startJob(routeEnv, {})).status).toBe(400)
    expect((await startJob(routeEnv, { 'Idempotency-Key': 'generate-plan:10k:QA' })).status).toBe(
      400
    )
    expect(
      (await startJob(routeEnv, { 'Idempotency-Key': jobId }, { ...longPlan, raceType: 'mile' }))
        .status
    ).toBe(400)
    expect(create).not.toHaveBeenCalled()
  })

  test.each(['GET', 'DELETE'])('%s on a job does not use up the API quota', async (method) => {
    const { workflow } = fakeWorkflow()
    const put = mock(async () => {})
    const getWithMetadata = mock(async () => ({ value: null, metadata: null }))
    const response = await app.request(
      `/api/training-plan-jobs/${jobId}`,
      {
        method,
        headers: {
          'X-App-Key': 'test-secret',
          'X-User-ID': 'qa-user',
          'CF-Connecting-IP': '192.0.2.1',
        },
      },
      {
        ...env({ get: async () => null, getWithMetadata, put } as unknown as KVNamespace, workflow),
      }
    )

    expect(response.status).toBe(404)
    expect(getWithMetadata).not.toHaveBeenCalled()
    expect(put).not.toHaveBeenCalled()
  })
})
