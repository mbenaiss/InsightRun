import Foundation
import HealthKit

@MainActor
struct HealthInsightReader {
  let store: HKHealthStore

  static var rmssdType: HKQuantityType? {
    guard #available(iOS 27.0, *) else { return nil }
    // The public identifier is available on devices before this SDK exposes its Swift member.
    return HKQuantityType.quantityType(
      forIdentifier: HKQuantityTypeIdentifier(
        rawValue: "HKQuantityTypeIdentifierHeartRateVariabilityRMSSD"))
  }

  func workoutEvidence(for workout: HKWorkout) async -> WorkoutEvidence {
    let quantities: [(String, HKQuantityTypeIdentifier, HKUnit)] = [
      ("heartRate", .heartRate, .count().unitDivided(by: .minute())),
      ("speed", .runningSpeed, .meter().unitDivided(by: .second())),
      ("power", .runningPower, .watt()),
      ("strideLength", .runningStrideLength, .meter()),
      ("groundContactTime", .runningGroundContactTime, .secondUnit(with: .milli)),
      ("verticalOscillation", .runningVerticalOscillation, .meterUnit(with: .centi)),
    ]
    var series: [String: [WorkoutSamplePoint]] = [:]
    for (name, identifier, unit) in quantities {
      guard !Task.isCancelled, let type = HKQuantityType.quantityType(forIdentifier: identifier)
      else { continue }
      let samples =
        (try? await quantitiesFor(type, predicate: HKQuery.predicateForObjects(from: workout)))
        ?? []
      series[name] = samples.filter {
        $0.startDate >= workout.startDate && $0.startDate <= workout.endDate
          && workout.pausedDuration(
            overlapping: $0.startDate...$0.startDate.addingTimeInterval(0.01)) == 0
      }.map {
        WorkoutSamplePoint(
          time: $0.startDate.timeIntervalSince(workout.startDate)
            - workout.pausedDuration(overlapping: workout.startDate...$0.startDate),
          value: $0.quantity.doubleValue(for: unit), source: Self.source(of: $0)
        )
      }
    }
    var zones: RecordedHeartRateZones?
    if #available(iOS 27.0, *), let group = workout.zoneGroup(for: HKQuantityType(.heartRate)) {
      let unit = HKUnit.count().unitDivided(by: .minute())
      let durations = Dictionary(grouping: group.zoneDurations, by: { $0.zone.index })
      zones = RecordedHeartRateZones(
        source: String(describing: group.configuration.source),
        zones: group.configuration.zones.map { zone in
          RecordedHeartRateZones.Zone(
            index: zone.index, minimum: zone.minimum?.doubleValue(for: unit),
            maximum: zone.maximum?.doubleValue(for: unit),
            seconds: (durations[zone.index] ?? []).reduce(0) { $0 + $1.duration }
          )
        }.sorted { $0.index < $1.index }
      )
    }
    return WorkoutEvidence(
      measuredAt: PayloadDate.timestamp(Date()), source: Self.category(of: workout),
      device: nil, softwareVersion: nil,
      zones: zones,
      signals: quantities.map {
        WorkoutEvidenceCalculator.summarize(
          metric: $0.0, samples: series[$0.0] ?? [], duration: workout.activeDuration)
      },
      phases: WorkoutEvidenceCalculator.phases(series: series, duration: workout.activeDuration)
    )
  }

  func rmssdTrend(for day: Date) async -> RMSSDTrend? {
    guard let type = Self.rmssdType,
      let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)
    else { return nil }
    let calendar = Calendar.current
    let day = calendar.startOfDay(for: day)
    guard let start = calendar.date(byAdding: .day, value: -30, to: day),
      let next = calendar.date(byAdding: .day, value: 1, to: day)
    else { return nil }
    let end = min(next, Date())
    let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
    do {
      async let samples = quantitiesFor(type, predicate: predicate)
      let sleep = try await HKSampleQueryDescriptor(
        predicates: [.categorySample(type: sleepType, predicate: predicate)],
        sortDescriptors: [SortDescriptor(\HKCategorySample.startDate)]
      ).result(for: store)
      let sessions = HealthKitManager.groupSleepSessions(sleep)
      let asleep: Set<Int> = [
        HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
        HKCategoryValueSleepAnalysis.asleepCore.rawValue,
        HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
        HKCategoryValueSleepAnalysis.asleepREM.rawValue,
      ]
      var observations: [RMSSDTrend.Observation] = []
      let values = try await samples
      for offset in -28...0 {
        guard let date = calendar.date(byAdding: .day, value: offset, to: day),
          let session = HealthKitManager.selectSleepSession(sessions, for: date, calendar: calendar)
        else { continue }
        guard let wake = session.map(\.endDate).max(), calendar.isDate(wake, inSameDayAs: date)
        else { continue }
        let ranges = session.filter { asleep.contains($0.value) }
        for sample in values
        where ranges.contains(where: {
          sample.startDate >= $0.startDate && sample.endDate <= $0.endDate
        }) {
          observations.append(
            RMSSDTrend.Observation(
              date: sample.startDate, night: date,
              value: sample.quantity.doubleValue(for: .secondUnit(with: .milli)),
              source: Self.source(of: sample), category: Self.category(of: sample)))
        }
      }
      return RMSSDTrend.calculate(observations: observations, day: day)
    } catch {
      return nil
    }
  }

  private func quantitiesFor(_ type: HKQuantityType, predicate: NSPredicate) async throws
    -> [HKQuantitySample]
  {
    try await HKSampleQueryDescriptor(
      predicates: [.quantitySample(type: type, predicate: predicate)],
      sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate)]
    ).result(for: store)
  }

  private static func source(of sample: HKSample) -> String {
    [
      sample.sourceRevision.source.bundleIdentifier, sample.sourceRevision.productType ?? "unknown",
      sample.sourceRevision.version ?? "unknown",
    ].joined(separator: "/")
  }

  // Apple Watch bundle identifiers embed a device UUID, so only a coarse category leaves the device.
  static func sourceCategory(bundleIdentifier: String, productType: String?) -> String {
    guard bundleIdentifier.hasPrefix("com.apple.") else { return "Third-party app" }
    if productType?.hasPrefix("Watch") == true { return "Apple Watch" }
    if productType?.hasPrefix("iPhone") == true { return "iPhone" }
    return "Other Apple device"
  }

  private static func category(of sample: HKSample) -> String {
    sourceCategory(
      bundleIdentifier: sample.sourceRevision.source.bundleIdentifier,
      productType: sample.sourceRevision.productType)
  }
}
