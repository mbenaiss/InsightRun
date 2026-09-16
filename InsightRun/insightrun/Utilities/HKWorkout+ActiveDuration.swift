//
//  HKWorkout+ActiveDuration.swift
//  InsightRun
//

import Foundation
import HealthKit

extension HKWorkout {
    /// Paused intervals paired from the workout's pause/resume events. A pause that
    /// never resumes (workout ended while paused) is closed at `endDate`.
    nonisolated private var pausedIntervals: [(start: Date, end: Date)] {
        guard let events = workoutEvents else { return [] }
        var intervals: [(Date, Date)] = []
        var pauseStart: Date?
        for event in events.sorted(by: { $0.dateInterval.start < $1.dateInterval.start }) {
            switch event.type {
            case .pause:
                if pauseStart == nil { pauseStart = event.dateInterval.start }
            case .resume:
                if let start = pauseStart {
                    intervals.append((start, event.dateInterval.start))
                    pauseStart = nil
                }
            default:
                break
            }
        }
        if let start = pauseStart { intervals.append((start, endDate)) }
        return intervals
    }

    /// Total paused time across the whole workout.
    nonisolated var pausedDuration: TimeInterval {
        pausedIntervals.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
    }

    /// Paused time overlapping a time window — used to de-inflate the per-km split
    /// that contains a pause (its GPS timestamp gap otherwise counts the pause).
    nonisolated func pausedDuration(overlapping range: ClosedRange<Date>) -> TimeInterval {
        pausedIntervals.reduce(0) { acc, interval in
            let lower = max(interval.start, range.lowerBound)
            let upper = min(interval.end, range.upperBound)
            return upper > lower ? acc + upper.timeIntervalSince(lower) : acc
        }
    }

    /// Moving time excluding paused intervals, to match what Apple Fitness shows.
    /// The `min` guards against double-counting when `duration` already excludes
    /// pauses (or when no pause events are present), so this never inflates.
    nonisolated var activeDuration: TimeInterval {
        let elapsed = endDate.timeIntervalSince(startDate)
        return min(duration, max(0, elapsed - pausedDuration))
    }
}

enum WorkoutSplitBoundaries {
    nonisolated static func kilometers(
        events: [HKWorkoutEvent], distance: Double, start: Date, end: Date
    ) -> [DateInterval]? {
        guard distance.isFinite, distance >= 1000, distance <= 1_000_000 else { return nil }
        var segments: [DateInterval] = []
        for event in events {
            guard event.type == .segment, event.dateInterval.duration > 0,
                  event.dateInterval.start >= start, event.dateInterval.end <= end,
                  event.metadata?.isEmpty != false else { continue }
            segments.append(event.dateInterval)
        }
        segments.sort { first, second in
            if first.start == second.start { return first.end < second.end }
            return first.start < second.start
        }

        // Apple records overlapping kilometer and mile chains; the earliest
        // contiguous boundary selects kilometers without mixing the two series.
        var selected: [DateInterval] = []
        var cursor = start
        for segment in segments where abs(segment.start.timeIntervalSince(cursor)) < 0.1 {
            selected.append(segment)
            cursor = segment.end
        }
        guard selected.count == Int(ceil(distance / 1000)),
              abs(end.timeIntervalSince(cursor)) <= 5 else { return nil }
        return selected
    }
}
