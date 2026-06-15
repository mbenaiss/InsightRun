//
//  HKWorkout+ActiveDuration.swift
//  InsightRun
//

import Foundation
import HealthKit

extension HKWorkout {
    /// Moving time excluding paused intervals, to match what Apple Fitness shows.
    /// `duration` can include paused time depending on the recording source, so we
    /// subtract the paused intervals derived from pause/resume events. The `min`
    /// guards against double-counting when `duration` already excludes pauses (or
    /// when no pause events are present), so this never inflates the value.
    var activeDuration: TimeInterval {
        let elapsed = endDate.timeIntervalSince(startDate)
        return min(duration, max(0, elapsed - pausedDuration))
    }

    /// Total paused time, summed from pause/resume event pairs.
    var pausedDuration: TimeInterval {
        guard let events = workoutEvents else { return 0 }
        var paused: TimeInterval = 0
        var pauseStart: Date?
        for event in events.sorted(by: { $0.dateInterval.start < $1.dateInterval.start }) {
            switch event.type {
            case .pause:
                if pauseStart == nil { pauseStart = event.dateInterval.start }
            case .resume:
                if let start = pauseStart {
                    paused += event.dateInterval.start.timeIntervalSince(start)
                    pauseStart = nil
                }
            default:
                break
            }
        }
        return paused
    }
}
