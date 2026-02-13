//
//  SuuntoWorkout.swift
//  InsightRun
//
//  Model for parsing FIT export files (Suunto, Garmin, etc.)
//

import Foundation
import CoreLocation
import FitFileParser

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
    case invalidFITFile(detail: String)
    case invalidDate(dateString: String)
    case missingRequiredFields(fields: [String])
    case fileReadFailed(path: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .invalidFITFile(let detail):
            return String(localized: "Invalid FIT file: \(detail). Ensure the file was exported from the Suunto app.", comment: "Suunto error: invalid FIT file")
        case .invalidDate(let dateString):
            return String(localized: "Could not parse workout date '\(dateString)'. Expected ISO8601 format.", comment: "Suunto error: invalid date")
        case .missingRequiredFields(let fields):
            return String(localized: "Missing required fields: \(fields.joined(separator: ", "))", comment: "Suunto error: missing fields")
        case .fileReadFailed(let path, let error):
            return String(localized: "Could not read file '\(path)': \(error.localizedDescription)", comment: "Suunto error: file read failed")
        }
    }
}

struct SuuntoParser {

    // Maximum samples to keep in memory (prevents memory issues for ultra-marathons)
    private static let maxSamplesInMemory = 2000

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

    static func parse(from url: URL) throws -> ParsedSuuntoWorkout {
        guard let fitFile = FitFile(file: url) else {
            throw SuuntoParserError.invalidFITFile(detail: "Could not open or parse the FIT file")
        }
        return try convert(fitFile)
    }

    /// Async version that loads and parses FIT file on background queue
    static func parseAsync(from url: URL) async throws -> ParsedSuuntoWorkout {
        let fitFile: FitFile? = await Task.detached(priority: .userInitiated) {
            FitFile(file: url)
        }.value

        guard let fitFile else {
            throw SuuntoParserError.fileReadFailed(path: url.lastPathComponent, underlying: NSError(
                domain: "SuuntoParser", code: 0,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "Could not parse FIT file", comment: "Suunto error: FIT parse failure")]
            ))
        }
        return try convert(fitFile)
    }

    // MARK: - FIT Conversion

    private static func convert(_ fitFile: FitFile) throws -> ParsedSuuntoWorkout {
        // Extract session data (summary)
        let sessions = fitFile.messages(forMessageType: FitMessageType.session)
        guard let session = sessions.first else {
            throw SuuntoParserError.missingRequiredFields(fields: ["session"])
        }

        let sessionFields = session.interpretedFields()

        // Start date
        guard let startDateValue = sessionFields["start_time"],
              let startDate = startDateValue.time else {
            throw SuuntoParserError.missingRequiredFields(fields: ["start_time"])
        }

        // Duration (seconds)
        let duration: TimeInterval
        if let totalTimer = sessionFields["total_timer_time"]?.valueUnit?.value {
            duration = totalTimer
        } else if let totalElapsed = sessionFields["total_elapsed_time"]?.valueUnit?.value {
            duration = totalElapsed
        } else {
            throw SuuntoParserError.missingRequiredFields(fields: ["total_timer_time"])
        }

        let endDate = startDate.addingTimeInterval(duration)

        // Distance (meters)
        let distance = sessionFields["total_distance"]?.valueUnit?.value ?? 0

        // Calories (kcal)
        let calories = sessionFields["total_calories"]?.valueUnit?.value ?? 0

        // Elevation
        let elevationGain = sessionFields["total_ascent"]?.valueUnit?.value ?? 0
        let elevationLoss = sessionFields["total_descent"]?.valueUnit?.value ?? 0

        // Heart rate from session
        let sessionAvgHR = sessionFields["avg_heart_rate"]?.valueUnit?.value
        let sessionMaxHR = sessionFields["max_heart_rate"]?.valueUnit?.value

        // Speed from session
        let sessionAvgSpeed = sessionFields["avg_speed"]?.valueUnit?.value
        let sessionMaxSpeed = sessionFields["max_speed"]?.valueUnit?.value

        // Running dynamics from session
        let sessionAvgCadence: Double? = {
            if let rpm = sessionFields["avg_running_cadence"]?.valueUnit?.value ?? sessionFields["avg_cadence"]?.valueUnit?.value {
                return rpm * 2.0 // rpm → spm
            }
            return nil
        }()
        let sessionAvgPower = sessionFields["avg_power"]?.valueUnit?.value
        let sessionAvgGCT = sessionFields["avg_stance_time"]?.valueUnit?.value
        let sessionAvgVO = sessionFields["avg_vertical_oscillation"]?.valueUnit?.value
        let sessionAvgStride = sessionFields["avg_step_length"]?.valueUnit?.value

        // Device info
        let deviceName: String = {
            let deviceInfos = fitFile.messages(forMessageType: FitMessageType.device_info)
            for info in deviceInfos {
                let fields = info.interpretedFields()
                if let name = fields["product_name"]?.name {
                    return name
                }
            }
            return "Suunto"
        }()

        // Activity type from session sport/sub_sport, fallback to sport message
        let activityType: String = {
            // 1) Try session-level sport field (most reliable)
            if let sportName = sessionFields["sport"]?.name, !sportName.isEmpty {
                // Combine with sub_sport for more precision (e.g. "running" + "trail" → "trail_running")
                if let subSport = sessionFields["sub_sport"]?.name, !subSport.isEmpty,
                   subSport != "generic" {
                    return "\(sportName)_\(subSport)"
                }
                return sportName
            }
            // 2) Fallback to sport message
            let sports = fitFile.messages(forMessageType: FitMessageType.sport)
            if let sport = sports.first {
                let fields = sport.interpretedFields()
                if let sportName = fields["sport"]?.name, !sportName.isEmpty {
                    if let subSport = fields["sub_sport"]?.name, !subSport.isEmpty,
                       subSport != "generic" {
                        return "\(sportName)_\(subSport)"
                    }
                    return sportName
                }
                if let name = fields["name"]?.name, !name.isEmpty {
                    return name
                }
            }
            return "Running"
        }()

        // MARK: - Record messages (time series)

        let records = fitFile.messages(forMessageType: FitMessageType.record)

        var heartRateSamples: [(date: Date, bpm: Double)] = []
        var cadenceSamples: [(date: Date, spm: Double)] = []
        var powerSamples: [(date: Date, watts: Double)] = []
        var altitudeSamples: [(date: Date, meters: Double)] = []
        var routeCoordinates: [CLLocationCoordinate2D] = []
        var distanceSamples: [DistanceSample] = []

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

        for record in records {
            let fields = record.interpretedFields()

            guard let timestampValue = fields["timestamp"],
                  let sampleDate = timestampValue.time else { continue }

            // Heart rate (bpm direct in FIT)
            if let hrValue = fields["heart_rate"]?.valueUnit?.value, hrValue > 30, hrValue < 250 {
                heartRateSamples.append((date: sampleDate, bpm: hrValue))
                hrSum += hrValue
                hrMax = max(hrMax, hrValue)
                hrCount += 1
            }

            // Speed (m/s)
            if let speed = fields["speed"]?.valueUnit?.value ?? fields["enhanced_speed"]?.valueUnit?.value, speed > 0 {
                speedSum += speed
                speedMax = max(speedMax, speed)
                speedCount += 1
            }

            // Cadence: FIT stores running cadence as rpm, convert to spm (×2)
            if let cadRpm = fields["cadence"]?.valueUnit?.value, cadRpm > 0 {
                let spm = cadRpm * 2.0
                if spm > 100, spm < 250 {
                    cadenceSamples.append((date: sampleDate, spm: spm))
                    cadenceSum += spm
                    cadenceCount += 1
                }
            }

            // Power (watts)
            if let power = fields["power"]?.valueUnit?.value, power > 0 {
                powerSamples.append((date: sampleDate, watts: power))
                powerSum += power
                powerCount += 1
            }

            // Altitude
            if let alt = fields["altitude"]?.valueUnit?.value ?? fields["enhanced_altitude"]?.valueUnit?.value {
                altitudeSamples.append((date: sampleDate, meters: alt))
            }

            // GPS coordinates — FitFileParser merges position_lat + position_long
            // into a single "position" field with .coordinate type
            if let posField = fields["position"],
               let coord = posField.coordinate {
                routeCoordinates.append(coord)
            }

            // Distance for split calculation
            if let dist = fields["distance"]?.valueUnit?.value, dist > 0 {
                let hrBpm = findClosestHR(for: sampleDate, in: heartRateSamples)
                let cadSpm: Double? = {
                    if let c = fields["cadence"]?.valueUnit?.value, c > 0 { return c * 2.0 }
                    return nil
                }()
                let alt = fields["altitude"]?.valueUnit?.value ?? fields["enhanced_altitude"]?.valueUnit?.value
                distanceSamples.append(DistanceSample(
                    date: sampleDate,
                    distance: dist,
                    hr: hrBpm,
                    power: fields["power"]?.valueUnit?.value,
                    cadence: cadSpm,
                    altitude: alt
                ))
            }
        }

        print("   💓 HR samples collected: \(heartRateSamples.count), matched to distance samples: \(distanceSamples.filter { $0.hr != nil }.count)/\(distanceSamples.count)")

        // MARK: - Splits from Lap messages (fallback to calculated)

        let lapMessages = fitFile.messages(forMessageType: FitMessageType.lap)
        var splits: [SuuntoSplit] = []

        if !lapMessages.isEmpty {
            for (index, lap) in lapMessages.enumerated() {
                let lapFields = lap.interpretedFields()

                let lapTime = lapFields["total_timer_time"]?.valueUnit?.value
                    ?? lapFields["total_elapsed_time"]?.valueUnit?.value ?? 0
                let lapDistance = lapFields["total_distance"]?.valueUnit?.value ?? 1000.0

                let pace = lapDistance > 0 ? (lapTime / (lapDistance / 1000.0)) / 60.0 : 0

                let avgHR = lapFields["avg_heart_rate"]?.valueUnit?.value
                let avgPower = lapFields["avg_power"]?.valueUnit?.value
                let avgCadence: Double? = {
                    if let c = lapFields["avg_running_cadence"]?.valueUnit?.value ?? lapFields["avg_cadence"]?.valueUnit?.value {
                        return c * 2.0
                    }
                    return nil
                }()
                let elevGain = lapFields["total_ascent"]?.valueUnit?.value

                let paceMin = Int(pace)
                let paceSec = Int((pace - Double(paceMin)) * 60)

                splits.append(SuuntoSplit(
                    kilometer: index + 1,
                    time: lapTime,
                    pace: pace,
                    averageHeartRate: avgHR,
                    averagePower: avgPower,
                    averageCadence: avgCadence,
                    elevationGain: elevGain
                ))

                print("   📏 Split km\(index + 1): \(String(format: "%.0f", lapTime))s = \(paceMin)'\(String(format: "%02d", paceSec))\"/km, HR: \(String(format: "%.0f", avgHR ?? 0)) bpm")
            }
        }

        // Fallback: calculate splits from distance samples if no laps
        if splits.isEmpty {
            splits = calculateSplits(from: distanceSamples, workoutStartDate: startDate)
        }

        // Calculate averages from records (use session values as fallback)
        let averageHeartRate = hrCount > 0 ? hrSum / Double(hrCount) : sessionAvgHR
        let maxHeartRate = hrMax > 0 ? hrMax : sessionMaxHR
        let averageSpeed = speedCount > 0 ? speedSum / Double(speedCount) : sessionAvgSpeed
        let maxSpeed = speedMax > 0 ? speedMax : sessionMaxSpeed
        let averageCadence = cadenceCount > 0 ? cadenceSum / Double(cadenceCount) : sessionAvgCadence
        let averagePower = powerCount > 0 ? powerSum / Double(powerCount) : sessionAvgPower

        // Running dynamics from session (not typically in records)
        let avgGroundContactTime = sessionAvgGCT
        let avgVerticalOscillation: Double? = {
            if let vo = sessionAvgVO {
                // FIT stores VO in mm, convert to cm
                return vo / 10.0
            }
            return nil
        }()
        let avgStrideLength: Double? = {
            if let stride = sessionAvgStride {
                // FIT stores step_length in mm, convert to meters
                return stride / 1000.0
            }
            return nil
        }()

        print("🔍 DEBUG FIT Parser:")
        print("   Device: \(deviceName)")
        print("   Activity: \(activityType)")
        print("   Cadence (from records): \(averageCadence ?? -1) spm (\(cadenceCount) samples)")
        print("   Power (from records): \(averagePower ?? -1) W (\(powerCount) samples)")
        print("   Stride (from session): \(avgStrideLength ?? -1) m")
        print("   GCT (from session): \(avgGroundContactTime ?? -1) ms")
        print("   VO (from session): \(avgVerticalOscillation ?? -1) cm")

        // Downsample large arrays to prevent memory issues
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
            duration: duration,
            distance: distance,
            calories: calories,
            elevationGain: elevationGain,
            elevationLoss: elevationLoss,
            averageHeartRate: averageHeartRate,
            maxHeartRate: maxHeartRate,
            averageSpeed: averageSpeed,
            maxSpeed: maxSpeed,
            averageGroundContactTime: avgGroundContactTime,
            averageVerticalOscillation: avgVerticalOscillation,
            averageStrideLength: avgStrideLength,
            averageCadence: averageCadence,
            averagePower: averagePower,
            vo2Max: nil, // Not available in standard FIT fields
            epoc: nil,
            trainingEffect: nil,
            routeCoordinates: downsampledRoute,
            hasRoute: !routeCoordinates.isEmpty,
            heartRateSamples: downsampledHR,
            cadenceSamples: downsampledCadence,
            powerSamples: downsampledPower,
            altitudeSamples: downsampledAltitude,
            splits: splits,
            deviceName: deviceName,
            activityType: activityType,
            feeling: nil,
            notes: nil
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
    /// HR and Distance samples may be in the same record, but we still match by timestamp for consistency
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
