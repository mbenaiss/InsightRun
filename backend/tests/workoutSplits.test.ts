import { describe, expect, test } from 'bun:test'
import { buildWorkoutCoachPrompt } from '../src/prompts'
import { type WorkoutData, workoutDataSchema } from '../src/types'

function prompt(splits: WorkoutData['splits']) {
  return buildWorkoutCoachPrompt(
    { workout: { date: '2026-09-16', duration: 7200, distance: 20000, splits } },
    'en'
  )
}

describe('workout split context', () => {
  test('uses the end of a long run for pacing while bounding the displayed context', () => {
    const splits = Array.from({ length: 20 }, (_, i) => ({
      kilometer: i + 1,
      pace: i < 10 ? '5:00' : '7:00',
      time: i < 10 ? '5:00' : '7:00',
      distanceMeters: 1000,
    }))
    const result = prompt(splits)
    expect(result).toContain('120s/km slower in 2nd half')
    expect(result).toContain('20 valid full-km splits')
    expect(result).toContain('km 20:')
    expect(result).not.toContain('  km 10:')
  })

  test('keeps kilometer labels aligned after invalid paces and short final segments', () => {
    const result = prompt([
      { kilometer: 1, pace: 'unavailable', time: '0:00' },
      { kilometer: 2, pace: '5:00', time: '5:00', distanceMeters: 1000 },
      { kilometer: 3, pace: '6:00', time: '6:00', distanceMeters: 1000 },
      { kilometer: 4, pace: '12:00', time: '2:24', distanceMeters: 200 },
    ])
    expect(result).toContain('Fastest: km 2 | Slowest: km 3')
    expect(result).toContain('2 valid full-km splits')
    expect(result).toContain('200 m')
  })

  test('does not derive pacing from zero or malformed values', () => {
    const result = prompt([
      { kilometer: 1, pace: '0:00', time: '0:00' },
      { kilometer: 2, pace: '5:99', time: '5:99' },
      { kilometer: 3, pace: '5:00', time: '5:00' },
      { kilometer: 4, pace: '-5:00', time: '5:00' },
      { kilometer: 5, pace: '8:00 /mi', time: '5:00' },
    ])
    expect(result).not.toContain('Derived Split Analysis')
    expect(result).not.toContain('NaN')
  })

  test('accepts legacy clients and bounded ultra-distance split data', () => {
    const workout = { date: '2026-09-16', duration: 7200, distance: 20000 }
    expect(
      workoutDataSchema.safeParse({
        ...workout,
        splits: [{ kilometer: 1, pace: '5:00', time: '5:00' }],
      }).success
    ).toBe(true)
    const splits = Array.from({ length: 1000 }, (_, i) => ({
      kilometer: i + 1,
      pace: '5:00',
      time: '5:00',
      distanceMeters: 1000,
    }))
    expect(workoutDataSchema.safeParse({ ...workout, splits }).success).toBe(true)
    expect(
      workoutDataSchema.safeParse({ ...workout, splits: [...splits, splits[0]] }).success
    ).toBe(false)
  })
})
