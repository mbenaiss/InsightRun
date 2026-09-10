import { afterEach, describe, expect, spyOn, test } from 'bun:test'
import app from '../src/routes/generateWorkout'
import fixture from './fixtures/open-intervals.json'

const env = {
  OPENROUTER_API_KEY: 'test-key',
  APP_SECRET: 'test-secret',
  POSTHOG_API_KEY: '',
  POSTHOG_HOST: '',
  RATE_LIMITER: {} as KVNamespace,
}

afterEach(() => {
  fetchMock?.mockRestore()
})

let fetchMock: ReturnType<typeof spyOn<typeof globalThis, 'fetch'>> | undefined

async function generate(outputs: unknown[]) {
  fetchMock = spyOn(globalThis, 'fetch')
  for (const output of outputs) {
    fetchMock.mockResolvedValueOnce(
      Response.json({
        choices: [{ message: { content: JSON.stringify(output) }, finish_reason: 'stop' }],
      })
    )
  }
  return app.request(
    '/',
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        userQuestion:
          'Échauffement ouvert ~1,5–2 km FC <150, boucle ×6 effort 0:30 à 4:39–4:48/km, récup 1:00 sans objectif, retour au calme ouvert jusqu’à 5 km.',
        language: 'fr',
        model: 'test-model',
      }),
    },
    env
  )
}

describe('workout generation response', () => {
  test('preserves open steps, repetitions, pace, heart rate and instructions', async () => {
    const response = await generate([fixture])
    expect(response.status).toBe(200)
    expect((await response.json()).workout).toEqual(fixture)
    expect(fetchMock).toHaveBeenCalledTimes(1)
  })

  test('normalizes open goals and inverted pace ranges without changing unit durations', async () => {
    const workout = structuredClone(fixture)
    workout.steps[0].goal.value = 2000
    workout.steps[1].targetPaceMin = '4:48/km'
    workout.steps[1].targetPaceMax = '4:39/km'
    const response = await generate([workout])
    expect(response.status).toBe(200)
    expect((await response.json()).workout).toEqual(fixture)
  })

  test('decodes open goals emitted without a value', async () => {
    const workout = JSON.parse(JSON.stringify(fixture))
    delete workout.steps[0].goal.value
    const response = await generate([workout])
    expect(response.status).toBe(200)
    expect((await response.json()).workout).toEqual(fixture)
  })

  test.each([
    0,
    1,
    -1,
    301,
    150.5,
    '150',
  ])('retries invalid heart rate ceiling %p', async (limit) => {
    const workout = JSON.parse(JSON.stringify(fixture))
    workout.steps[0].targetHeartRateMax = limit
    const response = await generate([workout, fixture])
    expect(response.status).toBe(200)
    const result = await response.json()
    expect(result.metadata.attempts).toBe(2)
    expect(result.workout).toEqual(fixture)
  })

  test.each(['0:00', '4:99', '4.65'])('retries invalid pace %s', async (pace) => {
    const workout = structuredClone(fixture)
    workout.steps[1].targetPaceMin = pace
    const response = await generate([workout, fixture])
    expect(response.status).toBe(200)
    expect((await response.json()).metadata.attempts).toBe(2)
  })

  test('rejects an incomplete pace range instead of exporting without an alert', async () => {
    const workout = structuredClone(fixture)
    delete workout.steps[1].targetPaceMax
    const response = await generate([workout, workout])
    expect(response.status).toBe(500)
  })

  test('retries when a recovery without a target receives a heart rate alert', async () => {
    const workout = structuredClone(fixture)
    workout.steps[2].targetHeartRateMax = 150
    const response = await generate([workout, fixture])
    expect(response.status).toBe(200)
    const result = await response.json()
    expect(result.metadata.attempts).toBe(2)
    expect(result.workout.steps[2].targetHeartRateMax).toBeUndefined()
  })

  test('rejects repeated failure to respect a recovery without a target', async () => {
    const workout = structuredClone(fixture)
    workout.steps[2].targetPaceMin = '6:00'
    workout.steps[2].targetPaceMax = '7:00'
    const response = await generate([workout, workout])
    expect(response.status).toBe(500)
  })
})
