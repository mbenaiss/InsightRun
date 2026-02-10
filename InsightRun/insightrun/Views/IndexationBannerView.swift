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
        VStack(spacing: 16) {
            // Header with icon and dismiss button
            HStack(spacing: 12) {
                // Running icon
                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // Title and description
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Update Athletic Profile", comment: "Banner title for profile update"))
                        .font(.headline)
                        .foregroundStyle(Color.irTextPrimary)

                    Text(String(localized: "Sync your recent workouts for better AI insights", comment: "Banner description for profile update"))
                        .font(.caption)
                        .foregroundStyle(Color.irTextSecondary)
                        .lineLimit(2)
                }

                Spacer()

                // Dismiss button
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.irTextSecondary)
                }
            }

            // Action buttons
            HStack(spacing: 12) {
                // Later button
                Button(action: onDismiss) {
                    Text(String(localized: "Later", comment: "Dismiss banner button"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.irTextSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.irCardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // Sync button
                Button(action: onSyncTapped) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text(String(localized: "Synchronize", comment: "Sync button in banner"))
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding()
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
