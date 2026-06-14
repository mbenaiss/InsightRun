//
//  DetailHeroCard.swift
//  InsightRun
//
//  Score detail sheet hero — mini half-arc gauge + giant value + status.
//  Used at the top of every metric detail sheet to keep the pulse-ring
//  visual language consistent.
//

import SwiftUI

struct DetailHeroCard: View {
    /// Numeric label shown center: e.g. "47", "108", "97".
    let valueLabel: String
    /// Optional small label rendered next to the value: "/100", "ms", "bpm", ...
    let unitLabel: String?
    /// Status caption rendered uppercased under the value (e.g. "MITIGÉE").
    let statusLabel: String
    /// Color driving the arc gradient + status text.
    let accent: Color
    /// Progress 0…1 used to position the arc end + needle. Pass `nil` to hide
    /// the gauge entirely (for metrics that don't fit a 0–100 scale).
    let progress: Double?

    var body: some View {
        VStack(spacing: 0) {
            if let progress {
                gauge(progress: progress)
            } else {
                rawValue
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.lg)
        .padding(.horizontal, Spacing.cardPadding)
        .background(
            LinearGradient(
                colors: [
                    accent.opacity(0.12),
                    Color.irCardBackground
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(valueLabel)\(unitLabel.map { " \($0)" } ?? ""), \(statusLabel)")
    }

    // MARK: Gauge variant

    private func gauge(progress: Double) -> some View {
        let clamped = max(0, min(1, progress))

        return GeometryReader { geo in
            let width = geo.size.width
            let height: CGFloat = 160
            let cx = width / 2
            let cy: CGFloat = 130
            let radius: CGFloat = 90
            let stroke: CGFloat = 14

            ZStack {
                arcTrack(cx: cx, cy: cy, radius: radius, stroke: stroke)
                arcValue(cx: cx, cy: cy, radius: radius, stroke: stroke, progress: clamped)
                ticks(cx: cx, cy: cy, radius: radius, stroke: stroke)
                needle(cx: cx, cy: cy, radius: radius, progress: clamped)
                centerLabels(cx: cx, cy: cy)
            }
            .frame(width: width, height: height)
        }
        .frame(height: 160)
    }

    private func arcTrack(cx: CGFloat, cy: CGFloat, radius: CGFloat, stroke: CGFloat) -> some View {
        DetailHalfArc(progress: 1.0)
            .stroke(Color.irBorder, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
            .frame(width: radius * 2, height: radius * 2)
            .position(x: cx, y: cy)
    }

    private func arcValue(cx: CGFloat, cy: CGFloat, radius: CGFloat, stroke: CGFloat, progress: Double) -> some View {
        let gradient = LinearGradient(
            colors: [accent.opacity(0.7), accent],
            startPoint: .leading,
            endPoint: .trailing
        )

        return DetailHalfArc(progress: progress)
            .stroke(gradient, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
            .frame(width: radius * 2, height: radius * 2)
            .position(x: cx, y: cy)
    }

    private func ticks(cx: CGFloat, cy: CGFloat, radius: CGFloat, stroke: CGFloat) -> some View {
        ZStack {
            ForEach(0..<11, id: \.self) { i in
                let angle: CGFloat = .pi + (CGFloat(i) / 10.0) * .pi
                let r1: CGFloat = radius + stroke / 2 + 3
                let r2: CGFloat = radius + stroke / 2 + 7
                Path { p in
                    p.move(to: CGPoint(x: cx + cos(angle) * r1, y: cy + sin(angle) * r1))
                    p.addLine(to: CGPoint(x: cx + cos(angle) * r2, y: cy + sin(angle) * r2))
                }
                .stroke(Color.irTextPrimary.opacity(0.18), lineWidth: 1)
            }
        }
    }

    private func needle(cx: CGFloat, cy: CGFloat, radius: CGFloat, progress: Double) -> some View {
        let angle: CGFloat = .pi + CGFloat(progress) * .pi
        let dot = CGPoint(x: cx + cos(angle) * radius, y: cy + sin(angle) * radius)

        return ZStack {
            Circle()
                .fill(Color.irTextPrimary)
                .frame(width: 10, height: 10)
                .position(dot)

            Circle()
                .fill(accent)
                .frame(width: 5, height: 5)
                .position(dot)
        }
    }

    private func centerLabels(cx: CGFloat, cy: CGFloat) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(valueLabel)
                    .font(IRFont.numXL.weight(.heavy))
                    .kerning(-3)
                    .foregroundStyle(Color.irTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                if let unitLabel {
                    Text(unitLabel)
                        .font(IRFont.footnote.weight(.semibold))
                        .foregroundStyle(Color.irTextSecondary.opacity(0.7))
                }
            }

            Text(statusLabel.uppercased())
                .font(IRFont.eyebrow.weight(.bold))
                .tracking(IRTracking.eyebrow)
                .foregroundStyle(accent)
        }
        .position(x: cx, y: cy - 14)
    }

    // MARK: Raw value variant (no gauge)

    private var rawValue: some View {
        VStack(spacing: Spacing.sm) {
            HStack(alignment: .lastTextBaseline, spacing: Spacing.xxs) {
                Text(valueLabel)
                    .font(IRFont.numXL.weight(.heavy))
                    .kerning(-2)
                    .foregroundStyle(Color.irTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                if let unitLabel {
                    Text(unitLabel)
                        .font(IRFont.bodyEmphasized.weight(.semibold))
                        .foregroundStyle(Color.irTextSecondary.opacity(0.7))
                }
            }

            Text(statusLabel.uppercased())
                .font(IRFont.microLabel.weight(.bold))
                .tracking(IRTracking.microLabel)
                .foregroundStyle(accent)
        }
        .padding(.vertical, Spacing.sm)
    }
}

// MARK: - Half arc shape

private struct DetailHalfArc: Shape {
    var progress: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let start = Angle(radians: .pi)
        let end = Angle(radians: .pi + Double.pi * max(0, min(1, progress)))
        path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        return path
    }
}

#Preview {
    VStack(spacing: Spacing.base) {
        DetailHeroCard(
            valueLabel: "47",
            unitLabel: "/100",
            statusLabel: "Mitigée",
            accent: .irWarning,
            progress: 0.47
        )

        DetailHeroCard(
            valueLabel: "108",
            unitLabel: "ms",
            statusLabel: "Above normal",
            accent: .irSuccess,
            progress: nil
        )
    }
    .padding()
    .background(Color.irBackgroundApp)
    .preferredColorScheme(.dark)
}
