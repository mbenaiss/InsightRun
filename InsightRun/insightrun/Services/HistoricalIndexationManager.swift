//
//  HistoricalIndexationManager.swift
//  InsightRun
//
//  Manager for historical workout indexation with real-time progress updates
//

import Foundation
import Combine

@MainActor
class HistoricalIndexationManager: ObservableObject {
    static let shared = HistoricalIndexationManager()

    // MARK: - Published State

    @Published var state: IndexationState = .idle
    @Published var progress: Double = 0
    @Published var currentWorkout: Int = 0
    @Published var totalWorkouts: Int = 0
    @Published var errorMessage: String?
    @Published var hasFailedOnce: Bool = false // Track if indexation failed at least once

    // MARK: - State Enum

    enum IndexationState: Equatable {
        case idle
        case preparing
        case indexing
        case generating
        case completed
        case failed
        case cancelled // State when user cancels indexation
        case retrying // State when retrying after a failure
    }

    // MARK: - Dependencies

    private let healthKitManager = HealthKitManager.shared
    private let backendClient = BackendAPIClient.shared
    private let summaryStorage = HistoricalSummaryStorage.shared

    // MARK: - Configuration

    private let maxWorkouts = 365
    private let model = "x-ai/grok-4-fast"

    // MARK: - Public API

    /// Reset state to idle (used for retry)
    func resetState() {
        print("🔄 HistoricalIndexationManager: Resetting state for retry...")
        state = .idle
        progress = 0
        currentWorkout = 0
        totalWorkouts = 0
        errorMessage = nil
    }

    /// Cancel ongoing indexation
    func cancel() {
        print("🛑 HistoricalIndexationManager: Cancelling indexation...")
        state = .cancelled
        errorMessage = String(localized: "Indexation cancelled by user", comment: "Message when user cancels indexation")
    }

    /// Perform historical indexation with progress updates
    func performIndexation() async throws {
        print("📊 HistoricalIndexationManager: Starting indexation...")

        // Reset state
        state = .preparing
        progress = 0
        currentWorkout = 0
        totalWorkouts = 0
        errorMessage = nil

        // Check for cancellation
        try Task.checkCancellation()

        // Step 1: Fetch workouts
        let workouts = try await fetchWorkouts()

        // Check for cancellation after fetching
        try Task.checkCancellation()

        guard !workouts.isEmpty else {
            throw IndexationError.noWorkouts
        }

        totalWorkouts = min(workouts.count, maxWorkouts)
        print("📊 HistoricalIndexationManager: Found \(workouts.count) workouts, will index \(totalWorkouts)")

        // Step 2: Convert workouts to API format
        state = .indexing
        let workoutDataList = try await convertWorkouts(workouts.prefix(maxWorkouts))

        // Check for cancellation after indexing
        try Task.checkCancellation()

        // Step 3: Generate summary via backend
        state = .generating
        progress = 0.8

        let summary = try await generateSummary(workoutDataList: Array(workoutDataList), workouts: Array(workouts.prefix(maxWorkouts)))

        // Check for cancellation after generation
        try Task.checkCancellation()

        // Step 4: Save summary
        summaryStorage.save(summary)

        // Step 5: Complete
        state = .completed
        progress = 1.0
        hasFailedOnce = false // Reset failure flag on success

        print("✅ HistoricalIndexationManager: Indexation completed successfully")
    }

    // MARK: - Private Methods

    private func fetchWorkouts() async throws -> [WorkoutModel] {
        do {
            let workouts = try await healthKitManager.fetchRunningWorkouts()
            return workouts
        } catch {
            print("❌ HistoricalIndexationManager: Failed to fetch workouts: \(error)")
            state = .failed
            errorMessage = String(localized: "Failed to fetch workouts from HealthKit", comment: "Error message when unable to fetch workouts from HealthKit")
            hasFailedOnce = true // Mark as failed
            throw IndexationError.healthKitError(error)
        }
    }

    private func convertWorkouts<C: Collection>(_ workouts: C) async throws -> [WorkoutData] where C.Element == WorkoutModel {
        var workoutDataList: [WorkoutData] = []
        let total = workouts.count

        for (index, workout) in workouts.enumerated() {
            // Check for cancellation in the loop
            try Task.checkCancellation()

            // Fetch essential metrics for each workout
            let metrics = try? await healthKitManager.fetchEssentialMetrics(for: workout)
            let workoutData = convertToWorkoutDataWithMetrics(workout: workout, metrics: metrics)
            workoutDataList.append(workoutData)

            // Update progress
            currentWorkout = index + 1
            progress = Double(index + 1) / Double(total) * 0.6 // 0-60% for indexing

            // Small delay to allow UI updates and check cancellation
            if index % 10 == 0 {
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
        }

        progress = 0.7 // Indexing phase complete

        return workoutDataList
    }

    private func generateSummary(workoutDataList: [WorkoutData], workouts: [WorkoutModel]) async throws -> HistoricalSummary {
        do {
            let language = getUserLanguage()

            // Fetch user health profile for personalized analysis
            let healthProfile = try? await healthKitManager.fetchHealthProfile()
            let profileData = healthProfile.map { profile in
                HealthProfileData(
                    age: profile.age,
                    sex: profile.biologicalSex.map { sex in
                        switch sex {
                        case .male: return "male"
                        case .female: return "female"
                        case .other: return "other"
                        case .notSet: return nil
                        @unknown default: return nil
                        }
                    } ?? nil,
                    bodyMass: profile.bodyMass,
                    bodyFatPercentage: profile.bodyFatPercentage,
                    exerciseTime: profile.exerciseTime.map { Int($0) },
                    cyclingDistance: profile.cyclingDistance,
                    swimmingDistance: profile.swimmingDistance
                )
            }

            let response = try await backendClient.generateHistoricalSummary(
                workouts: workoutDataList,
                profile: profileData,
                model: model,
                language: language
            )

            progress = 0.95

            let summary = HistoricalSummary(
                summary: response.summary,
                workoutCount: response.workoutCount,
                dateRangeStart: workouts.last?.startDate ?? Date(),
                dateRangeEnd: workouts.first?.startDate ?? Date()
            )

            return summary

        } catch {
            print("❌ HistoricalIndexationManager: Failed to generate summary: \(error)")
            state = .failed
            errorMessage = String(localized: "Failed to generate AI summary", comment: "Error message when unable to generate AI summary")
            hasFailedOnce = true // Mark as failed
            throw IndexationError.generationError(error)
        }
    }

    // MARK: - Helper Methods

    private func convertToWorkoutDataWithMetrics(
        workout: WorkoutModel,
        metrics: (heartRate: (avg: Double?, min: Double?, max: Double?)?, cadence: Int?, vo2Max: Double?, elevation: Double?)?
    ) -> WorkoutData {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        // Extract heart rate data if available
        let heartRateData: HeartRateData? = metrics?.heartRate.map { hr in
            HeartRateData(
                avg: hr.avg.map { Int($0) },
                min: hr.min.map { Int($0) },
                max: hr.max.map { Int($0) }
            )
        } ?? nil

        return WorkoutData(
            date: formatter.string(from: workout.startDate),
            duration: workout.duration,
            distance: workout.distance ?? 0,
            calories: workout.totalEnergyBurned,
            pace: workout.averagePace,
            speed: workout.averageSpeed,
            heartRate: heartRateData,
            minPace: nil, // Not essential for historical analysis
            cadence: metrics?.cadence,
            strideLength: nil, // Not essential for historical analysis
            runningPower: nil, // Not essential for historical analysis
            vo2Max: metrics?.vo2Max,
            elevationGain: metrics?.elevation,
            groundContactTime: nil, // Not essential for historical analysis
            verticalOscillation: nil, // Not essential for historical analysis
            mobility: nil, // Not essential for historical analysis
            splits: nil // Too detailed for historical analysis
        )
    }

    private func getUserLanguage() -> String {
        let preferredLanguage = Locale.current.language.languageCode?.identifier ?? "en"
        let supportedLanguages = ["fr", "en", "es", "de", "it", "pt", "nl", "ja", "zh", "ko", "ar"]
        return supportedLanguages.contains(preferredLanguage) ? preferredLanguage : "en"
    }

    // MARK: - Errors

    enum IndexationError: LocalizedError {
        case noWorkouts
        case healthKitError(Error)
        case generationError(Error)

        var errorDescription: String? {
            switch self {
            case .noWorkouts:
                return "No workouts found in HealthKit"
            case .healthKitError(let error):
                return "HealthKit error: \(error.localizedDescription)"
            case .generationError(let error):
                return "Generation error: \(error.localizedDescription)"
            }
        }
    }
}
