import { afterEach, describe, expect, mock, spyOn, test } from 'bun:test'
import { buildWorkoutCoachPrompt } from '../src/prompts'
import { buildSmartSuggestionPrompt, callModelForSuggestion } from '../src/routes/smartSuggestion'
import type { ChatRequestV2, WorkoutData } from '../src/types'
import { formatPace } from '../src/utils'

afterEach(() => mock.restore())
const workouts: WorkoutData[] = [
  {
    date: '2026-09-16',
    distance: 5000,
    duration: 1500,
    pace: 5,
    heartRate: { avg: 130, max: 140 },
  },
  {
    date: '2026-09-10',
    distance: 5000,
    duration: 1650,
    pace: 5.5,
    heartRate: { avg: 140, max: 150 },
  },
  {
    date: '2026-09-01',
    distance: 5000,
    duration: 1800,
    pace: 6,
    heartRate: { avg: 150, max: 160 },
  },
]
const recent = {
  workouts,
  totalDistance: 15000,
  totalDuration: 4950,
  totalCalories: 1000,
  avgPace: 5.5,
}
const payload: ChatRequestV2 = {
  promptType: 'workout_suggestion',
  language: 'en',
  data: { recentWorkouts: recent, profile: { age: 20 } },
}

describe('chronological coaching context', () => {
  test('input order cannot reverse the pace trend or invent a weekly period', () => {
    const prompt = buildWorkoutCoachPrompt(payload.data, 'en')
    const reversed = buildWorkoutCoachPrompt(
      { ...payload.data, recentWorkouts: { ...recent, workouts: [...workouts].reverse() } },
      'en'
    )
    expect(prompt).toBe(reversed)
    expect(prompt).toContain('Pace Trend: Faster (60s/km shift)')
    expect(prompt).not.toContain('Weekly Summary')
    expect(prompt).not.toContain('HR Efficiency:')
  })
  test('suggestion uses an age reference instead of the session maximum', () => {
    const prompt = buildSmartSuggestionPrompt(payload).system
    expect(prompt).toContain('Easy → Moderate → Moderate')
    expect(prompt).not.toContain('/km/km')
    const unknown = buildSmartSuggestionPrompt({
      ...payload,
      data: { recentWorkouts: recent },
    }).system
    expect(unknown).not.toContain('Recent intensity pattern')
  })
})

describe('suggestion response budget', () => {
  test.each([
    { content: '', reason: 'stop' },
    { content: 'An incomplete workout', reason: 'length' },
  ])('rejects incomplete output without a second network attempt: %p', async ({
    content,
    reason,
  }) => {
    const fetchMock = spyOn(globalThis, 'fetch').mockResolvedValue(
      Response.json({ choices: [{ message: { content }, finish_reason: reason }] })
    )
    await expect(
      callModelForSuggestion('test-key', 'system', 'user', 'test-model')
    ).rejects.toThrow()
    expect(fetchMock).toHaveBeenCalledTimes(1)
  })
  test('keeps one bounded attempt on an upstream failure', async () => {
    const fetchMock = spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response('Unavailable', { status: 503 })
    )
    await expect(
      callModelForSuggestion('test-key', 'system', 'user', 'test-model')
    ).rejects.toThrow()
    expect(fetchMock).toHaveBeenCalledTimes(1)
  })
  test('returns a complete editable workout', async () => {
    const content =
      'Easy return\n\n- Warm up: 5 min at 6:00/km\n- Run: 20 min at 5:40/km\n- Cool down: 5 min at 6:10/km'
    spyOn(globalThis, 'fetch').mockResolvedValue(
      Response.json({ choices: [{ message: { content }, finish_reason: 'stop' }] })
    )
    const { suggestion } = await callModelForSuggestion('test-key', 'system', 'user', 'test-model')
    expect(suggestion).toBe(content)
  })
})

test('pace formatting matches rounded app values and carries seconds into minutes', () => {
  expect(formatPace(6 + 45.7 / 60)).toBe('6:46/km')
  expect(formatPace(5.999)).toBe('6:00/km')
  expect(formatPace(0)).toBe('N/A')
})
