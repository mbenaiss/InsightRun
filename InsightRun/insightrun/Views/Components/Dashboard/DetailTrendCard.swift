//
//  DetailTrendCard.swift
//  InsightRun
//
//  7-day smooth trend curve used in the metric detail sheet.
//  Catmull-Rom-ish interpolation, dotted Y-grid (0/25/50/75/100), area gradient,
//  last-dot marker, day-of-week labels.
//

import SwiftUI

struct DetailTrendCard: View {
    let title: String
    let values: [Double]
    let labels: [String]
    let accent: Color
    /// Y-axis bounds. Defaults to `0…100` (matches score scale).
    var yMin: Double = 0
    var yMax: Double = 100

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.dash) {
            HStack {
                Text(title)
                    .font(IRFont.footnote.weight(.semibold))
                    .foregroundStyle(Color.irTextPrimary)
                Spacer()
                Text("\(values.count) " + String(localized: "days", comment: "Days suffix in trend chart"))
                    .font(IRFont.monoSM)
                    .foregroundStyle(Color.irTextSecondary.opacity(0.6))
            }

            if values.count >= 2 {
                chart
                    .frame(height: 140)
            } else {
                emptyState
            }
        }
        .padding(Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }

    private var emptyState: some View {
        Text(String(localized: "Not enough data yet.", comment: "Trend chart empty state"))
            .font(IRFont.caption)
            .foregroundStyle(Color.irTextSecondary)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
    }

    private var chart: some View {
        GeometryReader { geo in
            let pad = EdgeInsets(top: 8, leading: 26, bottom: 22, trailing: 8)
            let plotWidth = geo.size.width - pad.leading - pad.trailing
            let plotHeight = geo.size.height - pad.top - pad.bottom
            let stepX = values.count > 1 ? plotWidth / CGFloat(values.count - 1) : plotWidth
            let yRange = max(0.0001, yMax - yMin)

            let points: [CGPoint] = values.enumerated().map { index, value in
                let normalized = (value - yMin) / yRange
                let clamped = max(0, min(1, normalized))
                return CGPoint(
                    x: pad.leading + CGFloat(index) * stepX,
                    y: pad.top + (1 - CGFloat(clamped)) * plotHeight
                )
            }

            ZStack {
                gridLines(plotWidth: plotWidth, plotHeight: plotHeight, pad: pad)

                if points.count >= 2 {
                    let curve = smoothPath(points: points)

                    areaPath(curve: curve, points: points, pad: pad, plotHeight: plotHeight)
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.32), accent.opacity(0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    curve
                        .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    if let last = points.last {
                        Circle()
                            .stroke(Color.irTextPrimary, lineWidth: 1.5)
                            .background(Circle().fill(accent))
                            .frame(width: 7, height: 7)
                            .position(last)
                    }
                }

                dayLabels(stepX: stepX, pad: pad, height: geo.size.height)
            }
        }
    }

    private func gridLines(plotWidth: CGFloat, plotHeight: CGFloat, pad: EdgeInsets) -> some View {
        let levels: [Double] = [0, 25, 50, 75, 100]
        let yRange = max(0.0001, yMax - yMin)

        return ZStack {
            ForEach(levels, id: \.self) { level in
                let normalized = (level - yMin) / yRange
                let y = pad.top + (1 - CGFloat(normalized)) * plotHeight

                Path { p in
                    p.move(to: CGPoint(x: pad.leading, y: y))
                    p.addLine(to: CGPoint(x: pad.leading + plotWidth, y: y))
                }
                .stroke(
                    level == 0 || level == 100 ? Color.irBorder : Color.irBorder.opacity(0.5),
                    style: StrokeStyle(
                        lineWidth: 1,
                        dash: level == 0 || level == 100 ? [] : [2, 3]
                    )
                )

                Text("\(Int(level))")
                    .font(IRFont.monoSM)
                    .foregroundStyle(Color.irTextSecondary.opacity(0.6))
                    .position(x: pad.leading - 12, y: y)
            }
        }
    }

    private func dayLabels(stepX: CGFloat, pad: EdgeInsets, height: CGFloat) -> some View {
        ZStack {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                Text(label)
                    .font(IRFont.monoSM)
                    .foregroundStyle(Color.irTextSecondary.opacity(0.6))
                    .position(
                        x: pad.leading + CGFloat(index) * stepX,
                        y: height - 8
                    )
            }
        }
    }

    private func smoothPath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for i in 1..<points.count {
            let current = points[i]
            let previous = points[i - 1]
            let midX = (previous.x + current.x) / 2
            path.addCurve(
                to: current,
                control1: CGPoint(x: midX, y: previous.y),
                control2: CGPoint(x: midX, y: current.y)
            )
        }
        return path
    }

    private func areaPath(curve: Path, points: [CGPoint], pad: EdgeInsets, plotHeight: CGFloat) -> Path {
        var area = curve
        guard let last = points.last, let first = points.first else { return area }
        let baseline = pad.top + plotHeight
        area.addLine(to: CGPoint(x: last.x, y: baseline))
        area.addLine(to: CGPoint(x: first.x, y: baseline))
        area.closeSubpath()
        return area
    }
}

#Preview {
    DetailTrendCard(
        title: "Tendance · 7 jours",
        values: [62, 70, 88, 100, 75, 38, 39],
        labels: ["jeu", "ven", "sam", "dim", "lun", "mar", "mer"],
        accent: .irWarning
    )
    .padding()
    .background(Color.irBackgroundApp)
    .preferredColorScheme(.dark)
}
