import HealthKit
import SwiftData
import XCTest

@testable import insightrun

@MainActor
final class StatisticsViewModelTests: XCTestCase {
    func workout(date: Date, distance: Double? = 10000, duration: Double = 3600, id: UUID = UUID()) -> WorkoutModel {
        WorkoutModel(
            id: id, workoutType: .running, startDate: date,
            endDate: date.addingTimeInterval(duration), duration: duration, distance: distance,
            totalEnergyBurned: nil, sourceName: "Statistics tests", sourceVersion: nil, metadata: nil,
            averageHeartRate: nil, maxHeartRate: nil, elevationGain: nil, hasRoute: false)
    }

    func testLargeHistoryOverviewReads() async {
        let vm = StatisticsViewModel()
        let now = Date()
        vm.workouts = (0..<2000).map { workout(date: now.addingTimeInterval(-Double($0 + 1) * 86400)) }
        vm.selectedPeriod = .allTime
        let started = ContinuousClock.now
        var total = 0.0
        for _ in 0..<20 {
            total += vm.totalDistance + vm.totalDuration + (vm.averagePace ?? 0)
            total += vm.sparklineWorkouts.reduce(0, +) + vm.sparklineDistance.reduce(0, +)
            total += vm.sparklineDuration.reduce(0, +) + vm.sparklinePace.reduce(0, +)
            total += Double(
                vm.periodDistanceData.count + vm.paceDistributionData.count + vm.distanceDistributionData.count)
            total += vm.longestRun?.distance ?? 0
            total += vm.best5K?.duration ?? 0
            total += vm.best10K?.duration ?? 0
        }
        print("STATISTICS_OVERVIEW_2000_RUNS_20_READS=\(started.duration(to: .now))")
        XCTAssertGreaterThan(total, 0)
    }
}

extension StatisticsViewModelTests {
    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Paris")!
        value.firstWeekday = 2
        return value
    }

    func date(_ year: Int = 2026, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func model(at now: Date? = nil) -> StatisticsViewModel {
        let instant = now ?? date(2026, 9, 16)
        return StatisticsViewModel(now: { instant }, calendar: calendar, fetchWorkouts: { [] })
    }

    func testPeriodSummaryUsesSelectedWindowAndComparablePreviousMonth() async {
        let vm = model()
        vm.workouts = [
            workout(date: date(2026, 9, 15)), workout(date: date(2026, 9, 1)),
            workout(date: date(2026, 8, 15)), workout(date: date(2026, 8, 29)),
            workout(date: date(2026, 9, 20)),
        ]
        XCTAssertEqual(vm.totalWorkouts, 2)
        XCTAssertEqual(vm.totalDistance, 20000)
        XCTAssertEqual(vm.snapshot.previousTotals?.count, 1)
        vm.selectedPeriod = .thisWeek
        XCTAssertEqual(vm.totalWorkouts, 1)
        vm.selectedPeriod = .allTime
        XCTAssertEqual(vm.totalWorkouts, 4)
        XCTAssertNil(vm.snapshot.previousTotals)
        vm.selectedPeriod = .specificYear
        vm.selectedYear = 2025
        XCTAssertEqual(vm.totalWorkouts, 0)
    }

    func testCalendarMonthsLeapYearsAndFutureYearHaveValidWindows() async {
        let instant = date(2024, 3, 31)
        let vm = model(at: instant)
        vm.selectedPeriod = .sixMonths
        XCTAssertEqual(vm.snapshot.interval.start, date(2023, 9, 30))
        vm.selectedPeriod = .thisMonth
        XCTAssertEqual(vm.snapshot.previousInterval?.end, date(2024, 2, 29))
        vm.selectedPeriod = .specificYear
        vm.selectedYear = 2023
        XCTAssertEqual(vm.snapshot.interval.start, date(2023, 1, 1, hour: 0))
        XCTAssertEqual(vm.snapshot.interval.end, date(2024, 1, 1, hour: 0))
        XCTAssertEqual(vm.snapshot.previousInterval?.start, date(2022, 1, 1, hour: 0))
        vm.selectedYear = 2027
        XCTAssertEqual(vm.snapshot.interval.duration, 0)
        XCTAssertNil(vm.snapshot.previousInterval)
    }

    func testInvalidDistancesDoNotDistortPaceRecordsOrDistributions() async {
        let vm = model()
        vm.workouts = [
            workout(date: date(2026, 9, 1), distance: 5000, duration: 1800),
            workout(date: date(2026, 9, 2), distance: nil, duration: 600),
            workout(date: date(2026, 9, 3), distance: 0, duration: 900),
            workout(date: date(2026, 9, 4), distance: .nan, duration: .infinity),
            workout(date: date(2026, 9, 5), distance: 10000, duration: 3000),
        ]
        XCTAssertEqual(vm.totalDistance, 15000)
        XCTAssertEqual(vm.totalDuration, 6300)
        XCTAssertEqual(vm.averagePace ?? 0, 4800.0 / 60 / 15, accuracy: 0.0001)
        XCTAssertEqual(vm.distanceDistributionData.map(\.count).reduce(0, +), 2)
        XCTAssertEqual(vm.distanceDistributionData.map(\.percentage).reduce(0, +), 100, accuracy: 0.001)
        XCTAssertEqual(vm.paceDistributionData.map(\.percentage).reduce(0, +), 100, accuracy: 0.001)
        XCTAssertTrue(vm.paceDistributionData.allSatisfy { $0.zoneLabel.isEmpty })
    }

    func testTimelineIncludesMissingWeeksAndDoesNotInventFutureZeros() async {
        let vm = model()
        vm.workouts = [workout(date: date(2026, 9, 1)), workout(date: date(2026, 9, 15))]
        let buckets = vm.periodDistanceData
        XCTAssertEqual(buckets.count, 3)
        XCTAssertEqual(buckets.map(\.workoutCount), [1, 0, 1])
        XCTAssertEqual(buckets.map(\.id), vm.periodDistanceData.map(\.id))
        XCTAssertTrue(buckets.allSatisfy { $0.date < date(2026, 9, 16) })
        XCTAssertEqual(vm.sparklinePace.count, 2)
        vm.selectedPeriod = .thisWeek
        XCTAssertEqual(vm.snapshot.chartComponent, .day)
        XCTAssertEqual(vm.periodDistanceData.count, 3)
    }

    func testCalendarBucketsAcrossDaylightSavingKeepTotalsAndIdentities() async {
        for zone in ["Europe/Paris", "America/New_York", "Pacific/Auckland"] {
            var cal = calendar
            cal.timeZone = TimeZone(identifier: zone)!
            let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 12))!
            let vm = StatisticsViewModel(now: { now }, calendar: cal, fetchWorkouts: { [] })
            vm.selectedPeriod = .sixMonths
            vm.workouts = (0..<30).map { offset in
                workout(date: cal.date(byAdding: .day, value: -offset - 1, to: now)!)
            }
            XCTAssertEqual(vm.periodDistanceData.map(\.distance).reduce(0, +), vm.totalDistance)
            XCTAssertEqual(Set(vm.periodDistanceData.map(\.id)).count, vm.periodDistanceData.count)
        }
    }

    func testSameIdentifierEditsInvalidateAllAggregatesAndRecords() async {
        let vm = model()
        let id = UUID()
        vm.workouts = [workout(date: date(2026, 9, 15), distance: 5000, id: id)]
        XCTAssertEqual(vm.totalDistance, 5000)
        XCTAssertEqual(vm.best5K?.id, id)
        vm.workouts = [workout(date: date(2026, 9, 15), distance: 10000, id: id)]
        XCTAssertEqual(vm.totalDistance, 10000)
        XCTAssertNil(vm.best5K)
        XCTAssertEqual(vm.best10K?.id, id)
        XCTAssertEqual(vm.periodDistanceData.map(\.distance).reduce(0, +), 10000)
    }

    func testRefreshCoalescesAndFailurePreservesAvailableData() async {
        var calls = 0
        var failure = false
        let runs = [workout(date: date(2026, 9, 15))]
        let vm = StatisticsViewModel(fetchWorkouts: {
            calls += 1
            try await Task.sleep(for: .milliseconds(20))
            if failure { throw URLError(.notConnectedToInternet) }
            return runs
        })
        async let first: Void = vm.loadWorkouts()
        async let second: Void = vm.loadWorkouts()
        _ = await (first, second)
        XCTAssertEqual(calls, 1)
        await vm.loadWorkouts()
        XCTAssertEqual(calls, 1)
        failure = true
        await vm.refresh()
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(vm.workouts.count, 1)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
        failure = false
        await vm.refresh()
        XCTAssertNil(vm.errorMessage)
    }

    func testProgressionStartsWithPaceAndIgnoresCancelledPeriodResults() async {
        let instant = date(2026, 9, 16)
        let current = workout(date: date(2026, 9, 15))
        let previous = workout(date: date(2025, 9, 15))
        var completions: [UUID: CheckedContinuation<ProgressionDataPoint, Never>] = [:]
        let vm = StatisticsViewModel(
            now: { instant }, calendar: calendar, fetchWorkouts: { [] },
            fetchProgression: { run in
                await withCheckedContinuation { completions[run.id] = $0 }
            })
        vm.workouts = [current, previous]
        vm.loadProgressionMetrics()
        for _ in 0..<200 where completions[current.id] == nil { await Task.yield() }
        XCTAssertEqual(vm.progressionData.first?.averagePace, current.averagePace)
        vm.selectedPeriod = .specificYear
        vm.selectedYear = 2025
        vm.loadProgressionMetrics()
        completions[current.id]?.resume(returning: StatisticsViewModel.baseProgression(for: current))
        for _ in 0..<200 where completions[previous.id] == nil { await Task.yield() }
        completions[previous.id]?.resume(returning: StatisticsViewModel.baseProgression(for: previous))
        for _ in 0..<200 where vm.isLoadingProgression { await Task.yield() }
        XCTAssertEqual(vm.progressionData.map(\.workoutId), [previous.id])
        XCTAssertFalse(vm.isLoadingProgression)
        vm.cancelProgressionLoading()
    }

    func testProgressionReadsAreBoundedAndCached() async {
        let instant = date(2026, 9, 16)
        var calls = 0
        var active = 0
        var peak = 0
        let vm = StatisticsViewModel(
            now: { instant }, calendar: calendar, fetchWorkouts: { [] },
            fetchProgression: { run in
                calls += 1
                active += 1
                peak = max(peak, active)
                try? await Task.sleep(for: .milliseconds(2))
                active -= 1
                return StatisticsViewModel.baseProgression(for: run)
            })
        vm.workouts = (1...10).map { workout(date: date(2026, 9, $0)) }
        vm.loadProgressionMetrics()
        vm.loadProgressionMetrics()
        XCTAssertEqual(vm.performanceMetrics.first?.id, "averagePace")
        for _ in 0..<100 where vm.isLoadingProgression { try? await Task.sleep(for: .milliseconds(2)) }
        XCTAssertEqual(calls, 10)
        XCTAssertLessThanOrEqual(peak, 4)
        vm.loadProgressionMetrics()
        XCTAssertEqual(calls, 10)
        XCTAssertFalse(vm.isLoadingProgression)
    }
}

extension StatisticsViewModelTests {
    func monthlyContainer() throws -> ModelContainer {
        try ModelContainer(
            for: MonthlyStatsAnalysis.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    func testMonthlyInsightOnlyGeneratesOnRequestAndReusesValidCache() async throws {
        let container = try monthlyContainer()
        var calls = 0
        let vm = MonthlyCoachInsightViewModel(
            modelContext: container.mainContext, hasConsent: { true },
            requiresIndexation: { false },
            generate: { _, _ in
                calls += 1
                return "Your running volume increased by 10% over the same elapsed period."
            })
        let runs = [workout(date: date(2026, 9, 15))]
        await vm.loadInsight(thisMonth: runs, lastMonth: [])
        XCTAssertEqual(calls, 0)
        XCTAssertNil(vm.body)
        await vm.loadInsight(thisMonth: runs, lastMonth: [], generateIfNeeded: true)
        XCTAssertEqual(calls, 1)
        XCTAssertNotNil(vm.body)
        await vm.loadInsight(thisMonth: runs, lastMonth: [])
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<MonthlyStatsAnalysis>()), 1)
        let id = runs[0].id
        await vm.loadInsight(thisMonth: [workout(date: date(2026, 9, 15), distance: 12000, id: id)], lastMonth: [])
        XCTAssertNil(vm.body)
        XCTAssertEqual(calls, 1)
        await vm.generateInsight()
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<MonthlyStatsAnalysis>()), 1)
    }

    func testPreviousMonthChangesInvalidateInsightWithoutSpendingARequest() async throws {
        let container = try monthlyContainer()
        var calls = 0
        let vm = MonthlyCoachInsightViewModel(
            modelContext: container.mainContext, hasConsent: { true },
            requiresIndexation: { false },
            generate: { _, _ in
                calls += 1
                return "Your average pace changed while your distance remained similar this month."
            })
        let current = [workout(date: date(2026, 9, 15))]
        await vm.loadInsight(thisMonth: current, lastMonth: [], generateIfNeeded: true)
        await vm.loadInsight(thisMonth: current, lastMonth: [workout(date: date(2026, 8, 15))])
        XCTAssertNil(vm.body)
        XCTAssertEqual(calls, 1)
    }

    func testMonthlyConsentAndIndexationPreventGeneration() async throws {
        let container = try monthlyContainer()
        var consent = false
        var indexation = true
        var calls = 0
        let vm = MonthlyCoachInsightViewModel(
            modelContext: container.mainContext, hasConsent: { consent },
            requiresIndexation: { indexation },
            generate: { _, _ in
                calls += 1
                return "Your total running distance remains consistent across the two periods."
            })
        let runs = [workout(date: date(2026, 9, 15))]
        await vm.loadInsight(thisMonth: runs, lastMonth: [], generateIfNeeded: true)
        XCTAssertTrue(vm.needsConsent)
        XCTAssertEqual(calls, 0)
        consent = true
        await vm.generateInsight()
        XCTAssertTrue(vm.needsIndexation)
        XCTAssertFalse(vm.isLoading)
        XCTAssertEqual(calls, 0)
        indexation = false
        await vm.generateInsight()
        XCTAssertEqual(calls, 1)
        XCTAssertFalse(vm.needsIndexation)
    }

    func testMonthlyConcurrentRequestsAndLateResponsesCannotOverwriteNewData() async throws {
        let container = try monthlyContainer()
        var calls = 0
        var finish: CheckedContinuation<String, Error>?
        let vm = MonthlyCoachInsightViewModel(
            modelContext: container.mainContext, hasConsent: { true },
            requiresIndexation: { false },
            generate: { _, _ in
                calls += 1
                return try await withCheckedThrowingContinuation { finish = $0 }
            })
        let runs = [workout(date: date(2026, 9, 15))]
        let first = Task { await vm.loadInsight(thisMonth: runs, lastMonth: [], generateIfNeeded: true) }
        for _ in 0..<200 where finish == nil { await Task.yield() }
        guard finish != nil else {
            first.cancel()
            return XCTFail("Generation did not start")
        }
        await vm.generateInsight()
        XCTAssertEqual(calls, 1)
        await vm.loadInsight(thisMonth: runs + [workout(date: date(2026, 9, 14))], lastMonth: [])
        finish?.resume(returning: "This result belongs to an earlier snapshot and must not be saved.")
        await first.value
        XCTAssertNil(vm.body)
        XCTAssertFalse(vm.isLoading)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<MonthlyStatsAnalysis>()), 0)
    }

    func testMonthlyFailedRegenerationPreservesLastCompleteCache() async throws {
        let container = try monthlyContainer()
        var fail = false
        let text = "Your distance increased over the same number of days compared with last month."
        let vm = MonthlyCoachInsightViewModel(
            modelContext: container.mainContext, hasConsent: { true },
            requiresIndexation: { false },
            generate: { _, _ in
                if fail { throw URLError(.timedOut) }
                return text
            })
        let runs = [workout(date: date(2026, 9, 15))]
        await vm.loadInsight(thisMonth: runs, lastMonth: [], generateIfNeeded: true)
        fail = true
        await vm.regenerate()
        XCTAssertNotNil(vm.error)
        XCTAssertFalse(vm.isLoading)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<MonthlyStatsAnalysis>()).first?.body, text)
        await vm.loadInsight(thisMonth: runs, lastMonth: [])
        XCTAssertEqual(vm.body, text)
        XCTAssertNil(vm.error)
    }

    func testLegacyMonthlyInsightStoreMigratesWithoutLosingText() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("monthly.store")
        try autoreleasepool {
            let schema = Schema([LegacyMonthlySchema.MonthlyStatsAnalysis.self])
            let container = try ModelContainer(
                for: schema, configurations: ModelConfiguration(schema: schema, url: url))
            container.mainContext.insert(
                LegacyMonthlySchema.MonthlyStatsAnalysis(
                    monthKey: "2026-09-fr-v2", body: "Existing read.", workoutCount: 5))
            try container.mainContext.save()
        }
        let schema = Schema([MonthlyStatsAnalysis.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
        let entries = try container.mainContext.fetch(FetchDescriptor<MonthlyStatsAnalysis>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.body, "Existing read.")
        XCTAssertNil(entries.first?.dataFingerprint)
    }
}

private enum LegacyMonthlySchema {
    @Model final class MonthlyStatsAnalysis {
        @Attribute(.unique) var monthKey: String
        var body: String
        var workoutCount: Int
        var analyzedAt: Date
        init(monthKey: String, body: String, workoutCount: Int) {
            self.monthKey = monthKey
            self.body = body
            self.workoutCount = workoutCount
            self.analyzedAt = Date()
        }
    }
}

extension StatisticsViewModelTests {
    func testLargeProgressionChartsKeepExtremesWithoutRenderingEverySample() async {
        let start = date(2026, 1, 1)
        let points = (0..<5000).map { (date: start.addingTimeInterval(Double($0)), value: Double($0 % 71)) }
        let metric = StatisticsViewModel.MetricSeries(
            id: "cadence", name: "Cadence", icon: "", color: .green,
            unit: "spm", lowerIsBetter: false, metricInfoKey: nil, points: points)
        XCTAssertLessThanOrEqual(metric.chartPoints.count, 160)
        XCTAssertEqual(metric.chartPoints.first?.date, points.first?.date)
        XCTAssertEqual(metric.chartPoints.last?.date, points.last?.date)
        XCTAssertEqual(metric.chartPoints.map(\.value).min(), points.map(\.value).min())
        XCTAssertEqual(metric.chartPoints.map(\.value).max(), points.map(\.value).max())
        XCTAssertEqual(metric.average, points.map(\.value).reduce(0, +) / Double(points.count))
    }
}

extension StatisticsViewModelTests {
    func testProgressionAveragePaceMatchesOverviewWeightedByDistance() async {
        let vm = model()
        vm.workouts = [
            workout(date: date(2026, 9, 14), distance: 5000, duration: 1500),
            workout(date: date(2026, 9, 15), distance: 20000, duration: 7200),
        ]
        vm.progressionData = vm.workouts.map { StatisticsViewModel.baseProgression(for: $0) }
        XCTAssertEqual(vm.performanceMetrics.first?.average, vm.averagePace)
    }
}
