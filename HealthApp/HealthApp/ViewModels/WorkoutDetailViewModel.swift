//
//  WorkoutDetailViewModel.swift
//  HealthApp
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

        do {
            metrics = try await healthKitManager.fetchWorkoutMetrics(for: workout)
        } catch {
            errorMessage = "Impossible de charger les détails: \(error.localizedDescription)"
        }

        isLoading = false
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
