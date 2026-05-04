//
//  WidgetComponents.swift
//  InsightRunWidgets
//
//  Shared widget UI primitives derived from the v4-ios-widgets design.
//

import SwiftUI

// MARK: - Container background

extension View {
    /// Applies the widget surface treatment: dark fill (optionally a subtle
    /// gradient) + 0.5pt translucent border. Use as the `containerBackground`
    /// of every widget so the corner radius is iOS-driven.
    func wgContainerBackground(gradient: Bool = false) -> some View {
        containerBackground(for: .widget) {
            ZStack {
                if gradient {
                    LinearGradient(
                        colors: [
                            Color(uiColor: UIColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1.0)),
                            Color.wgSurface,
                            Color(uiColor: UIColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1.0))
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    Color.wgSurface
                }

                Rectangle()
                    .strokeBorder(Color.wgBorder, lineWidth: 0.5)
            }
        }
    }
}

// MARK: - Header (icon tile + uppercase mono label)

struct WGHeader: View {
    let label: String
    let icon: String
    var color: Color = .wgAccent

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 14, height: 14)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.22))
                )

            Text(label.uppercased())
                .font(WGFont.eyebrow)
                .tracking(WGTracking.eyebrow)
                .foregroundStyle(Color.wgTextSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Mini Ring (recovery score gauge)

struct WGMiniRing: View {
    let value: Int
    var size: CGFloat = 70
    var label: String?
    var color: Color = .wgAccent

    var body: some View {
        let progress = max(0, min(1, Double(value) / 100.0))
        let lineWidth: CGFloat = max(4, size * 0.075)

        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.06), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 1) {
                Text("\(value)")
                    .font(WGFont.num(size * 0.32))
                    .kerning(WGTracking.numHero(size * 0.32))
                    .foregroundStyle(Color.wgTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                if let label {
                    Text(label.uppercased())
                        .font(.system(size: max(7, size * 0.085), weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(color)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Mini stat (label + value + unit, optional left divider)

struct WGMiniStat: View {
    let label: String
    let value: String
    var unit: String = ""
    var valueColor: Color = .wgTextPrimary
    var mono: Bool = false
    var leadingDivider: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            if leadingDivider {
                Rectangle()
                    .fill(Color.wgBorder)
                    .frame(width: 0.5)
                    .padding(.trailing, 10)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(label.uppercased())
                    .font(WGFont.microLabel)
                    .tracking(WGTracking.microLabel)
                    .foregroundStyle(Color.wgTextTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(value)
                        .font(mono ? WGFont.mono(18, weight: .bold) : WGFont.num(18, weight: .bold))
                        .kerning(mono ? 0 : WGTracking.numBody(18))
                        .foregroundStyle(valueColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    if !unit.isEmpty {
                        Text(unit)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.wgTextTertiary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Sparkline (filled area + stroke)

struct WGSparkline: View {
    let values: [Double]
    var color: Color = .wgAccent
    var lineWidth: CGFloat = 1.6

    var body: some View {
        GeometryReader { geo in
            if values.count > 1 {
                let pts = points(in: geo.size)
                ZStack {
                    areaPath(points: pts, height: geo.size.height)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.45), color.opacity(0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    linePath(points: pts)
                        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 1
        let range = max(0.0001, maxV - minV)
        let step = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { idx, v in
            let x = CGFloat(idx) * step
            let yNorm = CGFloat((v - minV) / range)
            let y = size.height - (yNorm * (size.height - 4)) - 2
            return CGPoint(x: x, y: y)
        }
    }

    private func linePath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        points.dropFirst().forEach { path.addLine(to: $0) }
        return path
    }

    private func areaPath(points: [CGPoint], height: CGFloat) -> Path {
        var path = Path()
        guard let first = points.first, let last = points.last else { return path }
        path.move(to: CGPoint(x: first.x, y: height))
        path.addLine(to: first)
        points.dropFirst().forEach { path.addLine(to: $0) }
        path.addLine(to: CGPoint(x: last.x, y: height))
        path.closeSubpath()
        return path
    }
}

// MARK: - Bio mini tile (used inside large/medium overview widgets)

struct WGBioMini: View {
    let label: String
    let value: String
    var unit: String = ""
    let delta: String?
    var deltaPositive: Bool = true
    var color: Color = .wgAccent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(Color.wgTextTertiary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if let delta {
                    Text(delta)
                        .font(WGFont.mono(9, weight: .bold))
                        .foregroundStyle(deltaPositive ? Color.wgSuccess : Color.wgWarning)
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(WGFont.num(18, weight: .bold))
                    .kerning(WGTracking.numBody(18))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.wgTextTertiary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.wgBorder, lineWidth: 0.5)
        )
    }
}

// MARK: - Status colour helpers

enum WGStatusColor {
    static func recovery(score: Int) -> Color {
        switch score {
        case 75...:    return .wgSuccess
        case 55..<75:  return .wgAccent
        case 35..<55:  return .wgWarning
        default:       return .wgError
        }
    }

    static func recoveryLabel(score: Int) -> String {
        switch score {
        case 85...:
            return String(localized: "EXCELLENT", comment: "Widget recovery label: excellent").uppercased()
        case 70..<85:
            return String(localized: "GOOD", comment: "Widget recovery label: good").uppercased()
        case 50..<70:
            return String(localized: "FAIR", comment: "Widget recovery label: fair").uppercased()
        default:
            return String(localized: "LOW", comment: "Widget recovery label: low").uppercased()
        }
    }
}
