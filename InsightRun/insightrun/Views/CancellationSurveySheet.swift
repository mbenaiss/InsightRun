import SwiftUI

struct CancellationSurveySheet: View {
    let request: CancellationSurveyRequest
    let onAnswer: (CancellationReason) -> Void
    let onDismiss: () -> Void

    @State private var selectedReason: CancellationReason?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Spacing.base) {
                    VStack(spacing: Spacing.md) {
                        Image(systemName: "bubble.left.and.text.bubble.right.fill")
                            .font(IRFont.numLG)
                            .foregroundStyle(Color.irPrimaryAccent.gradient)
                            .padding(.top, Spacing.xl)

                        Text(String(localized: "cancellation_survey.title", defaultValue: "Why did you cancel?"))
                            .font(IRFont.title2.bold())
                            .multilineTextAlignment(.center)

                        Text(subtitle)
                            .font(IRFont.bodyEmphasized)
                            .foregroundStyle(Color.irTextSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, Spacing.xl)

                    VStack(spacing: Spacing.sm) {
                        ForEach(CancellationReason.allCases) { reason in
                            reasonButton(reason)
                        }
                    }
                    .padding(.horizontal, Spacing.xl)
                }
                .padding(.bottom, Spacing.base)
            }

            Button(action: onDismiss) {
                Text(String(localized: "cancellation_survey.not_now", defaultValue: "Not now"))
                    .font(IRFont.headline)
                    .foregroundStyle(Color.irTextSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .disabled(selectedReason != nil)
            .accessibilityIdentifier("cancellation-survey-not-now")
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.xxl)
        }
        .presentationDetents([.large])
    }

    private var subtitle: String {
        request.isTrial
            ? String(localized: "cancellation_survey.subtitle.trial",
                     defaultValue: "Your free trial stays active until it ends. Your answer helps us improve InsightRun.")
            : String(localized: "cancellation_survey.subtitle.subscription",
                     defaultValue: "Your subscription stays active until the end of the period. Your answer helps us improve InsightRun.")
    }

    private func reasonButton(_ reason: CancellationReason) -> some View {
        let isSelected = selectedReason == reason
        return Button {
            guard selectedReason == nil else { return }
            selectedReason = reason
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { onAnswer(reason) }
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: reason.symbol)
                    .font(IRFont.headline)
                    .foregroundStyle(Color.irPrimaryAccent)
                    .frame(width: 28)
                Text(reason.title)
                    .font(IRFont.body)
                    .foregroundStyle(Color.irTextPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: Spacing.sm)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(IRFont.headline)
                        .foregroundStyle(Color.irSuccess)
                }
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(isSelected ? Color.irPrimaryAccent.opacity(0.15) : Color.irCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(isSelected ? Color.irPrimaryAccent : Color.irBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("cancellation-survey-\(reason.rawValue)")
    }
}

#Preview {
    CancellationSurveySheet(
        request: CancellationSurveyRequest(productId: "com.altcode.insightrun.Annual", isTrial: true, unsubscribeDetectedAt: Date()),
        onAnswer: { _ in },
        onDismiss: {}
    )
}
