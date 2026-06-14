//
//  AIConsentSheet.swift
//  InsightRun
//
//  AI consent screen for data sharing with OpenRouter (Apple 5.1.1 compliance)
//

import SwiftUI

struct AIConsentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onConsent: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Spacing.base) {
                    // Header Section
                    VStack(spacing: Spacing.md) {
                        Image(systemName: "hand.raised.circle.fill")
                            .font(IRFont.numLG)
                            .foregroundStyle(Color.irPrimaryAccent.gradient)
                            .padding(.top, Spacing.xl)

                        Text(String(localized: "consent.title"))
                            .font(IRFont.title2.bold())
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Spacing.base)

                        Text(String(localized: "consent.description"))
                            .font(IRFont.bodyEmphasized)
                            .foregroundStyle(Color.irTextSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, Spacing.xl)
                    }

                    // Data Collection Section
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text(String(localized: "consent.data_header"))
                            .font(IRFont.headline)
                        
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            DataCategoryRow(text: String(localized: "consent.data.health_profile"))
                            DataCategoryRow(text: String(localized: "consent.data.history"))
                            DataCategoryRow(text: String(localized: "consent.data.workout"))
                        }
                    }
                    .padding(Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.irCard2)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    .padding(.horizontal, Spacing.xl)

                    // Privacy Section
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text(String(localized: "consent.privacy_header"))
                            .font(IRFont.headline)
                        
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            PrivacyCheckRow(text: String(localized: "consent.privacy.anonymous"))
                            PrivacyCheckRow(text: String(localized: "consent.privacy.only_analysis"))
                            PrivacyCheckRow(text: String(localized: "consent.privacy.no_storage"))
                            PrivacyCheckRow(text: String(localized: "consent.privacy.no_sale"))
                        }
                    }
                    .padding(Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.irCard2)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    .padding(.horizontal, Spacing.xl)

                    // Provider & Privacy link
                    VStack(spacing: Spacing.md) {
                        VStack(alignment: .center, spacing: Spacing.xxs) {
                            Text(String(localized: "consent.processed_by"))
                                .font(IRFont.caption)
                                .foregroundStyle(Color.irTextSecondary)
                            
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "brain.head.profile")
                                    .foregroundStyle(Color.irPrimaryAccent)
                                Text(String(localized: "consent.provider_openrouter"))
                                    .font(IRFont.body.bold())
                            }
                        }
                        .padding(.vertical, Spacing.xs)
                        .padding(.horizontal, Spacing.base)
                        .background(Color.irCard2)
                        .clipShape(Capsule())

                        Link(destination: URL(string: "https://insightrun.altcode.studio/privacy")!) {
                            HStack(spacing: Spacing.xxs) {
                                Text(String(localized: "consent.privacy_policy"))
                                    .font(IRFont.footnote)
                                Image(systemName: "arrow.up.right")
                                    .font(IRFont.microLabel)
                            }
                            .foregroundStyle(Color.irPrimaryAccent)
                        }
                    }
                }
                .padding(.bottom, Spacing.base)
            }

            // Buttons pinned at bottom
            HStack(spacing: Spacing.md) {
                Button {
                    onDecline()
                } label: {
                    Text(String(localized: "consent.dont_allow"))
                        .font(IRFont.headline)
                        .foregroundStyle(Color.irTextPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .padding(.vertical, Spacing.sm)
                        .background(Color.irCardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                }

                Button {
                    ConsentService.shared.grantAIConsent()
                    onConsent()
                } label: {
                    Text(String(localized: "consent.allow"))
                        .font(IRFont.headline)
                        .foregroundStyle(Color.irTextOnAccent)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .padding(.vertical, Spacing.sm)
                        .background(Color.irPrimaryAccent)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.xxl)
        }
        .interactiveDismissDisabled()
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }
}

// MARK: - Data Category Row Component
struct DataCategoryRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Text("•")
                .font(IRFont.body)
                .foregroundStyle(Color.irTextSecondary)
            Text(text)
                .font(IRFont.body)
                .foregroundStyle(Color.irTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Privacy Check Row Component
struct PrivacyCheckRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(IRFont.body)
                .foregroundStyle(Color.irSuccess)
            Text(text)
                .font(IRFont.body)
                .foregroundStyle(Color.irTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    AIConsentSheet(
        onConsent: { print("Consented") },
        onDecline: { print("Declined") }
    )
}
