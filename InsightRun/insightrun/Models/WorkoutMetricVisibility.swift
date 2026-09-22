import Foundation

enum WorkoutChartMetric: Hashable {
  case heartRate, pace, elevation, power
}

extension WorkoutMetrics {
  var hasDisplayPerformanceMetrics: Bool {
    [minPace, maxSpeed, averageCadence, strideLength, runningPower, vo2Max]
      .contains { MetricDisplayValue.positive($0) != nil }
  }

  var hasDisplayRunningFormMetrics: Bool {
    [groundContactTime, verticalOscillation, groundContactTimeBalance, runningEfficiency]
      .contains { MetricDisplayValue.positive($0) != nil }
  }

  var displayHeartRateZones: [RecordedHeartRateZones.Zone] {
    (evidence?.zones?.zones ?? []).filter { MetricDisplayValue.positive($0.seconds) != nil }
  }

  var displaySplits: [Split] {
    (splits ?? []).filter { split in
      [split.distance, split.time, split.pace, split.averageHeartRate, split.averagePower]
        .contains { MetricDisplayValue.positive($0) != nil }
    }
  }

  var displayIntervals: [WorkoutInterval] {
    (intervals ?? []).filter { interval in
      [
        interval.duration, interval.distance, interval.pace, interval.averageHeartRate,
        interval.averagePower, interval.targetPaceMin, interval.targetPaceMax,
      ]
      .contains { MetricDisplayValue.positive($0) != nil }
    }
  }

  var displayChartMetrics: [WorkoutChartMetric] {
    let splits = displaySplits.filter { MetricDisplayValue.positive($0.distance) != nil }
    var charts: [WorkoutChartMetric] = []
    if splits.contains(where: { MetricDisplayValue.positive($0.averageHeartRate) != nil }) {
      charts.append(.heartRate)
    }
    if splits.contains(where: { MetricDisplayValue.positive($0.pace) != nil }) {
      charts.append(.pace)
    }
    if splits.contains(where: {
      MetricDisplayValue.positive($0.elevationGain) != nil
        || MetricDisplayValue.positive($0.elevationLoss) != nil
    }) {
      charts.append(.elevation)
    }
    if splits.contains(where: { MetricDisplayValue.positive($0.averagePower) != nil }) {
      charts.append(.power)
    }
    return charts
  }
}
