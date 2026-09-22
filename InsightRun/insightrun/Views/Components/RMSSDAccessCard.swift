import HealthKit
import SwiftUI

struct RMSSDAccessCard: View {
  let refresh: () async -> Void
  @State private var requesting = false
  @State private var message: String?

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      Text(
        String(
          localized: "insights.rmssd.empty",
          defaultValue:
            "Requires RMSSD measurements and recorded sleep. No data can also mean access is unavailable."
        )
      )
      .font(IRFont.body).foregroundStyle(Color.irTextSecondary)
      Button(String(localized: "insights.rmssd.enable", defaultValue: "Enable RMSSD access")) {
        Task {
          guard let type = HealthInsightReader.rmssdType else { return }
          requesting = true
          defer { requesting = false }
          do {
            try await HKHealthStore().requestAuthorization(toShare: [], read: [type])
            await refresh()
          } catch {
            message = String(
              localized: "insights.rmssd.error",
              defaultValue: "Unable to request Health access. Try again from Settings.")
          }
        }
      }
      .disabled(requesting)
      .tint(Color.irPrimaryAccent)
      if requesting { ProgressView() }
      if let message { Text(message).font(IRFont.caption) }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Spacing.cardPadding)
    .detailCard()
  }
}
