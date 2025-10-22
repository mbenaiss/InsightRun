//
//  WorkoutMetrics.swift
//  HealthApp
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

    // Elevation
    var totalElevationAscent: Double? // meters
    var totalElevationDescent: Double? // meters

    // Splits (per kilometer)
    var splits: [Split]?

    // Route data
    var routePoints: [RoutePoint]?

    // Additional metrics (Apple Watch Series 7+)
    var groundContactTime: Double? // milliseconds
    var groundContactTimeBalance: Double? // percentage
    var verticalOscillation: Double? // centimeters
    var runningEfficiency: Double? // percentage

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
