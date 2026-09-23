import HealthKit
import XCTest
@testable import insightrun

@MainActor
final class DailyReadinessViewModelTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var cache: DailyMetricsCache!

    override func setUp() {
        suite = "coach-tests-\(UUID())"
        defaults = UserDefaults(suiteName: suite)
        cache = DailyMetricsCache.createForTesting(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        cache = nil
        defaults = nil
    }

    private func response(_ text: String = "A complete analysis.", source: String = "ai", score: Int = 80) -> DailyReadinessResponse {
        DailyReadinessResponse(score: score, status: "good", recommendation: text, summary: text,
                               detail: text, suggestedWorkoutType: "moderate", insights: [], coachingSource: source)
    }

    private func viewModel(
        cache customCache: DailyMetricsCache? = nil,
        loadWorkouts: @escaping @MainActor (Date, Date) async throws -> [WorkoutModel] = { _, _ in [] },
        fetch: @escaping @MainActor (DailyReadinessRequest) async throws -> DailyReadinessResponse
    ) -> DailyReadinessViewModel {
        DailyReadinessViewModel(dailyCache: customCache ?? cache, hasConsent: { true }, requiresIndexation: { false },
                                loadNoSleepMode: { true }, loadWorkouts: loadWorkouts, fetchReadiness: fetch,
                                isDemo: { false })
    }

    private func baseline(restingHeartRate: Double) -> PersonalBaseline {
        PersonalBaseline(id: UUID(), computedAt: Date(), dataPointCount: 14,
                         restingHeartRateAverage: restingHeartRate, restingHeartRateStdDev: 3,
                         hrvAverage: 70, hrvStdDev: 10, walkingHeartRateAverage: 100, walkingHeartRateStdDev: 5,
                         respiratoryRateAverage: 14, respiratoryRateStdDev: 1,
                         oxygenSaturationAverage: 97, oxygenSaturationStdDev: 1,
                         sleepDurationAverage: 7 * 3600, sleepEfficiencyAverage: 90,
                         deepSleepPercentageAverage: 18, remSleepPercentageAverage: 22)
    }

    private func sleep(hours: Double) -> SleepData {
        let end = Calendar.current.startOfDay(for: Date()).addingTimeInterval(7 * 3600)
        return SleepData(date: end, sleepStart: end.addingTimeInterval(-hours * 3600), sleepEnd: end,
                         totalSleepDuration: hours * 3600, timeInBed: hours * 3600 / 0.9,
                         deepSleepDuration: nil, coreSleepDuration: nil, remSleepDuration: nil,
                         awakeDuration: nil, napDuration: nil)
    }

    private func activity(steps: Double, calories: Double = 100, minutes: Double = 10, basal: Double = 500) -> DailyActivityData {
        DailyActivityData(steps: steps, activeCalories: calories, basalCalories: basal,
                          exerciseMinutes: minutes, activeCaloriesGoal: nil, exerciseMinutesGoal: nil)
    }

    func testSmallActivityChangesReuseAnalysisButMeaningfulEffortRefreshesIt() async {
        var requests: [DailyReadinessRequest] = []
        let model = viewModel { requests.append($0); return self.response() }
        let recovery = RecoveryMetrics(date: Date(), restingHeartRate: 50, hrvAverage: 75)
        await model.fetchDailyReadiness(recoveryMetrics: recovery, activityData: activity(steps: 1000), effortScore: 20)
        await model.fetchDailyReadiness(recoveryMetrics: recovery, activityData: activity(steps: 1100, calories: 101, basal: 900), effortScore: 21)
        XCTAssertEqual(requests.count, 1)
        await model.fetchDailyReadiness(recoveryMetrics: recovery, activityData: activity(steps: 5000, minutes: 25), effortScore: 60)
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.last?.cachedScore, 80)
        XCTAssertEqual(model.readinessScore, 80)
    }

    func testIntradayVitalsAndBaselineRefreshKeepTheFrozenScore() async {
        var requests: [DailyReadinessRequest] = []
        let model = viewModel { request in
            requests.append(request)
            return self.response(score: request.cachedScore == nil ? 80 : 70)
        }
        let morning = RecoveryMetrics(date: Date(), restingHeartRate: 50, hrvAverage: 75, walkingHeartRate: 95,
                                      sleepData: sleep(hours: 7), respiratoryRate: 14, oxygenSaturation: 98,
                                      baseline: baseline(restingHeartRate: 50))
        await model.fetchDailyReadiness(recoveryMetrics: morning)
        let afternoon = RecoveryMetrics(date: Date(), restingHeartRate: 58, hrvAverage: 75, walkingHeartRate: 112,
                                        sleepData: sleep(hours: 7), respiratoryRate: 17, oxygenSaturation: 94,
                                        baseline: baseline(restingHeartRate: 53))
        await model.fetchDailyReadiness(recoveryMetrics: afternoon)
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.last?.cachedScore, 80)
        XCTAssertEqual(model.readinessScore, 80)
        XCTAssertEqual(cache.getCachedScoreForToday()?.score, 80)
    }

    func testLateNightDataRecomputesTheScore() async {
        var requests: [DailyReadinessRequest] = []
        let model = viewModel { request in
            requests.append(request)
            return self.response(score: request.recovery.sleepData == nil ? 80 : 62)
        }
        await model.fetchDailyReadiness(recoveryMetrics: RecoveryMetrics(date: Date(), restingHeartRate: 50))
        let syncedNight = RecoveryMetrics(date: Date(), restingHeartRate: 50, hrvAverage: 48, sleepData: sleep(hours: 5.5))
        await model.fetchDailyReadiness(recoveryMetrics: syncedNight)
        XCTAssertEqual(requests.count, 2)
        XCTAssertNil(requests.last?.cachedScore)
        XCTAssertEqual(model.readinessScore, 62)
        await model.fetchDailyReadiness(recoveryMetrics: syncedNight, effortScore: 60)
        XCTAssertEqual(requests.last?.cachedScore, 62)
    }

    func testLanguageChangeKeepsTheFrozenScore() async {
        var requests: [DailyReadinessRequest] = []
        let recovery = RecoveryMetrics(date: Date(), restingHeartRate: 50, hrvAverage: 75)
        let french = DailyMetricsCache.createForTesting(defaults: defaults, language: "fr")
        await viewModel(cache: french) { requests.append($0); return self.response() }
            .fetchDailyReadiness(recoveryMetrics: recovery)
        let english = DailyMetricsCache.createForTesting(defaults: defaults, language: "en")
        XCTAssertNil(english.getReadiness(for: Date()))
        let model = viewModel(cache: english) { requests.append($0); return self.response(score: 70) }
        await model.fetchDailyReadiness(recoveryMetrics: recovery)
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.last?.cachedScore, 80)
        XCTAssertEqual(model.readinessScore, 80)
    }

    func testScoreCachedBeforeTheLanguageIndependentKeyStaysFrozen() async {
        cache.cacheReadiness(score: 77, status: "excellent", recommendation: "Morning advice", workoutType: "moderate",
                             inputSignature: "legacy")
        defaults.removeObject(forKey: "com.insightrun.dailyReadinessScore")
        var requests: [DailyReadinessRequest] = []
        let model = viewModel { requests.append($0); return self.response(score: 67) }
        await model.fetchDailyReadiness(recoveryMetrics: RecoveryMetrics(date: Date(), restingHeartRate: 50, hrvAverage: 75))
        XCTAssertEqual(requests.last?.cachedScore, 77)
        XCTAssertEqual(model.readinessScore, 77)
        XCTAssertNil(cache.getCachedScoreForToday(nightSignature: "unrelated"))
        XCTAssertEqual(cache.getCachedScoreForToday()?.score, 77)
    }

    func testNewWorkoutInvalidatesAnalysisAndUsesOnlyCompletedRuns() async {
        var workouts: [WorkoutModel] = []
        var requests: [DailyReadinessRequest] = []
        let model = viewModel(loadWorkouts: { _, _ in workouts }) { requests.append($0); return self.response() }
        let recovery = RecoveryMetrics(date: Date(), hrvAverage: 75)
        await model.fetchDailyReadiness(recoveryMetrics: recovery)
        workouts = [WorkoutModel(id: UUID(), workoutType: .running, startDate: Date().addingTimeInterval(-7200), endDate: Date().addingTimeInterval(-3600), duration: 3600, distance: 10000, totalEnergyBurned: nil, sourceName: "Test", sourceVersion: nil, metadata: nil, averageHeartRate: nil, maxHeartRate: nil, elevationGain: nil, hasRoute: false)]
        await model.fetchDailyReadiness(recoveryMetrics: recovery)
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.last?.recentWorkouts?.first?.distanceMeters, 10000)
        XCTAssertGreaterThanOrEqual(requests.last?.recentWorkouts?.first?.hoursAgo ?? -1, 0)
    }

    func testCachedAnalysisAppearsBeforeLoadingAndSurvivesFailure() async {
        cache.cacheReadiness(score: 80, status: "good", recommendation: "Previous advice", workoutType: "moderate")
        var fail = true
        let model = viewModel { _ in
            if fail { throw URLError(.notConnectedToInternet) }
            return self.response("Updated advice")
        }
        model.restoreCachedReadiness(for: Date())
        XCTAssertEqual(model.recommendation, "Previous advice")
        let recovery = RecoveryMetrics(date: Date(), hrvAverage: 75)
        await model.fetchDailyReadiness(recoveryMetrics: recovery)
        XCTAssertEqual(model.recommendation, "Previous advice")
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(cache.getReadiness(for: Date())?.recommendation, "Previous advice")
        fail = false
        await model.fetchDailyReadiness(recoveryMetrics: recovery, forceRefresh: true)
        XCTAssertEqual(model.recommendation, "Updated advice")
        XCTAssertNil(model.errorMessage)
    }

    func testIdenticalConcurrentRequestsShareOneBackendCall() async {
        var calls = 0
        var continuation: CheckedContinuation<DailyReadinessResponse, Never>?
        let started = expectation(description: "Backend started")
        let model = viewModel { _ in
            calls += 1
            started.fulfill()
            return await withCheckedContinuation { continuation = $0 }
        }
        let recovery = RecoveryMetrics(date: Date(), hrvAverage: 75)
        let first = Task { await model.fetchDailyReadiness(recoveryMetrics: recovery) }
        await fulfillment(of: [started], timeout: 2)
        let second = Task { await model.fetchDailyReadiness(recoveryMetrics: recovery) }
        for _ in 0..<20 { await Task.yield() }
        continuation?.resume(returning: response())
        await first.value
        await second.value
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(model.recommendation, "A complete analysis.")
        XCTAssertFalse(model.isLoading)
    }

    func testChangingDayRejectsLateResponseAndDoesNotCacheIt() async {
        var continuation: CheckedContinuation<DailyReadinessResponse, Never>?
        let started = expectation(description: "Backend started")
        let model = viewModel { _ in
            started.fulfill()
            return await withCheckedContinuation { continuation = $0 }
        }
        let task = Task { await model.fetchDailyReadiness(recoveryMetrics: RecoveryMetrics(date: Date(), hrvAverage: 75)) }
        await fulfillment(of: [started], timeout: 2)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        await model.fetchDailyReadiness(for: yesterday)
        continuation?.resume(returning: response("Late advice"))
        await task.value
        XCTAssertTrue(model.recommendation.isEmpty)
        XCTAssertNil(model.readinessScore)
        XCTAssertNil(cache.getReadiness(for: Date()))
        XCTAssertFalse(model.isLoading)
    }

    func testFailedWorkoutReadDoesNotSendIncompleteTrainingContext() async {
        var calls = 0
        let model = viewModel(loadWorkouts: { _, _ in throw URLError(.cannotLoadFromNetwork) }) { _ in
            calls += 1
            return self.response()
        }
        await model.fetchDailyReadiness(recoveryMetrics: RecoveryMetrics(date: Date(), hrvAverage: 75))
        XCTAssertEqual(calls, 0)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)
    }

    func testFallbackExpiresSoonerThanAIAnalysisAndKeepsItsSource() async {
        let model = viewModel { _ in self.response("Basic advice", source: "fallback") }
        await model.fetchDailyReadiness(recoveryMetrics: RecoveryMetrics(date: Date(), hrvAverage: 75))
        XCTAssertTrue(model.isFallback)
        let cached = cache.getReadiness(for: Date())!
        XCTAssertNotNil(cache.getCachedReadiness(effortScore: 0, cardiacLoadScore: nil, now: cached.cacheDate.addingTimeInterval(299)))
        XCTAssertNil(cache.getCachedReadiness(effortScore: 0, cardiacLoadScore: nil, now: cached.cacheDate.addingTimeInterval(301)))
        XCTAssertEqual(cache.getCachedScoreForToday()?.score, 80)
        cache.cacheReadiness(score: 80, status: "good", recommendation: "AI", workoutType: "moderate", coachingSource: "ai")
        let ai = cache.getReadiness(for: Date())!
        XCTAssertNotNil(cache.getCachedReadiness(effortScore: 0, cardiacLoadScore: nil, now: ai.cacheDate.addingTimeInterval(301)))
        XCTAssertNil(cache.getCachedReadiness(effortScore: 0, cardiacLoadScore: nil, now: ai.cacheDate.addingTimeInterval(3601)))
    }
}
