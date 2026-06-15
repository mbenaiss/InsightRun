//
//  WorkoutDetailViewModel.swift
//  InsightRun
//
//  ViewModel for the workout detail screen
//

import SwiftUI
import Combine

@MainActor
class WorkoutDetailViewModel: ObservableObject {
    @Published var metrics: WorkoutMetrics?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isLoadingDetails = false

    private let healthKitManager = HealthKitManager.shared
    private let stravaAPIClient = StravaAPIClient.shared
    private let workout: WorkoutModel
    private var retryCount = 0
    private let maxRetries = 2

    init(workout: WorkoutModel) {
        self.workout = workout
    }

    // MARK: - Actions

    func loadMetrics() async {
        isLoading = true
        errorMessage = nil

        let stravaId: Int64? = (workout.metadata?["strava_id"] as? String).flatMap { Int64($0) }

        // A Strava-only workout was reconstructed with sourceName "Strava" and has
        // no HealthKit backing. A merged workout carries a strava_id but keeps its
        // HealthKit source (e.g. "Apple Watch"), so we must still load HK route,
        // intervals and HR samples on top of the Strava detail.
        let isStravaOnly = workout.sourceName.lowercased().contains("strava")
        let isMerged = !isStravaOnly && stravaId != nil

        if isStravaOnly {
            metrics = createMetricsFromWorkout()

            if let stravaId {
                await loadStravaDetailedData(activityId: stravaId)
            }
        } else {
            do {
                metrics = try await healthKitManager.fetchWorkoutMetrics(for: workout)
            } catch let error as HealthKitError {
                switch error {
                case .notAvailable:
                    errorMessage = String(localized: "HealthKit is not available on this device")
                case .authorizationDenied:
                    errorMessage = String(localized: "HealthKit data access denied. Please grant access in Settings")
                case .dataNotAvailable, .queryFailed:
                    // Fallback to basic metrics from WorkoutModel
                    // This can happen for indoor workouts or when detailed data is unavailable
                    metrics = createMetricsFromWorkout()
                }
            } catch {
                // Fallback to basic metrics for any error
                metrics = createMetricsFromWorkout()
            }

            // Merged workout: layer Strava splits/elevation on top of HK metrics.
            if isMerged, let stravaId {
                await loadStravaDetailedData(activityId: stravaId)
            }
        }

        // Enrich with Suunto data if available (fills gaps where HealthKit has no data)
        enrichWithSuuntoData()

        isLoading = false

        // Retry if metrics are incomplete (e.g. opened from notification before
        // HealthKit sync). Skip the retry for runs that simply never recorded HR
        // (no watch): retrying re-fetches everything twice for nothing.
        let canHaveHeartRate = workout.averageHeartRate != nil || workout.maxHeartRate != nil
        if !isStravaOnly && metricsIncomplete && canHaveHeartRate && retryCount < maxRetries {
            retryCount += 1
            do {
                try await Task.sleep(for: .seconds(10))
                await loadMetrics()
            } catch {
                return
            }
        }
    }

    private var metricsIncomplete: Bool {
        guard let m = metrics else { return true }
        return m.averageHeartRate == nil && m.splits == nil
    }

    // MARK: - Suunto Enrichment

    private func enrichWithSuuntoData() {
        guard var currentMetrics = metrics else { return }
        var metadata = workout.metadata

        // If no Suunto data in metadata, try to find matching Suunto workout from cache
        if metadata?["suunto_device"] == nil {
            print("⌚ No Suunto metadata, checking cache for matching workout...")
            if let suuntoData = findMatchingSuuntoWorkout() {
                metadata = suuntoData
                print("✅ Found matching Suunto workout in cache!")
            }
        }

        // Debug: print all suunto metadata
        print("🔍 DEBUG Suunto metadata:")
        print("   suunto_device: \(metadata?["suunto_device"] ?? "nil")")
        print("   suunto_avg_hr: \(metadata?["suunto_avg_hr"] ?? "nil")")
        print("   suunto_max_hr: \(metadata?["suunto_max_hr"] ?? "nil")")
        print("   suunto_cadence: \(metadata?["suunto_cadence"] ?? "nil")")
        print("   suunto_power: \(metadata?["suunto_power"] ?? "nil")")
        print("   suunto_stride_length: \(metadata?["suunto_stride_length"] ?? "nil")")
        print("   suunto_vo2max: \(metadata?["suunto_vo2max"] ?? "nil")")
        print("   suunto_ground_contact_time: \(metadata?["suunto_ground_contact_time"] ?? "nil")")
        print("   suunto_vertical_oscillation: \(metadata?["suunto_vertical_oscillation"] ?? "nil")")

        // Only enrich if Suunto data is present
        guard metadata?["suunto_device"] != nil else {
            print("⚠️ No Suunto device in metadata, skipping enrichment")
            return
        }

        print("⌚ Enriching metrics with Suunto data...")

        // Heart Rate - prefer Suunto data if available
        if let avgHR = metadata?["suunto_avg_hr"] as? Double {
            currentMetrics.averageHeartRate = avgHR
            print("   + Avg HR: \(avgHR) bpm")
        }
        if let maxHR = metadata?["suunto_max_hr"] as? Double {
            currentMetrics.maxHeartRate = maxHR
            print("   + Max HR: \(maxHR) bpm")
        }

        // Cadence (Suunto provides spm directly)
        if currentMetrics.averageCadence == nil,
           let cadence = metadata?["suunto_cadence"] as? Double {
            currentMetrics.averageCadence = cadence
            print("   + Cadence: \(cadence) spm")
        }

        // Running Power
        if currentMetrics.runningPower == nil,
           let power = metadata?["suunto_power"] as? Double {
            currentMetrics.runningPower = power
            print("   + Power: \(power) W")
        }

        // Ground Contact Time
        if currentMetrics.groundContactTime == nil,
           let gct = metadata?["suunto_ground_contact_time"] as? Double {
            currentMetrics.groundContactTime = gct
            print("   + GCT: \(gct) ms")
        }

        // Vertical Oscillation
        if currentMetrics.verticalOscillation == nil,
           let vo = metadata?["suunto_vertical_oscillation"] as? Double {
            currentMetrics.verticalOscillation = vo
            print("   + Vertical Osc: \(vo) cm")
        }

        // Stride Length
        if currentMetrics.strideLength == nil,
           let stride = metadata?["suunto_stride_length"] as? Double {
            currentMetrics.strideLength = stride
            print("   + Stride: \(stride) m")
        }

        // VO2max
        if currentMetrics.vo2Max == nil,
           let vo2max = metadata?["suunto_vo2max"] as? Double {
            currentMetrics.vo2Max = vo2max
            print("   + VO2max: \(vo2max) ml/kg/min")
        }

        // Splits: Use Suunto splits if HealthKit splits are missing or all identical
        if let suuntoSplitsData = metadata?["suunto_splits"] as? [[String: Any]], !suuntoSplitsData.isEmpty {
            let needsSuuntoSplits = shouldUseSuuntoSplits(currentSplits: currentMetrics.splits)
            print("   📏 Suunto splits available: \(suuntoSplitsData.count), needs replacement: \(needsSuuntoSplits)")

            if needsSuuntoSplits {
                let suuntoSplits = suuntoSplitsData.compactMap { dict -> Split? in
                    guard let km = dict["km"] as? Int,
                          let time = dict["time"] as? Double,
                          let pace = dict["pace"] as? Double else { return nil }
                    return Split(
                        kilometer: km,
                        distance: 1000, // Each split is ~1km
                        time: time,
                        pace: pace,
                        averageHeartRate: dict["hr"] as? Double,
                        averagePower: dict["power"] as? Double,
                        elevationGain: dict["elev"] as? Double,
                        elevationLoss: nil
                    )
                }
                if !suuntoSplits.isEmpty {
                    currentMetrics.splits = suuntoSplits
                    print("   + Replaced splits with \(suuntoSplits.count) Suunto splits")
                    for split in suuntoSplits {
                        print("     km\(split.kilometer): \(formatPace(split.pace))")
                    }
                }
            }
        }

        metrics = currentMetrics
    }

    /// Determine if we should use Suunto splits instead of HealthKit splits
    /// Returns true if HealthKit splits are missing, empty, or all have identical pace (approximated)
    private func shouldUseSuuntoSplits(currentSplits: [Split]?) -> Bool {
        guard let splits = currentSplits, splits.count > 1 else {
            return true // No splits or only one split - use Suunto
        }

        // Check if all paces are identical (within 0.01 min/km tolerance)
        let paces = splits.map { $0.pace }
        let firstPace = paces[0]
        let allIdentical = paces.allSatisfy { abs($0 - firstPace) < 0.01 }

        if allIdentical {
            print("   ⚠️ All HealthKit splits have identical pace (\(formatPace(firstPace))) - using Suunto splits")
        }

        return allIdentical
    }

    // MARK: - Strava Detailed Data

    private func loadStravaDetailedData(activityId: Int64) async {
        isLoadingDetails = true

        do {
            print("📡 Fetching detailed Strava data for activity \(activityId)...")
            let detailedActivity = try await stravaAPIClient.fetchActivity(id: activityId)

            // Convert Strava splits to app's Split model
            let splits = convertStravaSplits(detailedActivity.splitsMetric)

            // Update metrics with detailed data
            if var currentMetrics = metrics {
                // Update with detailed data
                if let avgSpeed = detailedActivity.averageSpeed {
                    currentMetrics.averageSpeed = avgSpeed * 3.6 // m/s to km/h
                }
                if let maxSpeed = detailedActivity.maxSpeed {
                    currentMetrics.maxSpeed = maxSpeed * 3.6 // m/s to km/h
                }
                if let avgHR = detailedActivity.averageHeartrate {
                    currentMetrics.averageHeartRate = avgHR
                }
                if let maxHR = detailedActivity.maxHeartrate {
                    currentMetrics.maxHeartRate = maxHR
                }
                if let cadence = detailedActivity.averageCadence {
                    currentMetrics.averageCadence = cadence * 2 // Strava reports single-leg, we want spm
                }

                // Update elevation from detailed activity
                if detailedActivity.totalElevationGain > 0 {
                    currentMetrics.totalElevationAscent = detailedActivity.totalElevationGain
                }

                // Calculate min pace (best pace) from splits
                if let splits = splits, !splits.isEmpty {
                    let minPace = splits.map { $0.pace }.min()
                    currentMetrics.minPace = minPace
                }

                // Add splits
                currentMetrics.splits = splits

                metrics = currentMetrics
                print("✅ Loaded detailed Strava data: \(splits?.count ?? 0) splits, elevation: \(detailedActivity.totalElevationGain)m")
            }
        } catch {
            print("⚠️ Failed to load detailed Strava data: \(error.localizedDescription)")
            // Don't show error to user - basic metrics still work
        }

        isLoadingDetails = false
    }

    private func convertStravaSplits(_ stravaSplits: [StravaSplit]?) -> [Split]? {
        guard let stravaSplits = stravaSplits, !stravaSplits.isEmpty else { return nil }

        return stravaSplits.map { stravaSplit in
            Split(
                kilometer: stravaSplit.split,
                distance: stravaSplit.distance,
                time: TimeInterval(stravaSplit.movingTime),
                pace: stravaSplit.pace ?? 0,
                averageHeartRate: stravaSplit.averageHeartrate,
                averagePower: nil,
                elevationGain: stravaSplit.elevationDifference != nil && stravaSplit.elevationDifference! > 0 ? stravaSplit.elevationDifference : nil,
                elevationLoss: stravaSplit.elevationDifference != nil && stravaSplit.elevationDifference! < 0 ? abs(stravaSplit.elevationDifference!) : nil
            )
        }
    }

    /// Create basic WorkoutMetrics from WorkoutModel data (for Strava workouts or fallback)
    private func createMetricsFromWorkout() -> WorkoutMetrics {
        // Extract Strava-specific data from metadata
        let maxSpeed = workout.metadata?["max_speed"] as? Double
        let avgSpeedFromMetadata = workout.metadata?["average_speed"] as? Double

        // Convert maxSpeed from m/s to km/h for display
        let maxSpeedKmh: Double? = maxSpeed.map { $0 * 3.6 }

        // Strava metadata speeds are in m/s; convert to km/h to match the
        // WorkoutMetrics.averageSpeed contract. workout.averageSpeed is already km/h.
        let avgSpeed = avgSpeedFromMetadata.map { $0 * 3.6 } ?? workout.averageSpeed

        return WorkoutMetrics(
            workout: workout,
            averageHeartRate: workout.averageHeartRate,
            minHeartRate: nil,
            maxHeartRate: workout.maxHeartRate,
            firstHeartRate: nil,
            lastHeartRate: nil,
            heartRateZones: nil,
            averagePace: workout.averagePace,
            minPace: nil,
            maxPace: nil,
            averageSpeed: avgSpeed,
            maxSpeed: maxSpeedKmh,
            totalSteps: nil,
            averageCadence: nil,
            strideLength: nil,
            runningPower: nil,
            firstPower: nil,
            lastPower: nil,
            totalElevationAscent: workout.elevationGain,
            totalElevationDescent: nil,
            splits: nil,
            routePoints: nil,
            groundContactTime: nil,
            groundContactTimeBalance: nil,
            verticalOscillation: nil,
            runningEfficiency: nil
        )
    }

    // MARK: - Formatting Helpers

    func formatPace(_ pace: Double) -> String {
        Formatters.paceFromMinutesPerKm(pace)
    }

    func formatSpeed(_ speed: Double) -> String {
        // speed is already km/h; Formatters.speed expects m/s.
        Formatters.speed(metersPerSecond: speed / 3.6)
    }

    func formatHeartRate(_ hr: Double) -> String {
        Formatters.heartRate(hr)
    }

    func formatDistance(_ meters: Double) -> String {
        Formatters.distance(km: meters / 1000.0)
    }

    func formatElevation(_ meters: Double) -> String {
        Formatters.elevation(meters: meters)
    }

    func formatPower(_ watts: Double) -> String {
        return String(format: "%.0f W", watts)
    }

    func formatCadence(_ spm: Double) -> String {
        Formatters.cadence(spm)
    }

    func formatStrideLength(_ meters: Double) -> String {
        return String(format: "%.2f m", meters)
    }

    func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    func formatPercentage(_ value: Double) -> String {
        Formatters.percent(value, fractionDigits: 1)
    }

    // MARK: - Suunto Cache Lookup

    /// Find matching Suunto workout from cache and return its metadata
    private func findMatchingSuuntoWorkout() -> [String: Any]? {
        let suuntoService = SuuntoImportService.shared

        do {
            let cachedWorkouts = try suuntoService.fetchAllCachedWorkouts()
            let tolerance: TimeInterval = 5 * 60 // 5 minutes

            for parsed in cachedWorkouts {
                let timeDiff = abs(workout.startDate.timeIntervalSince(parsed.startDate))

                if timeDiff < tolerance {
                    // Check duration similarity (within 5%)
                    let durationDiff = abs(workout.duration - parsed.duration) / max(workout.duration, parsed.duration)
                    if durationDiff < 0.05 {
                        // Found match! Build metadata dictionary
                        return buildSuuntoMetadata(from: parsed)
                    }
                }
            }
        } catch {
            print("⚠️ Could not load Suunto cache: \(error.localizedDescription)")
        }

        return nil
    }

    /// Build Suunto metadata dictionary from parsed workout
    private func buildSuuntoMetadata(from parsed: ParsedSuuntoWorkout) -> [String: Any] {
        var metadata: [String: Any] = [:]

        metadata["suunto_device"] = parsed.deviceName

        // Heart rate
        if let avgHR = parsed.averageHeartRate {
            metadata["suunto_avg_hr"] = avgHR
        }
        if let maxHR = parsed.maxHeartRate {
            metadata["suunto_max_hr"] = maxHR
        }

        if let cadence = parsed.averageCadence {
            metadata["suunto_cadence"] = cadence
        }
        if let power = parsed.averagePower {
            metadata["suunto_power"] = power
        }
        if let stride = parsed.averageStrideLength {
            metadata["suunto_stride_length"] = stride
        }
        if let vo2max = parsed.vo2Max {
            metadata["suunto_vo2max"] = vo2max
        }
        if let gct = parsed.averageGroundContactTime {
            metadata["suunto_ground_contact_time"] = gct
        }
        if let vo = parsed.averageVerticalOscillation {
            metadata["suunto_vertical_oscillation"] = vo
        }

        // Splits
        if !parsed.splits.isEmpty {
            let splitsData = parsed.splits.map { split -> [String: Any] in
                var dict: [String: Any] = [
                    "km": split.kilometer,
                    "time": split.time,
                    "pace": split.pace
                ]
                if let hr = split.averageHeartRate { dict["hr"] = hr }
                if let power = split.averagePower { dict["power"] = power }
                if let cadence = split.averageCadence { dict["cadence"] = cadence }
                if let elev = split.elevationGain { dict["elev"] = elev }
                return dict
            }
            metadata["suunto_splits"] = splitsData
        }

        return metadata
    }
}
