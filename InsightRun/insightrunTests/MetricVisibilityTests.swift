import HealthKit
import XCTest

@testable import insightrun

final class MetricVisibilityTests: XCTestCase {
  private func metrics() -> WorkoutMetrics {
    WorkoutMetrics(
      workout: WorkoutModel(
        id: UUID(), workoutType: .running, startDate: Date(), endDate: Date(),
        duration: 0, distance: nil, totalEnergyBurned: nil, sourceName: "Test",
        sourceVersion: nil, metadata: nil, averageHeartRate: nil, maxHeartRate: nil,
        elevationGain: nil, hasRoute: false))
  }

  private func split(
    distance: Double = 1000, pace: Double = 6, heartRate: Double? = nil,
    power: Double? = nil
  ) -> Split {
    Split(
      kilometer: 1, distance: distance, time: 360, pace: pace,
      averageHeartRate: heartRate, averagePower: power, elevationGain: 0, elevationLoss: nil)
  }

  func testUnavailableMeasurementsDoNotCreateSectionsOrCharts() {
    for value: Double? in [nil, 0, -1, .nan, .infinity] {
      var metrics = metrics()
      metrics.minPace = value
      metrics.maxSpeed = value
      metrics.averageCadence = value
      metrics.strideLength = value
      metrics.runningPower = value
      metrics.vo2Max = value
      metrics.groundContactTime = value
      metrics.verticalOscillation = value
      metrics.groundContactTimeBalance = value
      metrics.runningEfficiency = value
      metrics.splits = [split(pace: value ?? 0, heartRate: value, power: value)]
      XCTAssertFalse(metrics.hasDisplayPerformanceMetrics)
      XCTAssertFalse(metrics.hasDisplayRunningFormMetrics)
      XCTAssertTrue(metrics.displayChartMetrics.isEmpty)
    }
  }

  func testPartialWorkoutKeepsOnlyChartsBackedByMeasurements() {
    var metrics = metrics()
    metrics.runningPower = 200
    metrics.splits = [split(pace: 6, heartRate: 0, power: nil)]
    XCTAssertEqual(metrics.displayChartMetrics, [.pace])
    XCTAssertTrue(metrics.hasDisplayPerformanceMetrics)
    XCTAssertFalse(metrics.hasDisplayRunningFormMetrics)
    metrics.splits = [split(pace: 6, heartRate: 145, power: 220)]
    XCTAssertEqual(metrics.displayChartMetrics, [.heartRate, .pace, .power])
    metrics.groundContactTime = 240
    XCTAssertTrue(metrics.hasDisplayRunningFormMetrics)
  }

  func testMissingSplitSamplesDoNotBecomeZeroOrShiftLaterDistances() {
    var metrics = metrics()
    metrics.splits = [
      split(heartRate: 140, power: 180), split(heartRate: 0, power: 0),
      split(heartRate: 150, power: 200),
    ]
    let heartRate = InteractiveHeartRateChart(metrics: metrics).heartRateData
    let power = InteractivePowerChart(metrics: metrics).powerData
    XCTAssertEqual(heartRate.map(\.km), [0, 1, 3])
    XCTAssertEqual(heartRate.map(\.value), [140, 140, 150])
    XCTAssertEqual(power.map(\.km), [0, 1, 3])
    XCTAssertEqual(power.map(\.value), [180, 180, 200])
  }

  func testEntirelyEmptySplitsAreHidden() {
    var metrics = metrics()
    metrics.splits = [
      Split(
        kilometer: 1, distance: 0, time: 0, pace: 0,
        averageHeartRate: nil, averagePower: 0,
        elevationGain: 0, elevationLoss: 0)
    ]
    XCTAssertTrue(metrics.displaySplits.isEmpty)
    XCTAssertTrue(metrics.displayIntervals.isEmpty)
    XCTAssertTrue(metrics.displayHeartRateZones.isEmpty)
  }

  func testRecordedZonesWithNoTimeAreHidden() {
    var metrics = metrics()
    metrics.evidence = WorkoutEvidence(
      measuredAt: Date().ISO8601Format(), source: "test", device: nil, softwareVersion: nil,
      zones: RecordedHeartRateZones(
        source: "system",
        zones: [
          .init(index: 0, minimum: nil, maximum: 130, seconds: 0),
          .init(index: 1, minimum: 130, maximum: 145, seconds: 240),
          .init(index: 2, minimum: 145, maximum: nil, seconds: .nan),
        ]), signals: [], phases: [])
    XCTAssertEqual(metrics.displayHeartRateZones.map(\.index), [1])
  }

  func testTemperatureCanBeNegativeButMissingAndZeroValuesAreHidden() {
    XCTAssertEqual(MetricDisplayValue.nonZero(-5), -5)
    XCTAssertEqual(MetricDisplayValue.nonZero(18), 18)
    for value: Double? in [nil, 0, .nan, .infinity, -.infinity] {
      XCTAssertNil(MetricDisplayValue.nonZero(value))
    }
  }
}
