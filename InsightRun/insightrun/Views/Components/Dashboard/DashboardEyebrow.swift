//
//  DashboardEyebrow.swift
//  InsightRun
//
//  Numbered section header used across the redesigned dashboard:
//  "01 ─ Title"
//

import SwiftUI

struct DashboardEyebrow: View {
    let title: String

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Rectangle()
                .fill(Color.irTextTertiary)
                .frame(width: Spacing.cardPadding, height: 1)

            Text(title.uppercased())
                .font(IRFont.eyebrow.weight(.bold))
                .tracking(IRTracking.eyebrow)
                .foregroundStyle(Color.irTextTertiary)

            Spacer()
        }
        .padding(.horizontal, Spacing.xxs)
        .padding(.bottom, Spacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    VStack(alignment: .leading) {
        DashboardEyebrow(title: "Disponibilité")
        DashboardEyebrow(title: "Charge & récupération")
        DashboardEyebrow(title: "Signaux")
    }
    .padding()
    .background(Color.irBackgroundApp)
    .preferredColorScheme(.dark)
}
