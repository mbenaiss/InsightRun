//
//  AIConsentSheet.swift
//  InsightRun
//
//  AI consent screen for data sharing with OpenRouter (Apple 5.1.2(i) compliance)
//

import SwiftUI

struct AIConsentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onConsent: () -> Void
    let onDecline: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Icon
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 70))
                        .foregroundStyle(.blue.gradient)
                        .padding(.top, 32)

                    VStack(spacing: 20) {
                        // Title
                        Text(String(localized: "consent.title", comment: "Title of AI consent screen"))
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.irTextPrimary)

                        // Main description with bold requirement
                        VStack(alignment: .leading, spacing: 16) {
                            Text(String(localized: "consent.requirement", comment: "Bold requirement text"))
                                .font(.body)
                                .fontWeight(.bold)
                                .multilineTextAlignment(.leading)
                                .foregroundStyle(Color.irTextPrimary)

                            // How it works
                            VStack(alignment: .leading, spacing: 8) {
                                Text(String(localized: "consent.how_it_works", comment: "How it works header"))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.irTextPrimary)

                                Text(String(localized: "consent.how_description", comment: "How it works description"))
                                    .font(.body)
                                    .foregroundStyle(Color.irTextSecondary)
                            }

                            // Privacy guarantees
                            VStack(alignment: .leading, spacing: 8) {
                                Text(String(localized: "consent.privacy_header", comment: "Privacy header"))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.irTextPrimary)

                                VStack(alignment: .leading, spacing: 6) {
                                    PrivacyCheckRow(text: String(localized: "consent.privacy.anonymous", comment: "Anonymous data guarantee"))
                                    PrivacyCheckRow(text: String(localized: "consent.privacy.no_storage", comment: "No storage guarantee"))
                                    PrivacyCheckRow(text: String(localized: "consent.privacy.no_sale", comment: "No sale guarantee"))
                                    PrivacyCheckRow(text: String(localized: "consent.privacy.only_analysis", comment: "Only for analysis guarantee"))
                                }
                            }
                        }
                        .padding(.horizontal, 24)

                        // Privacy policy link
                        Link(destination: URL(string: "https://insightrun.altcode.studio/privacy")!) {
                            HStack {
                                Image(systemName: "lock.shield.fill")
                                    .foregroundStyle(Color.irPrimaryAccent)
                                Text(String(localized: "consent.privacy_policy", comment: "Privacy policy link"))
                                    .font(.subheadline)
                                    .foregroundStyle(Color.irPrimaryAccent)
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundStyle(Color.irPrimaryAccent)
                            }
                        }
                        .padding(.top, 8)

                        // Question
                        Text(String(localized: "consent.question", comment: "Question asking user to continue"))
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.irTextPrimary)
                            .padding(.top, 16)

                        // Buttons
                        VStack(spacing: 12) {
                            // Accept button
                            Button(action: {
                                ConsentService.shared.grantAIConsent()
                                onConsent()
                            }) {
                                Text(String(localized: "consent.accept", comment: "Button to accept consent"))
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 56)
                                    .background(Color.irPrimaryAccent)
                                    .cornerRadius(16)
                            }

                            // Decline button
                            Button(action: {
                                onDecline()
                            }) {
                                Text(String(localized: "consent.decline", comment: "Button to decline consent"))
                                    .font(.headline)
                                    .foregroundStyle(Color.irTextSecondary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 56)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
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
