import Foundation

struct RMSSDTrend: Codable, Equatable {
  struct Night: Codable, Equatable, Identifiable {
    var id: String { date }
    let date: String
    let median: Double
    let sampleCount: Int
  }

  let metric: String
  let context: String
  let source: String
  let sourceChanged: Bool
  let latestSampleAt: String
  let measuredAt: String
  let currentNight: Night?
  let baselineMedian: Double?
  let baselineNights: Int
  let recentMedian: Double?
  let recentNights: Int
  let nights: [Night]

  var isBaselineReady: Bool { baselineNights >= 7 }

  static func statusDescription(_ trend: RMSSDTrend?) -> String {
    guard let trend, trend.currentNight != nil else {
      return String(localized: "No data available")
    }
    if trend.baselineMedian != nil {
      return String(localized: "insights.rmssd.ready", defaultValue: "Reference ready")
    }
    return String(
      localized: "insights.rmssd.progress",
      defaultValue: "Reference: \(trend.baselineNights)/7 nights")
  }

  func history(endingOn date: Date, calendar: Calendar = .current) -> [TrendDataPoint] {
    let day = calendar.startOfDay(for: date)
    guard let start = calendar.date(byAdding: .day, value: -6, to: day),
      let end = calendar.date(byAdding: .day, value: 1, to: day)
    else { return [] }
    let formatter = ISO8601DateFormatter()
    return nights.compactMap { night in
      guard let date = formatter.date(from: night.date), date >= start, date < end else {
        return nil
      }
      return TrendDataPoint(date: date, value: night.median)
    }.sorted { $0.date < $1.date }
  }

  static func median(_ values: [Double]) -> Double? {
    let values = values.filter { $0.isFinite && $0 > 0 }.sorted()
    guard !values.isEmpty else { return nil }
    let middle = values.count / 2
    return values.count.isMultiple(of: 2)
      ? (values[middle - 1] + values[middle]) / 2 : values[middle]
  }

  struct Observation {
    let date: Date
    let night: Date
    let value: Double
    // Device-specific identity, kept on device to detect source changes.
    let source: String
    let category: String
  }

  static func calculate(
    observations: [Observation], day: Date, now: Date = Date(), calendar: Calendar = .current
  ) -> RMSSDTrend? {
    let day = calendar.startOfDay(for: day)
    guard let lower = calendar.date(byAdding: .day, value: -28, to: day),
      let upper = calendar.date(byAdding: .day, value: 1, to: day)
    else { return nil }
    let observations = observations.filter {
      $0.value.isFinite && $0.value > 0 && $0.night >= lower && $0.night < upper && $0.date <= now
    }
    guard let latest = observations.max(by: { $0.date < $1.date }) else { return nil }
    let sameSource = observations.filter { $0.source == latest.source }
    let grouped = Dictionary(grouping: sameSource) { calendar.startOfDay(for: $0.night) }
    let datedNights = grouped.compactMap { date, values -> (Date, Night)? in
      guard values.count >= 3, let median = median(values.map(\.value)) else { return nil }
      // The backend validates night dates as timestamps, so the local day is sent as local midnight.
      let night = PayloadDate.timestamp(date, timeZone: calendar.timeZone)
      return (date, Night(date: night, median: median, sampleCount: values.count))
    }.sorted { $0.0 < $1.0 }
    let baseline = datedNights.filter { $0.0 < day }
    let recentStart = calendar.date(byAdding: .day, value: -6, to: day) ?? day
    let recent = datedNights.filter { $0.0 >= recentStart }
    return RMSSDTrend(
      metric: "RMSSD", context: "asleep", source: latest.category,
      sourceChanged: Set(observations.map(\.source)).count > 1,
      latestSampleAt: PayloadDate.timestamp(latest.date, timeZone: calendar.timeZone),
      measuredAt: PayloadDate.timestamp(now, timeZone: calendar.timeZone),
      currentNight: datedNights.first(where: { $0.0 == day })?.1,
      baselineMedian: baseline.count >= 7 ? median(baseline.map { $0.1.median }) : nil,
      baselineNights: baseline.count, recentMedian: median(recent.map { $0.1.median }),
      recentNights: recent.count, nights: datedNights.map(\.1)
    )
  }
}
