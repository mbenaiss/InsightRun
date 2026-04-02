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

    // MARK: - Private Properties

    private var isCancelled = false
    private var indexationStartTime: Date?
    private var lastErrorRetryable = true
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

        isCancelled = false
        state = .loading(progress: 0.0)
        progress = 0.0
        indexationStartTime = Date()

        do {
            // Step 0: Verify HealthKit availability and authorization
            guard healthKitManager.isHealthDataAvailable else {
                throw IndexationError.healthKitNotAvailable
            }

            if !healthKitManager.isHealthKitAuthorized {
                try await healthKitManager.requestAuthorization()
            }

            // Step 1: Fetch total workouts
            print("📊 BatchIndexationManager: Fetching workouts from HealthKit...")
            let allWorkouts = try await healthKitManager.fetchRunningWorkouts()

            guard !isCancelled else {
                state = .cancelled
                return
            }

            // Limit to max workouts and sort by date (most recent first)
            let workoutsToProcess = Array(allWorkouts.prefix(BatchIndexationConfig.maxWorkouts))

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
            let batchRequestType = RequestType.batchProcessing.rawValue // Backend selects optimal model
            let consolidationRequestType = RequestType.moderate.rawValue // Backend selects optimal model
            let language = Locale.current.language.languageCode?.identifier ?? "en"

            // Step 3: Process batches
            for batchIndex in 0..<totalBatches {
                guard !isCancelled else {
                    state = .cancelled
                    return
                }

                currentBatch = batchIndex + 1
                print("📊 BatchIndexationManager: Processing batch \(currentBatch)/\(totalBatches) with requestType: \(batchRequestType)...")

                let startIndex = batchIndex * BatchIndexationConfig.batchSize
                let endIndex = min(startIndex + BatchIndexationConfig.batchSize, workoutsToProcess.count)
                let batchWorkouts = Array(workoutsToProcess[startIndex..<endIndex])

                // Convert batch workouts to WorkoutData
                let batchData = try await processBatch(batchWorkouts)

                // Send batch to backend for analysis
                let batchResponse = try await backendClient.analyzeBatch(
                    workouts: batchData,
                    batchIndex: batchIndex,
                    requestType: batchRequestType,
                    model: nil, // Backend will select model
                    language: language
                )

                // Collect partial summary
                batchSummaries.append(batchResponse.partialSummary)

                // Update progress (0-70%)
                let batchProgress = Double(currentBatch) / Double(totalBatches)
                progress = batchProgress * BatchIndexationConfig.batchProcessingWeight
                state = .loading(progress: progress)

                // Track batch processed
                AnalyticsService.shared.trackIndexationBatchProcessed(
                    batchNumber: currentBatch,
                    totalBatches: totalBatches,
                    progress: progress
                )

                print("📊 BatchIndexationManager: Batch \(currentBatch) completed (\(Int(progress * 100))%)")
            }

            guard !isCancelled else {
                state = .cancelled
                return
            }

            // Step 4: Consolidation
            print("📊 BatchIndexationManager: Starting final consolidation...")
            state = .loading(progress: 0.70)
            progress = 0.70

            try await consolidateAndSave(
                batchSummaries: batchSummaries,
                totalWorkouts: workoutsToProcess.count,
                requestType: consolidationRequestType,
                language: language
            )

            // Step 5: Complete
            progress = 1.0
            state = .completed

            // Track indexation completed
            let duration = indexationStartTime.map { Date().timeIntervalSince($0) } ?? 0
            AnalyticsService.shared.trackIndexationCompleted(
                workoutsCount: workoutsToProcess.count,
                durationSeconds: duration,
                totalBatches: totalBatches
            )

            print("✅ BatchIndexationManager: Indexation completed successfully!")

        } catch {
            print("❌ BatchIndexationManager: Indexation failed: \(error)")
            let categorizedMessage = categorizeError(error)
            let errorDesc = error.localizedDescription
            lastErrorRetryable = !isNonRetryableError(errorDesc)
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

    /// Check if an error is not worth retrying (auth/permission errors)
    private func isNonRetryableError(_ message: String) -> Bool {
        let nonRetryableKeywords = [
            "authorization", "permission", "consent", "denied", "not available",
            "inaccessible", "uiviewservicehostsession"
        ]
        let lowered = message.lowercased()
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
            "is_retryable": lastErrorRetryable
        ]

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
            default:
                return String(localized: "A network error occurred. Please try again.", comment: "Indexation generic network error")
            }
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

            // Convert to WorkoutData
            let workoutData = WorkoutData(
                date: ISO8601DateFormatter().string(from: workout.startDate),
                duration: workout.duration,
                distance: workout.distance ?? 0,
                calories: workout.totalEnergyBurned,
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
