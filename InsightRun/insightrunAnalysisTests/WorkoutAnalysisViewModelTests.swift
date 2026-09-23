import Combine
import Foundation
import HealthKit
import SwiftData
import XCTest

@testable import insightrun

@MainActor
final class WorkoutAnalysisViewModelTests: XCTestCase {
    func testCachedAnalysisInAnotherLanguageStaysVisibleAsOutdatedWithoutAutomaticTransmission() async throws {
        let harness = try AnalysisHarness()
        let otherLanguage = AppLanguage.current == "fr" ? "en" : "fr"
        let analysis = WorkoutAnalysis(workoutId: harness.workout.id, analysisText: AnalysisHarness.completeResponse)
        analysis.inputSignature = try XCTUnwrap(harness.viewModel.inputSignature(language: otherLanguage))
        harness.modelContext.insert(analysis)
        try harness.modelContext.save()

        await harness.viewModel.loadAnalysis()

        XCTAssertEqual(harness.viewModel.analysisText, AnalysisHarness.completeResponse)
        XCTAssertEqual(harness.viewModel.analysisSource, .cache)
        XCTAssertTrue(harness.viewModel.isOutdated)
        XCTAssertEqual(harness.client.requestCount, 0)

        await harness.viewModel.regenerateAnalysis()

        XCTAssertEqual(harness.client.requestCount, 1)
        XCTAssertFalse(harness.viewModel.isOutdated)
        XCTAssertEqual(try harness.savedAnalyses().first?.inputSignature, harness.viewModel.inputSignature())
    }

    func testFeedbackChangeMarksCachedAnalysisOutdatedWithoutAutomaticTransmission() async throws {
        let harness = try AnalysisHarness()
        try harness.cacheAnalysis(AnalysisHarness.completeResponse)
        await harness.viewModel.loadAnalysis(allowGeneration: false)
        XCTAssertEqual(harness.viewModel.analysisSource, .cache)
        XCTAssertFalse(harness.viewModel.isOutdated)
        WorkoutFeedbackStore.shared.save(WorkoutFeedback(effort: 8, intent: "easy"), for: harness.workout)
        defer { WorkoutFeedbackStore.shared.save(WorkoutFeedback(), for: harness.workout) }
        await harness.viewModel.loadAnalysis()
        XCTAssertEqual(harness.viewModel.analysisText, AnalysisHarness.completeResponse)
        XCTAssertTrue(harness.viewModel.isOutdated)
        XCTAssertEqual(harness.client.requestCount, 0)
        await harness.viewModel.generateAnalysis()
        XCTAssertEqual(harness.client.requestCount, 1)
        XCTAssertEqual(try harness.savedAnalyses().first?.inputSignature, harness.viewModel.inputSignature())
    }

    func testRefreshingIdenticalMeasurementsKeepsCachedAnalysisButNewCoverageMarksItOutdated() async throws {
        let harness = try AnalysisHarness()
        func metrics(date: String, coverage: Double) -> WorkoutMetrics {
            WorkoutMetrics(workout: harness.workout, evidence: WorkoutEvidence(
                measuredAt: date, source: "com.apple.health", device: "Watch", softwareVersion: "27", zones: nil,
                signals: [WorkoutSignalQuality(metric: "heartRate", sampleCount: 100, coverage: coverage, longestGapSeconds: 5, sourceCount: 1)], phases: []))
        }
        harness.viewModel.updateMetrics(metrics(date: "2026-09-21T12:00:00Z", coverage: 0.8))
        try harness.cacheAnalysis(AnalysisHarness.completeResponse)
        harness.viewModel.updateMetrics(metrics(date: "2026-09-21T13:00:00Z", coverage: 0.8))
        await harness.viewModel.loadAnalysis(allowGeneration: false)
        XCTAssertEqual(harness.viewModel.analysisSource, .cache)
        XCTAssertFalse(harness.viewModel.isOutdated)
        harness.viewModel.updateMetrics(metrics(date: "2026-09-21T13:00:00Z", coverage: 0.9))
        await harness.viewModel.loadAnalysis(allowGeneration: false)
        XCTAssertEqual(harness.viewModel.analysisText, AnalysisHarness.completeResponse)
        XCTAssertTrue(harness.viewModel.isOutdated)
    }

    func testSignatureIgnoresFieldsOutsideItsStableSubset() async throws {
        let harness = try AnalysisHarness()
        harness.viewModel.updateMetrics(WorkoutMetrics(workout: harness.workout, averageHeartRate: 145, maxHeartRate: 165))
        try harness.cacheAnalysis(AnalysisHarness.completeResponse)
        var enriched = WorkoutMetrics(workout: harness.workout, averageHeartRate: 145.2, maxHeartRate: 165)
        enriched.averageCadence = 172
        enriched.vo2Max = 51
        enriched.walkingSteadiness = 98
        enriched.temperature = 18
        harness.viewModel.updateMetrics(enriched)
        await harness.viewModel.loadAnalysis(allowGeneration: false)
        XCTAssertFalse(harness.viewModel.isOutdated)
        enriched.averageHeartRate = 151
        harness.viewModel.updateMetrics(enriched)
        await harness.viewModel.loadAnalysis(allowGeneration: false)
        XCTAssertTrue(harness.viewModel.isOutdated)
        XCTAssertEqual(harness.client.requestCount, 0)
    }

    func testSignatureFromBeforeTheStableSubsetIsAdoptedOnce() async throws {
        let harness = try AnalysisHarness()
        try harness.cacheAnalysis(AnalysisHarness.completeResponse)
        let cached = try XCTUnwrap(harness.modelContext.fetch(FetchDescriptor<WorkoutAnalysis>()).first)
        cached.inputSignature = String(repeating: "a", count: 64)
        try harness.modelContext.save()

        await harness.viewModel.loadAnalysis()

        XCTAssertEqual(harness.viewModel.analysisSource, .cache)
        XCTAssertFalse(harness.viewModel.isOutdated)
        XCTAssertEqual(harness.client.requestCount, 0)
        XCTAssertEqual(try harness.savedAnalyses().first?.inputSignature, harness.viewModel.inputSignature())
    }

    func testMissingConsentDoesNotStartGeneration() async throws {
        let harness = try AnalysisHarness()
        harness.hasConsent = false

        await harness.viewModel.loadAnalysis()
        harness.viewModel.recordAnalysisViewed()

        XCTAssertTrue(harness.viewModel.needsConsent)
        XCTAssertFalse(harness.viewModel.isLoading)
        XCTAssertNil(harness.viewModel.analysisText)
        XCTAssertNil(harness.viewModel.analysisSource)
        XCTAssertEqual(harness.indexationChecks, 0)
        XCTAssertEqual(harness.client.requestCount, 0)
        XCTAssertEqual(harness.analytics.startedCount, 0)
        XCTAssertTrue(harness.analytics.completedSamples.isEmpty)
        XCTAssertTrue(harness.analytics.viewedSources.isEmpty)
        XCTAssertTrue(harness.analytics.failureReasons.isEmpty)
        XCTAssertTrue(try harness.savedAnalyses().isEmpty)
    }

    func testConsentRetryGeneratesAnalysisAndClearsGate() async throws {
        let harness = try AnalysisHarness()
        harness.hasConsent = false
        await harness.viewModel.generateAnalysis()

        harness.hasConsent = true
        await harness.viewModel.generateAnalysis()

        XCTAssertFalse(harness.viewModel.needsConsent)
        XCTAssertEqual(harness.client.requestCount, 1)
        XCTAssertEqual(harness.analytics.startedCount, 1)
        XCTAssertEqual(harness.analytics.completedSamples, [false])
        XCTAssertEqual(harness.viewModel.analysisSource, .generated)
        XCTAssertEqual(try harness.savedAnalyses().count, 1)
    }

    func testSampleAnalysisIsViewedOnceWithoutGeneration() async throws {
        let harness = try AnalysisHarness(isSample: true)
        harness.hasConsent = false
        harness.indexationRequired = true

        await harness.viewModel.loadAnalysis()
        harness.viewModel.recordAnalysisViewed()
        await harness.viewModel.loadAnalysis()
        harness.viewModel.recordAnalysisViewed()
        await harness.viewModel.generateAnalysis()
        harness.viewModel.recordAnalysisViewed()

        XCTAssertEqual(harness.viewModel.analysisText, MockData.sampleWorkoutAnalysis)
        XCTAssertEqual(harness.viewModel.analysisSource, .sample)
        XCTAssertEqual(harness.analytics.viewedSources, [.sample])
        XCTAssertEqual(harness.client.requestCount, 0)
        XCTAssertEqual(harness.indexationChecks, 0)
        XCTAssertEqual(harness.analytics.startedCount, 0)
        XCTAssertTrue(harness.analytics.completedSamples.isEmpty)
        XCTAssertTrue(harness.analytics.failureReasons.isEmpty)
        XCTAssertFalse(harness.viewModel.needsConsent)
        XCTAssertFalse(harness.viewModel.needsIndexation)
        XCTAssertTrue(try harness.savedAnalyses().isEmpty)
    }

    func testCachedAnalysisIsViewedOnceWithoutGeneration() async throws {
        let harness = try AnalysisHarness()
        let savedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try harness.cacheAnalysis(AnalysisHarness.completeResponse, analyzedAt: savedAt)
        harness.hasConsent = false
        harness.indexationRequired = true

        await harness.viewModel.loadAnalysis()
        harness.viewModel.recordAnalysisViewed()
        await harness.viewModel.loadAnalysis()
        harness.viewModel.recordAnalysisViewed()

        XCTAssertEqual(harness.viewModel.analysisText, AnalysisHarness.completeResponse)
        XCTAssertEqual(harness.viewModel.analysisSource, .cache)
        XCTAssertEqual(harness.viewModel.analyzedAt, savedAt)
        XCTAssertEqual(harness.analytics.viewedSources, [.cache])
        XCTAssertEqual(harness.client.requestCount, 0)
        XCTAssertEqual(harness.indexationChecks, 0)
        XCTAssertEqual(harness.analytics.startedCount, 0)
        XCTAssertTrue(harness.analytics.completedSamples.isEmpty)
        XCTAssertTrue(harness.analytics.failureReasons.isEmpty)
        XCTAssertFalse(harness.viewModel.needsConsent)
        XCTAssertFalse(harness.viewModel.needsIndexation)
        XCTAssertEqual(try harness.savedAnalyses().count, 1)
    }

    func testCachedAnalysisRemainsAvailableWhenGenerationIsDisallowed() async throws {
        let harness = try AnalysisHarness()
        try harness.cacheAnalysis(AnalysisHarness.completeResponse)

        await harness.viewModel.loadAnalysis(allowGeneration: false)
        harness.viewModel.recordAnalysisViewed()

        XCTAssertEqual(harness.viewModel.analysisText, AnalysisHarness.completeResponse)
        XCTAssertEqual(harness.viewModel.analysisSource, .cache)
        XCTAssertEqual(harness.analytics.viewedSources, [.cache])
        XCTAssertEqual(harness.client.requestCount, 0)
        XCTAssertEqual(harness.indexationChecks, 0)
        XCTAssertEqual(harness.analytics.startedCount, 0)
        XCTAssertTrue(harness.analytics.completedSamples.isEmpty)
        XCTAssertTrue(harness.analytics.failureReasons.isEmpty)
        XCTAssertEqual(try harness.savedAnalyses().count, 1)
    }

    func testMissingCacheDoesNotGenerateWhenGenerationIsDisallowed() async throws {
        let harness = try AnalysisHarness()

        await harness.viewModel.loadAnalysis(allowGeneration: false)
        harness.viewModel.recordAnalysisViewed()

        XCTAssertNil(harness.viewModel.analysisText)
        XCTAssertNil(harness.viewModel.analysisSource)
        XCTAssertFalse(harness.viewModel.isLoading)
        XCTAssertEqual(harness.client.requestCount, 0)
        XCTAssertEqual(harness.indexationChecks, 0)
        XCTAssertEqual(harness.analytics.startedCount, 0)
        XCTAssertTrue(harness.analytics.completedSamples.isEmpty)
        XCTAssertTrue(harness.analytics.viewedSources.isEmpty)
        XCTAssertTrue(harness.analytics.failureReasons.isEmpty)
        XCTAssertTrue(try harness.savedAnalyses().isEmpty)
    }

    func testSuccessfulGenerationTracksCompletionAndPersistsFinalResponse() async throws {
        let harness = try AnalysisHarness()

        await harness.viewModel.generateAnalysis()
        harness.viewModel.recordAnalysisViewed()
        harness.viewModel.recordAnalysisViewed()

        XCTAssertEqual(harness.client.requestCount, 1)
        XCTAssertEqual(harness.client.requestedWorkoutID, harness.workout.id)
        XCTAssertEqual(harness.analytics.startedCount, 1)
        XCTAssertEqual(harness.analytics.completedSamples, [false])
        XCTAssertEqual(harness.analytics.viewedSources, [.generated])
        XCTAssertTrue(harness.analytics.failureReasons.isEmpty)
        XCTAssertEqual(harness.viewModel.analysisText, AnalysisHarness.completeResponse)
        XCTAssertEqual(harness.viewModel.analysisSource, .generated)
        XCTAssertFalse(harness.viewModel.isLoading)
        XCTAssertNil(harness.viewModel.error)

        let saved = try XCTUnwrap(harness.savedAnalyses().first)
        XCTAssertEqual(saved.workoutId, harness.workout.id)
        XCTAssertEqual(saved.analysisText, AnalysisHarness.completeResponse)
        XCTAssertEqual(saved.analyzedAt, harness.viewModel.analyzedAt)
    }

    func testEmptyResponseFailsWithoutCompletionOrPersistence() async throws {
        try await assertFailedGeneration(response: " \n\t ", reason: .emptyResponse)
    }

    func testCompleteMarkdownIsGeneratedPersistedAndReloadedWithoutAnotherRequest() async throws {
        let harness = try AnalysisHarness()
        let response = """
            ## Summary
            Your pace remained stable throughout this aerobic session.

            ## Next action
            **Keep your next recovery run comfortable for twenty minutes.**
            """
        harness.client.stubbedResponse = response

        await harness.viewModel.generateAnalysis()
        harness.viewModel.recordAnalysisViewed()

        XCTAssertEqual(harness.viewModel.analysisText, response)
        XCTAssertEqual(harness.viewModel.analysisSource, .generated)
        XCTAssertNil(harness.viewModel.error)
        XCTAssertEqual(harness.analytics.completedSamples, [false])
        XCTAssertTrue(harness.analytics.failureReasons.isEmpty)
        XCTAssertEqual(try harness.savedAnalyses().first?.analysisText, response)

        await harness.viewModel.loadAnalysis(allowGeneration: false)
        harness.viewModel.recordAnalysisViewed()

        XCTAssertEqual(harness.viewModel.analysisText, response)
        XCTAssertEqual(harness.viewModel.analysisSource, .cache)
        XCTAssertEqual(harness.client.requestCount, 1)
        XCTAssertEqual(harness.analytics.viewedSources, [.generated, .cache])
        XCTAssertTrue(harness.analytics.failureReasons.isEmpty)
        XCTAssertEqual(try harness.savedAnalyses().count, 1)
    }

    func testIncompleteResponseFailsWithoutCompletionOrPersistence() async throws {
        try await assertFailedGeneration(
            response: "Your pace remained stable throughout this session. For your next workout, try",
            reason: .incompleteResponse
        )
    }

    func testServiceErrorRejectsOtherwiseCompleteResponse() async throws {
        try await assertFailedGeneration(
            response: AnalysisHarness.completeResponse,
            serviceError: "The service is unavailable.",
            reason: .serviceError
        )
    }

    func testIndexationGateThenRetryStartsOnlyOneGeneration() async throws {
        let harness = try AnalysisHarness()
        harness.indexationRequired = true

        await harness.viewModel.loadAnalysis()

        XCTAssertTrue(harness.viewModel.needsIndexation)
        XCTAssertFalse(harness.viewModel.isLoading)
        XCTAssertEqual(harness.client.requestCount, 0)
        XCTAssertEqual(harness.analytics.startedCount, 0)
        XCTAssertTrue(harness.analytics.completedSamples.isEmpty)
        XCTAssertTrue(try harness.savedAnalyses().isEmpty)

        harness.indexationRequired = false
        await harness.viewModel.loadAnalysis()

        XCTAssertFalse(harness.viewModel.needsIndexation)
        XCTAssertEqual(harness.indexationChecks, 2)
        XCTAssertEqual(harness.client.requestCount, 1)
        XCTAssertEqual(harness.analytics.startedCount, 1)
        XCTAssertEqual(harness.analytics.completedSamples, [false])
        XCTAssertEqual(harness.viewModel.analysisSource, .generated)
        XCTAssertEqual(try harness.savedAnalyses().count, 1)
    }

    func testConcurrentCallsDuringRequestDoNotGenerateTwice() async throws {
        let harness = try AnalysisHarness()
        let started = expectation(description: "The analysis request started")
        let suspension = AnalysisSuspension(onSuspend: { started.fulfill() })
        harness.client.suspension = suspension
        let generation = Task { await harness.viewModel.generateAnalysis() }
        await fulfillment(of: [started], timeout: 2)

        await harness.viewModel.generateAnalysis()
        await harness.viewModel.loadAnalysis()
        await harness.viewModel.regenerateAnalysis()
        harness.viewModel.recordAnalysisViewed()

        XCTAssertTrue(harness.viewModel.isLoading)
        XCTAssertEqual(harness.client.requestCount, 1)
        XCTAssertEqual(harness.analytics.startedCount, 1)
        XCTAssertTrue(harness.analytics.completedSamples.isEmpty)
        XCTAssertTrue(harness.analytics.viewedSources.isEmpty)
        XCTAssertTrue(try harness.savedAnalyses().isEmpty)

        suspension.resume()
        await generation.value

        XCTAssertEqual(harness.client.requestCount, 1)
        XCTAssertEqual(harness.analytics.completedSamples, [false])
        XCTAssertEqual(try harness.savedAnalyses().count, 1)
    }

    func testConcurrentCallsDuringIndexationCheckDoNotGenerateTwice() async throws {
        let harness = try AnalysisHarness()
        let started = expectation(description: "The indexation check started")
        let suspension = AnalysisSuspension(onSuspend: { started.fulfill() })
        harness.indexationSuspension = suspension
        let generation = Task { await harness.viewModel.generateAnalysis() }
        await fulfillment(of: [started], timeout: 2)

        await harness.viewModel.generateAnalysis()
        await harness.viewModel.loadAnalysis()
        await harness.viewModel.regenerateAnalysis()

        XCTAssertEqual(harness.indexationChecks, 1)
        XCTAssertEqual(harness.client.requestCount, 0)
        XCTAssertEqual(harness.analytics.startedCount, 0)

        suspension.resume()
        await generation.value

        XCTAssertEqual(harness.client.requestCount, 1)
        XCTAssertEqual(harness.analytics.startedCount, 1)
        XCTAssertEqual(harness.analytics.completedSamples, [false])
        XCTAssertEqual(try harness.savedAnalyses().count, 1)
    }

    func testIncompleteCacheIsReplacedByGeneratedAnalysis() async throws {
        let harness = try AnalysisHarness()
        try harness.cacheAnalysis("An analysis interrupted before it could provide the next")

        await harness.viewModel.loadAnalysis()

        XCTAssertEqual(harness.client.requestCount, 1)
        XCTAssertEqual(harness.viewModel.analysisSource, .generated)
        XCTAssertEqual(harness.analytics.completedSamples, [false])
        let saved = try harness.savedAnalyses()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.analysisText, AnalysisHarness.completeResponse)
    }

    func testFailedRegenerationPreservesExistingCache() async throws {
        let harness = try AnalysisHarness()
        try harness.cacheAnalysis(AnalysisHarness.completeResponse)
        await harness.viewModel.loadAnalysis()
        harness.client.stubbedError = "The service is unavailable."

        await harness.viewModel.regenerateAnalysis()

        XCTAssertEqual(harness.client.requestCount, 1)
        XCTAssertEqual(harness.analytics.failureReasons, [.serviceError])
        XCTAssertTrue(harness.analytics.completedSamples.isEmpty)
        XCTAssertEqual(harness.viewModel.analysisText, AnalysisHarness.completeResponse)
        XCTAssertEqual(harness.viewModel.analysisSource, .cache)
        XCTAssertEqual(harness.viewModel.error, "The service is unavailable.")
        let saved = try harness.savedAnalyses()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.analysisText, AnalysisHarness.completeResponse)
    }

    func testCancelledGenerationIsNeitherSavedNorReported() async throws {
        let harness = try AnalysisHarness()
        try harness.cacheAnalysis(AnalysisHarness.completeResponse)
        await harness.viewModel.loadAnalysis()
        let started = expectation(description: "The analysis request started")
        let suspension = AnalysisSuspension(onSuspend: { started.fulfill() })
        harness.client.suspension = suspension
        harness.client.stubbedResponse = "Your pace remained stable. For your next run, keep it easy."
        let generation = Task { await harness.viewModel.regenerateAnalysis() }
        await fulfillment(of: [started], timeout: 2)

        generation.cancel()
        suspension.resume()
        await generation.value

        XCTAssertFalse(harness.viewModel.isLoading)
        XCTAssertNil(harness.viewModel.error)
        XCTAssertEqual(harness.viewModel.analysisText, AnalysisHarness.completeResponse)
        XCTAssertEqual(harness.viewModel.analysisSource, .cache)
        XCTAssertTrue(harness.analytics.completedSamples.isEmpty)
        XCTAssertTrue(harness.analytics.failureReasons.isEmpty)
        XCTAssertEqual(try harness.savedAnalyses().first?.analysisText, AnalysisHarness.completeResponse)
    }

    func testLegacyAnalysisStaysVisibleAfterContextVersionChangesUntilRegenerated() async throws {
        let harness = try AnalysisHarness()
        try harness.cacheAnalysis(AnalysisHarness.completeResponse)
        let cached = try harness.modelContext.fetch(FetchDescriptor<WorkoutAnalysis>()).first!
        cached.contextVersion = nil
        try harness.modelContext.save()

        await harness.viewModel.loadAnalysis()

        XCTAssertEqual(harness.client.requestCount, 0)
        XCTAssertEqual(harness.viewModel.analysisSource, .cache)
        XCTAssertTrue(harness.viewModel.isOutdated)

        await harness.viewModel.regenerateAnalysis()

        XCTAssertEqual(harness.client.requestCount, 1)
        XCTAssertEqual(harness.viewModel.analysisSource, .generated)
        XCTAssertEqual(try harness.savedAnalyses().first?.contextVersion, WorkoutAnalysis.currentContextVersion)
    }

    func testPreviousCoachingPromptCacheIsReplacedWithContextAwareRequest() async throws {
        let harness = try AnalysisHarness()
        try harness.cacheAnalysis(AnalysisHarness.completeResponse)
        let cached = try XCTUnwrap(harness.modelContext.fetch(FetchDescriptor<WorkoutAnalysis>()).first)
        cached.contextVersion = 7
        try harness.modelContext.save()

        await harness.viewModel.loadAnalysis()
        XCTAssertEqual(harness.viewModel.analysisText, AnalysisHarness.completeResponse)
        XCTAssertTrue(harness.viewModel.isOutdated)
        XCTAssertEqual(harness.client.requestCount, 0)

        await harness.viewModel.regenerateAnalysis()

        XCTAssertEqual(harness.client.requestCount, 1)
        let question = try XCTUnwrap(harness.client.requestedQuestion)
        XCTAssertTrue(question.contains("180"))
        XCTAssertTrue(question.contains("un seul paragraphe continu") || question.contains("one continuous paragraph"))
        XCTAssertTrue(question.contains("aucun retour à la ligne") || question.contains("ni retour à la ligne") || question.contains("line breaks"))
        XCTAssertFalse(question.contains("## "))
        XCTAssertTrue(question.contains("pourquoi il est utile") || question.contains("why it is useful"))
        XCTAssertTrue(question.contains("estimation Apple") || question.contains("Apple estimate"))
        XCTAssertTrue(question.contains("Sur tapis") || question.contains("For treadmill runs"))
        XCTAssertTrue(question.contains("cible cardiaque") || question.contains("heart-rate target"))
        XCTAssertEqual(try harness.savedAnalyses().first?.contextVersion, WorkoutAnalysis.currentContextVersion)
    }

    func testChangedHeartRateReferenceMarksAnalysisOutdatedWithoutLosingOfflineCache() async throws {
        let harness = try AnalysisHarness()
        harness.estimatedMaxHR = 190
        try harness.cacheAnalysis(AnalysisHarness.completeResponse)
        await harness.viewModel.loadAnalysis(allowGeneration: false)
        XCTAssertEqual(harness.viewModel.analysisSource, .cache)

        harness.estimatedMaxHR = 189
        await harness.viewModel.loadAnalysis()
        XCTAssertFalse(harness.viewModel.isOutdated)

        harness.estimatedMaxHR = 187
        await harness.viewModel.loadAnalysis()

        XCTAssertEqual(harness.viewModel.analysisText, AnalysisHarness.completeResponse)
        XCTAssertEqual(harness.viewModel.analysisSource, .cache)
        XCTAssertTrue(harness.viewModel.isOutdated)
        XCTAssertEqual(harness.client.requestCount, 0)
        XCTAssertEqual(try harness.savedAnalyses().first?.estimatedMaxHR, 190)

        harness.client.stubbedResponse = ""
        harness.client.stubbedError = URLError(.notConnectedToInternet).localizedDescription
        await harness.viewModel.regenerateAnalysis()
        XCTAssertFalse(harness.viewModel.isLoading)
        XCTAssertNotNil(harness.viewModel.error)
        XCTAssertEqual(harness.viewModel.analysisText, AnalysisHarness.completeResponse)
        XCTAssertTrue(harness.viewModel.isOutdated)
        XCTAssertEqual(try harness.savedAnalyses().first?.estimatedMaxHR, 190)
        XCTAssertEqual(try harness.savedAnalyses().first?.analysisText, AnalysisHarness.completeResponse)

        harness.client.stubbedError = nil
        harness.client.stubbedResponse = AnalysisHarness.completeResponse
        await harness.viewModel.regenerateAnalysis()
        XCTAssertEqual(harness.client.requestCount, 2)
        XCTAssertFalse(harness.viewModel.isOutdated)
        XCTAssertEqual(try harness.savedAnalyses().first?.estimatedMaxHR, 187)
    }

    func testAgePermissionChangesMarkThePreviousReferenceOutdated() async throws {
        let harness = try AnalysisHarness()
        harness.estimatedMaxHR = 190
        try harness.cacheAnalysis(AnalysisHarness.completeResponse)
        harness.estimatedMaxHR = nil

        await harness.viewModel.loadAnalysis()

        XCTAssertEqual(harness.viewModel.analysisSource, .cache)
        XCTAssertTrue(harness.viewModel.isOutdated)
        XCTAssertEqual(harness.client.requestCount, 0)
        await harness.viewModel.regenerateAnalysis()
        XCTAssertNil(try harness.savedAnalyses().first?.estimatedMaxHR)
        await harness.viewModel.loadAnalysis()
        XCTAssertEqual(harness.client.requestCount, 1)
        XCTAssertEqual(harness.viewModel.analysisSource, .cache)
        XCTAssertFalse(harness.viewModel.isOutdated)
    }

    func testHeartRateReferenceUsesTheSameAgeFormulaAndZoneBoundariesAsTheBackend() async {
        XCTAssertEqual(HeartRateReference.maximum(age: 20), 200)
        XCTAssertEqual(HeartRateReference.maximum(age: 40), 180)
        for age in [nil, 0, -1, 121] {
            XCTAssertNil(HeartRateReference.maximum(age: age))
        }
        for (average, expected) in [(119.0, 1), (120, 2), (140, 3), (160, 4), (180, 5)] {
            XCTAssertEqual(HeartRateReference.zone(average: average, maximum: 200), expected)
        }
        XCTAssertNil(HeartRateReference.zone(average: 140, maximum: nil))
        XCTAssertNil(HeartRateReference.zone(average: .infinity, maximum: 200))
        XCTAssertNil(HeartRateReference.zone(average: .nan, maximum: 200))
    }

    func testLegacyPersistentStoreMigratesWithoutLosingAnalyses() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("analyses.store")
        let workoutID = UUID()
        try autoreleasepool {
            let schema = Schema([LegacyAnalysisSchema.WorkoutAnalysis.self])
            let configuration = ModelConfiguration(schema: schema, url: url)
            let container = try ModelContainer(for: schema, configurations: configuration)
            container.mainContext.insert(LegacyAnalysisSchema.WorkoutAnalysis(workoutId: workoutID, analysisText: AnalysisHarness.completeResponse))
            try container.mainContext.save()
        }
        let schema = Schema([WorkoutAnalysis.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
        let records = try container.mainContext.fetch(FetchDescriptor<WorkoutAnalysis>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.workoutId, workoutID)
        XCTAssertEqual(records.first?.analysisText, AnalysisHarness.completeResponse)
        XCTAssertNil(records.first?.contextVersion)
        XCTAssertNil(records.first?.estimatedMaxHR)
    }

    private func assertFailedGeneration(
        response: String,
        serviceError: String? = nil,
        reason: WorkoutAnalysisFailureReason,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let harness = try AnalysisHarness()
        harness.client.stubbedResponse = response
        harness.client.stubbedError = serviceError

        await harness.viewModel.generateAnalysis()
        harness.viewModel.recordAnalysisViewed()

        XCTAssertEqual(harness.client.requestCount, 1, file: file, line: line)
        XCTAssertEqual(harness.analytics.startedCount, 1, file: file, line: line)
        XCTAssertEqual(harness.analytics.failureReasons, [reason], file: file, line: line)
        XCTAssertTrue(harness.analytics.completedSamples.isEmpty, file: file, line: line)
        XCTAssertTrue(harness.analytics.viewedSources.isEmpty, file: file, line: line)
        XCTAssertNil(harness.viewModel.analysisText, file: file, line: line)
        XCTAssertNil(harness.viewModel.analysisSource, file: file, line: line)
        XCTAssertNil(harness.viewModel.analyzedAt, file: file, line: line)
        XCTAssertNotNil(harness.viewModel.error, file: file, line: line)
        XCTAssertFalse(harness.viewModel.isLoading, file: file, line: line)
        XCTAssertTrue(try harness.savedAnalyses().isEmpty, file: file, line: line)
    }
}

@MainActor
private final class AnalysisHarness {
    static let completeResponse = """
        ## Summary
        Your pace remained stable throughout this aerobic session.

        ## Next action
        Keep your next recovery run comfortable for twenty minutes.
        """

    let container: ModelContainer
    let modelContext: ModelContext
    let workout: WorkoutModel
    let client = AnalysisClientStub()
    let analytics = AnalysisTrackingSpy()
    var estimatedMaxHR: Int?
    var hasConsent = true
    var indexationRequired = false
    var indexationChecks = 0
    var indexationSuspension: AnalysisSuspension?

    lazy var viewModel = WorkoutAnalysisViewModel(
        workout: workout,
        metrics: nil,
        modelContext: modelContext,
        aiService: client,
        analytics: analytics,
        hasAIConsent: { [unowned self] in hasConsent },
        requiresIndexation: { [unowned self] in
            indexationChecks += 1
            await indexationSuspension?.wait()
            return indexationRequired
        },
        isDemo: false,
        maximumHeartRate: { [unowned self] in estimatedMaxHR }
    )

    init(isSample: Bool = false) throws {
        let schema = Schema([WorkoutAnalysis.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        modelContext = ModelContext(container)
        modelContext.autosaveEnabled = false
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        workout = WorkoutModel(
            id: UUID(),
            workoutType: .running,
            startDate: startedAt,
            endDate: startedAt.addingTimeInterval(1_800),
            duration: 1_800,
            distance: 5_000,
            totalEnergyBurned: 300,
            sourceName: "Analysis unit tests",
            sourceVersion: nil,
            metadata: isSample ? ["is_sample": true] : nil,
            averageHeartRate: 145,
            maxHeartRate: 165,
            elevationGain: 25,
            hasRoute: false
        )
    }

    func cacheAnalysis(_ text: String, analyzedAt: Date = Date()) throws {
        let analysis = WorkoutAnalysis(workoutId: workout.id, analysisText: text, analyzedAt: analyzedAt, estimatedMaxHR: estimatedMaxHR)
        analysis.inputSignature = viewModel.inputSignature()
        modelContext.insert(analysis)
        try modelContext.save()
    }

    func savedAnalyses() throws -> [WorkoutAnalysis] {
        let verificationContext = ModelContext(container)
        return try verificationContext.fetch(FetchDescriptor<WorkoutAnalysis>())
    }
}

@MainActor
private final class AnalysisClientStub: WorkoutAnalysisClient {
    private let responses = PassthroughSubject<String, Never>()
    private(set) var streamedResponse = ""
    private(set) var error: String?
    private(set) var requestCount = 0
    private(set) var requestedWorkoutID: UUID?
    private(set) var requestedQuestion: String?
    var stubbedResponse = AnalysisHarness.completeResponse
    var stubbedError: String?
    var suspension: AnalysisSuspension?

    var responsePublisher: AnyPublisher<String, Never> {
        responses.eraseToAnyPublisher()
    }

    func askQuestion(question: String, mode: AIAssistantMode) async {
        requestCount += 1
        requestedQuestion = question
        if case .singleWorkout(let workout, _) = mode {
            requestedWorkoutID = workout.id
        }
        await suspension?.wait()
        streamedResponse = stubbedResponse
        error = stubbedError
        responses.send(streamedResponse)
    }
}

@MainActor
private final class AnalysisTrackingSpy: WorkoutAnalysisTracking {
    private(set) var startedCount = 0
    private(set) var viewedSources: [WorkoutAnalysisSource] = []
    private(set) var failureReasons: [WorkoutAnalysisFailureReason] = []
    private(set) var completedSamples: [Bool] = []

    func trackWorkoutAnalysisStarted() {
        startedCount += 1
    }

    func trackWorkoutAnalysisViewed(source: WorkoutAnalysisSource) {
        viewedSources.append(source)
    }

    func trackWorkoutAnalysisFailed(reason: WorkoutAnalysisFailureReason) {
        failureReasons.append(reason)
    }

    func trackWorkoutAnalysisCompleted(isSample: Bool) {
        completedSamples.append(isSample)
    }
}

@MainActor
private final class AnalysisSuspension {
    private let onSuspend: () -> Void
    private var continuation: CheckedContinuation<Void, Never>?

    init(onSuspend: @escaping () -> Void) {
        self.onSuspend = onSuspend
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            onSuspend()
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private enum LegacyAnalysisSchema {
    @Model
    final class WorkoutAnalysis {
        @Attribute(.unique) var workoutId: UUID
        var analysisText: String
        var analyzedAt: Date

        init(workoutId: UUID, analysisText: String) {
            self.workoutId = workoutId
            self.analysisText = analysisText
            self.analyzedAt = Date()
        }
    }
}
