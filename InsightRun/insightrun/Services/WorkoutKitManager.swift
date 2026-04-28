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
            return String(localized: "Workout export requires authorization. Open the Fitness app on your iPhone or Apple Watch, then try again.", comment: "Error when WorkoutKit authorization is denied")
        case .exportFailed(let error):
            let underlying = error.localizedDescription
            return String(localized: "Failed to export workout: \(underlying). Make sure WorkoutKit is authorized — try opening the Apple Watch Workout app first.", comment: "Error when export fails with guidance")
        case .unsupportedSportType:
            return String(localized: "This sport type is not supported yet", comment: "Error when sport type is not supported")
        case .tooManySteps:
            return String(localized: "Workout has too many steps (max 50)", comment: "Error when workout has too many steps")
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
        // Validate workout with detailed logging
        print("🔍 WorkoutKitManager: Validating workout '\(aiWorkout.name)'")
        print("   - Name: '\(aiWorkout.name)' (isEmpty: \(aiWorkout.name.isEmpty))")
        print("   - Steps count: \(aiWorkout.steps.count) (max: 50)")
        print("   - Total distance: \(aiWorkout.totalDistance ?? 0)m")
        print("   - Estimated duration: \(aiWorkout.estimatedDuration ?? 0)s")

        for (index, step) in aiWorkout.steps.enumerated() {
            print("   - Step \(index + 1): type=\(step.type.rawValue), goal=\(step.goal.type.rawValue)(\(step.goal.value)), isValid=\(step.isValid)")
            if !step.isValid {
                print("      ⚠️ Invalid step: goalValid=\(step.goal.isValid), hrZone=\(step.targetHeartRateZone ?? -1)")
            }
        }

        guard aiWorkout.isValid else {
            print("❌ WorkoutKitManager: Workout validation failed")
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

        // Separate warmup, cooldown, and main blocks.
        // When a work/interval step has repetitions > 1 and is immediately
        // followed by a recovery step, both are grouped into a single
        // IntervalBlock with iterations = repetitions — so a "6×800m récup
        // 400m" workout becomes ONE block of (800m + 400m) repeated 6 times,
        // not 6 separate blocks. This matches Apple Fitness's native rendering.
        var warmupWorkoutStep: WorkoutKit.WorkoutStep?
        var cooldownWorkoutStep: WorkoutKit.WorkoutStep?
        var blocks: [IntervalBlock] = []

        var i = 0
        while i < aiWorkout.steps.count {
            let step = aiWorkout.steps[i]

            if step.type == .warmup, warmupWorkoutStep == nil {
                warmupWorkoutStep = try convertToWorkoutStep(step)
                i += 1
                continue
            }
            if step.type == .cooldown {
                cooldownWorkoutStep = try convertToWorkoutStep(step)
                i += 1
                continue
            }

            let iterations = max(step.repetitions ?? 1, 1)
            var blockSteps = [try convertToIntervalStep(step)]
            if iterations > 1,
               i + 1 < aiWorkout.steps.count,
               aiWorkout.steps[i + 1].type == .recovery {
                blockSteps.append(try convertToIntervalStep(aiWorkout.steps[i + 1]))
                i += 1
            }
            blocks.append(IntervalBlock(steps: blockSteps, iterations: iterations))
            i += 1
        }

        // Create custom workout with proper warmup and cooldown
        let customWorkout = CustomWorkout(
            activity: activityType,
            location: .outdoor,
            displayName: aiWorkout.name,
            warmup: warmupWorkoutStep,
            blocks: blocks,
            cooldown: cooldownWorkoutStep
        )

        let totalSteps = (warmupWorkoutStep != nil ? 1 : 0) + blocks.count + (cooldownWorkoutStep != nil ? 1 : 0)
        print("✅ WorkoutKitManager: Created custom workout '\(aiWorkout.name)' with \(totalSteps) steps (warmup: \(warmupWorkoutStep != nil), blocks: \(blocks.count), cooldown: \(cooldownWorkoutStep != nil))")

        return customWorkout
    }

    // MARK: - Convert Steps

    /// Convert WorkoutStep to WorkoutKit WorkoutStep (for warmup/cooldown)
    private func convertToWorkoutStep(_ step: WorkoutStep) throws -> WorkoutKit.WorkoutStep {
        // Create alert for pace and/or heart rate zone
        let alert = createWorkoutAlert(for: step)

        // Create WorkoutKit WorkoutStep based on goal type
        switch step.goal.type {
        case .distance:
            let meters = step.goal.value
            let goal = WorkoutKit.WorkoutGoal.distance(meters, UnitLength.meters)
            return WorkoutKit.WorkoutStep(goal: goal, alert: alert)

        case .duration:
            let seconds = step.goal.value
            let goal = WorkoutKit.WorkoutGoal.time(seconds, UnitDuration.seconds)
            return WorkoutKit.WorkoutStep(goal: goal, alert: alert)

        case .open:
            let goal = WorkoutKit.WorkoutGoal.open
            return WorkoutKit.WorkoutStep(goal: goal, alert: alert)
        }
    }

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
        // Priority 1: Pace
        // Check if pace range is specified (min/max)
        if let paceMin = step.targetPaceMin, let paceMax = step.targetPaceMax {
            if let speedRange = convertPaceRangeToSpeedRange(paceMin, paceMax) {
                // Use SpeedRangeAlert for pace range
                return SpeedRangeAlert.speed(speedRange, unit: UnitSpeed.metersPerSecond, metric: .current)
            }
        }

        // Otherwise check for single pace value
        if let paceString = step.targetPace {
            if let speed = convertPaceToSpeed(paceString) {
                // Use SpeedThresholdAlert for exact pace target
                return SpeedThresholdAlert.speed(speed, unit: UnitSpeed.metersPerSecond, metric: .current)
            }
        }

        // Priority 2: Heart rate zone
        // Only use HR zone if no pace is specified
        if let hrZone = step.targetHeartRateZone {
            return HeartRateZoneAlert.heartRate(zone: hrZone)
        }

        return nil
    }

    /// Convert pace string (e.g., "4:30") to speed in m/s
    /// Returns exact speed value for use with SpeedThresholdAlert
    private func convertPaceToSpeed(_ paceString: String) -> Double? {
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

        return speedMetersPerSecond
    }

    /// Convert pace range (e.g., "6:52" to "7:22") to speed range in m/s
    /// Returns a range for use with SpeedRangeAlert
    private func convertPaceRangeToSpeedRange(_ paceMin: String, _ paceMax: String) -> ClosedRange<Double>? {
        guard let minSpeed = convertPaceToSpeed(paceMax), // Slower pace = lower speed
              let maxSpeed = convertPaceToSpeed(paceMin) else { // Faster pace = higher speed
            return nil
        }

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

        } catch let error as WorkoutKitError {
            print("❌ WorkoutKitManager: Failed to export workout - \(error)")

            await MainActor.run {
                exportError = error
                isExporting = false
            }

            AnalyticsService.shared.trackWorkoutExportFailed(
                workoutName: workout.name,
                errorType: String(describing: error),
                errorMessage: error.localizedDescription,
                debugInfo: exportDebugInfo(workout: workout, error: error)
            )

            throw error
        } catch {
            print("❌ WorkoutKitManager: Failed to export workout - \(error)")

            let workoutError = WorkoutKitError.exportFailed(error)

            await MainActor.run {
                exportError = workoutError
                isExporting = false
            }

            AnalyticsService.shared.trackWorkoutExportFailed(
                workoutName: workout.name,
                errorType: "export_failed",
                errorMessage: error.localizedDescription,
                debugInfo: exportDebugInfo(workout: workout, error: error)
            )

            throw workoutError
        }
    }

    // MARK: - Debug Info

    /// Collect diagnostic information for export failures
    private func exportDebugInfo(workout: AIGeneratedWorkout, error: Error) -> [String: Any] {
        var info: [String: Any] = [
            "step_count": workout.steps.count,
            "sport": workout.sport.rawValue,
            "has_total_distance": workout.totalDistance != nil,
            "has_estimated_duration": workout.estimatedDuration != nil,
            "debug_error": String(describing: error),
            "error_type_full": String(reflecting: type(of: error))
        ]

        // Extract NSError domain/code for system errors
        let nsError = error as NSError
        info["ns_error_domain"] = nsError.domain
        info["ns_error_code"] = nsError.code
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            info["underlying_domain"] = underlying.domain
            info["underlying_code"] = underlying.code
            info["underlying_description"] = underlying.localizedDescription
        }

        // WorkoutKit authorization state (check synchronously via last known)
        if let exportError = error as? WorkoutKitError {
            switch exportError {
            case .authorizationDenied:
                info["failure_stage"] = "authorization"
            case .invalidWorkout:
                info["failure_stage"] = "validation"
                // Log which steps are invalid
                let invalidSteps = workout.steps.enumerated()
                    .filter { !$0.element.isValid }
                    .map { "step_\($0.offset):\($0.element.type.rawValue)" }
                info["invalid_steps"] = invalidSteps.joined(separator: ",")
            case .exportFailed:
                info["failure_stage"] = "schedule"
            case .tooManySteps:
                info["failure_stage"] = "validation_too_many_steps"
            default:
                info["failure_stage"] = "unknown"
            }
        }

        return info
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

    func trackWorkoutExportFailed(workoutName: String, errorType: String, errorMessage: String, debugInfo: [String: Any] = [:]) {
        var properties: [String: Any] = [
            "workout_name": workoutName,
            "error_type": errorType,
            "error_message": errorMessage
        ]
        // Merge debug info for root cause analysis
        for (key, value) in debugInfo {
            properties["debug_\(key)"] = value
        }
        track(.workoutExportFailed, properties: properties)
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
