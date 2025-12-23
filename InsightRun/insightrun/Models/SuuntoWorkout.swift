//
//  SuuntoWorkout.swift
//  InsightRun
//
//  Model for parsing Suunto JSON export files
//

import Foundation
import CoreLocation

// MARK: - Root Structure

struct SuuntoExport: Codable {
    let DeviceLog: SuuntoDeviceLog
}

struct SuuntoDeviceLog: Codable {
    let Header: SuuntoHeader
    let Samples: [SuuntoSample]
}

// MARK: - Header (Summary Data)

struct SuuntoHeader: Codable {
    let Activity: String
    let ActivityType: Int
    let DateTime: String
    let Duration: Double // seconds
    let Distance: Double // meters
    let Energy: Double? // joules
    let TotalEnergy: Double? // joules
    let Ascent: Double?
    let Descent: Double?
    let StepCount: Int?
    let PauseDuration: Double?

    // Device info
    let Device: SuuntoDevice?

    // Heart rate zones
    let HrZones: SuuntoHrZones?

    // Advanced metrics
    let MAXVO2: Double?
    let EPOC: Double?
    let PeakTrainingEffect: Double?
    let FitnessAge: Int?
    let RecoveryTime: Double?

    // Running dynamics
    let GroundContactTime: SuuntoMinMaxAvg?
    let VerticalOscillation: SuuntoMinMaxAvg?
    let Stride: SuuntoMinMaxAvg?
    let LeftGroundContactBalance: SuuntoMinMaxAvg?
    let RightGroundContactBalance: SuuntoMinMaxAvg?

    // Altitude
    let Altitude: SuuntoMinMax?

    // Speed
    let DownhillSpeed: SuuntoMinMaxAvg?

    // Personal thresholds
    let LacticThHr: Double?
    let LacticThPace: Double?
    let Personal: SuuntoPersonal?

    // Feeling
    let Feeling: Int?
    let Notes: String?
}

struct SuuntoDevice: Codable {
    let Name: String?
    let SerialNumber: String?
    let Info: SuuntoDeviceInfo?
}

struct SuuntoDeviceInfo: Codable {
    let SW: String?
    let HW: String?
}

struct SuuntoHrZones: Codable {
    let Zone1Duration: Double?
    let Zone2Duration: Double?
    let Zone3Duration: Double?
    let Zone4Duration: Double?
    let Zone5Duration: Double?
    let Zone2LowerLimit: Double?
    let Zone3LowerLimit: Double?
    let Zone4LowerLimit: Double?
    let Zone5LowerLimit: Double?
}

struct SuuntoMinMaxAvg: Codable {
    let Avg: Double?
    let Max: Double?
    let Min: Double?
}

struct SuuntoMinMax: Codable {
    let Max: Double?
    let Min: Double?
}

struct SuuntoPersonal: Codable {
    let MaxHR: Double? // in Hz (divide by 60 for bpm factor)
    let RestHR: Double?
}

// MARK: - Samples (Time Series Data)

struct SuuntoSample: Codable {
    let TimeISO8601: String

    // GPS (coordinates in radians!)
    let GPSLatitude: Double?
    let GPSLongitude: Double?
    let Latitude: Double?
    let Longitude: Double?
    let GPSAltitude: Double?
    let GPSSpeed: Double?
    let GPSHeading: Double?

    // Satellite info
    let EHPE: Double?
    let EVPE: Double?
    let NumberOfSatellites: Int?

    // Heart rate (in Hz, multiply by 60 for bpm)
    let HR: Double?

    // Metrics
    let Altitude: Double?
    let Speed: Double?
    let Distance: Double?
    let Cadence: Double? // in Hz
    let Power: Double? // watts
    let Temperature: Double? // Kelvin

    // Running dynamics
    let VerticalOscillation: Double?
    let GroundContactTime: Double?

    // Pressure
    let AbsPressure: Double?
    let SeaLevelPressure: Double?
    let VerticalSpeed: Double?

    // Battery (for diagnostics)
    let BatteryCharge: Double?

    // Events (laps, start/stop)
    let Events: [SuuntoEvent]?

    // UTC time
    let UTC: String?
}

struct SuuntoEvent: Codable {
    let Lap: SuuntoLap?
    let Activity: SuuntoActivityEvent?
    let ArrayBegin: Int?
}

struct SuuntoLap: Codable {
    let `Type`: String?
    let Duration: Double? // seconds since start
    let Distance: Double? // meters
    let Time: Double? // lap time in seconds
    let HR: SuuntoLapHR?
    let Cadence: SuuntoLapCadence?
    let Power: SuuntoLapPower?
    let Ascent: Double?
    let Descent: Double?
    let Speed: SuuntoLapSpeed?
}

struct SuuntoLapHR: Codable {
    let Avg: Double?
    let Max: Double?
    let Min: Double?
}

struct SuuntoLapCadence: Codable {
    let Avg: Double?
}

struct SuuntoLapPower: Codable {
    let Avg: Double?
}

struct SuuntoLapSpeed: Codable {
    let Avg: Double?
}

struct SuuntoActivityEvent: Codable {
    let ActivityType: Int?
    let CustomModeId: String?
}

// MARK: - Suunto Split

struct SuuntoSplit {
    let kilometer: Int
    let time: TimeInterval // seconds for this km
    let pace: Double // min/km
    let averageHeartRate: Double?
    let averagePower: Double?
    let averageCadence: Double?
    let elevationGain: Double?
}

// MARK: - Parsed Workout (Converted to usable units)

struct ParsedSuuntoWorkout {
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval
    let distance: Double // meters
    let calories: Double // kcal
    let elevationGain: Double // meters
    let elevationLoss: Double // meters

    // Heart rate (bpm)
    let averageHeartRate: Double?
    let maxHeartRate: Double?

    // Speed (m/s)
    let averageSpeed: Double?
    let maxSpeed: Double?

    // Running dynamics
    let averageGroundContactTime: Double? // milliseconds
    let averageVerticalOscillation: Double? // centimeters
    let averageStrideLength: Double? // meters
    let averageCadence: Double? // steps per minute
    let averagePower: Double? // watts

    // Advanced metrics
    let vo2Max: Double?
    let epoc: Double?
    let trainingEffect: Double?

    // Route
    let routeCoordinates: [CLLocationCoordinate2D]
    let hasRoute: Bool

    // Samples for detailed analysis
    let heartRateSamples: [(date: Date, bpm: Double)]
    let cadenceSamples: [(date: Date, spm: Double)]
    let powerSamples: [(date: Date, watts: Double)]
    let altitudeSamples: [(date: Date, meters: Double)]

    // Splits (calculated from distance samples)
    let splits: [SuuntoSplit]

    // Metadata
    let deviceName: String
    let activityType: String
    let feeling: Int?
    let notes: String?
}

// MARK: - Parser

enum SuuntoParserError: Error, LocalizedError {
    case invalidJSON
    case invalidDate
    case missingRequiredFields

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "Invalid Suunto JSON format"
        case .invalidDate:
            return "Could not parse workout date"
        case .missingRequiredFields:
            return "Missing required workout fields"
        }
    }
}

struct SuuntoParser {

    // Maximum samples to keep in memory (prevents memory issues for ultra-marathons)
    private static let maxSamplesInMemory = 2000

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601FormatterNoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Downsample an array to maxCount elements, preserving first and last elements
    /// Uses uniform sampling to maintain data distribution
    private static func downsample<T>(_ array: [T], to maxCount: Int) -> [T] {
        guard array.count > maxCount else { return array }

        var result: [T] = []
        result.reserveCapacity(maxCount)

        let step = Double(array.count - 1) / Double(maxCount - 1)
        for i in 0..<maxCount {
            let index = min(Int(Double(i) * step), array.count - 1)
            result.append(array[index])
        }

        return result
    }

    static func parse(from data: Data) throws -> ParsedSuuntoWorkout {
        let decoder = JSONDecoder()
        let export = try decoder.decode(SuuntoExport.self, from: data)
        return try convert(export)
    }

    static func parse(from url: URL) throws -> ParsedSuuntoWorkout {
        let data = try Data(contentsOf: url)
        return try parse(from: data)
    }

    /// Async version that loads file data on background queue to avoid blocking main thread
    static func parseAsync(from url: URL) async throws -> ParsedSuuntoWorkout {
        let data = try await Task.detached(priority: .userInitiated) {
            try Data(contentsOf: url)
        }.value
        return try parse(from: data)
    }

    private static func parseDate(_ dateString: String) -> Date? {
        if let date = iso8601Formatter.date(from: dateString) {
            return date
        }
        return iso8601FormatterNoFraction.date(from: dateString)
    }

    private static func convert(_ export: SuuntoExport) throws -> ParsedSuuntoWorkout {
        let header = export.DeviceLog.Header
        let samples = export.DeviceLog.Samples

        // Parse start date
        guard let startDate = parseDate(header.DateTime) else {
            throw SuuntoParserError.invalidDate
        }

        let endDate = startDate.addingTimeInterval(header.Duration)

        // Convert energy from joules to kcal
        let energyJoules = header.TotalEnergy ?? header.Energy ?? 0
        let calories = energyJoules / 4184.0 // 1 kcal = 4184 joules

        // Extract heart rate samples and calculate averages
        var heartRateSamples: [(date: Date, bpm: Double)] = []
        var cadenceSamples: [(date: Date, spm: Double)] = []
        var powerSamples: [(date: Date, watts: Double)] = []
        var altitudeSamples: [(date: Date, meters: Double)] = []
        var routeCoordinates: [CLLocationCoordinate2D] = []

        var hrSum: Double = 0
        var hrMax: Double = 0
        var hrCount: Int = 0

        var speedSum: Double = 0
        var speedMax: Double = 0
        var speedCount: Int = 0

        var cadenceSum: Double = 0
        var cadenceCount: Int = 0

        var powerSum: Double = 0
        var powerCount: Int = 0

        // For split calculation
        var distanceSamples: [SuuntoParser.DistanceSample] = []

        for sample in samples {
            guard let sampleDate = parseDate(sample.TimeISO8601) else { continue }

            // Heart rate: Suunto stores as fraction of maxHR or in Hz
            // If value < 10, it's likely in Hz (multiply by 60)
            // If value > 10, it's likely already in some form we need to interpret
            if let hr = sample.HR, hr > 0 {
                // Suunto stores HR as a ratio or in Hz
                // Values like 1.08, 1.95, 2.0 etc are HR in Hz (need * 60)
                // Values > 3.5 Hz would be > 210 bpm which is very high
                let bpm: Double
                if hr < 4.0 {
                    // Likely in Hz, convert to bpm
                    bpm = hr * 60.0
                } else {
                    // Already in bpm or similar
                    bpm = hr
                }

                if bpm > 30 && bpm < 250 { // Sanity check
                    heartRateSamples.append((date: sampleDate, bpm: bpm))
                    hrSum += bpm
                    hrMax = max(hrMax, bpm)
                    hrCount += 1
                }
            }

            // Speed
            if let speed = sample.Speed ?? sample.GPSSpeed, speed > 0 {
                speedSum += speed
                speedMax = max(speedMax, speed)
                speedCount += 1
            }

            // Cadence: Suunto stores in Hz, convert to steps per minute
            if let cadence = sample.Cadence, cadence > 0 {
                let spm = cadence * 60.0 * 2.0 // Hz to steps/min (×2 for both feet)
                if spm > 100 && spm < 250 { // Sanity check
                    cadenceSamples.append((date: sampleDate, spm: spm))
                    cadenceSum += spm
                    cadenceCount += 1
                }
            }

            // Power
            if let power = sample.Power, power > 0 {
                powerSamples.append((date: sampleDate, watts: power))
                powerSum += power
                powerCount += 1
            }

            // Altitude
            if let altitude = sample.Altitude ?? sample.GPSAltitude {
                altitudeSamples.append((date: sampleDate, meters: altitude))
            }

            // GPS coordinates (Suunto stores in radians, convert to degrees)
            if let lat = sample.GPSLatitude ?? sample.Latitude,
               let lon = sample.GPSLongitude ?? sample.Longitude {
                // Convert from radians to degrees
                let latDegrees = lat * (180.0 / .pi)
                let lonDegrees = lon * (180.0 / .pi)

                // Sanity check for valid coordinates
                if latDegrees >= -90 && latDegrees <= 90 &&
                   lonDegrees >= -180 && lonDegrees <= 180 {
                    routeCoordinates.append(CLLocationCoordinate2D(
                        latitude: latDegrees,
                        longitude: lonDegrees
                    ))
                }
            }

            // Collect distance samples for split calculation
            if let distance = sample.Distance, distance > 0 {
                // Find HR from the closest HR sample (HR and Distance are in separate samples)
                let hrBpm = findClosestHR(for: sampleDate, in: heartRateSamples)

                // Convert cadence to spm
                var cadSpm: Double? = nil
                if let cad = sample.Cadence, cad > 0 {
                    cadSpm = cad * 60.0 * 2.0
                }
                distanceSamples.append(DistanceSample(
                    date: sampleDate,
                    distance: distance,
                    hr: hrBpm,
                    power: sample.Power,
                    cadence: cadSpm,
                    altitude: sample.Altitude ?? sample.GPSAltitude
                ))
            }
        }

        // Debug: show how many distance samples have HR matched
        let distanceSamplesWithHR = distanceSamples.filter { $0.hr != nil }.count
        print("   💓 HR samples collected: \(heartRateSamples.count), matched to distance samples: \(distanceSamplesWithHR)/\(distanceSamples.count)")

        // Calculate splits from distance samples (pass workout start date for accurate timing)
        let splits = calculateSplits(from: distanceSamples, workoutStartDate: startDate)

        // Calculate averages
        let averageHeartRate = hrCount > 0 ? hrSum / Double(hrCount) : nil
        let maxHeartRate = hrMax > 0 ? hrMax : nil
        let averageSpeed = speedCount > 0 ? speedSum / Double(speedCount) : header.DownhillSpeed?.Avg
        let maxSpeed = speedMax > 0 ? speedMax : header.DownhillSpeed?.Max
        let averageCadence = cadenceCount > 0 ? cadenceSum / Double(cadenceCount) : nil
        let averagePower = powerCount > 0 ? powerSum / Double(powerCount) : nil

        // Running dynamics from header (convert units)
        let avgGroundContactTime = header.GroundContactTime?.Avg.map { $0 * 1000 } // seconds to ms
        let avgVerticalOscillation = header.VerticalOscillation?.Avg.map { $0 * 100 } // meters to cm
        let avgStrideLength = header.Stride?.Avg

        // Device name
        let deviceName = header.Device?.Name ?? "Suunto"

        // Debug: print parsed values
        print("🔍 DEBUG Suunto Parser:")
        print("   Device: \(deviceName)")
        print("   Cadence (from samples): \(averageCadence ?? -1) spm (\(cadenceCount) samples)")
        print("   Power (from samples): \(averagePower ?? -1) W (\(powerCount) samples)")
        print("   Stride (from header): \(avgStrideLength ?? -1) m")
        print("   GCT (from header): \(avgGroundContactTime ?? -1) ms")
        print("   VO (from header): \(avgVerticalOscillation ?? -1) cm")
        print("   VO2max (from header): \(header.MAXVO2 ?? -1)")
        print("   Training Effect: \(header.PeakTrainingEffect ?? -1)")

        // Downsample large arrays to prevent memory issues (ultra-marathons can have 20,000+ samples)
        let downsampledHR = downsample(heartRateSamples, to: maxSamplesInMemory)
        let downsampledCadence = downsample(cadenceSamples, to: maxSamplesInMemory)
        let downsampledPower = downsample(powerSamples, to: maxSamplesInMemory)
        let downsampledAltitude = downsample(altitudeSamples, to: maxSamplesInMemory)
        let downsampledRoute = downsample(routeCoordinates, to: maxSamplesInMemory)

        if heartRateSamples.count > maxSamplesInMemory {
            print("   ⚠️ Downsampled HR from \(heartRateSamples.count) to \(downsampledHR.count) samples")
        }
        if routeCoordinates.count > maxSamplesInMemory {
            print("   ⚠️ Downsampled route from \(routeCoordinates.count) to \(downsampledRoute.count) points")
        }

        return ParsedSuuntoWorkout(
            startDate: startDate,
            endDate: endDate,
            duration: header.Duration,
            distance: header.Distance,
            calories: calories,
            elevationGain: header.Ascent ?? 0,
            elevationLoss: header.Descent ?? 0,
            averageHeartRate: averageHeartRate,
            maxHeartRate: maxHeartRate,
            averageSpeed: averageSpeed,
            maxSpeed: maxSpeed,
            averageGroundContactTime: avgGroundContactTime,
            averageVerticalOscillation: avgVerticalOscillation,
            averageStrideLength: avgStrideLength,
            averageCadence: averageCadence,
            averagePower: averagePower,
            vo2Max: header.MAXVO2,
            epoc: header.EPOC,
            trainingEffect: header.PeakTrainingEffect,
            routeCoordinates: downsampledRoute,
            hasRoute: !routeCoordinates.isEmpty,
            heartRateSamples: downsampledHR,
            cadenceSamples: downsampledCadence,
            powerSamples: downsampledPower,
            altitudeSamples: downsampledAltitude,
            splits: splits,
            deviceName: deviceName,
            activityType: header.Activity,
            feeling: header.Feeling,
            notes: header.Notes
        )
    }

    // MARK: - Split Calculation

    struct DistanceSample {
        let date: Date
        let distance: Double
        let hr: Double?
        let power: Double?
        let cadence: Double?
        let altitude: Double?
    }

    /// Find the closest HR sample to a given date using binary search (O(log n) complexity)
    /// HR and Distance samples are in separate JSON objects, so we need to match them by timestamp
    /// Assumes hrSamples are sorted by date (ascending)
    static func findClosestHR(for date: Date, in hrSamples: [(date: Date, bpm: Double)], tolerance: TimeInterval = 10.0) -> Double? {
        guard !hrSamples.isEmpty else { return nil }

        let targetTime = date.timeIntervalSince1970

        // Binary search to find insertion point
        var low = 0
        var high = hrSamples.count - 1

        while low < high {
            let mid = (low + high) / 2
            if hrSamples[mid].date.timeIntervalSince1970 < targetTime {
                low = mid + 1
            } else {
                high = mid
            }
        }

        // Check candidates: the found index and the one before it
        var bestSample: (date: Date, bpm: Double)?
        var minInterval: TimeInterval = .infinity

        // Check index found by binary search
        if low < hrSamples.count {
            let interval = abs(hrSamples[low].date.timeIntervalSince(date))
            if interval < minInterval {
                minInterval = interval
                bestSample = hrSamples[low]
            }
        }

        // Check previous index (might be closer)
        if low > 0 {
            let interval = abs(hrSamples[low - 1].date.timeIntervalSince(date))
            if interval < minInterval {
                minInterval = interval
                bestSample = hrSamples[low - 1]
            }
        }

        // Only return HR if within tolerance
        if minInterval <= tolerance, let sample = bestSample {
            return sample.bpm
        }

        return nil
    }

    static func calculateSplits(from samples: [DistanceSample], workoutStartDate: Date? = nil) -> [SuuntoSplit] {
        guard samples.count > 1 else { return [] }

        // Sort by time (not distance, to handle edge cases)
        let sortedSamples = samples.sorted { $0.date < $1.date }

        var splits: [SuuntoSplit] = []
        var currentKm = 1
        var lastKmCrossingTime = workoutStartDate ?? sortedSamples[0].date
        var lastKmCrossingIndex = 0

        print("   📊 Calculating splits from \(sortedSamples.count) distance samples")
        print("   📊 Start time: \(lastKmCrossingTime)")

        for i in 1..<sortedSamples.count {
            let prevSample = sortedSamples[i - 1]
            let currSample = sortedSamples[i]
            let targetDistance = Double(currentKm) * 1000.0

            // Check if we crossed the km marker between prev and curr samples
            if prevSample.distance < targetDistance && currSample.distance >= targetDistance {
                // Linear interpolation to find exact crossing time
                let d1 = prevSample.distance
                let d2 = currSample.distance
                let t1 = prevSample.date
                let t2 = currSample.date

                let crossingTime: Date
                if d2 - d1 > 0 {
                    let ratio = (targetDistance - d1) / (d2 - d1)
                    let timeDiff = t2.timeIntervalSince(t1) * ratio
                    crossingTime = t1.addingTimeInterval(timeDiff)
                } else {
                    crossingTime = currSample.date
                }

                // Calculate time for this km
                let kmTime = crossingTime.timeIntervalSince(lastKmCrossingTime)
                let pace = kmTime / 60.0 // min/km (already normalized to 1km)

                // Calculate averages for this km segment
                let segmentSamples = Array(sortedSamples[lastKmCrossingIndex...i])

                let hrs = segmentSamples.compactMap { $0.hr }
                let avgHR = hrs.isEmpty ? nil : hrs.reduce(0, +) / Double(hrs.count)

                let powers = segmentSamples.compactMap { $0.power }
                let avgPower = powers.isEmpty ? nil : powers.reduce(0, +) / Double(powers.count)

                let cadences = segmentSamples.compactMap { $0.cadence }
                let avgCadence = cadences.isEmpty ? nil : cadences.reduce(0, +) / Double(cadences.count)

                // Calculate elevation gain
                var elevGain: Double? = nil
                let altitudes = segmentSamples.compactMap { $0.altitude }
                if altitudes.count > 1 {
                    var gain = 0.0
                    for j in 1..<altitudes.count {
                        let diff = altitudes[j] - altitudes[j - 1]
                        if diff > 0 { gain += diff }
                    }
                    elevGain = gain > 0 ? gain : nil
                }

                let paceMin = Int(pace)
                let paceSec = Int((pace - Double(paceMin)) * 60)

                splits.append(SuuntoSplit(
                    kilometer: currentKm,
                    time: kmTime,
                    pace: pace,
                    averageHeartRate: avgHR,
                    averagePower: avgPower,
                    averageCadence: avgCadence,
                    elevationGain: elevGain
                ))

                print("   📏 Split km\(currentKm): \(String(format: "%.0f", kmTime))s = \(paceMin)'\(String(format: "%02d", paceSec))\"/km, HR: \(String(format: "%.0f", avgHR ?? 0)) bpm")

                lastKmCrossingTime = crossingTime
                lastKmCrossingIndex = i
                currentKm += 1
            }
        }

        // Handle final partial split (e.g., last 500m of a 10.5km run)
        if let lastSample = sortedSamples.last,
           lastKmCrossingIndex < sortedSamples.count - 1 {
            let lastDistance = lastSample.distance
            let previousKmDistance = Double(currentKm - 1) * 1000.0
            let partialDistance = lastDistance - previousKmDistance

            // Only add if partial distance is significant (> 100m)
            if partialDistance > 100 {
                let segmentSamples = Array(sortedSamples[lastKmCrossingIndex...])
                let endTime = lastSample.date
                let segmentTime = endTime.timeIntervalSince(lastKmCrossingTime)

                // Calculate pace normalized to 1km for comparison
                let pacePerKm = segmentTime / (partialDistance / 1000.0) / 60.0

                let hrs = segmentSamples.compactMap { $0.hr }
                let avgHR = hrs.isEmpty ? nil : hrs.reduce(0, +) / Double(hrs.count)

                let powers = segmentSamples.compactMap { $0.power }
                let avgPower = powers.isEmpty ? nil : powers.reduce(0, +) / Double(powers.count)

                let cadences = segmentSamples.compactMap { $0.cadence }
                let avgCadence = cadences.isEmpty ? nil : cadences.reduce(0, +) / Double(cadences.count)

                var elevGain: Double? = nil
                let altitudes = segmentSamples.compactMap { $0.altitude }
                if altitudes.count > 1 {
                    var gain = 0.0
                    for j in 1..<altitudes.count {
                        let diff = altitudes[j] - altitudes[j - 1]
                        if diff > 0 { gain += diff }
                    }
                    elevGain = gain > 0 ? gain : nil
                }

                let paceMin = Int(pacePerKm)
                let paceSec = Int((pacePerKm - Double(paceMin)) * 60)

                splits.append(SuuntoSplit(
                    kilometer: currentKm,
                    time: segmentTime,
                    pace: pacePerKm,
                    averageHeartRate: avgHR,
                    averagePower: avgPower,
                    averageCadence: avgCadence,
                    elevationGain: elevGain
                ))

                print("   📏 Split km\(currentKm) (partial \(String(format: "%.0f", partialDistance))m): \(String(format: "%.0f", segmentTime))s = \(paceMin)'\(String(format: "%02d", paceSec))\"/km, HR: \(String(format: "%.0f", avgHR ?? 0)) bpm")
            }
        }

        return splits
    }
}
