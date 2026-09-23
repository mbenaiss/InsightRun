import XCTest

@testable import insightrun

@MainActor
final class WeeklySummaryViewModelTests: XCTestCase {
    private final class Sources {
        var hrv: Double = 60
        var coachingWeeks: [Date] = []
    }

    private let calendar = Calendar.current

    private func makeViewModel(_ sources: Sources) -> WeeklySummaryViewModel {
        WeeklySummaryViewModel(
            loadWorkouts: { start, _ in
                [WorkoutModel(id: UUID(), workoutType: .running, startDate: start, endDate: start.addingTimeInterval(1_800),
                              duration: 1_800, distance: 5_000, totalEnergyBurned: nil, sourceName: "Weekly tests",
                              sourceVersion: nil, metadata: nil, averageHeartRate: nil, maxHeartRate: nil,
                              elevationGain: nil, hasRoute: false)]
            },
            loadRecovery: { date in RecoveryMetrics(date: date, restingHeartRate: 50, hrvAverage: sources.hrv) },
            loadInsight: { snapshot in
                sources.coachingWeeks.append(snapshot.weekStart)
                return WeeklyCoachingInsight(tldr: "Consistent week", highlight: nil, detail: "Keep the easy runs easy.")
            }
        )
    }

    func testDashboardCardRefreshKeepsTheRecapCoachingAndDetails() async {
        let sources = Sources()
        let model = makeViewModel(sources)
        let today = calendar.startOfDay(for: Date())
        await model.load(for: today)
        XCTAssertEqual(model.coachingTLDR, "Consistent week")
        XCTAssertEqual(model.averageHRV, 60)

        await model.load(for: today, minimumRefreshInterval: 0, includeCoaching: false, includeDetails: false)

        XCTAssertEqual(model.coachingTLDR, "Consistent week")
        XCTAssertNotNil(model.coachingTimestamp)
        XCTAssertEqual(model.averageHRV, 60)
        XCTAssertEqual(sources.coachingWeeks.count, 1)
    }

    func testReopeningTheRecapAfterACardRefreshReloadsDetailsAndCoaching() async {
        let sources = Sources()
        let model = makeViewModel(sources)
        let today = calendar.startOfDay(for: Date())
        await model.load(for: today)
        sources.hrv = 70
        await model.load(for: today, minimumRefreshInterval: 0, includeCoaching: false, includeDetails: false)

        await model.load(minimumRefreshInterval: 60)
        await model.loadCoachingIfNeeded()

        XCTAssertEqual(model.averageHRV, 70)
        XCTAssertEqual(model.coachingTLDR, "Consistent week")
        XCTAssertEqual(sources.coachingWeeks.count, 2)
    }

    func testChangingWeekForTheCardClearsThePreviousWeekDetails() async throws {
        let sources = Sources()
        let model = makeViewModel(sources)
        let today = calendar.startOfDay(for: Date())
        await model.load(for: today)
        XCTAssertEqual(model.averageHRV, 60)
        let lastWeek = try XCTUnwrap(calendar.date(byAdding: .weekOfYear, value: -1, to: today))

        await model.load(for: lastWeek, minimumRefreshInterval: 60, includeCoaching: false, includeDetails: false)

        XCTAssertNil(model.averageHRV)
        XCTAssertTrue(model.dailyHRV.isEmpty)
        XCTAssertNil(model.distanceChange)
        XCTAssertTrue(model.coachingTLDR.isEmpty)
        XCTAssertNil(model.coachingTimestamp)

        sources.hrv = 40
        await model.load(minimumRefreshInterval: 60)
        await model.loadCoachingIfNeeded()

        XCTAssertEqual(model.averageHRV, 40)
        XCTAssertEqual(model.coachingTLDR, "Consistent week")
        XCTAssertEqual(sources.coachingWeeks.last, calendar.dateInterval(of: .weekOfYear, for: lastWeek)?.start)
    }
}
