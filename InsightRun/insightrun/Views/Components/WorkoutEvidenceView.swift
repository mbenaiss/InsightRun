import SwiftUI

struct WorkoutHeartRateZonesView: View {
  let metrics: WorkoutMetrics

  var body: some View {
    if let group = metrics.evidence?.zones, !group.zones.isEmpty {
      MetricsCard {
        VStack(alignment: .leading, spacing: Spacing.sm) {
          Text(String(localized: "insights.zones", defaultValue: "Recorded heart-rate zones"))
            .font(IRFont.bodyEmphasized)
          Text(
            group.source == "system"
              ? String(localized: "insights.zones.system", defaultValue: "Apple automatic zones")
              : String(localized: "insights.zones.custom", defaultValue: "Custom workout zones")
          )
          .font(IRFont.caption).foregroundStyle(Color.irTextSecondary)
          ForEach(group.zones) { zone in
            HStack {
              Text("Z\(zone.index + 1)").font(IRFont.body.weight(.semibold))
              Text(bounds(zone)).font(IRFont.caption).foregroundStyle(Color.irTextSecondary)
              Spacer()
              Text(
                String(
                  format: "%d:%02d", Int(zone.seconds.rounded()) / 60,
                  Int(zone.seconds.rounded()) % 60)
              ).font(IRFont.body.monospacedDigit())
            }
            ProgressView(value: min(1, zone.seconds / max(1, metrics.workout.duration)))
              .tint(Color.irPrimaryAccent)
          }
        }
        .padding(Spacing.cardPadding)
      }
    }
  }

  private func bounds(_ zone: RecordedHeartRateZones.Zone) -> String {
    if let lower = zone.minimum, let upper = zone.maximum {
      return "\(Int(lower))–<\(Int(upper)) bpm"
    }
    if let upper = zone.maximum { return "<\(Int(upper)) bpm" }
    if let lower = zone.minimum { return "≥\(Int(lower)) bpm" }
    return ""
  }

}

struct WorkoutFeedbackSheet: View {
  let workout: WorkoutModel
  @Environment(\.dismiss) private var dismiss
  @State private var effort = 0
  @State private var intent = ""
  @State private var legs = ""
  @State private var achieved = ""

  var body: some View {
    NavigationStack {
      Form {
        Picker(
          String(localized: "insights.feedback.effort", defaultValue: "Perceived effort"),
          selection: $effort
        ) {
          Text(String(localized: "insights.unspecified", defaultValue: "Not specified")).tag(0)
          ForEach(1...10, id: \.self) { Text("\($0)/10").tag($0) }
        }
        Picker(
          String(localized: "insights.feedback.intent", defaultValue: "Session goal"),
          selection: $intent
        ) {
          option("", String(localized: "insights.unspecified", defaultValue: "Not specified"))
          option("easy", String(localized: "insights.intent.easy", defaultValue: "Easy run"))
          option("long", String(localized: "insights.intent.long", defaultValue: "Long run"))
          option("tempo", String(localized: "insights.intent.tempo", defaultValue: "Tempo"))
          option(
            "intervals", String(localized: "insights.intent.intervals", defaultValue: "Intervals"))
          option("race", String(localized: "insights.intent.race", defaultValue: "Race"))
        }
        Picker(
          String(localized: "insights.feedback.legs", defaultValue: "How your legs felt"),
          selection: $legs
        ) {
          option("", String(localized: "insights.unspecified", defaultValue: "Not specified"))
          option("fresh", String(localized: "insights.legs.fresh", defaultValue: "Fresh"))
          option("normal", String(localized: "insights.legs.normal", defaultValue: "Normal"))
          option("heavy", String(localized: "insights.legs.heavy", defaultValue: "Heavy"))
          option("sore", String(localized: "insights.legs.sore", defaultValue: "Sore"))
        }
        Picker(
          String(localized: "insights.feedback.achieved", defaultValue: "Goal achieved"),
          selection: $achieved
        ) {
          option("", String(localized: "insights.unspecified", defaultValue: "Not specified"))
          option("yes", String(localized: "insights.achieved.yes", defaultValue: "Yes"))
          option("partly", String(localized: "insights.achieved.partly", defaultValue: "Partly"))
          option("no", String(localized: "insights.achieved.no", defaultValue: "No"))
        }
      }
      .navigationTitle(
        String(localized: "insights.feedback.title", defaultValue: "Session feedback")
      )
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(localized: "Cancel")) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(String(localized: "Save")) {
            WorkoutFeedbackStore.shared.save(
              WorkoutFeedback(
                effort: effort == 0 ? nil : effort, intent: intent.isEmpty ? nil : intent,
                legs: legs.isEmpty ? nil : legs, goalAchieved: achieved.isEmpty ? nil : achieved
              ), for: workout)
            dismiss()
          }
        }
      }
      .onAppear {
        let saved = WorkoutFeedbackStore.shared.feedback(for: workout)
        effort = saved?.effort ?? 0
        intent = saved?.intent ?? ""
        legs = saved?.legs ?? ""
        achieved = saved?.goalAchieved ?? ""
      }
    }
  }

  private func option(_ value: String, _ label: String) -> some View { Text(label).tag(value) }
}
