//
//  BatchIndexationManager.swift
//  InsightRun
//
//  Manager for orchestrating workout indexation by batches
//  Processes up to 365 workouts in batches of 50 to avoid memory issues
//

import Foundation
import Combine
import CryptoKit
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
    static let batchSize = 100
    static let maxWorkouts = 365
    static let checkCancellationEvery = 5

    /// Concurrency caps. Per-workout HealthKit fetches overlap their I/O; batch
    /// uploads overlap their network + LLM latency. Bounded so we neither flood
    /// HealthKit with hundreds of simultaneous queries nor trip the backend's
    /// per-IP rate limit.
    static let metricsConcurrency = 6
    static let uploadConcurrency = 3

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
    @Published var isResuming: Bool = false // Resuming a previously interrupted run

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
    private let progressStore = IndexationProgressStore.shared
    private static let iso8601Formatter = ISO8601DateFormatter()

    // Progress accounting (drives the continuous progress bar across the
    // concurrent metric-fetch and upload phases, including resumed work).
    private var metricsFetchedCount = 0
    private var uploadedBatchCount = 0
    private var resumedWorkoutCount = 0
    private var resumedBatchCount = 0

    // Background task assertion so a brief backgrounding doesn't kill an
    // in-flight batch before it can finish and persist.
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    private init() {}

    // MARK: - Public Methods

    /// Start the indexation process
    func startIndexation() async throws {
        guard !state.isActive else {
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
        metricsFetchedCount = 0
        uploadedBatchCount = 0
        resumedWorkoutCount = 0
        resumedBatchCount = 0
        isResuming = false

        // Keep indexation alive for a short grace period if the user briefly
        // backgrounds the app, so an in-flight batch can finish and persist.
        beginBackgroundTask()
        defer { endBackgroundTask() }

        do {
            // Step 0: Verify HealthKit availability and authorization
            currentPhase = "healthkit_auth"
            guard healthKitManager.isHealthDataAvailable else {
                throw IndexationError.healthKitNotAvailable
            }

            // Only present the system permission sheet if setup was never completed.
            // Re-requesting on every retry re-probes HealthKit needlessly (iOS never
            // re-shows the dialog) and pollutes permission analytics.
            if !healthKitManager.hasCompletedHealthKitSetup {
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

            // Backend Zod enforces `duration > 0` on every workout. Third-party
            // imports (Strava/Garmin/manual entries) occasionally land in
            // HealthKit with zero or NaN duration — drop them pre-flight so one
            // malformed record doesn't reject a whole batch.
            let workoutsToProcess = allCandidates.filter { $0.duration.isFinite && $0.duration > 0 }
            totalWorkoutCount = workoutsToProcess.count
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
                progressStore.clearAll()
                progress = 1.0
                state = .completed
                print("✅ BatchIndexationManager: No workouts found, saved empty summary")
                return
            }

            print("📊 BatchIndexationManager: Processing \(workoutsToProcess.count) workouts...")

            // Step 2: Calculate batches
            totalBatches = Int(ceil(Double(workoutsToProcess.count) / Double(BatchIndexationConfig.batchSize)))

            let language = AppLanguage.current
            let userId = UserIdentityService.shared.userID
            let signature = Self.datasetSignature(for: workoutsToProcess)
            let batchRequestType = RequestType.batchProcessing.rawValue // Backend selects optimal model

            // Resume any still-valid partial run for this exact dataset; otherwise
            // wipe stale state and start fresh.
            var batchSummaries = loadResumableSummaries(userId: userId, signature: signature)
            resumedBatchCount = batchSummaries.count
            resumedWorkoutCount = batchSummaries.keys.reduce(0) { $0 + batchRange($1, total: totalWorkoutCount).count }
            if resumedBatchCount > 0 {
                isResuming = true
                print("♻️ BatchIndexationManager: Resuming — \(resumedBatchCount)/\(totalBatches) batches already done")
            } else {
                progressStore.clearAll()
            }
            print("📊 BatchIndexationManager: \(totalBatches) batches (\(batchSummaries.count) reused), then consolidate")

            AnalyticsService.shared.trackIndexationStarted(
                workoutsCount: workoutsToProcess.count,
                totalBatches: totalBatches
            )
            recomputeBatchProgress()

            let missingBatches = (0..<totalBatches).filter { batchSummaries[$0] == nil }

            // Step 3a: Fetch per-workout metrics concurrently (HealthKit I/O bound).
            currentPhase = "fetch_metrics"
            let workoutDataByBatch = await fetchWorkoutData(forBatches: missingBatches, in: workoutsToProcess)

            guard !isCancelled else {
                state = .cancelled
                return
            }

            // Step 3b: Upload batches concurrently (network/LLM bound), persisting each.
            currentPhase = "upload_batches"
            let uploadResult = try await uploadBatches(
                workoutDataByBatch,
                workoutsToProcess: workoutsToProcess,
                requestType: batchRequestType,
                language: language,
                userId: userId,
                signature: signature
            )
            batchSummaries.merge(uploadResult.summaries) { _, new in new }
            let lastSkippedError = uploadResult.lastSkippedError

            // If every batch was rejected by the server, surface the last
            // error so the user sees something — otherwise we'd consolidate
            // an empty list and fail in a more confusing way.
            let orderedSummaries = (0..<totalBatches).compactMap { batchSummaries[$0] }
            if orderedSummaries.isEmpty, let lastSkippedError {
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
                batchSummaries: orderedSummaries,
                totalWorkouts: indexedWorkoutCount,
                requestType: RequestType.moderate.rawValue,
                language: language,
                dateRangeStart: workoutsToProcess.last?.startDate ?? Date(),
                dateRangeEnd: workoutsToProcess.first?.startDate ?? Date()
            )

            // Step 5: Complete — drop the now-consumed partial-run state.
            progressStore.clearAll()
            currentPhase = "completed"
            progress = 1.0
            state = .completed
            isResuming = false

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
    nonisolated static func isClient4xx(_ error: BackendError) -> Bool {
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

    /// Reset in-memory state. Deliberately does NOT clear the persisted
    /// progress store — that is what lets an interrupted run resume.
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
        isResuming = false
        metricsFetchedCount = 0
        uploadedBatchCount = 0
        resumedWorkoutCount = 0
        resumedBatchCount = 0
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

    // MARK: - Concurrent Batch Processing

    /// Build the upload payload for a single workout. Never throws — a failed
    /// metric fetch degrades to nil fields rather than dropping the workout.
    private func makeWorkoutData(for workout: WorkoutModel) async -> WorkoutData {
        let metrics = try? await healthKitManager.fetchEssentialMetrics(for: workout)

        // Clamp numeric fields to what the backend Zod schema accepts:
        // `distance` must be >= 0, any number must be finite (NaN/Inf from
        // third-party imports gets serialized to null and rejected).
        let safeDistance = max(workout.distance ?? 0, 0)
        let safeCalories = workout.totalEnergyBurned.flatMap { $0.isFinite ? max($0, 0) : nil }

        return WorkoutData(
            date: Self.iso8601Formatter.string(from: workout.startDate),
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
    }

    /// Fetch metrics for every workout of the missing batches in bounded waves.
    /// HealthKit query latency overlaps within a wave; the actor-isolated glue
    /// (counters, progress) runs between waves so nothing races.
    private func fetchWorkoutData(forBatches missing: [Int], in workouts: [WorkoutModel]) async -> [Int: [WorkoutData]] {
        struct Slot { let batch: Int; let position: Int; let workout: WorkoutModel }

        var slots: [Slot] = []
        var buffers: [Int: [WorkoutData?]] = [:]
        for batch in missing {
            let range = batchRange(batch, total: workouts.count)
            buffers[batch] = Array(repeating: nil, count: range.count)
            for (position, index) in range.enumerated() {
                slots.append(Slot(batch: batch, position: position, workout: workouts[index]))
            }
        }
        guard !slots.isEmpty else { return [:] }

        let limit = max(1, BatchIndexationConfig.metricsConcurrency)
        for start in stride(from: 0, to: slots.count, by: limit) {
            if isCancelled { break }
            let wave = slots[start..<min(start + limit, slots.count)]
            let results = await withTaskGroup(of: (Int, Int, WorkoutData).self) { group in
                for slot in wave {
                    group.addTask {
                        (slot.batch, slot.position, await self.makeWorkoutData(for: slot.workout))
                    }
                }
                var collected: [(Int, Int, WorkoutData)] = []
                for await result in group { collected.append(result) }
                return collected
            }

            for (batch, position, data) in results {
                buffers[batch]?[position] = data
            }
            metricsFetchedCount += results.count
            recomputeBatchProgress()
        }

        return buffers.mapValues { $0.compactMap { $0 } }
    }

    /// Upload the missing batches in bounded waves. Each successful batch is
    /// persisted immediately so an interruption resumes instead of restarting.
    /// A 4xx rejection skips that batch (a partial summary beats a hard failure);
    /// any other error propagates and fails the run with progress preserved.
    private func uploadBatches(
        _ dataByBatch: [Int: [WorkoutData]],
        workoutsToProcess: [WorkoutModel],
        requestType: String,
        language: String,
        userId: String,
        signature: String
    ) async throws -> (summaries: [Int: String], lastSkippedError: BackendError?) {
        var summaries: [Int: String] = [:]
        var lastSkippedError: BackendError?
        let batches = dataByBatch.keys.sorted()
        guard !batches.isEmpty else { return ([:], nil) }

        let limit = max(1, BatchIndexationConfig.uploadConcurrency)
        for start in stride(from: 0, to: batches.count, by: limit) {
            if isCancelled { break }
            let wave = batches[start..<min(start + limit, batches.count)]
            let results = try await withThrowingTaskGroup(of: (Int, BatchAnalysisResponse?, BackendError?).self) { group in
                for batch in wave {
                    let workouts = dataByBatch[batch] ?? []
                    group.addTask {
                        do {
                            let response = try await self.backendClient.analyzeBatch(
                                workouts: workouts,
                                batchIndex: batch,
                                requestType: requestType,
                                model: nil,
                                language: language
                            )
                            return (batch, response, nil)
                        } catch let backendError as BackendError where Self.isClient4xx(backendError) {
                            return (batch, nil, backendError)
                        }
                    }
                }
                var collected: [(Int, BatchAnalysisResponse?, BackendError?)] = []
                for try await result in group { collected.append(result) }
                return collected
            }

            for (batch, response, skipError) in results {
                if let response {
                    summaries[batch] = response.partialSummary
                    uploadedBatchCount += 1
                    lastBatchWorkoutCount = response.workoutCount
                    persistBatch(batch, summary: response.partialSummary, workoutsToProcess: workoutsToProcess, userId: userId, signature: signature)
                } else if let skipError {
                    skippedWorkoutCount += dataByBatch[batch]?.count ?? 0
                    lastSkippedError = skipError
                    AnalyticsService.shared.track(
                        .indexationFailed,
                        properties: indexationDebugInfo(error: skipError, categorizedMessage: "skipped_batch_4xx")
                    )
                    print("⚠️ BatchIndexationManager: Batch \(batch) skipped (\(skipError.localizedDescription))")
                }

                recomputeBatchProgress()
                AnalyticsService.shared.trackIndexationBatchProcessed(
                    batchNumber: resumedBatchCount + uploadedBatchCount,
                    totalBatches: totalBatches,
                    progress: progress
                )
            }
        }
        return (summaries, lastSkippedError)
    }

    /// Persist a completed batch (summary + run cursor) so it survives an
    /// interruption and is reused on the next attempt.
    private func persistBatch(_ batch: Int, summary: String, workoutsToProcess: [WorkoutModel], userId: String, signature: String) {
        let range = batchRange(batch, total: workoutsToProcess.count)
        let slice = workoutsToProcess[range]
        let batchSummary = BatchSummary(
            batchNumber: batch,
            totalBatches: totalBatches,
            summary: summary,
            workoutCount: range.count,
            dateRangeStart: slice.last?.startDate ?? Date(),
            dateRangeEnd: slice.first?.startDate ?? Date(),
            userId: userId,
            status: .completed
        )
        progressStore.saveBatchSummary(batchSummary)
        progressStore.saveProgress(
            totalBatches: totalBatches,
            lastCompletedBatch: resumedBatchCount + uploadedBatchCount,
            batchStatuses: [:],
            userId: userId,
            datasetSignature: signature
        )
    }

    /// Consolidate all batch summaries and save the final summary.
    private func consolidateAndSave(
        batchSummaries: [String],
        totalWorkouts: Int,
        requestType: String,
        language: String,
        dateRangeStart: Date,
        dateRangeEnd: Date
    ) async throws {
        guard !batchSummaries.isEmpty else {
            throw IndexationError.noWorkoutsToConsolidate
        }

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

        progress = 0.85
        state = .loading(progress: progress)

        print("📊 BatchIndexationManager: Consolidating \(batchSummaries.count) batch summaries with requestType: \(requestType)...")

        let response = try await backendClient.consolidateBatches(
            batchSummaries: batchSummaries,
            totalWorkouts: totalWorkouts,
            profile: profileData,
            requestType: requestType,
            model: nil, // Backend will select model
            language: language
        )

        let summary = HistoricalSummary(
            summary: response.summary,
            workoutCount: response.workoutCount,
            dateRangeStart: dateRangeStart,
            dateRangeEnd: dateRangeEnd
        )
        storage.save(summary)

        progress = 1.0
        state = .loading(progress: progress)

        print("✅ BatchIndexationManager: Summary saved successfully")
    }

    // MARK: - Resume & Progress Helpers

    /// Workout index range covered by a batch.
    private func batchRange(_ batch: Int, total: Int) -> Range<Int> {
        let start = batch * BatchIndexationConfig.batchSize
        let end = min(start + BatchIndexationConfig.batchSize, total)
        return start..<max(start, end)
    }

    /// Reuse completed batch summaries from a previous run, but only when they
    /// belong to the exact same dataset (signature) and batch layout — otherwise
    /// the slices wouldn't line up.
    private func loadResumableSummaries(userId: String, signature: String) -> [Int: String] {
        guard let saved = progressStore.loadProgress(forUserId: userId),
              saved.datasetSignature == signature,
              saved.totalBatches == totalBatches,
              !saved.isComplete else {
            return [:]
        }
        var summaries: [Int: String] = [:]
        for batch in progressStore.loadBatchSummaries(forUserId: userId)
        where batch.status == .completed && batch.batchNumber >= 0 && batch.batchNumber < totalBatches {
            summaries[batch.batchNumber] = batch.summary
        }
        return summaries
    }

    /// Drive the 0–70% band continuously: 30% weight on metric fetching, 70% on
    /// batch uploads, counting resumed work as already done so a resumed run
    /// starts mid-bar instead of at zero.
    private func recomputeBatchProgress() {
        guard totalWorkoutCount > 0, totalBatches > 0 else { return }
        let metricsFraction = Double(resumedWorkoutCount + metricsFetchedCount) / Double(totalWorkoutCount)
        let uploadFraction = Double(resumedBatchCount + uploadedBatchCount) / Double(totalBatches)
        let combined = 0.3 * metricsFraction + 0.7 * uploadFraction
        progress = min(BatchIndexationConfig.batchProcessingWeight, BatchIndexationConfig.batchProcessingWeight * combined)
        currentBatch = resumedBatchCount + uploadedBatchCount
        state = .loading(progress: progress)
    }

    /// Stable fingerprint of the dataset so resumed batch slices line up exactly.
    private static func datasetSignature(for workouts: [WorkoutModel]) -> String {
        let joined = workouts.map { $0.id.uuidString }.joined(separator: ",")
        let digest = SHA256.hash(data: Data(joined.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Background Task

    private func beginBackgroundTask() {
        endBackgroundTask()
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "WorkoutIndexation") { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
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
