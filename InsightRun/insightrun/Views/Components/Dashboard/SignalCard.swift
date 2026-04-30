//
//  SignalCard.swift
//  InsightRun
//
//  Compact signal metric card (HRV, RHR, Respiration, SpO₂).
//  Used in the "Signaux" 2-up grid at the bottom of the dashboard.
//

import SwiftUI

struct SignalCard: View {
    let icon: String
    let color: Color
    let label: String
    let value: String
    let unit: String
    let status: String?
    let statusColor: Color
    let trend: [Double]
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                header

                HStack(alignment: .lastTextBaseline, spacing: Spacing.xxs) {
                    Text(value)
                        .font(IRFont.numMD.weight(.bold))
                        .kerning(-0.5)
                        .foregroundStyle(Color.irTextPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(unit)
                        .font(IRFont.eyebrow)
                        .foregroundStyle(Color.irTextSecondary)
                }

                MicroSparkline(values: trend, color: color)
                    .frame(height: 26)

                if let status, !status.isEmpty {
                    Text(status)
                        .font(IRFont.microLabel.weight(.semibold))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .padding(Spacing.base - 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.irCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .strokeBorder(Color.irBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(IRFont.eyebrow.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(color.opacity(0.16))
                )

            Text(label)
                .font(IRFont.eyebrow.weight(.medium))
                .foregroundStyle(Color.irTextSecondary)
                .lineLimit(1)
                .layoutPriority(1)

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(IRFont.eyebrow.weight(.bold))
                .foregroundStyle(Color.irTextSecondary.opacity(0.55))
        }
    }
}

#Preview {
    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
        SignalCard(
            icon: "waveform.path.ecg",
            color: Color.irAIAccent,
            label: "VFC repos",
            value: "109",
            unit: "ms",
            status: "Dans la normale",
            statusColor: .irSuccess,
            trend: [102, 98, 105, 110, 104, 108, 112, 109]
        )
        SignalCard(
            icon: "heart.fill",
            color: .irWarning,
            label: "FC repos",
            value: "56",
            unit: "bpm",
            status: "Au-dessus normale",
            statusColor: .irWarning,
            trend: [54, 53, 55, 56, 58, 56, 57, 56]
        )
    }
    .padding()
    .background(Color.irBackgroundApp)
    .preferredColorScheme(.dark)
}
