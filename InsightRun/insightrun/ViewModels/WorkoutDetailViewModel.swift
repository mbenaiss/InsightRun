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

    init(workout: WorkoutModel) {
        self.workout = workout
    }

    // MARK: - Actions

    func loadMetrics() async {
        isLoading = true
        errorMessage = nil

        // Check if workout comes from Strava (not in HealthKit)
        let isStravaWorkout = workout.sourceName.lowercased().contains("strava") ||
                              workout.metadata?["strava_id"] != nil

        if isStravaWorkout {
            // For Strava workouts, first create basic metrics, then fetch detailed data
            metrics = createMetricsFromWorkout()

            // Fetch detailed Strava data in background
            if let stravaIdString = workout.metadata?["strava_id"] as? String,
               let stravaId = Int64(stravaIdString) {
                await loadStravaDetailedData(activityId: stravaId)
            }
        } else {
            // For HealthKit workouts, fetch detailed metrics
            do {
                metrics = try await healthKitManager.fetchWorkoutMetrics(for: workout)
            } catch let error as HealthKitError {
                switch error {
                case .notAvailable:
                    errorMessage = "HealthKit n'est pas disponible sur cet appareil"
                case .authorizationDenied:
                    errorMessage = "Accès aux données HealthKit refusé. Veuillez autoriser l'accès dans Réglages"
                case .dataNotAvailable, .queryFailed:
                    // Fallback to basic metrics from WorkoutModel
                    // This can happen for indoor workouts or when detailed data is unavailable
                    metrics = createMetricsFromWorkout()
                }
            } catch {
                // Fallback to basic metrics for any error
                metrics = createMetricsFromWorkout()
            }
        }

        isLoading = false
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

        // Use averageSpeed from metadata if available (more accurate for Strava)
        let avgSpeed = avgSpeedFromMetadata ?? workout.averageSpeed

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
        let minutes = Int(pace)
        let seconds = Int((pace - Double(minutes)) * 60)
        return String(format: "%d'%02d\"/km", minutes, seconds)
    }

    func formatSpeed(_ speed: Double) -> String {
        return String(format: "%.1f km/h", speed)
    }

    func formatHeartRate(_ hr: Double) -> String {
        return String(format: "%.0f bpm", hr)
    }

    func formatDistance(_ meters: Double) -> String {
        let km = meters / 1000.0
        return String(format: "%.2f km", km)
    }

    func formatElevation(_ meters: Double) -> String {
        return String(format: "%.0f m", meters)
    }

    func formatPower(_ watts: Double) -> String {
        return String(format: "%.0f W", watts)
    }

    func formatCadence(_ spm: Double) -> String {
        return String(format: "%.0f spm", spm)
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
        return String(format: "%.1f%%", value)
    }
}
