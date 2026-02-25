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
                VStack(spacing: 16) {
                    // Header Section
                    VStack(spacing: 12) {
                        Image(systemName: "hand.raised.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.blue.gradient)
                            .padding(.top, 24)

                        Text(String(localized: "consent.title"))
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)

                        Text(String(localized: "consent.description"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 24)
                    }

                    // Data Collection Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text(String(localized: "consent.data_header"))
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            DataCategoryRow(text: String(localized: "consent.data.health_profile"))
                            DataCategoryRow(text: String(localized: "consent.data.history"))
                            DataCategoryRow(text: String(localized: "consent.data.workout"))
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 24)

                    // Privacy Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text(String(localized: "consent.privacy_header"))
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            PrivacyCheckRow(text: String(localized: "consent.privacy.anonymous"))
                            PrivacyCheckRow(text: String(localized: "consent.privacy.only_analysis"))
                            PrivacyCheckRow(text: String(localized: "consent.privacy.no_storage"))
                            PrivacyCheckRow(text: String(localized: "consent.privacy.no_sale"))
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 24)

                    // Provider & Privacy link
                    VStack(spacing: 12) {
                        VStack(alignment: .center, spacing: 4) {
                            Text(String(localized: "consent.processed_by"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            HStack(spacing: 6) {
                                Image(systemName: "brain.head.profile")
                                    .foregroundStyle(.blue)
                                Text(String(localized: "consent.provider_openrouter"))
                                    .font(.subheadline.bold())
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 16)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())

                        Link(destination: URL(string: "https://insightrun.altcode.studio/privacy")!) {
                            HStack(spacing: 4) {
                                Text(String(localized: "consent.privacy_policy"))
                                    .font(.footnote)
                                Image(systemName: "arrow.up.right")
                                    .font(.caption2)
                            }
                            .foregroundStyle(Color.irPrimaryAccent)
                        }
                    }
                }
                .padding(.bottom, 16)
            }

            // Buttons pinned at bottom
            HStack(spacing: 12) {
                Button {
                    onDecline()
                } label: {
                    Text(String(localized: "consent.dont_allow"))
                        .font(.headline)
                        .foregroundStyle(Color.irTextPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.irCardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button {
                    ConsentService.shared.grantAIConsent()
                    onConsent()
                } label: {
                    Text(String(localized: "consent.allow"))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.irPrimaryAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
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
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.body)
                .foregroundStyle(Color.irTextSecondary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.irTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Privacy Check Row Component
struct PrivacyCheckRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.body)
                .foregroundStyle(Color.irSuccess)
            Text(text)
                .font(.body)
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
