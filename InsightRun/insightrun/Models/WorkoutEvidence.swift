import Foundation

struct RecordedHeartRateZones: Codable, Equatable {
  struct Zone: Codable, Equatable, Identifiable {
    var id: Int { index }
    let index: Int
    let minimum: Double?
    let maximum: Double?
    let seconds: Double
  }

  let source: String
  let zones: [Zone]
}

struct WorkoutSignalQuality: Codable, Equatable, Identifiable {
  var id: String { metric }
  let metric: String
  let sampleCount: Int
  let coverage: Double
  let longestGapSeconds: Double
  let sourceCount: Int
}

struct WorkoutPhase: Codable, Equatable, Identifiable {
  var id: Int { index }
  let index: Int
  let startOffsetSeconds: Double
  let durationSeconds: Double
  var heartRate: Double?
  var speed: Double?
  var power: Double?
  var strideLength: Double?
  var groundContactTime: Double?
  var verticalOscillation: Double?
}

struct WorkoutEvidence: Codable, Equatable {
  let measuredAt: String
  let source: String
  let device: String?
  let softwareVersion: String?
  let zones: RecordedHeartRateZones?
  let signals: [WorkoutSignalQuality]
  let phases: [WorkoutPhase]
}

struct WorkoutSamplePoint {
  let time: Double
  let value: Double
  let source: String
}

enum WorkoutEvidenceCalculator {
  static func summarize(
    metric: String, samples: [WorkoutSamplePoint], duration: Double,
    maximumGap: Double = 15
  ) -> WorkoutSignalQuality {
    let samples = samples.filter {
      $0.time.isFinite && $0.time >= 0 && $0.time <= duration && $0.value.isFinite && $0.value > 0
    }
    let times = Array(Set(samples.map(\.time))).sorted()
    guard duration > 0, let first = times.first, let last = times.last else {
      return WorkoutSignalQuality(
        metric: metric, sampleCount: 0, coverage: 0, longestGapSeconds: max(0, duration),
        sourceCount: 0)
    }
    let gaps = zip(times, times.dropFirst()).map { $1 - $0 }
    // Only interpolate between nearby observations; long gaps remain unobserved.
    let covered = gaps.filter { $0 <= maximumGap }.reduce(0, +)
    return WorkoutSignalQuality(
      metric: metric, sampleCount: samples.count, coverage: min(1, covered / duration),
      longestGapSeconds: ([first, duration - last] + gaps).max() ?? duration,
      sourceCount: Set(samples.map(\.source)).count
    )
  }

  static func phases(series: [String: [WorkoutSamplePoint]], duration: Double) -> [WorkoutPhase] {
    guard duration.isFinite, duration > 0 else { return [] }
    return (0..<3).map { index in
      let start = Double(index) * duration / 3
      let end = Double(index + 1) * duration / 3
      func average(_ metric: String) -> Double? {
        let samples = (series[metric] ?? []).filter {
          $0.time >= start && $0.time < end && $0.value.isFinite && $0.value > 0
        }
        guard
          summarize(
            metric: metric,
            samples: samples.map {
              WorkoutSamplePoint(time: $0.time - start, value: $0.value, source: $0.source)
            }, duration: end - start
          ).coverage >= 0.7
        else { return nil }
        let sources = Dictionary(grouping: samples, by: \.source)
        guard sources.count == 1 else { return nil }
        return samples.map(\.value).reduce(0, +) / Double(samples.count)
      }
      return WorkoutPhase(
        index: index, startOffsetSeconds: start, durationSeconds: end - start,
        heartRate: average("heartRate"), speed: average("speed"), power: average("power"),
        strideLength: average("strideLength"), groundContactTime: average("groundContactTime"),
        verticalOscillation: average("verticalOscillation")
      )
    }
  }
}

struct WorkoutExecution: Codable {
  var heartRateChangePercent: Double?
  var comparisonBasis: String?
  var unavailableReason: String?
  var workPaceVariationPercent: Double?
  var intervalsWithinTarget: Int?
  var intervalsWithTarget: Int?
  var strideLengthChangePercent: Double?
  var groundContactTimeChangePercent: Double?
  var verticalOscillationChangePercent: Double?

  static func calculate(metrics: WorkoutMetrics) -> WorkoutExecution {
    var result = WorkoutExecution()
    let work = (metrics.intervals ?? []).filter { $0.type == .work }
    let paces = work.compactMap(\.pace).filter { $0.isFinite && $0 > 0 }
    if paces.count >= 2 {
      let mean = paces.reduce(0, +) / Double(paces.count)
      let variance = paces.map { pow($0 - mean, 2) }.reduce(0, +) / Double(paces.count)
      result.workPaceVariationPercent = sqrt(variance) / mean * 100
    }
    let targets = work.filter {
      guard let pace = $0.pace, let lower = $0.targetPaceMin, let upper = $0.targetPaceMax else {
        return false
      }
      return pace.isFinite && lower > 0 && upper >= lower
    }
    if !targets.isEmpty {
      result.intervalsWithTarget = targets.count
      result.intervalsWithinTarget =
        targets.filter { interval in
          guard let pace = interval.pace, let lower = interval.targetPaceMin,
            let upper = interval.targetPaceMax
          else { return false }
          return pace >= lower && pace <= upper
        }.count
    }
    guard metrics.workout.duration >= 1200,
      (metrics.pausedTime ?? 0) <= 5,
      !(metrics.intervals ?? []).contains(where: { $0.type == .recovery })
    else {
      result.unavailableReason =
        "Requires a continuous run of at least 20 minutes without recovery intervals or significant pauses."
      return result
    }
    guard let first = metrics.evidence?.phases.first, let last = metrics.evidence?.phases.last,
      let firstHR = first.heartRate, let lastHR = last.heartRate, firstHR > 0
    else {
      result.unavailableReason = "Insufficient heart-rate coverage in the first or last third."
      return result
    }
    guard !(metrics.evidence?.signals ?? []).contains(where: { $0.sourceCount > 1 }) else {
      result.unavailableReason =
        "Multiple measurement sources prevent a consistent phase comparison."
      return result
    }
    guard
      metrics.workout.isIndoor
        || ((metrics.totalElevationAscent != nil && metrics.totalElevationDescent != nil)
          && ((metrics.totalElevationAscent ?? 0) + (metrics.totalElevationDescent ?? 0))
            / max(1, metrics.workout.distance ?? 0) < 0.01)
    else {
      result.unavailableReason = "Terrain is hilly or elevation coverage is unavailable."
      return result
    }
    if let a = first.speed, let b = last.speed, a > 0, abs(b / a - 1) <= 0.05 {
      result.comparisonBasis = "speed_within_5_percent"
      func change(_ first: Double?, _ last: Double?) -> Double? {
        guard let first, let last, first > 0 else { return nil }
        return (last / first - 1) * 100
      }
      result.strideLengthChangePercent = change(first.strideLength, last.strideLength)
      result.groundContactTimeChangePercent = change(
        first.groundContactTime, last.groundContactTime)
      result.verticalOscillationChangePercent = change(
        first.verticalOscillation, last.verticalOscillation)
    } else if let a = first.power, let b = last.power, a > 0, abs(b / a - 1) <= 0.05 {
      result.comparisonBasis = "power_within_5_percent"
    } else {
      result.unavailableReason =
        "Speed and power are not sufficiently similar between the first and last third."
      return result
    }
    result.heartRateChangePercent = (lastHR / firstHR - 1) * 100
    return result
  }
}
