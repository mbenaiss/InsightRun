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
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.irTextSecondary.opacity(0.5))
                .frame(width: 18, height: 1)

            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Color.irTextSecondary.opacity(0.7))

            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
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
