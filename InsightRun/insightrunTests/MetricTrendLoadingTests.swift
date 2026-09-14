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
