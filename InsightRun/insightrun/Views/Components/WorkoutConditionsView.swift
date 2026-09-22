import SwiftUI

struct WorkoutConditionsView: View {
  let sessionLabel: String
  let metrics: WorkoutMetrics
  let feedback: WorkoutFeedback?

  private var temperature: Double? {
    metrics.temperature.flatMap { $0.isFinite ? $0 : nil }
  }

  private var humidity: Double? {
    metrics.humidity.flatMap { $0.isFinite && (0...100).contains($0) ? $0 : nil }
  }

  private var recordedEffort: Double? {
    metrics.workout.effortScore.flatMap { $0.isFinite && (1...10).contains($0) ? $0 : nil }
  }

  private var perceivedEffort: Int? {
    feedback?.effort.flatMap { (1...10).contains($0) ? $0 : nil }
  }

  var body: some View {
    FlowLayout(spacing: Spacing.sm) {
      Text(sessionLabel)
        .font(IRFont.eyebrow.weight(.heavy))
        .tracking(IRTracking.eyebrow)
        .foregroundStyle(Color.irTextTertiary)

      if let temperature {
        indicator(
          label: String(localized: "workout.conditions.temperature", defaultValue: "Temperature"),
          value: "\(number(temperature)) °C", icon: "thermometer.medium",
          identifier: "workout-weather-temperature")
      }
      if let humidity {
        indicator(
          label: String(localized: "workout.conditions.humidity", defaultValue: "Humidity"),
          value: Formatters.percent(humidity), icon: "humidity.fill",
          identifier: "workout-weather-humidity")
      }
      if let recordedEffort {
        indicator(
          label: metrics.workout.effortIsEstimated
            ? String(
              localized: "workout.conditions.effort.estimated", defaultValue: "Apple estimate")
            : String(
              localized: "workout.conditions.effort.recorded",
              defaultValue: "Recorded perceived effort"),
          value: "\(number(recordedEffort))/10", icon: "gauge.with.dots.needle.67percent",
          identifier: "workout-recorded-effort")
      }
      if let perceivedEffort {
        indicator(
          label: String(localized: "insights.feedback.effort", defaultValue: "Perceived effort"),
          value: "\(Formatters.integer(perceivedEffort))/10", icon: "person.fill",
          identifier: "workout-perceived-effort")
      }
    }
  }

  private func indicator(label: String, value: String, icon: String, identifier: String)
    -> some View
  {
    Label(value, systemImage: icon)
      .font(IRFont.caption)
      .monospacedDigit()
      .foregroundStyle(Color.irTextSecondary)
      .accessibilityLabel("\(label), \(value)")
      .accessibilityIdentifier(identifier)
  }

  private func number(_ value: Double) -> String {
    Formatters.decimal(value, fractionDigits: value == value.rounded() ? 0 : 1)
  }
}
