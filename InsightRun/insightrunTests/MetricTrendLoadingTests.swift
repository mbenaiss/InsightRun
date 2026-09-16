import HealthKit
import XCTest
@testable import insightrun

@MainActor
final class MetricTrendLoadingTests: XCTestCase {
    func testCalorieChartsShareDailyReadsAndProduceConsistentTotals() async {
        var calls = 0
        var active = 0
        var maxActive = 0
        let service = MetricTrendDataService { _ in
            calls += 1
            active += 1
            maxActive = max(maxActive, active)
            await Task.yield()
            active -= 1
            return DailyActivityData(steps: 100, activeCalories: 50, basalCalories: 150,
                                     exerciseMinutes: 10, activeCaloriesGoal: nil, exerciseMinutesGoal: nil)
        }
        async let totals = service.caloriesTotalTrend(days: 7)
        async let breakdown = service.caloriesBreakdownTrend(days: 7)
        let (totalPoints, breakdownPoints) = await (totals, breakdown)
        XCTAssertEqual(calls, 7)
        XCTAssertEqual(maxActive, 1)
        XCTAssertEqual(totalPoints.count, 7)
        XCTAssertEqual(totalPoints.map(\.value), breakdownPoints.map(\.total))
        XCTAssertEqual(totalPoints.map(\.date), breakdownPoints.map(\.date))
        _ = await service.caloriesTotalTrend(days: 7)
        XCTAssertEqual(calls, 7)
    }

    func testEmptyActivityReadDoesNotPreventLaterDataFromAppearing() async {
        var calls = 0
        var calories: Double = 0
        let service = MetricTrendDataService { _ in
            calls += 1
            return DailyActivityData(steps: 0, activeCalories: calories, basalCalories: 0,
                                     exerciseMinutes: 0, activeCaloriesGoal: nil, exerciseMinutesGoal: nil)
        }
        let first = await service.caloriesTotalTrend(days: 2)
        XCTAssertTrue(first.isEmpty)
        calories = 20
        let next = await service.caloriesBreakdownTrend(days: 2)
        XCTAssertEqual(calls, 4)
        XCTAssertEqual(next.map(\.total), [20, 20])
    }
}

extension MetricTrendLoadingTests {
    func testActivityHistoryUsesSelectedDayAndDoesNotOverwriteGlobalEffort() async {
        let day = Calendar.current.startOfDay(for: Date().addingTimeInterval(-10 * 86_400))
        var requested: [Date] = []
        let service = MetricTrendDataService { date in
            requested.append(date)
            return DailyActivityData(steps: 1000, activeCalories: 50, basalCalories: 150,
                                     exerciseMinutes: 10, activeCaloriesGoal: nil, exerciseMinutesGoal: nil)
        }
        let original = TrainingLoadService.shared.dailyEffortScore
        TrainingLoadService.shared.dailyEffortScore = 73
        defer { TrainingLoadService.shared.dailyEffortScore = original }
        let effort = await service.effortTrend(days: 3, endingOn: day)
        XCTAssertEqual(requested.last, day)
        XCTAssertEqual(effort.last?.date, day)
        XCTAssertEqual(requested.count, 3)
        XCTAssertEqual(TrainingLoadService.shared.dailyEffortScore, 73)
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        let totals = await service.caloriesTotalTrend(days: 3, endingOn: nextDay)
        XCTAssertEqual(totals.last?.date, nextDay)
        XCTAssertEqual(requested.count, 4)
    }

    func testRefreshInvalidatesActivityHistoryAndUsesNewValues() async {
        var calls = 0
        var calories: Double = 50
        let service = MetricTrendDataService { _ in
            calls += 1
            return DailyActivityData(steps: 1000, activeCalories: calories, basalCalories: 150,
                                     exerciseMinutes: 10, activeCaloriesGoal: nil, exerciseMinutesGoal: nil)
        }
        _ = await service.caloriesTotalTrend(days: 2)
        calories = 100
        service.invalidateCache()
        let values = await service.caloriesBreakdownTrend(days: 2)
        XCTAssertEqual(values.map(\.total), [250, 250])
        XCTAssertEqual(calls, 4)
    }

    func testDashboardActivityIsReusedByEveryActivityChart() async {
        var calls = 0
        let activity = DailyActivityData(steps: 1000, activeCalories: 50, basalCalories: 150,
                                         exerciseMinutes: 10, activeCaloriesGoal: nil, exerciseMinutesGoal: nil)
        let service = MetricTrendDataService { _ in calls += 1; return activity }
        service.seedActivity(activity, for: Date())
        async let effort = service.effortTrend(days: 7)
        async let totals = service.caloriesTotalTrend(days: 7)
        async let breakdown = service.caloriesBreakdownTrend(days: 7)
        let values = await (effort, totals, breakdown)
        XCTAssertEqual(calls, 6)
        XCTAssertEqual(values.0.last?.value, Double(MetricTrendDataService.computeEffortScore(activity: activity)))
        XCTAssertEqual(values.1.last?.value, values.2.last?.total)
    }

    func testReadinessTrendReflectsNewScoreWithoutWaitingForCacheExpiry() async {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let cache = DailyMetricsCache.createForTesting(defaults: defaults)
        let service = MetricTrendDataService()
        cache.cacheReadiness(score: 40, status: "fair", recommendation: "Rest", workoutType: "rest")
        let first = await service.readinessTrend(metricsCache: cache)
        cache.cacheReadiness(score: 82, status: "good", recommendation: "Ready", workoutType: "moderate")
        let updated = await service.readinessTrend(metricsCache: cache)
        XCTAssertEqual(first.last?.value, 40)
        XCTAssertEqual(updated.last?.value, 82)
    }

    func testHistoricalReadinessDoesNotReuseTodayOrInventMissingScore() async {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let cache = DailyMetricsCache.createForTesting(defaults: defaults)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        cache.cacheReadiness(score: 31, status: "poor", recommendation: "Yesterday", workoutType: "rest", date: yesterday)
        cache.cacheReadiness(score: 82, status: "good", recommendation: "Today", workoutType: "moderate")
        let viewModel = DailyReadinessViewModel(dailyCache: cache)
        await viewModel.fetchDailyReadiness(for: yesterday)
        XCTAssertEqual(viewModel.readinessScore, 31)
        XCTAssertEqual(viewModel.recommendation, "Yesterday")
        XCTAssertEqual(viewModel.status, .poor)
        await viewModel.fetchDailyReadiness(for: yesterday.addingTimeInterval(-86_400))
        XCTAssertNil(viewModel.readinessScore)
        XCTAssertTrue(viewModel.recommendation.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testChangedRecoveryInvalidatesFrozenScoreButActivityDoesNot() {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let cache = DailyMetricsCache.createForTesting(defaults: defaults)
        cache.cacheReadiness(score: 82, status: "good", recommendation: "Ready", workoutType: "moderate",
                             effortScore: 20, inputSignature: "activity-1", recoverySignature: "morning")
        XCTAssertNotNil(cache.getCachedReadiness(effortScore: 20, cardiacLoadScore: nil, inputSignature: "activity-1"))
        XCTAssertNil(cache.getCachedReadiness(effortScore: 20, cardiacLoadScore: nil, inputSignature: "activity-2"))
        XCTAssertEqual(cache.getCachedScoreForToday(recoverySignature: "morning")?.score, 82)
        XCTAssertNil(cache.getCachedScoreForToday(recoverySignature: "updated-sleep"))
    }

    func testRefreshCoordinatorCoalescesAndThrottlesAutomaticLoads() async {
        let coordinator = DashboardRefreshCoordinator()
        let day = Calendar.current.startOfDay(for: Date())
        var calls = 0
        let operation = { @MainActor in calls += 1; await Task.yield() }
        async let first: Void = coordinator.refresh(for: day, operation: operation)
        async let second: Void = coordinator.refresh(for: day, operation: operation)
        _ = await (first, second)
        await coordinator.refresh(for: day, operation: operation)
        XCTAssertEqual(calls, 1)
        await coordinator.refresh(for: day, force: true, operation: operation)
        XCTAssertEqual(calls, 2)
    }

    func testChangingDateCancelsOldLoadBeforePublishingNewDay() async {
        let coordinator = DashboardRefreshCoordinator()
        let day = Calendar.current.startOfDay(for: Date())
        var started = false
        var displayed: Date?
        let first = Task {
            await coordinator.refresh(for: day) {
                started = true
                while !Task.isCancelled { await Task.yield() }
                if !Task.isCancelled { displayed = day }
            }
        }
        while !started { await Task.yield() }
        let nextDay = day.addingTimeInterval(-86_400)
        await coordinator.refresh(for: nextDay) { displayed = nextDay }
        await first.value
        XCTAssertEqual(displayed, nextDay)
    }
}

extension MetricTrendLoadingTests {
    func testVitalAndSleepChartsShareRecoveryReadsWithWeeklyDetails() async {
        var calls = 0
        let service = MetricTrendDataService(recoveryLoader: { date in
            calls += 1
            await Task.yield()
            return MockData.recoveryMetrics(for: date)
        })
        let day = Calendar.current.startOfDay(for: Date())
        service.seedRecovery(MockData.recoveryMetrics(for: day), for: day)
        async let hrv = service.metricTrend(for: .hrv)
        async let restingHR = service.metricTrend(for: .restingHeartRate)
        async let respiratory = service.metricTrend(for: .respiratoryRate)
        async let oxygen = service.metricTrend(for: .oxygenSaturation)
        async let sleep = service.sleepTrend()
        let values = await (hrv, restingHR, respiratory, oxygen, sleep)
        XCTAssertEqual(calls, 6)
        XCTAssertEqual(values.0.count, 7)
        XCTAssertEqual(values.4.count, 7)
        for offset in 0..<3 {
            _ = try? await service.recoveryMetrics(for: Calendar.current.date(byAdding: .day, value: -offset, to: day)!)
        }
        XCTAssertEqual(calls, 6)
    }
}

extension MetricTrendLoadingTests {
    func testAutomaticRefreshReusesPastActivityAndUpdatesToday() async {
        var requested: [Date] = []
        let activity = DailyActivityData(steps: 1000, activeCalories: 50, basalCalories: 150,
                                         exerciseMinutes: 10, activeCaloriesGoal: nil, exerciseMinutesGoal: nil)
        let service = MetricTrendDataService { date in requested.append(date); return activity }
        _ = await service.caloriesTotalTrend(days: 3)
        service.invalidateCache(keepingHistoricalData: true)
        let updated = DailyActivityData(steps: 2000, activeCalories: 100, basalCalories: 150,
                                        exerciseMinutes: 20, activeCaloriesGoal: nil, exerciseMinutesGoal: nil)
        service.seedActivity(updated, for: Date())
        let points = await service.caloriesTotalTrend(days: 3)
        XCTAssertEqual(requested.count, 3)
        XCTAssertEqual(points.map(\.value), [200, 200, 250])
    }
}

private struct RecoveryScoreFixture: Decodable {
    let name: String
    let expected: Int
    let recovery: RecoveryData
    let baseline: PersonalBaselineData?
    let noSleepMode: Bool?

    @MainActor
    func metrics() -> RecoveryMetrics {
        let date = Date(timeIntervalSince1970: 1_789_516_800)
        let sleep = recovery.sleepData.map {
            SleepData(date: date, sleepStart: date.addingTimeInterval(-$0.totalDuration), sleepEnd: date,
                      totalSleepDuration: $0.totalDuration, timeInBed: $0.totalDuration * 100 / $0.efficiency,
                      deepSleepDuration: $0.deepDuration, coreSleepDuration: nil, remSleepDuration: $0.remDuration,
                      awakeDuration: nil, napDuration: nil)
        }
        let reference = baseline.map {
            PersonalBaseline(id: UUID(), computedAt: date, dataPointCount: $0.dataPointCount,
                             restingHeartRateAverage: $0.restingHeartRateAverage, restingHeartRateStdDev: $0.restingHeartRateStdDev,
                             hrvAverage: $0.hrvAverage, hrvStdDev: $0.hrvStdDev,
                             walkingHeartRateAverage: nil, walkingHeartRateStdDev: nil,
                             respiratoryRateAverage: $0.respiratoryRateAverage, respiratoryRateStdDev: $0.respiratoryRateStdDev,
                             oxygenSaturationAverage: nil, oxygenSaturationStdDev: nil,
                             sleepDurationAverage: $0.sleepDurationAverage, sleepEfficiencyAverage: $0.sleepEfficiencyAverage,
                             deepSleepPercentageAverage: $0.deepSleepPercentageAverage, remSleepPercentageAverage: $0.remSleepPercentageAverage)
        }
        return RecoveryMetrics(date: date, restingHeartRate: recovery.restingHeartRate, hrvAverage: recovery.hrv,
                               walkingHeartRate: recovery.walkingHeartRate, sleepData: noSleepMode == true ? nil : sleep,
                               respiratoryRate: recovery.respiratoryRate, oxygenSaturation: recovery.oxygenSaturation, baseline: reference)
    }
}

extension MetricTrendLoadingTests {
    func testRecoveryScoresMatchSharedBackendNumericalContract() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "recovery-scores", withExtension: "json"))
        let fixtures = try JSONDecoder().decode([RecoveryScoreFixture].self, from: Data(contentsOf: url))
        XCTAssertEqual(fixtures.count, 12)
        for fixture in fixtures {
            XCTAssertEqual(fixture.metrics().recoveryScore, fixture.expected, fixture.name)
        }
    }

    func testReadinessPayloadPreservesMeasurementsAndSleepReferences() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "recovery-scores", withExtension: "json"))
        let fixture = try JSONDecoder().decode([RecoveryScoreFixture].self, from: Data(contentsOf: url))[0]
        let source = fixture.metrics()
        let metrics = RecoveryMetrics(date: source.date, restingHeartRate: 50.6, hrvAverage: 75.4,
                                      sleepData: source.sleepData, respiratoryRate: 12.5, oxygenSaturation: 98.7, baseline: source.baseline)
        let payload = RecoveryData(metrics: metrics)
        let data = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
        XCTAssertEqual(data["restingHeartRate"] as? Double, 50.6)
        XCTAssertEqual(data["hrv"] as? Double, 75.4)
        XCTAssertEqual(data["respiratoryRate"] as? Double, 12.5)
        XCTAssertEqual(data["oxygenSaturation"] as? Double, 98.7)
        let baseline = PersonalBaselineData(baseline: try XCTUnwrap(source.baseline))
        XCTAssertEqual(baseline.deepSleepPercentageAverage, 18)
        XCTAssertEqual(baseline.remSleepPercentageAverage, 22)
    }

    func testSleepScoreMatchesDisplayedPointsAndIgnoresStages() {
        let date = Date()
        func sleep(hours: Double, efficiency: Double, deep: Double? = nil) -> SleepData {
            SleepData(date: date, sleepStart: date.addingTimeInterval(-hours * 3600), sleepEnd: date,
                      totalSleepDuration: hours * 3600, timeInBed: hours * 3600 * 100 / efficiency,
                      deepSleepDuration: deep, coreSleepDuration: nil, remSleepDuration: nil,
                      awakeDuration: nil, napDuration: nil)
        }
        XCTAssertEqual(sleep(hours: 8, efficiency: 90).qualityScore, 100)
        XCTAssertEqual(sleep(hours: 8, efficiency: 90, deep: 300).qualityScore, 100)
        XCTAssertEqual(sleep(hours: 6.5, efficiency: 80).qualityScore, 80)
        XCTAssertEqual(sleep(hours: 4, efficiency: 80).qualityScore, 45)
        XCTAssertEqual(sleep(hours: 10, efficiency: 90).qualityScore, 75)
        XCTAssertEqual(sleep(hours: 0, efficiency: 90).qualityScore, 0)
        XCTAssertEqual(sleep(hours: 8, efficiency: 120).sleepEfficiency, 100)
    }
}

extension MetricTrendLoadingTests {
    func testSleepSelectionCannotReuseAnEarlierNight() throws {
        let day = Calendar.current.startOfDay(for: Date())
        let type = try XCTUnwrap(HKObjectType.categoryType(forIdentifier: .sleepAnalysis))
        func sample(start: TimeInterval, end: TimeInterval) -> HKCategorySample {
            HKCategorySample(type: type, value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                             start: day.addingTimeInterval(start * 3600), end: day.addingTimeInterval(end * 3600))
        }
        let previousNight = [sample(start: -25, end: -17)]
        XCTAssertNil(HealthKitManager.selectSleepSession([previousNight], for: day))
        let currentNight = [sample(start: -1, end: 7)]
        XCTAssertEqual(HealthKitManager.selectSleepSession([previousNight, currentNight], for: day)?.first?.uuid, currentNight.first?.uuid)
        let daytimeSleep = [sample(start: 15, end: 17)]
        XCTAssertEqual(HealthKitManager.selectSleepSession([previousNight, daytimeSleep], for: day)?.first?.uuid, daytimeSleep.first?.uuid)
    }

    func testCardiacLoadMatchesTRIMPAndPersonalNormalization() {
        let service = TrainingLoadService.shared
        let date = Date()
        let workout = WorkoutModel(id: UUID(), workoutType: .running, startDate: date,
                                   endDate: date.addingTimeInterval(2700), duration: 2700, distance: 8000,
                                   totalEnergyBurned: nil, sourceName: "Numerical fixture", sourceVersion: nil, metadata: nil,
                                   averageHeartRate: 150, maxHeartRate: nil, elevationGain: nil, hasRoute: false, isIndoor: false)
        XCTAssertEqual(service.workoutLoad(workout: workout, restingHR: 50, maxHR: 190, biologicalSex: .male), 81.0715195052, accuracy: 0.000001)
        XCTAssertEqual(service.workoutLoad(workout: workout, restingHR: 50, maxHR: 190, biologicalSex: .female), 91.1242997930, accuracy: 0.000001)
        XCTAssertEqual(service.cardiacScore(acuteLoad: 44.6, chronicLoad: 26.6), 16)
        XCTAssertEqual(service.cardiacScore(acuteLoad: 40, chronicLoad: 40), 10)
        XCTAssertEqual(service.cardiacScore(acuteLoad: 80, chronicLoad: 20), 20)
        XCTAssertEqual(service.cardiacScore(acuteLoad: 20, chronicLoad: 5), 5)
        XCTAssertEqual(service.cardiacScore(acuteLoad: 0, chronicLoad: 0), 0)
        XCTAssertEqual(TrainingLoadService.freshnessScoreFromTSB(26.6 - 44.6), 28)
    }

    func testEffortRejectsInvalidGoalsAndBoundsEachContribution() {
        let activity = DailyActivityData(steps: 5000, activeCalories: 200, basalCalories: 0, exerciseMinutes: 15,
                                         activeCaloriesGoal: 0, exerciseMinutesGoal: -5)
        XCTAssertEqual(MetricTrendDataService.computeEffortScore(activity: activity), 50)
        let invalid = DailyActivityData(steps: -.infinity, activeCalories: -20, basalCalories: 0, exerciseMinutes: .nan,
                                        activeCaloriesGoal: nil, exerciseMinutesGoal: nil)
        XCTAssertEqual(MetricTrendDataService.computeEffortScore(activity: invalid), 0)
    }

    func testMissingRecoveryMeasurementsCannotProduceAPresentableScore() {
        let date = Date()
        XCTAssertFalse(RecoveryMetrics(date: date).hasRecoveryMeasurements())
        XCTAssertFalse(RecoveryMetrics(date: date, walkingHeartRate: 90).hasRecoveryMeasurements())
        XCTAssertTrue(RecoveryMetrics(date: date, oxygenSaturation: 98).hasRecoveryMeasurements())
        let sleep = SleepData(date: date, sleepStart: date, sleepEnd: date.addingTimeInterval(8 * 3600),
                              totalSleepDuration: 8 * 3600, timeInBed: 9 * 3600,
                              deepSleepDuration: nil, coreSleepDuration: nil, remSleepDuration: nil,
                              awakeDuration: nil, napDuration: nil)
        let metrics = RecoveryMetrics(date: date, sleepData: sleep)
        XCTAssertTrue(metrics.hasRecoveryMeasurements())
        XCTAssertFalse(metrics.hasRecoveryMeasurements(includeSleep: false))
    }

    func testConflictingSleepStagesKeepSleepDurationAndEfficiency() throws {
        let date = Date()
        let sleep = SleepData(date: date, sleepStart: date.addingTimeInterval(-8 * 3600), sleepEnd: date,
                              totalSleepDuration: 8 * 3600, timeInBed: 9 * 3600,
                              deepSleepDuration: 2 * 3600, coreSleepDuration: 6 * 3600,
                              remSleepDuration: 2 * 3600, awakeDuration: nil, napDuration: nil)
        XCTAssertNil(sleep.deepSleepDuration)
        XCTAssertNil(sleep.coreSleepDuration)
        XCTAssertNil(sleep.remSleepDuration)
        XCTAssertEqual(sleep.totalSleepDuration, 8 * 3600)
        XCTAssertEqual(sleep.qualityScore, 100)
        let metrics = RecoveryMetrics(date: date, hrvAverage: 60, sleepData: sleep, oxygenSaturation: 98)
        let payload = RecoveryData(metrics: metrics)
        XCTAssertEqual(payload.hrv, 60)
        XCTAssertEqual(payload.oxygenSaturation, 98)
        XCTAssertEqual(payload.sleepData?.totalDuration, 8 * 3600)
        XCTAssertNil(payload.sleepData?.deepDuration)
        XCTAssertNil(payload.sleepData?.remDuration)
    }
}
