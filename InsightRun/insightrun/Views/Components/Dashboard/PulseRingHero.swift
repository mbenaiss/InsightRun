//
//  PulseRingHero.swift
//  InsightRun
//
//  Half-ring readiness gauge with gradient, ticks, baseline marker and pulsing halo.
//

import SwiftUI

struct PulseRingHero: View {
    let score: Int
    let yesterdayScore: Int?
    let statusTitle: String
    let statusColor: Color
    let footerSummary: String?
    var onTap: (() -> Void)?

    @State private var halo = false

    var body: some View {
        Button {
            onTap?()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                header

                gauge
                    .padding(.top, Spacing.sm)

                if let footerSummary {
                    Divider()
                        .background(Color.irBorder)
                        .padding(.top, Spacing.sm)

                    footer(summary: footerSummary)
                        .padding(.top, Spacing.sm)
                }
            }
            .padding(.horizontal, Spacing.base)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.base)
            .background(heroBackground)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xl)
                    .strokeBorder(Color.irBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pulse-ring-hero")
        .onAppear { halo = true }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text(String(localized: "AVAILABILITY", comment: "Pulse ring eyebrow"))
                .font(.system(size: 11, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(Color.irTextSecondary)

            Spacer()

            HStack(spacing: 8) {
                StatusChip(title: statusTitle, color: statusColor)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.irTextSecondary)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.06))
                    )
            }
        }
    }

    // MARK: Gauge

    private var gauge: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height: CGFloat = 190
            let cx = width / 2
            let cy: CGFloat = 145
            let radius: CGFloat = 110
            let stroke: CGFloat = 22

            ZStack {
                pulsingHalo(at: CGPoint(x: cx, y: height))

                gaugeShape(cx: cx, cy: cy, radius: radius, stroke: stroke)
                ticks(cx: cx, cy: cy, radius: radius, stroke: stroke)
                yesterdayMarker(cx: cx, cy: cy, radius: radius, stroke: stroke)
                needle(cx: cx, cy: cy, radius: radius)
                centerScore(cx: cx, cy: cy)
            }
            .frame(width: width, height: height)
        }
        .frame(height: 190)
    }

    private func pulsingHalo(at center: CGPoint) -> some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [
                        Color.irWarning.opacity(0.22),
                        Color.irWarning.opacity(0)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 160
                )
            )
            .frame(width: 320, height: 200)
            .position(x: center.x, y: center.y)
            .scaleEffect(halo ? 1.06 : 1.0)
            .opacity(halo ? 0.85 : 0.55)
            .animation(.easeInOut(duration: 4.2).repeatForever(autoreverses: true), value: halo)
            .allowsHitTesting(false)
    }

    private func gaugeShape(cx: CGFloat, cy: CGFloat, radius: CGFloat, stroke: CGFloat) -> some View {
        let progress = max(0, min(1, Double(score) / 100.0))
        let arcGradient = AngularGradient(
            gradient: Gradient(stops: [
                .init(color: Color.irError, location: 0.50),
                .init(color: Color.irWarning, location: 0.70),
                .init(color: Color.irSuccess, location: 0.90),
                .init(color: Color.irSuccess, location: 1.0)
            ]),
            center: .init(x: cx / max(cx, 1), y: cy / max(cy, 1)),
            startAngle: .degrees(0),
            endAngle: .degrees(360)
        )

        return ZStack {
            HalfArc(progress: 1.0)
                .stroke(arcGradient, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .frame(width: radius * 2, height: radius * 2)
                .opacity(0.12)
                .position(x: cx, y: cy)

            HalfArc(progress: progress)
                .stroke(arcGradient, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .frame(width: radius * 2, height: radius * 2)
                .position(x: cx, y: cy)
        }
    }

    private func ticks(cx: CGFloat, cy: CGFloat, radius: CGFloat, stroke: CGFloat) -> some View {
        ZStack {
            ForEach(0..<11, id: \.self) { i in
                let angle: CGFloat = .pi + (CGFloat(i) / 10.0) * .pi
                let r1: CGFloat = radius + stroke / 2 + 4
                let r2: CGFloat = radius + stroke / 2 + 9
                Path { p in
                    p.move(to: CGPoint(x: cx + cos(angle) * r1, y: cy + sin(angle) * r1))
                    p.addLine(to: CGPoint(x: cx + cos(angle) * r2, y: cy + sin(angle) * r2))
                }
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private func yesterdayMarker(cx: CGFloat, cy: CGFloat, radius: CGFloat, stroke: CGFloat) -> some View {
        if let yesterday = yesterdayScore {
            let angle: CGFloat = .pi + (CGFloat(yesterday) / 100.0) * .pi
            let inner: CGFloat = radius - stroke / 2 - 2
            let outer: CGFloat = radius + stroke / 2 + 2
            let labelRadius: CGFloat = radius + stroke / 2 + 18
            let labelX: CGFloat = cx + cos(angle) * labelRadius
            let labelY: CGFloat = cy + sin(angle) * labelRadius + 3

            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: cx + cos(angle) * inner, y: cy + sin(angle) * inner))
                    p.addLine(to: CGPoint(x: cx + cos(angle) * outer, y: cy + sin(angle) * outer))
                }
                .stroke(Color.white.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

                Text(String(localized: "yesterday", comment: "Pulse ring yesterday marker"))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color.irTextSecondary.opacity(0.7))
                    .position(x: labelX, y: labelY)
            }
        }
    }

    private func needle(cx: CGFloat, cy: CGFloat, radius: CGFloat) -> some View {
        let progress: CGFloat = CGFloat(max(0, min(1, Double(score) / 100.0)))
        let angle: CGFloat = .pi + progress * .pi
        let inner: CGFloat = radius - 18
        let needleEnd = CGPoint(x: cx + cos(angle) * inner, y: cy + sin(angle) * inner)
        let dot = CGPoint(x: cx + cos(angle) * radius, y: cy + sin(angle) * radius)

        return ZStack {
            Path { p in
                p.move(to: CGPoint(x: cx, y: cy))
                p.addLine(to: needleEnd)
            }
            .stroke(Color.white.opacity(0.20), style: StrokeStyle(lineWidth: 1, lineCap: .round))

            Circle()
                .fill(Color.white)
                .frame(width: 12, height: 12)
                .position(dot)

            Circle()
                .fill(Color.irWarning)
                .frame(width: 6, height: 6)
                .position(dot)
        }
    }

    private func centerScore(cx: CGFloat, cy: CGFloat) -> some View {
        VStack(spacing: 2) {
            Text("\(score)")
                .font(.system(size: 84, weight: .heavy, design: .rounded))
                .kerning(-3.5)
                .foregroundStyle(Color.irTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text("/100")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(2.5)
                .foregroundStyle(Color.irTextSecondary.opacity(0.7))
        }
        .position(x: cx, y: cy - 4)
    }

    // MARK: Footer

    private func footer(summary: String) -> some View {
        HStack {
            if let yesterday = yesterdayScore {
                let delta = score - yesterday
                let isUp = delta >= 0
                HStack(spacing: 6) {
                    Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isUp ? Color.irSuccess : Color.irError)

                    Text("\(delta >= 0 ? "+" : "")\(delta)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.irTextPrimary)

                    Text(String(localized: "vs yesterday", comment: "Pulse ring delta caption"))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.irTextSecondary)
                }
            }

            Spacer()

            Text(summary)
                .font(.system(size: 11))
                .foregroundStyle(Color.irTextSecondary.opacity(0.7))
                .lineLimit(1)
        }
    }

    private var heroBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color.irCardBackground,
                Color.irCardBackground.opacity(0.85)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Half Arc Shape

private struct HalfArc: Shape {
    var progress: Double

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let startAngle = Angle(radians: .pi)
        let endAngle = Angle(radians: .pi + Double.pi * max(0, min(1, progress)))
        p.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        return p
    }
}

// MARK: - Status Chip

struct StatusChip: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(color.opacity(0.14))
            )
            .overlay(
                Capsule().strokeBorder(color.opacity(0.30), lineWidth: 0.5)
            )
    }
}

#Preview {
    VStack(spacing: 20) {
        PulseRingHero(
            score: 47,
            yesterdayScore: 52,
            statusTitle: "Mitigée",
            statusColor: .irWarning,
            footerSummary: "FC repos ↑ · sommeil OK"
        )

        PulseRingHero(
            score: 82,
            yesterdayScore: 76,
            statusTitle: "Bonne",
            statusColor: .irSuccess,
            footerSummary: "Tous signaux OK"
        )
    }
    .padding()
    .background(Color.irBackgroundApp)
    .preferredColorScheme(.dark)
}
