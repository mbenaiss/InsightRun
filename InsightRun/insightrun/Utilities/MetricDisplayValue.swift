import Foundation

enum MetricDisplayValue {
  static func positive(_ value: Double?) -> Double? {
    value.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
  }

  static func nonZero(_ value: Double?) -> Double? {
    value.flatMap { $0.isFinite && $0 != 0 ? $0 : nil }
  }
}
