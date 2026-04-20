//
//  BatchIndexationManager.swift
//  InsightRun
//
//  Manager for orchestrating workout indexation by batches
//  Processes up to 365 workouts in batches of 50 to avoid memory issues
//

import Foundation
import Combine
import HealthKit
import UIKit

// MARK: - Indexation State

enum IndexationState: Equatable {
    case idle
    case loading(progress: Double)
    case completed
    case failed(String)
    case cancelled

    var isActive: Bool {
        switch self {
        case .loading:
            return true
        default:
            return false
        }
    }
}

// MARK: - Configuration

struct BatchIndexationConfig {
    static let batchSize = 50
    static let maxWorkouts = 365
    static let checkCancellationEvery = 5

    // Progress weights (total = 100%)
    static let batchProcessingWeight = 0.70  // 0-70%
    static let consolidationWeight = 0.30    // 70-100%
}

// MARK: - Batch Indexation Manager

@MainActor
class BatchIndexationManager: ObservableObject {
    static let shared = BatchIndexationManager()

    // MARK: - Published Properties

    @Published var progress: Double = 0.0
    @Published var state: IndexationState = .idle
    @Published var currentBatch: Int = 0
    @Published var totalBatches: Int = 0
    @Published var hasFailedOnce: Bool = false // Track if indexation failed at least once
    @Published var needsConsent: Bool = false
    @Published var retryCount: Int = 0
    @Published var retryDisabled: Bool = false
    @Published var needsManualHealthKitSetup: Bool = false
    @Published var needsGuidedAccessDisabled: Bool = false
    @Published var skippedWorkoutCount: Int = 0

    // MARK: - Private Properties

    private var isCancelled = false
    private var indexationStartTime: Date?
    private var lastErrorRetryable = true
    private var currentPhase: String = "idle"
    private var totalWorkoutCount: Int = 0
    private var lastBatchWorkoutCount: Int = 0
    static let maxRetries = 3
    private let healthKitManager = HealthKitManager.shared
    private let backendClient = BackendAPIClient.shared
    private let storage = HistoricalSummaryStorage.shared

    private init() {}

    // MARK: - Public Methods

    /// Start the indexation process
    func startIndexation() async throws {
        guard state != .loading(progress: 0.0) else {
            print("⚠️ BatchIndexationManager: Indexation already in progress")
            return
        }

        // Check AI consent before sending data to backend
        guard ConsentService.shared.hasConsentedToAIDataSharing else {
            needsConsent = true
            return
        }

        currentPhase = "preflight"

        // Guided Access blocks HealthKit's privacy UI *and* "Open Settings".
        // Surface a dedicated state instead of letting indexation fail with an
        // opaque UIViewServiceHostSession error and polluting analytics.
        if UIAccessibility.isGuidedAccessEnabled {
            needsGuidedAccessDisabled = true
            state = .failed(String(localized: "Guided Access is active. Triple-click the side button to disable it, then try again.", comment: "Indexation guided access active error"))
            lastErrorRetryable = false
            return
        }

        isCancelled = false
        state = .loading(progress: 0.0)
        progress = 0.0
        indexationStartTime = Date()
        totalWorkoutCount = 0
        lastBatchWorkoutCount = 0
        skippedWorkoutCount = 0

        do {
            // Step 0: Verify HealthKit availability and authorization
            currentPhase = "healthkit_auth"
            guard healthKitManager.isHealthDataAvailable else {
                throw IndexationError.healthKitNotAvailable
            }

            if !healthKitManager.isHealthKitAuthorized {
                try await healthKitManager.requestAuthorization()
            }

            // Step 1: Fetch total workouts
            currentPhase = "fetch_workouts"
            print("📊 BatchIndexationManager: Fetching workouts from HealthKit...")
            let allWorkouts = try await healthKitManager.fetchRunningWorkouts()

            guard !isCancelled else {
                state = .cancelled
                return
            }

            // Limit to max workouts and sort by date (most recent first)
            let allCandidates = Array(allWorkouts.prefix(BatchIndexationConfig.maxWorkouts))
            totalWorkoutCount = allCandidates.count

            // Backend Zod enforces `duration > 0` on every workout. Third-party
            // imports (Strava/Garmin/manual entries) occasionally land in
            // HealthKit with zero or NaN duration — drop them pre-flight so one
            // malformed record doesn't reject a whole 50-workout batch.
            let workoutsToProcess = allCandidates.filter { $0.duration.isFinite && $0.duration > 0 }
            let preflightDropped = allCandidates.count - workoutsToProcess.count
            if preflightDropped > 0 {
                skippedWorkoutCount += preflightDropped
                print("⚠️ BatchIndexationManager: \(preflightDropped) workouts excluded (invalid duration)")
            }

            // No workouts: save an empty summary and complete
            if workoutsToProcess.isEmpty {
                let emptySummary = HistoricalSummary(
                    summary: "",
                    generatedDate: Date(),
                    indexedAt: Date(),
                    version: 1,
                    workoutCount: 0,
                    dateRangeStart: Date(),
                    dateRangeEnd: Date()
                )
                storage.save(emptySummary)
                progress = 1.0
                state = .completed
                print("✅ BatchIndexationManager: No workouts found, saved empty summary")
                return
            }

            print("📊 BatchIndexationManager: Processing \(workoutsToProcess.count) workouts...")

            // Step 2: Calculate batches
            totalBatches = Int(ceil(Double(workoutsToProcess.count) / Double(BatchIndexationConfig.batchSize)))
            print("📊 BatchIndexationManager: Will process \(totalBatches) batches, then consolidate")

            // Track indexation started
            AnalyticsService.shared.trackIndexationStarted(
                workoutsCount: workoutsToProcess.count,
                totalBatches: totalBatches
            )

            var batchSummaries: [String] = []
            var lastSkippedError: BackendError?
            let batchRequestType = RequestType.batchProcessing.rawValue // Backend selects optimal model
            let consolidationRequestType = RequestType.moderate.rawValue // Backend selects optimal model
            let language = AppLanguage.current

            // Step 3: Process batches
            for batchIndex in 0..<totalBatches {
                guard !isCancelled else {
                    state = .cancelled
                    return
                }

                currentBatch = batchIndex + 1
                currentPhase = "batch_\(currentBatch)_of_\(totalBatches)"
                print("📊 BatchIndexationManager: Processing batch \(currentBatch)/\(totalBatches) with requestType: \(batchRequestType)...")

                let startIndex = batchIndex * BatchIndexationConfig.batchSize
                let endIndex = min(startIndex + BatchIndexationConfig.batchSize, workoutsToProcess.count)
                let batchWorkouts = Array(workoutsToProcess[startIndex..<endIndex])

                // Convert batch workouts to WorkoutData
                let batchData = try await processBatch(batchWorkouts)
                lastBatchWorkoutCount = batchData.count

                do {
                    let batchResponse = try await backendClient.analyzeBatch(
                        workouts: batchData,
                        batchIndex: batchIndex,
                        requestType: batchRequestType,
                        model: nil, // Backend will select model
                        language: language
                    )
                    batchSummaries.append(batchResponse.partialSummary)
                } catch let backendError as BackendError where Self.isClient4xx(backendError) {
                    // Client-side rejection (typically a malformed workout).
                    // Skip the batch, track for diagnostics, keep indexing —
                    // a partial summary beats a hard failure for the user.
                    skippedWorkoutCount += batchWorkouts.count
                    lastSkippedError = backendError
                    AnalyticsService.shared.track(
                        .indexationFailed,
                        properties: indexationDebugInfo(error: backendError, categorizedMessage: "skipped_batch_4xx")
                    )
                    print("⚠️ BatchIndexationManager: Batch \(currentBatch) skipped (\(backendError.localizedDescription)) — \(batchWorkouts.count) workouts excluded")
                }

                // Update progress (0-70%) regardless of success/skip
                let batchProgress = Double(currentBatch) / Double(totalBatches)
                progress = batchProgress * BatchIndexationConfig.batchProcessingWeight
                state = .loading(progress: progress)

                AnalyticsService.shared.trackIndexationBatchProcessed(
                    batchNumber: currentBatch,
                    totalBatches: totalBatches,
                    progress: progress
                )

                print("📊 BatchIndexationManager: Batch \(currentBatch) completed (\(Int(progress * 100))%)")
            }

            // If every batch was rejected by the server, surface the last
            // error so the user sees something — otherwise we'd consolidate
            // an empty list and fail in a more confusing way.
            if batchSummaries.isEmpty, let lastSkippedError {
                throw lastSkippedError
            }

            guard !isCancelled else {
                state = .cancelled
                return
            }

            // Step 4: Consolidation
            currentPhase = "consolidation"
            print("📊 BatchIndexationManager: Starting final consolidation...")
            state = .loading(progress: 0.70)
            progress = 0.70

            let indexedWorkoutCount = workoutsToProcess.count - skippedWorkoutCount
            try await consolidateAndSave(
                batchSummaries: batchSummaries,
                totalWorkouts: indexedWorkoutCount,
                requestType: consolidationRequestType,
                language: language
            )

            // Step 5: Complete
            currentPhase = "completed"
            progress = 1.0
            state = .completed

            let duration = indexationStartTime.map { Date().timeIntervalSince($0) } ?? 0
            AnalyticsService.shared.trackIndexationCompleted(
                workoutsCount: indexedWorkoutCount,
                durationSeconds: duration,
                totalBatches: totalBatches
            )

            if skippedWorkoutCount > 0 {
                print("✅ BatchIndexationManager: Indexation completed — \(skippedWorkoutCount) workouts excluded (\(indexedWorkoutCount)/\(workoutsToProcess.count) indexed)")
            } else {
                print("✅ BatchIndexationManager: Indexation completed successfully!")
            }

        } catch {
            print("❌ BatchIndexationManager: Indexation failed: \(error)")
            let categorizedMessage = categorizeError(error)
            let errorDesc = error.localizedDescription
            lastErrorRetryable = !isNonRetryableError(error)
            let lowered = errorDesc.lowercased()
            needsManualHealthKitSetup = lowered.contains("uiviewservicehostsession") || lowered.contains("inaccessible")
            state = .failed(categorizedMessage)
            hasFailedOnce = true

            AnalyticsService.shared.track(.indexationFailed, properties: indexationDebugInfo(error: error, categorizedMessage: categorizedMessage))

            throw error
        }
    }

    /// Cancel the current indexation
    func cancel() {
        guard state.isActive else { return }

        print("⚠️ BatchIndexationManager: Cancelling indexation...")
        isCancelled = true
        state = .cancelled

        // Track indexation cancelled
        AnalyticsService.shared.trackIndexationCancelled(
            cancelledAtBatch: currentBatch,
            totalBatches: totalBatches,
            progress: progress
        )
    }

    /// Retry after failure with exponential backoff
    func retry() async throws {
        guard case .failed = state else {
            print("⚠️ BatchIndexationManager: Can only retry after failure")
            return
        }

        // Check if max retries exceeded
        guard retryCount < Self.maxRetries else {
            print("⚠️ BatchIndexationManager: Max retries (\(Self.maxRetries)) reached")
            state = .failed(String(localized: "Indexation failed after multiple attempts. Please try again later.", comment: "Indexation max retry error"))
            retryDisabled = true
            return
        }

        // Check if error is not retryable (auth/permission)
        guard lastErrorRetryable else {
            print("⚠️ BatchIndexationManager: Non-retryable error, blocking retry")
            retryDisabled = true
            return
        }

        retryCount += 1

        // Exponential backoff: 2s, 5s, 15s
        let backoffSeconds: [UInt64] = [2, 5, 15]
        let delay = backoffSeconds[min(retryCount - 1, backoffSeconds.count - 1)]
        print("⏱️ BatchIndexationManager: Retry \(retryCount)/\(Self.maxRetries) after \(delay)s backoff...")

        retryDisabled = true
        try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
        retryDisabled = false

        try await startIndexation()
    }

    /// HTTP 4xx client errors (excluding 408 Timeout and 429 Rate Limit) —
    /// retrying the same payload yields the same result.
    static func isClient4xx(_ error: BackendError) -> Bool {
        if case .unknownError(let code, _) = error {
            return (400..<500).contains(code) && code != 408 && code != 429
        }
        return false
    }

    /// Check if an error is not worth retrying (client-side issues that
    /// won't self-heal: auth/permission errors, malformed payloads, etc.)
    private func isNonRetryableError(_ error: Error) -> Bool {
        if let backendError = error as? BackendError {
            switch backendError {
            case .unauthorized, .blocked, .invalidResponse:
                return true
            case .unknownError:
                return Self.isClient4xx(backendError)
            case .rateLimitExceeded, .serverError:
                return false
            }
        }

        let nonRetryableKeywords = [
            "authorization", "permission", "consent", "denied", "not available",
            "inaccessible", "uiviewservicehostsession"
        ]
        let lowered = error.localizedDescription.lowercased()
        return nonRetryableKeywords.contains { lowered.contains($0) }
    }

    /// Reset state
    func reset() {
        isCancelled = false
        progress = 0.0
        state = .idle
        currentBatch = 0
        totalBatches = 0
        retryCount = 0
        retryDisabled = false
        lastErrorRetryable = true
        needsManualHealthKitSetup = false
        needsGuidedAccessDisabled = false
        currentPhase = "idle"
        totalWorkoutCount = 0
        lastBatchWorkoutCount = 0
        skippedWorkoutCount = 0
    }

    // MARK: - Private Methods

    /// Collect diagnostic info for indexation failures
    private func indexationDebugInfo(error: Error, categorizedMessage: String) -> [String: Any] {
        var props: [String: Any] = [
            "error_type": String(describing: type(of: error)),
            "error_message": error.localizedDescription,
            "debug_error_full": String(describing: error),
            "retry_count": retryCount,
            "categorized_message": categorizedMessage,
            "is_retryable": lastErrorRetryable,
            "phase": currentPhase,
            "total_workout_count": totalWorkoutCount,
            "last_batch_workout_count": lastBatchWorkoutCount,
            "skipped_workout_count": skippedWorkoutCount
        ]

        if let startTime = indexationStartTime {
            props["elapsed_seconds"] = Int(Date().timeIntervalSince(startTime))
        }

        if currentBatch > 0 { props["failed_at_batch"] = currentBatch }
        if totalBatches > 0 { props["total_batches"] = totalBatches }

        let nsError = error as NSError
        props["ns_error_domain"] = nsError.domain
        props["ns_error_code"] = nsError.code
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            props["underlying_domain"] = underlying.domain
            props["underlying_code"] = underlying.code
        }

        if let urlError = error as? URLError {
            props["url_error_code"] = urlError.code.rawValue
            props["url_error_url"] = urlError.failingURL?.absoluteString ?? "nil"
        }

        if let backendError = error as? BackendError {
            props["backend_error"] = String(describing: backendError)
            if case .unknownError(let code, let body) = backendError {
                props["http_status_code"] = code
                if let body = body { props["http_response_body"] = body }
            }
        }

        return props
    }

    /// Categorize errors into user-friendly messages
    private func categorizeError(_ error: Error) -> String {
        let description = error.localizedDescription.lowercased()

        // Network errors — retryable
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return String(localized: "No internet connection. Please check your network and try again.", comment: "Indexation network error")
            case .timedOut:
                return String(localized: "The request timed out. Please try again.", comment: "Indexation timeout error")
            case .cancelled:
                // -999: request cancelled, typically because the app was
                // backgrounded mid-request during a long batch call.
                return String(localized: "Indexation was interrupted. Keep the app open and try again.", comment: "Indexation cancelled error")
            default:
                return String(localized: "A network error occurred. Please try again.", comment: "Indexation generic network error")
            }
        }

        // Backend rejected the payload (HTTP 4xx) — retrying won't help
        if let backendError = error as? BackendError,
           case .unknownError(let code, _) = backendError,
           (400..<500).contains(code) {
            return String(localized: "One of your workouts contains invalid data. Please contact support.", comment: "Indexation backend 4xx error")
        }

        // Auth/permission errors — not retryable
        if description.contains("authorization") || description.contains("permission") || description.contains("denied") {
            return String(localized: "Permission error. Please check HealthKit access in Settings > Health.", comment: "Indexation permission error")
        }

        // iOS system dialog crash (UIViewServiceHostSession)
        if description.contains("uiviewservicehostsession") || description.contains("inaccessible") {
            return String(localized: "HealthKit authorization could not be completed. Please go to Settings > Health > Insight Run to grant access manually, then try again.", comment: "Indexation iOS dialog crash error")
        }

        // HealthKit errors — not retryable
        if error is IndexationError {
            return error.localizedDescription
        }

        // Default
        return error.localizedDescription
    }

    /// Process a batch of workouts
    private func processBatch(_ workouts: [WorkoutModel]) async throws -> [WorkoutData] {
        var workoutDataArray: [WorkoutData] = []

        for (index, workout) in workouts.enumerated() {
            // Check cancellation every N workouts
            if index % BatchIndexationConfig.checkCancellationEvery == 0 {
                guard !isCancelled else {
                    throw IndexationError.cancelled
                }
            }

            // Fetch essential metrics (use try? to continue on error)
            let metrics = try? await healthKitManager.fetchEssentialMetrics(for: workout)

            // Clamp numeric fields to what the backend Zod schema accepts:
            // `distance` must be >= 0, any number must be finite (NaN/Inf from
            // third-party imports gets serialized to null and rejected).
            let safeDistance = max(workout.distance ?? 0, 0)
            let safeCalories = workout.totalEnergyBurned.flatMap { $0.isFinite ? max($0, 0) : nil }

            let workoutData = WorkoutData(
                date: ISO8601DateFormatter().string(from: workout.startDate),
                duration: workout.duration,
                distance: safeDistance,
                calories: safeCalories,
                pace: workout.averagePace,
                speed: workout.averageSpeed,
                heartRate: metrics?.heartRate.map { hr in
                    HeartRateData(
                        avg: hr.avg.map { Int($0.rounded()) },
                        min: hr.min.map { Int($0.rounded()) },
                        max: hr.max.map { Int($0.rounded()) }
                    )
                },
                minPace: nil,
                cadence: metrics?.cadence,
                strideLength: nil,
                runningPower: nil,
                vo2Max: metrics?.vo2Max,
                elevationGain: metrics?.elevation,
                groundContactTime: nil,
                verticalOscillation: nil,
                mobility: nil,
                splits: nil
            )

            workoutDataArray.append(workoutData)
        }

        return workoutDataArray
    }

    /// Consolidate all batch summaries and save final summary
    private func consolidateAndSave(batchSummaries: [String], totalWorkouts: Int, requestType: String, language: String) async throws {
        guard !batchSummaries.isEmpty else {
            throw IndexationError.noWorkoutsToConsolidate
        }

        // Update progress
        progress = 0.75
        state = .loading(progress: progress)

        // Fetch health profile
        let healthProfile = try? await healthKitManager.fetchHealthProfile()
        let profileData = healthProfile.map { profile in
            HealthProfileData(
                age: profile.age,
                sex: profile.biologicalSex.map { sex in
                    switch sex {
                    case HKBiologicalSex.male: return "male"
                    case HKBiologicalSex.female: return "female"
                    default: return "other"
                    }
                },
                bodyMass: profile.bodyMass,
                bodyFatPercentage: profile.bodyFatPercentage,
                exerciseTime: profile.exerciseTime.map { Int($0) },
                cyclingDistance: profile.cyclingDistance,
                swimmingDistance: profile.swimmingDistance
            )
        }

        // Update progress
        progress = 0.80
        state = .loading(progress: progress)

        // Call backend for consolidation
        print("📊 BatchIndexationManager: Consolidating \(batchSummaries.count) batch summaries with requestType: \(requestType)...")

        let response = try await backendClient.consolidateBatches(
            batchSummaries: batchSummaries,
            totalWorkouts: totalWorkouts,
            profile: profileData,
            requestType: requestType,
            model: nil, // Backend will select model
            language: language
        )

        // Update progress
        progress = 0.90
        state = .loading(progress: progress)

        // Get date range from HealthKit workouts
        let allWorkouts = try await healthKitManager.fetchRunningWorkouts()
        let workoutsToIndex = Array(allWorkouts.prefix(totalWorkouts))

        let dateRangeStart = workoutsToIndex.last?.startDate ?? Date() // Oldest
        let dateRangeEnd = workoutsToIndex.first?.startDate ?? Date() // Most recent

        // Create and save summary
        let summary = HistoricalSummary(
            summary: response.summary,
            workoutCount: response.workoutCount,
            dateRangeStart: dateRangeStart,
            dateRangeEnd: dateRangeEnd
        )

        storage.save(summary)

        // Update progress
        progress = 1.0
        state = .loading(progress: progress)

        print("✅ BatchIndexationManager: Summary saved successfully")
    }
}

// MARK: - Errors

enum IndexationError: LocalizedError {
    case noWorkoutsFound
    case noWorkoutsToConsolidate
    case cancelled
    case batchProcessingFailed(String)
    case consolidationFailed(String)
    case healthKitNotAvailable

    var errorDescription: String? {
        switch self {
        case .noWorkoutsFound:
            return String(localized: "No workouts found in HealthKit")
        case .noWorkoutsToConsolidate:
            return String(localized: "No workout data to consolidate")
        case .cancelled:
            return String(localized: "Indexation was cancelled")
        case .batchProcessingFailed(let message):
            return String(localized: "Batch processing failed: \(message)")
        case .consolidationFailed(let message):
            return String(localized: "Consolidation failed: \(message)")
        case .healthKitNotAvailable:
            return String(localized: "HealthKit is not available. Please grant access in Settings > Health to analyze your workouts.")
        }
    }
}
