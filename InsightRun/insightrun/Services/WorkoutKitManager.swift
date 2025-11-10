//
//  WorkoutKitManager.swift
//  InsightRun
//
//  Service for creating and exporting custom workouts to Apple Fitness app via WorkoutKit
//

import Foundation
import WorkoutKit
import HealthKit
import Combine

enum WorkoutKitError: LocalizedError {
    case invalidWorkout
    case workoutKitNotAvailable
    case authorizationDenied
    case exportFailed(Error)
    case unsupportedSportType
    case tooManySteps

    var errorDescription: String? {
        switch self {
        case .invalidWorkout:
            return String(localized: "The workout is invalid and cannot be exported", comment: "Error when workout data is invalid")
        case .workoutKitNotAvailable:
            return String(localized: "WorkoutKit is not available on this device", comment: "Error when WorkoutKit is not supported")
        case .authorizationDenied:
            return String(localized: "Access to export workouts was denied. Please allow authorization when prompted again.", comment: "Error when WorkoutKit authorization is denied")
        case .exportFailed(let error):
            return String(localized: "Failed to export workout: %@", comment: "Error when export fails").replacingOccurrences(of: "%@", with: error.localizedDescription)
        case .unsupportedSportType:
            return String(localized: "This sport type is not supported yet", comment: "Error when sport type is not supported")
        case .tooManySteps:
            return String(localized: "Workout has too many steps (max 50)", comment: "Error when workout has too many steps")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .authorizationDenied:
            return String(localized: "To re-authorize, you may need to delete and reinstall the app, then allow access when prompted. Alternatively, open the Fitness app on your iPhone or Apple Watch to check connected apps.", comment: "Recovery suggestion for authorization denied")
        default:
            return nil
        }
    }
}

@MainActor
class WorkoutKitManager: ObservableObject {
    static let shared = WorkoutKitManager()

    @Published var isExporting = false
    @Published var exportError: WorkoutKitError?

    private init() {}

    // MARK: - Create Custom Workout

    /// Convert AIGeneratedWorkout to WorkoutKit CustomWorkout
    func createCustomWorkout(from aiWorkout: AIGeneratedWorkout) throws -> CustomWorkout {
        // Validate workout
        guard aiWorkout.isValid else {
            throw WorkoutKitError.invalidWorkout
        }

        guard aiWorkout.steps.count <= 50 else {
            throw WorkoutKitError.tooManySteps
        }

        // Convert sport type to HKWorkoutActivityType
        let activityType: HKWorkoutActivityType
        switch aiWorkout.sport {
        case .running:
            activityType = .running
        case .cycling:
            activityType = .cycling
        case .swimming:
            throw WorkoutKitError.unsupportedSportType // Not supported in MVP
        }

        // Build interval blocks from steps
        var blocks: [IntervalBlock] = []

        for step in aiWorkout.steps {
            let intervalStep = try convertToIntervalStep(step)
            let block = IntervalBlock(steps: [intervalStep], iterations: 1)
            blocks.append(block)
        }

        // Create custom workout
        let customWorkout = CustomWorkout(
            activity: activityType,
            location: .outdoor,
            displayName: aiWorkout.name,
            warmup: nil, // Warmup is included in blocks
            blocks: blocks,
            cooldown: nil // Cooldown is included in blocks
        )

        print("✅ WorkoutKitManager: Created custom workout '\(aiWorkout.name)' with \(blocks.count) steps")

        return customWorkout
    }

    // MARK: - Convert Steps

    /// Convert WorkoutStep to WorkoutKit IntervalStep
    private func convertToIntervalStep(_ step: WorkoutStep) throws -> IntervalStep {
        // Determine if this is work or recovery
        let purpose: IntervalStep.Purpose = step.type == .recovery ? .recovery : .work

        // Create alert for pace and/or heart rate zone
        let alert = createWorkoutAlert(for: step)

        // Create WorkoutKit WorkoutStep based on goal type
        let workoutKitStep: WorkoutKit.WorkoutStep

        switch step.goal.type {
        case .distance:
            let meters = step.goal.value
            let goal = WorkoutKit.WorkoutGoal.distance(meters, UnitLength.meters)
            workoutKitStep = WorkoutKit.WorkoutStep(goal: goal, alert: alert)

        case .duration:
            let seconds = step.goal.value
            let goal = WorkoutKit.WorkoutGoal.time(seconds, UnitDuration.seconds)
            workoutKitStep = WorkoutKit.WorkoutStep(goal: goal, alert: alert)

        case .open:
            let goal = WorkoutKit.WorkoutGoal.open
            workoutKitStep = WorkoutKit.WorkoutStep(goal: goal, alert: alert)
        }

        // Create IntervalStep with purpose and workout step
        return IntervalStep(purpose, step: workoutKitStep)
    }

    /// Create WorkoutAlert from target pace and/or heart rate zone
    private func createWorkoutAlert(for step: WorkoutStep) -> (any WorkoutAlert)? {
        // Priority 1: Pace (convert to speed range)
        // For most workouts, pace is the primary target
        if let paceString = step.targetPace {
            if let speedRange = convertPaceToSpeedRange(paceString) {
                return SpeedRangeAlert.speed(speedRange, unit: UnitSpeed.metersPerSecond, metric: .current)
            }
        }

        // Priority 2: Heart rate zone
        // Only use HR zone if no pace is specified
        if let hrZone = step.targetHeartRateZone {
            return HeartRateZoneAlert.heartRate(zone: hrZone)
        }

        return nil
    }

    /// Convert pace string (e.g., "4:30") to speed range in m/s
    /// Returns a range with ±5% tolerance
    private func convertPaceToSpeedRange(_ paceString: String) -> ClosedRange<Double>? {
        // Parse pace format "4:30" or "4:30/km"
        let cleanPace = paceString.replacingOccurrences(of: "/km", with: "").trimmingCharacters(in: .whitespaces)
        let components = cleanPace.split(separator: ":")

        guard components.count == 2,
              let minutes = Double(components[0]),
              let seconds = Double(components[1]) else {
            return nil
        }

        // Convert pace to speed
        let totalSecondsPerKm = (minutes * 60) + seconds
        let speedKmPerHour = 3600 / totalSecondsPerKm // km/h
        let speedMetersPerSecond = speedKmPerHour * 1000 / 3600 // m/s

        // Create range with ±5% tolerance
        let tolerance = 0.05
        let minSpeed = speedMetersPerSecond * (1 - tolerance)
        let maxSpeed = speedMetersPerSecond * (1 + tolerance)

        return minSpeed...maxSpeed
    }

    // MARK: - Authorization

    /// Check current authorization status
    func checkAuthorizationStatus() async -> Bool {
        let authState = await WorkoutScheduler.shared.authorizationState
        return authState == .authorized
    }

    /// Request authorization to export workouts to Fitness app
    func requestAuthorization() async throws {
        let authState = await WorkoutScheduler.shared.requestAuthorization()

        guard authState == .authorized else {
            throw WorkoutKitError.authorizationDenied
        }
    }

    // MARK: - Export to Fitness App

    /// Export workout to Apple Fitness app
    func exportToFitnessApp(_ workout: AIGeneratedWorkout) async throws {
        await MainActor.run {
            isExporting = true
            exportError = nil
        }

        do {
            // Request authorization if needed
            let authState = await WorkoutScheduler.shared.requestAuthorization()

            guard authState == .authorized else {
                throw WorkoutKitError.authorizationDenied
            }

            print("✅ WorkoutKitManager: WorkoutKit authorization granted")

            // Create custom workout
            let customWorkout = try createCustomWorkout(from: workout)

            // Create workout plan
            let workoutPlan = WorkoutPlan(.custom(customWorkout))

            // Schedule workout for immediate availability (now)
            let now = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: Date())
            await WorkoutScheduler.shared.schedule(workoutPlan, at: now)

            print("✅ WorkoutKitManager: Workout '\(workout.name)' exported successfully to Fitness app")
            print("📱 Check the Fitness app or Apple Watch Workout app to see your scheduled workout")

            // Track analytics
            AnalyticsService.shared.trackWorkoutExported(
                workoutName: workout.name,
                sport: workout.sport.rawValue,
                stepCount: workout.steps.count,
                totalDistance: workout.totalDistance,
                estimatedDuration: workout.estimatedDuration
            )

            await MainActor.run {
                isExporting = false
            }

        } catch {
            print("❌ WorkoutKitManager: Failed to export workout - \(error)")

            let workoutError = WorkoutKitError.exportFailed(error)

            await MainActor.run {
                exportError = workoutError
                isExporting = false
            }

            // Track error
            AnalyticsService.shared.trackWorkoutExportFailed(
                workoutName: workout.name,
                errorType: "export_failed",
                errorMessage: error.localizedDescription
            )

            throw workoutError
        }
    }

    // MARK: - Utility

    /// Check if WorkoutKit is available
    var isWorkoutKitAvailable: Bool {
        if #available(iOS 17.0, *) {
            return true
        }
        return false
    }

    /// Get available workout activities
    var availableActivities: [HKWorkoutActivityType] {
        return [.running, .cycling]
    }
}

// MARK: - Analytics Extension

extension AnalyticsService {
    func trackWorkoutExported(workoutName: String, sport: String, stepCount: Int, totalDistance: Double?, estimatedDuration: TimeInterval?) {
        var properties: [String: Any] = [
            "workout_name": workoutName,
            "sport": sport,
            "step_count": stepCount
        ]

        if let distance = totalDistance {
            properties["total_distance_m"] = distance
        }

        if let duration = estimatedDuration {
            properties["estimated_duration_s"] = duration
        }

        track(.workoutExported, properties: properties)
    }

    func trackWorkoutExportFailed(workoutName: String, errorType: String, errorMessage: String) {
        track(.workoutExportFailed, properties: [
            "workout_name": workoutName,
            "error_type": errorType,
            "error_message": errorMessage
        ])
    }

    func trackWorkoutGenerationRequested(prompt: String, userLevel: String?) {
        var properties: [String: Any] = [
            "prompt_length": prompt.count
        ]

        if let level = userLevel {
            properties["user_level"] = level
        }

        track(.workoutGenerationRequested, properties: properties)
    }

    func trackWorkoutGenerated(workoutName: String, generationTimeMs: Int, modelUsed: String) {
        track(.workoutGenerated, properties: [
            "workout_name": workoutName,
            "generation_time_ms": generationTimeMs,
            "model_used": modelUsed
        ])
    }

    func trackWorkoutGenerationFailed(errorType: String, errorMessage: String) {
        track(.workoutGenerationFailed, properties: [
            "error_type": errorType,
            "error_message": errorMessage
        ])
    }
}
