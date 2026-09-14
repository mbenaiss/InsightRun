import { describe, expect, test } from 'bun:test'
import { buildWorkoutCoachPrompt } from '../src/prompts'
import { estimateMaxHR } from '../src/utils'

describe('heart rate reference', () => {
  test('matches the app age reference and rejects unavailable or invalid ages', () => {
    expect(estimateMaxHR(20)).toBe(200)
    expect(estimateMaxHR(40)).toBe(180)
    for (const age of [undefined, 0, -1, 121, 25.5, Number.NaN, Number.POSITIVE_INFINITY]) {
      expect(estimateMaxHR(age)).toBeNull()
    }
  })

  test('uses the age reference instead of the session maximum', () => {
    const prompt = buildWorkoutCoachPrompt(
      {
        profile: { age: 20 },
        workout: {
          date: '2026-09-14',
          duration: 1800,
          distance: 5,
          heartRate: { avg: 140, max: 150 },
        },
      },
      'en'
    )
    expect(prompt).toContain('70% of estimated max HR (200 bpm)')
    expect(prompt).not.toContain('93% of estimated max HR')
  })

  test('does not invent a percentage when age is unavailable', () => {
    const prompt = buildWorkoutCoachPrompt(
      {
        workout: {
          date: '2026-09-14',
          duration: 1800,
          distance: 5,
          heartRate: { avg: 140, max: 150 },
        },
      },
      'en'
    )
    expect(prompt).not.toContain('Estimated Intensity:')
  })
})
