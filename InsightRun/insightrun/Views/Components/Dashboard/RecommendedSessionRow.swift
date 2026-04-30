//
//  RecommendedSessionRow.swift
//  InsightRun
//
//  Recommended-session row used under the "Séance recommandée" eyebrow:
//  square icon · title · subtitle · chevron.
//

import SwiftUI

struct RecommendedSessionRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(iconColor.opacity(0.18))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.irTextPrimary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.irTextSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.irTextSecondary.opacity(0.6))
            }
            .padding(Spacing.base)
            .background(Color.irCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(Color.irBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    RecommendedSessionRow(
        icon: "figure.run",
        iconColor: .irSuccess,
        title: "Footing facile · amplitude contrôlée",
        subtitle: "6,0 km · 40 min · RPE 2–3"
    )
    .padding()
    .background(Color.irBackgroundApp)
    .preferredColorScheme(.dark)
}
