//
//  PulseCoachingCard.swift
//  InsightRun
//
//  Coaching card aligned with the Pulse Ring design:
//  · sparkle glyph + "Coach · time" header
//  · TL;DR with highlighted keyword (yellow underline)
//  · row of reason chips
//  · expandable detail
//

import SwiftUI

struct PulseCoachingCard: View {
    let timestampLabel: String
    let tldr: String
    let highlightWord: String?
    let reasons: [String]
    let detail: String
    var onCreatePlan: (() -> Void)?

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            tldrBlock
                .padding(.horizontal, Spacing.base + 2)
                .padding(.bottom, Spacing.md)

            if expanded {
                expandedDetails
            }

            Divider()
                .background(Color.irBorder)

            expandToggle

            if let onCreatePlan {
                Divider()
                    .background(Color.irBorder)

                createPlanButton(action: onCreatePlan)
            }
        }
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var expandedDetails: some View {
        if !reasons.isEmpty {
            reasonsRow
                .padding(.horizontal, Spacing.base + 2)
                .padding(.bottom, Spacing.md)
        }

        if !detail.isEmpty && detail != tldr {
            Text(detail)
                .font(.system(size: 14))
                .lineSpacing(3)
                .foregroundStyle(Color.irTextSecondary)
                .padding(.horizontal, Spacing.base + 2)
                .padding(.bottom, Spacing.md)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(
                        LinearGradient(
                            colors: [Color.irAIAccent, Color.irAIAccentSecondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.black)
            }
            .frame(width: 22, height: 22)

            Text(String(localized: "COACH · \(timestampLabel)", comment: "Dashboard coach card header"))
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(Color.irTextPrimary)
        }
        .padding(.horizontal, Spacing.base + 2)
        .padding(.top, Spacing.base)
        .padding(.bottom, Spacing.sm + 2)
    }

    private var tldrBlock: some View {
        let highlight = highlightWord?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let highlight, !highlight.isEmpty, let range = tldr.range(of: highlight) {
            return AnyView(
                (Text(tldr[tldr.startIndex..<range.lowerBound])
                    + Text(tldr[range])
                        .foregroundStyle(Color.irAIAccent)
                        .underline(true, color: Color.irAIAccent.opacity(0.6))
                    + Text(tldr[range.upperBound..<tldr.endIndex]))
                .font(.system(size: 17, weight: .semibold))
                .lineSpacing(2)
                .kerning(-0.1)
                .foregroundStyle(Color.irTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            )
        } else {
            return AnyView(
                Text(tldr)
                    .font(.system(size: 17, weight: .semibold))
                    .lineSpacing(2)
                    .kerning(-0.1)
                    .foregroundStyle(Color.irTextPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            )
        }
    }

    private var reasonsRow: some View {
        FlowLayout(spacing: 6) {
            ForEach(reasons, id: \.self) { reason in
                Text(reason)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.irTextSecondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        Capsule().strokeBorder(Color.irBorder, lineWidth: 0.5)
                    )
            }
        }
    }

    private var expandToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
        } label: {
            HStack {
                Text(expanded
                    ? String(localized: "Reduce", comment: "Coaching collapse")
                    : String(localized: "View detail", comment: "Coaching expand"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.irTextSecondary)

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.irTextSecondary)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .padding(.horizontal, Spacing.base + 2)
            .padding(.vertical, Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func createPlanButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .bold))

                Text(String(localized: "Create a training plan", comment: "Dashboard create plan button"))
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background(Color.irAIAccent)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("create-training-plan")
    }
}

// MARK: - Flow layout for chips

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        totalHeight = y + rowHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        let maxX = bounds.maxX

        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x + size.width > maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}

#Preview {
    PulseCoachingCard(
        timestampLabel: "29 avr, 10:07",
        tldr: "Récup mitigée. Vise 20–30 min de footing facile (RPE 2–3), pas plus.",
        highlightWord: "mitigée",
        reasons: ["VFC ↑", "FC repos ↑", "Sommeil 6h46", "Charge cardiaque stable"],
        detail: "Ta VFC à 108 ms est au-dessus de la baseline mais ta FC repos à 56 bpm reste 5 bpm au-dessus de la normale...",
        onCreatePlan: {}
    )
    .padding()
    .background(Color.irBackgroundApp)
    .preferredColorScheme(.dark)
}
