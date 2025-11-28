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

    private let healthKitManager = HealthKitManager.shared
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
            // For Strava workouts, create metrics from available WorkoutModel data
            metrics = createMetricsFromWorkout()
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

    /// Create basic WorkoutMetrics from WorkoutModel data (for Strava workouts or fallback)
    private func createMetricsFromWorkout() -> WorkoutMetrics {
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
            averageSpeed: workout.averageSpeed,
            maxSpeed: nil,
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
