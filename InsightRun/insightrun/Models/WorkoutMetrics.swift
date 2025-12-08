//
//  WorkoutMetrics.swift
//  InsightRun
//
//  Detailed metrics and statistics for a workout
//

import Foundation
import CoreLocation

struct WorkoutMetrics {
    // Basic info
    let workout: WorkoutModel

    // Heart rate data
    var averageHeartRate: Double?
    var minHeartRate: Double?
    var maxHeartRate: Double?
    var firstHeartRate: Double? // First HR sample at workout start
    var lastHeartRate: Double? // Last HR sample at workout end
    var heartRateZones: HeartRateZones?

    // Performance metrics
    var averagePace: Double? // min/km
    var minPace: Double? // fastest pace
    var maxPace: Double? // slowest pace
    var averageSpeed: Double? // km/h
    var maxSpeed: Double?
    var totalSteps: Int? // total step count during workout
    var averageCadence: Double? // steps per minute (calculated from totalSteps)
    var strideLength: Double? // meters
    var runningPower: Double? // watts (Apple Watch Series 6+)
    var firstPower: Double? // First power sample at workout start
    var lastPower: Double? // Last power sample at workout end

    // Elevation
    var totalElevationAscent: Double? // meters
    var totalElevationDescent: Double? // meters

    // Splits (per kilometer)
    var splits: [Split]?

    // Intervals (workout segments like warmup, work, recovery)
    var intervals: [WorkoutInterval]?

    // Route data
    var routePoints: [RoutePoint]?

    // Additional metrics (Apple Watch Series 7+)
    var groundContactTime: Double? // milliseconds
    var groundContactTimeBalance: Double? // percentage
    var verticalOscillation: Double? // centimeters
    var runningEfficiency: Double? // percentage

    // Mobility Metrics (Apple Watch Series 4+)
    var walkingSteadiness: Double? // percentage (0-100)
    var walkingAsymmetry: Double? // percentage
    var doubleSupportPercentage: Double? // percentage
    var walkingSpeed: Double? // km/h
    var stairAscentSpeed: Double? // km/h (vertical speed)
    var stairDescentSpeed: Double? // km/h (vertical speed)

    // VO2 Max (if available)
    var vo2Max: Double? // ml/kg/min

    // Environmental
    var temperature: Double? // Celsius
    var humidity: Double? // percentage

    // Movement analysis
    var movingTime: TimeInterval?
    var pausedTime: TimeInterval?
}

struct HeartRateZones {
    var zone1: TimeInterval? // Recovery (< 60% max HR)
    var zone2: TimeInterval? // Aerobic (60-70%)
    var zone3: TimeInterval? // Tempo (70-80%)
    var zone4: TimeInterval? // Threshold (80-90%)
    var zone5: TimeInterval? // Maximum (> 90%)

    var maxHeartRate: Double // Used for calculations
}

struct Split: Identifiable {
    let id = UUID()
    let kilometer: Int // 1, 2, 3, etc.
    let distance: Double // actual distance in meters
    let time: TimeInterval // seconds for this split
    let pace: Double // min/km
    let averageHeartRate: Double?
    let averagePower: Double? // watts
    let elevationGain: Double? // meters
    let elevationLoss: Double? // meters

    var timeFormatted: String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var paceFormatted: String {
        let minutes = Int(pace)
        let seconds = Int((pace - Double(minutes)) * 60)
        return String(format: "%d'%02d\"", minutes, seconds)
    }
}

struct RoutePoint: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let altitude: Double? // meters
    let timestamp: Date
    let horizontalAccuracy: Double? // meters
    let verticalAccuracy: Double? // meters
    let speed: Double? // m/s
}

// MARK: - Workout Interval (Lap/Segment)

enum IntervalType: String {
    case warmup = "warmup"
    case work = "work"
    case recovery = "recovery"
    case cooldown = "cooldown"
    case unknown = "unknown"

    var localizedName: String {
        switch self {
        case .warmup:
            return String(localized: "Warmup", comment: "Interval type: warmup")
        case .work:
            return String(localized: "Work", comment: "Interval type: work")
        case .recovery:
            return String(localized: "Recovery", comment: "Interval type: recovery")
        case .cooldown:
            return String(localized: "Cooldown", comment: "Interval type: cooldown")
        case .unknown:
            return String(localized: "Interval", comment: "Interval type: unknown")
        }
    }

    var icon: String {
        switch self {
        case .warmup:
            return "figure.walk"
        case .work:
            return "flame.fill"
        case .recovery:
            return "arrow.down.heart"
        case .cooldown:
            return "wind"
        case .unknown:
            return "timer"
        }
    }

    var color: String {
        switch self {
        case .warmup:
            return "yellow"
        case .work:
            return "orange"
        case .recovery:
            return "green"
        case .cooldown:
            return "blue"
        case .unknown:
            return "gray"
        }
    }
}

struct WorkoutInterval: Identifiable {
    let id = UUID()
    let index: Int // 1, 2, 3, etc.
    let type: IntervalType
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval // seconds
    let distance: Double? // meters
    let pace: Double? // min/km
    let averageHeartRate: Double?
    let averagePower: Double? // watts
    let targetPaceMin: Double? // min/km (target pace range minimum)
    let targetPaceMax: Double? // min/km (target pace range maximum)

    var durationFormatted: String {
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return String(format: "%dh %02dm %02ds", hours, remainingMinutes, seconds)
        }
        return String(format: "%dm %02ds", minutes, seconds)
    }

    var durationCompactFormatted: String {
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return String(format: "%dh %02dm", hours, remainingMinutes)
        }
        if seconds == 0 {
            return String(format: "%d mn", minutes)
        }
        return String(format: "%d mn %02d s", minutes, seconds)
    }

    var paceFormatted: String? {
        guard let pace = pace else { return nil }
        let minutes = Int(pace)
        let seconds = Int((pace - Double(minutes)) * 60)
        return String(format: "%d'%02d\"/km", minutes, seconds)
    }

    var targetPaceRangeFormatted: String? {
        guard let minPace = targetPaceMin, let maxPace = targetPaceMax else { return nil }
        let minMinutes = Int(minPace)
        let minSeconds = Int((minPace - Double(minMinutes)) * 60)

        // If min == max (threshold), show single value
        if abs(minPace - maxPace) < 0.01 {
            return String(format: "%d'%02d\"/km", minMinutes, minSeconds)
        }

        // Otherwise show range
        let maxMinutes = Int(maxPace)
        let maxSeconds = Int((maxPace - Double(maxMinutes)) * 60)
        return String(format: "%d'%02d\"-%d'%02d\"/km", minMinutes, minSeconds, maxMinutes, maxSeconds)
    }

    var distanceFormatted: String? {
        guard let distance = distance else { return nil }
        if distance >= 1000 {
            return String(format: "%.2f km", distance / 1000)
        }
        return String(format: "%.0f m", distance)
    }
}

extension WorkoutMetrics {
    var bestSplit: Split? {
        splits?.min(by: { $0.pace < $1.pace })
    }

    var worstSplit: Split? {
        splits?.max(by: { $0.pace < $1.pace })
    }

    var averageSplitPace: Double? {
        guard let splits = splits, !splits.isEmpty else { return nil }
        let totalPace = splits.reduce(0.0) { $0 + $1.pace }
        return totalPace / Double(splits.count)
    }

    var totalElevationChange: Double? {
        guard let ascent = totalElevationAscent, let descent = totalElevationDescent else {
            return totalElevationAscent ?? totalElevationDescent
        }
        return ascent + descent
    }

    var movingPercentage: Double? {
        guard let movingTime = movingTime else { return nil }
        let totalTime = workout.duration
        guard totalTime > 0 else { return nil }
        return (movingTime / totalTime) * 100.0
    }
}
