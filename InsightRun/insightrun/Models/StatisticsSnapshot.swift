import Foundation
import HealthKit

struct StatisticsTotals {
    let count: Int
    let distance: Double
    let duration: TimeInterval
    let averagePace: Double?
    let activeDays: Int

    init(workouts: [WorkoutModel], calendar: Calendar) {
        count = workouts.count
        var distance = 0.0
        var duration = 0.0
        var paceDistance = 0.0
        var paceDuration = 0.0
        var days = Set<Date>()
        for workout in workouts {
            days.insert(calendar.startOfDay(for: workout.startDate))
            let validDuration = workout.duration.isFinite && workout.duration > 0
            if validDuration { duration += workout.duration }
            if let meters = workout.distance, meters.isFinite, meters > 0 {
                distance += meters
                if validDuration {
                    paceDistance += meters
                    paceDuration += workout.duration
                }
            }
        }
        self.distance = distance
        self.duration = duration
        averagePace = paceDistance > 0 ? paceDuration / 60 / (paceDistance / 1000) : nil
        activeDays = days.count
    }
}

struct StatisticsSnapshot {
    let interval: DateInterval
    let previousInterval: DateInterval?
    let workouts: [WorkoutModel]
    let previousWorkouts: [WorkoutModel]
    let totals: StatisticsTotals
    let previousTotals: StatisticsTotals?
    let buckets: [StatisticsViewModel.PeriodData]
    let chartComponent: Calendar.Component
    let availableYears: [Int]
    let longestRun: WorkoutModel?
    let longestDuration: WorkoutModel?
    let distanceRecords: [Int: WorkoutModel]

    init(
        workouts all: [WorkoutModel], period: StatisticsViewModel.TimePeriod, year: Int,
        granularity: StatisticsViewModel.ChartGranularity, now: Date, calendar: Calendar
    ) {
        let runs = all.filter { $0.workoutType == .running && $0.startDate <= now }
        availableYears = Array(
            Set(
                runs.map { calendar.component(.year, from: $0.startDate) }
                    + [calendar.component(.year, from: now)])
        ).sorted(by: >)
        let ranges = Self.ranges(
            period: period, year: year, now: now,
            first: runs.map(\.startDate).min(), calendar: calendar)
        interval = ranges.current
        previousInterval = ranges.previous
        workouts = runs.filter { $0.startDate >= ranges.current.start && $0.startDate < ranges.current.end }
        previousWorkouts =
            ranges.previous.map { previous in
                runs.filter { $0.startDate >= previous.start && $0.startDate < previous.end }
            } ?? []
        totals = StatisticsTotals(workouts: workouts, calendar: calendar)
        previousTotals = ranges.previous == nil ? nil : StatisticsTotals(workouts: previousWorkouts, calendar: calendar)

        let days = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 0
        chartComponent = period == .thisWeek ? .day : (granularity == .month || days > 1096 ? .month : .weekOfYear)
        buckets = Self.makeBuckets(
            workouts: workouts, interval: interval, component: chartComponent, calendar: calendar)

        let validRuns = runs.filter {
            ($0.distance ?? 0).isFinite && ($0.distance ?? 0) > 0 && $0.duration.isFinite && $0.duration > 0
        }
        longestRun = validRuns.max { ($0.distance ?? 0) < ($1.distance ?? 0) }
        longestDuration = runs.filter { $0.duration.isFinite && $0.duration > 0 }.max { $0.duration < $1.duration }
        var records: [Int: WorkoutModel] = [:]
        for (index, target) in [5000.0, 10000, 21097.5, 42195].enumerated() {
            let tolerance = [250.0, 500, 1000, 1000][index]
            records[index] = validRuns.filter {
                ($0.distance ?? 0) >= target && ($0.distance ?? 0) <= target + tolerance
            }
            .min { $0.duration < $1.duration }
        }
        distanceRecords = records
    }

    static func ranges(
        period: StatisticsViewModel.TimePeriod, year: Int, now: Date, first: Date?,
        calendar: Calendar
    ) -> (current: DateInterval, previous: DateInterval?) {
        func shifted(_ date: Date, _ component: Calendar.Component, _ value: Int) -> Date {
            calendar.date(byAdding: component, value: value, to: date) ?? date
        }
        let start: Date
        let end: Date
        let previousStart: Date?
        let previousEnd: Date?
        switch period {
        case .thisWeek, .thisMonth:
            let component: Calendar.Component = period == .thisWeek ? .weekOfYear : .month
            start = calendar.dateInterval(of: component, for: now)?.start ?? calendar.startOfDay(for: now)
            end = now
            previousStart = shifted(start, component, -1)
            previousEnd = shifted(now, component, -1)
        case .sixMonths, .oneYear:
            let months = period == .sixMonths ? 6 : 12
            start = shifted(now, .month, -months)
            end = now
            previousStart = shifted(start, .month, -months)
            previousEnd = start
        case .specificYear:
            let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? now
            start = min(yearStart, now)
            end = min(shifted(yearStart, .year, 1), now)
            previousStart = yearStart <= now ? shifted(yearStart, .year, -1) : nil
            previousEnd = yearStart <= now ? shifted(end, .year, -1) : nil
        case .allTime:
            start = min(first ?? now, now)
            end = now
            previousStart = nil
            previousEnd = nil
        }
        let previous = previousStart.flatMap { previousStart in
            previousEnd.map { DateInterval(start: previousStart, end: max(previousStart, $0)) }
        }
        return (DateInterval(start: start, end: max(start, end)), previous)
    }

    private static func makeBuckets(
        workouts: [WorkoutModel], interval: DateInterval, component: Calendar.Component,
        calendar: Calendar
    ) -> [StatisticsViewModel.PeriodData] {
        guard interval.duration > 0 else { return [] }
        let grouped = Dictionary(grouping: workouts) { workout in
            calendar.dateInterval(of: component, for: workout.startDate)?.start ?? workout.startDate
        }
        var cursor = calendar.dateInterval(of: component, for: interval.start)?.start ?? interval.start
        var result: [StatisticsViewModel.PeriodData] = []
        while cursor < interval.end {
            let totals = StatisticsTotals(workouts: grouped[cursor] ?? [], calendar: calendar)
            result.append(
                .init(
                    date: cursor, distance: totals.distance, duration: totals.duration,
                    workoutCount: totals.count, averagePace: totals.averagePace))
            guard let next = calendar.date(byAdding: component, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        return result
    }
}
