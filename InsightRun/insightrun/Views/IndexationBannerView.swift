//
//  IndexationBannerView.swift
//  InsightRun
//
//  Compact banner to prompt users to update their athletic profile
//

import SwiftUI

struct IndexationBannerView: View {
    // MARK: - Callbacks

    let onSyncTapped: () -> Void
    let onDismiss: () -> Void

    // MARK: - Body

    var body: some View {
        VStack(spacing: Spacing.base) {
            // Header with icon and dismiss button
            HStack(spacing: Spacing.md) {
                // Running icon
                Image(systemName: "figure.run.circle.fill")
                    .font(IRFont.title1)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.irPrimaryAccent, Color.irPrimaryAccent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // Title and description
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(String(localized: "Update Athletic Profile", comment: "Banner title for profile update"))
                        .font(IRFont.headline)
                        .foregroundStyle(Color.irTextPrimary)

                    Text(String(localized: "Sync your recent workouts for better AI insights", comment: "Banner description for profile update"))
                        .font(IRFont.caption)
                        .foregroundStyle(Color.irTextSecondary)
                        .lineLimit(2)
                }

                Spacer()

                // Dismiss button
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(IRFont.numSM)
                        .foregroundStyle(Color.irTextSecondary)
                }
            }

            // Action buttons
            HStack(spacing: Spacing.md) {
                // Later button
                Button(action: onDismiss) {
                    Text(String(localized: "Later", comment: "Dismiss banner button"))
                        .font(IRFont.body)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.irTextSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .background(Color.irCardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
                }

                // Sync button
                Button(action: onSyncTapped) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "arrow.clockwise")
                        Text(String(localized: "Synchronize", comment: "Sync button in banner"))
                    }
                    .font(IRFont.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.irTextPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .background(
                        LinearGradient(
                            colors: [Color.irPrimaryAccent, Color.irPrimaryAccent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
                }
            }
        }
        .padding()
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .shadow(color: Color.irShadowStrong, radius: 8, y: 4)
    }
}

// MARK: - Preview

#Preview {
    VStack {
        IndexationBannerView(
            onSyncTapped: {
                print("Sync tapped")
            },
            onDismiss: {
                print("Dismissed")
            }
        )
        .padding()

        Spacer()
    }
    .background(Color(.systemBackground))
}
