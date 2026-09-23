import Foundation
import HealthKit
import XCTest

@testable import insightrun

@MainActor
final class TrainingInsightsTests: XCTestCase {
  private var calendar: Calendar {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(secondsFromGMT: 0)!
    return value
  }

  private func workout() -> WorkoutModel {
    WorkoutModel(
      id: UUID(), workoutType: .running, startDate: Date(timeIntervalSince1970: 1_700_000_000),
      endDate: Date(timeIntervalSince1970: 1_700_003_600), duration: 3600, distance: 10000,
      totalEnergyBurned: nil, sourceName: "Apple Watch", sourceVersion: "27", metadata: nil,
      averageHeartRate: 150, maxHeartRate: 170, elevationGain: 10, hasRoute: true,
      effortScore: 7, effortIsEstimated: true)
  }

  private func evidence(speed: Double = 3) -> WorkoutEvidence {
    WorkoutEvidence(
      measuredAt: "2026-09-21T12:00:00Z", source: "com.apple.health", device: "Watch",
      softwareVersion: "27",
      zones: nil, signals: [],
      phases: [
        WorkoutPhase(
          index: 0, startOffsetSeconds: 0, durationSeconds: 1200, heartRate: 140, speed: 3),
        WorkoutPhase(
          index: 2, startOffsetSeconds: 2400, durationSeconds: 1200, heartRate: 154, speed: speed),
      ])
  }

  func testCoverageDoesNotBridgeMissingMinutesOrMultiplyOverlappingSources() {
    let samples = [0.0, 5, 10, 590, 595, 600].flatMap { time in
      [
        WorkoutSamplePoint(time: time, value: 140, source: "a"),
        WorkoutSamplePoint(time: time, value: 140, source: "b"),
      ]
    }
    let result = WorkoutEvidenceCalculator.summarize(
      metric: "heartRate", samples: samples, duration: 600)
    XCTAssertEqual(result.coverage, 20.0 / 600, accuracy: 0.001)
    XCTAssertEqual(result.longestGapSeconds, 580)
    XCTAssertEqual(result.sourceCount, 2)
  }

  func testPhasesOmitSparseAndMixedSourceAverages() {
    let dense = stride(from: 0.0, through: 600, by: 5).map {
      WorkoutSamplePoint(time: $0, value: 140, source: "a")
    }
    XCTAssertNotNil(
      WorkoutEvidenceCalculator.phases(series: ["heartRate": dense], duration: 600).first?.heartRate
    )
    let mixed = dense + [WorkoutSamplePoint(time: 20, value: 180, source: "b")]
    XCTAssertNil(
      WorkoutEvidenceCalculator.phases(series: ["heartRate": mixed], duration: 600).first?.heartRate
    )
    XCTAssertNil(
      WorkoutEvidenceCalculator.phases(series: ["heartRate": Array(dense.prefix(2))], duration: 600)
        .first?.heartRate)
  }

  func testComparableRunProducesDescriptiveHeartRateChange() throws {
    let metrics = WorkoutMetrics(
      workout: workout(), totalElevationAscent: 10, totalElevationDescent: 10, evidence: evidence())
    let result = WorkoutExecution.calculate(metrics: metrics)
    XCTAssertEqual(try XCTUnwrap(result.heartRateChangePercent), 10, accuracy: 0.001)
    XCTAssertEqual(result.comparisonBasis, "speed_within_5_percent")
  }

  func testDifferentSpeedUnknownTerrainAndPausesPreventComparison() {
    let cases = [
      WorkoutMetrics(
        workout: workout(), totalElevationAscent: 10, totalElevationDescent: 10,
        evidence: evidence(speed: 4)),
      WorkoutMetrics(workout: workout(), evidence: evidence()),
      WorkoutMetrics(
        workout: workout(), totalElevationAscent: 10, totalElevationDescent: 10, pausedTime: 60,
        evidence: evidence()),
    ]
    for metrics in cases {
      let result = WorkoutExecution.calculate(metrics: metrics)
      XCTAssertNil(result.heartRateChangePercent)
      XCTAssertNotNil(result.unavailableReason)
    }
  }

  func testIntervalsMatchTheirOwnTargetsAndRecoveryExcludesDrift() {
    let run = workout()
    let intervals = [(IntervalType.work, 5.0), (.recovery, 7.0), (.work, 6.0)].enumerated().map {
      index, item in
      WorkoutInterval(
        index: index, type: item.0, startDate: run.startDate, endDate: run.endDate,
        duration: 300, distance: 1000, pace: item.1, averageHeartRate: 150, averagePower: 200,
        targetPaceMin: 4.9, targetPaceMax: 5.1)
    }
    let result = WorkoutExecution.calculate(
      metrics: WorkoutMetrics(workout: run, intervals: intervals, evidence: evidence()))
    XCTAssertEqual(result.intervalsWithinTarget, 1)
    XCTAssertEqual(result.intervalsWithTarget, 2)
    XCTAssertNotNil(result.workPaceVariationPercent)
    XCTAssertNil(result.heartRateChangePercent)
  }

  private func observations(
    day: Date, offsets: ClosedRange<Int>, source: String = "watch-a", value: Double = 100
  ) -> [RMSSDTrend.Observation] {
    offsets.flatMap { offset in
      let night = calendar.date(byAdding: .day, value: offset, to: day)!
      return (1...3).map {
        RMSSDTrend.Observation(
          date: night.addingTimeInterval(Double($0) * 300), night: night, value: value,
          source: source, category: "Apple Watch")
      }
    }
  }

  func testRMSSDReferenceExcludesCurrentNightAndWeightsNightsEqually() throws {
    let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
    let values =
      observations(day: day, offsets: -7 ... -1)
      + observations(day: day, offsets: 0...0, value: 200)
    let result = try XCTUnwrap(
      RMSSDTrend.calculate(
        observations: values, day: day, now: day.addingTimeInterval(86400), calendar: calendar))
    XCTAssertEqual(result.baselineMedian, 100)
    XCTAssertEqual(result.currentNight?.median, 200)
    XCTAssertEqual(result.baselineNights, 7)
    XCTAssertEqual(result.recentNights, 7)
  }

  func testRMSSDDeviceChangeStartsNewReferenceAndKeepsMissingNightUnknown() throws {
    let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
    let values =
      observations(day: day, offsets: -20 ... -4)
      + observations(day: day, offsets: -3 ... -1, source: "watch-b", value: 120)
    let result = try XCTUnwrap(
      RMSSDTrend.calculate(
        observations: values, day: day, now: day.addingTimeInterval(86400), calendar: calendar))
    XCTAssertEqual(result.baselineNights, 3)
    XCTAssertNil(result.baselineMedian)
    XCTAssertNil(result.currentNight)
    XCTAssertTrue(result.sourceChanged)
    XCTAssertEqual(result.nights.count, 3)
  }

  func testRMSSDHistoryUsesCalendarWindowAndDoesNotFillMissingNights() throws {
    let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
    let values =
      observations(day: day, offsets: -15 ... -5)
      + observations(day: day, offsets: -2 ... -1, value: 120)
    let result = try XCTUnwrap(
      RMSSDTrend.calculate(
        observations: values, day: day, now: day.addingTimeInterval(86400), calendar: calendar))
    let history = result.history(endingOn: day, calendar: calendar)
    XCTAssertEqual(history.count, 4)
    XCTAssertEqual(history.map(\.value), [100, 100, 120, 120])
    XCTAssertEqual(history.first?.date, calendar.date(byAdding: .day, value: -6, to: day))
    XCTAssertEqual(history.last?.date, calendar.date(byAdding: .day, value: -1, to: day))
    XCTAssertNil(result.currentNight)
  }

  func testRMSSDAnalysisKeepsItsReferenceSeparateAndInvalidatesChangedContext() throws {
    let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
    let values =
      observations(day: day, offsets: -7 ... -1)
      + observations(day: day, offsets: 0...0, value: 120)
    func metrics(_ values: [RMSSDTrend.Observation], now: Date) -> RecoveryMetrics {
      RecoveryMetrics(
        date: day, hrvAverage: 50,
        rmssd: RMSSDTrend.calculate(
          observations: values, day: day, now: now, calendar: calendar))
    }
    let original = metrics(values, now: day.addingTimeInterval(3600))
    let refreshed = metrics(values, now: day.addingTimeInterval(7200))
    let changed = metrics(
      observations(day: day, offsets: -7 ... -1, value: 80)
        + observations(day: day, offsets: 0...0, value: 120), now: day.addingTimeInterval(7200))
    XCTAssertEqual(
      ScoreAnalysisViewModel.contextSignature(original),
      ScoreAnalysisViewModel.contextSignature(refreshed))
    XCTAssertNotEqual(
      ScoreAnalysisViewModel.contextSignature(original),
      ScoreAnalysisViewModel.contextSignature(changed))
    XCTAssertEqual(original.recoveryScore, changed.recoveryScore)
    let prompt = ScoreAnalysisViewModel().testBuildMetricPrompt(
      metricType: .rmssd, value: 120, unit: "ms")
    XCTAssertTrue(prompt.contains("never the SDNN HRV reference"))
    XCTAssertTrue(prompt.contains("reference is still building"))
  }

  func testRMSSDRejectsFutureAndInsufficientSamples() {
    let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
    let values = observations(day: day, offsets: 1...1)
    XCTAssertNil(RMSSDTrend.calculate(observations: values, day: day, now: day, calendar: calendar))
    let sparse = observations(day: day, offsets: 0...0).prefix(2)
    let result = RMSSDTrend.calculate(
      observations: Array(sparse), day: day, now: day.addingTimeInterval(86400), calendar: calendar)
    XCTAssertNil(result?.currentNight)
    XCTAssertEqual(result?.baselineNights, 0)
  }

  func testPayloadPreservesSplitContextEffortAndFeedback() throws {
    let run = workout()
    let feedback = WorkoutFeedback(effort: 8, intent: "long", legs: "heavy", goalAchieved: "yes")
    WorkoutFeedbackStore.shared.save(feedback, for: run)
    defer { WorkoutFeedbackStore.shared.save(WorkoutFeedback(), for: run) }
    let split = Split(
      kilometer: 1, distance: 1000, time: 300, pace: 5, averageHeartRate: 150, averagePower: 210,
      elevationGain: 5, elevationLoss: 4)
    let data = WorkoutAIService().convertToWorkoutData(
      workout: run,
      metrics: WorkoutMetrics(workout: run, splits: [split], temperature: 19, evidence: evidence()))
    XCTAssertEqual(data.effortSource, "apple_estimated")
    XCTAssertEqual(data.feedback, feedback)
    XCTAssertEqual(data.splits?.first?.heartRate, 150)
    XCTAssertEqual(data.splits?.first?.power, 210)
    XCTAssertEqual(data.temperatureCelsius, 19)
    XCTAssertNotNil(data.evidence)
    XCTAssertNoThrow(try JSONEncoder().encode(data))
  }

  func testFeedbackSurvivesRelaunchAndCanBeCleared() throws {
    let suite = "TrainingInsightsTests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let run = workout()
    WorkoutFeedbackStore(defaults: defaults).save(
      WorkoutFeedback(effort: 8, intent: "easy"), for: run)
    let restored = WorkoutFeedbackStore(defaults: defaults)
    XCTAssertEqual(restored.feedback(for: run)?.effort, 8)
    restored.save(WorkoutFeedback(), for: run)
    XCTAssertNil(WorkoutFeedbackStore(defaults: defaults).feedback(for: run))
  }
}
