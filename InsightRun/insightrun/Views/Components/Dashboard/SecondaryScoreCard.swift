//
//  SecondaryScoreCard.swift
//  InsightRun
//
//  Compact score card with delta vs baseline, progress bar with baseline tick, and 7-day sparkline.
//  Used as a 2-up grid below the Pulse Ring hero (Effort + Sleep).
//

import SwiftUI

struct SecondaryScoreCard: View {
    let title: String
    let score: Int
    let baseline: Int
    let accent: Color
    let trend: [Double]
    var onTap: (() -> Void)?

    private var delta: Int { score - baseline }

    var body: some View {
        Button {
            onTap?()
        } label: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                header

                scoreRow

                progressBar

                MicroSparkline(values: trend, color: accent)
                    .frame(height: 22)
                    .padding(.top, Spacing.sm)
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
        HStack {
            Text(title.uppercased())
                .font(IRFont.microLabel.weight(.bold))
                .tracking(1.6)
                .foregroundStyle(Color.irTextSecondary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(IRFont.eyebrow.weight(.bold))
                .foregroundStyle(Color.irTextSecondary.opacity(0.6))
        }
    }

    private var scoreRow: some View {
        HStack(alignment: .lastTextBaseline) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text("\(score)")
                    .font(IRFont.title1.weight(.heavy))
                    .kerning(-1)
                    .foregroundStyle(Color.irTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("/100")
                    .font(IRFont.eyebrow.weight(.semibold))
                    .foregroundStyle(Color.irTextSecondary.opacity(0.6))
            }

            Spacer()

            Text("\(delta >= 0 ? "+" : "")\(delta)")
                .font(IRFont.monoSM.weight(.bold))
                .foregroundStyle(delta >= 0 ? Color.irSuccess : Color.irError)
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let progress = max(0, min(1, Double(score) / 100.0))
            let baselineX = max(0, min(1, Double(baseline) / 100.0)) * width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.irBorder)

                Capsule()
                    .fill(accent)
                    .frame(width: progress * width)

                Rectangle()
                    .fill(Color.irTextPrimary.opacity(0.4))
                    .frame(width: 1, height: 8)
                    .offset(x: baselineX, y: 0)
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Building Baseline Card

/// Empty-state twin of `SecondaryScoreCard`. Shown when a metric exists but the
/// underlying signal isn't usable yet (e.g. freshness/TSB before ~6 weeks of
/// training history). Keeps the 2-up grid layout balanced without lying with a
/// 0/100 score.
struct BuildingBaselineCard: View {
    let title: String
    let message: String
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Text(title.uppercased())
                        .font(IRFont.microLabel.weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(Color.irTextSecondary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(IRFont.eyebrow.weight(.bold))
                        .foregroundStyle(Color.irTextSecondary.opacity(0.6))
                }

                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text("—")
                        .font(IRFont.title1.weight(.heavy))
                        .kerning(-1)
                        .foregroundStyle(Color.irTextPrimary)

                    Text("/100")
                        .font(IRFont.eyebrow.weight(.semibold))
                        .foregroundStyle(Color.irTextSecondary.opacity(0.6))
                }

                Text(message)
                    .font(IRFont.caption)
                    .foregroundStyle(Color.irTextSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Spacing.xs)
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
}

// MARK: - Micro Sparkline

struct MicroSparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height

            if let path = linePath(width: width, height: height) {
                ZStack {
                    areaPath(width: width, height: height)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.35), color.opacity(0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    path
                        .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))

                    if let last = lastPoint(width: width, height: height) {
                        Circle()
                            .fill(color)
                            .frame(width: 3, height: 3)
                            .position(last)
                    }
                }
            }
        }
    }

    private func points(width: CGFloat, height: CGFloat) -> [CGPoint]? {
        guard values.count > 1 else { return nil }
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 1
        let range = max(0.0001, maxV - minV)
        let step = width / CGFloat(values.count - 1)
        return values.enumerated().map { idx, v in
            let x = CGFloat(idx) * step
            let y = height - CGFloat((v - minV) / range) * (height - 4) - 2
            return CGPoint(x: x, y: y)
        }
    }

    private func linePath(width: CGFloat, height: CGFloat) -> Path? {
        guard let pts = points(width: width, height: height), let first = pts.first else { return nil }
        var path = Path()
        path.move(to: first)
        pts.dropFirst().forEach { path.addLine(to: $0) }
        return path
    }

    private func areaPath(width: CGFloat, height: CGFloat) -> Path {
        var path = Path()
        guard let pts = points(width: width, height: height), let first = pts.first else { return path }
        path.move(to: CGPoint(x: first.x, y: height))
        path.addLine(to: first)
        pts.dropFirst().forEach { path.addLine(to: $0) }
        if let last = pts.last {
            path.addLine(to: CGPoint(x: last.x, y: height))
        }
        path.closeSubpath()
        return path
    }

    private func lastPoint(width: CGFloat, height: CGFloat) -> CGPoint? {
        points(width: width, height: height)?.last
    }
}

#Preview {
    HStack(spacing: Spacing.sm) {
        SecondaryScoreCard(
            title: "Effort",
            score: 39,
            baseline: 55,
            accent: .irWarning,
            trend: [62, 70, 88, 100, 75, 38, 39]
        )
        SecondaryScoreCard(
            title: "Sommeil",
            score: 90,
            baseline: 75,
            accent: .irSuccess,
            trend: [85, 78, 88, 92, 80, 85, 90]
        )
    }
    .padding()
    .background(Color.irBackgroundApp)
    .preferredColorScheme(.dark)
}
