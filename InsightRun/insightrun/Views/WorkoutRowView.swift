//
//  WorkoutRowView.swift
//  InsightRun
//
//  Pulse-Ring session card: type badge + intensity chips + inline mono stats
//  + RPE dots + bottom load bar.
//

import SwiftUI
import HealthKit

// MARK: - Strava Icon (Official Strava brand logo)
struct StravaIconView: View {
    var size: CGFloat = 14
    var color: Color = .white

    var body: some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / 64.0

            var backPath = Path()
            backPath.move(to: CGPoint(x: 41.03 * scale, y: 47.852 * scale))
            backPath.addLine(to: CGPoint(x: 35.458 * scale, y: 36.876 * scale))
            backPath.addLine(to: CGPoint(x: 27.286 * scale, y: 36.876 * scale))
            backPath.addLine(to: CGPoint(x: 41.03 * scale, y: 64 * scale))
            backPath.addLine(to: CGPoint(x: 54.766 * scale, y: 36.876 * scale))
            backPath.addLine(to: CGPoint(x: 46.586 * scale, y: 36.876 * scale))
            backPath.closeSubpath()
            context.fill(backPath, with: .color(color.opacity(0.6)))

            var frontPath = Path()
            frontPath.move(to: CGPoint(x: 27.898 * scale, y: 21.944 * scale))
            frontPath.addLine(to: CGPoint(x: 35.462 * scale, y: 36.872 * scale))
            frontPath.addLine(to: CGPoint(x: 46.586 * scale, y: 36.872 * scale))
            frontPath.addLine(to: CGPoint(x: 27.898 * scale, y: 0 * scale))
            frontPath.addLine(to: CGPoint(x: 9.234 * scale, y: 36.876 * scale))
            frontPath.addLine(to: CGPoint(x: 20.35 * scale, y: 36.876 * scale))
            frontPath.closeSubpath()
            context.fill(frontPath, with: .color(color))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Suunto Icon
struct SuuntoIconView: View {
    var size: CGFloat = 14
    var color: Color = .white

    var body: some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / 24.0
            let centerX = canvasSize.width / 2
            let padding = 3.0 * scale

            var trianglePath = Path()
            trianglePath.move(to: CGPoint(x: centerX, y: padding))
            trianglePath.addLine(to: CGPoint(x: canvasSize.width - padding, y: canvasSize.height - padding))
            trianglePath.addLine(to: CGPoint(x: padding, y: canvasSize.height - padding))
            trianglePath.closeSubpath()
            context.fill(trianglePath, with: .color(color))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Workout type classification (Pulse-Ring labels)

enum WorkoutSessionType {
    case interval     // intervals — red
    case tempo        // tempo / threshold — orange
    case easy         // easy / recovery — green
    case long         // long run — purple

    var color: Color {
        switch self {
        case .interval: return .irError
        case .tempo:    return .irWarning
        case .easy:     return .irSuccess
        case .long:     return Color(hex: "BF5AF2")
        }
    }

    var localizedLabel: String {
        switch self {
        case .interval: return String(localized: "Intervals", comment: "Workout type: intervals")
        case .tempo:    return String(localized: "Tempo", comment: "Workout type: tempo")
        case .easy:     return String(localized: "Easy run", comment: "Workout type: easy run")
        case .long:     return String(localized: "Long run", comment: "Workout type: long run")
        }
    }

    static func classify(_ workout: WorkoutModel) -> WorkoutSessionType {
        let km = (workout.distance ?? 0) / 1000.0
        let pace = workout.averagePace ?? 0 // min/km

        if km >= 18 {
            return .long
        }
        if pace > 0 {
            if pace <= 4.8 { return .interval }
            if pace <= 5.6 { return .tempo }
        }
        // Anything not classified above (incl. moderate/easy paces) is a footing.
        return .easy
    }
}

// MARK: - Workout source (used for source overlay)

private enum RowWorkoutSource {
    case strava, apple, suunto, garmin, polar, coros, imported, other

    var color: Color {
        switch self {
        case .strava: return Color(hex: "FC5200")
        case .apple: return .pink
        case .suunto: return Color(hex: "E84545")
        case .garmin: return Color(hex: "007CC3")
        case .polar: return Color(hex: "D32F2F")
        case .coros: return Color(hex: "FF6B00")
        case .imported: return Color(hex: "FF9500")
        case .other: return .blue
        }
    }

    static func classify(sourceName: String) -> RowWorkoutSource {
        let s = sourceName.lowercased()
        if s.contains("strava") { return .strava }
        if s.contains("suunto") { return .suunto }
        if s.contains("garmin") { return .garmin }
        if s.contains("polar")  { return .polar }
        if s.contains("coros")  { return .coros }
        if s.contains("apple") || s.contains("watch") || s.contains("health") { return .apple }
        if s.contains("import") { return .imported }
        return .other
    }
}

// MARK: - Pulse-Ring session card

struct WorkoutRowView: View {
    let workout: WorkoutModel

    private var sessionType: WorkoutSessionType { WorkoutSessionType.classify(workout) }
    private var source: RowWorkoutSource { RowWorkoutSource.classify(sourceName: workout.sourceName) }

    private var dayLabel: String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "EEE"
        return f.string(from: workout.startDate).capitalized
    }

    private var dateLabel: String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "d MMM"
        return f.string(from: workout.startDate)
    }

    private var timeLabel: String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "HH:mm"
        return f.string(from: workout.startDate)
    }

    private var distanceText: String {
        guard let distance = workout.distance else { return "—" }
        let km = distance / 1000.0
        return String(format: "%.2f", km)
    }

    private var durationCompact: String {
        let total = Int(workout.duration)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%dh%02d", h, m) }
        return String(format: "%d:%02d", m, s)
    }

    private var paceText: String? {
        guard let pace = workout.averagePace else { return nil }
        let m = Int(pace)
        let s = Int((pace - Double(m)) * 60)
        return String(format: "%d'%02d\"", m, s)
    }

    private var heartRateText: String? {
        guard let hr = workout.averageHeartRate else { return nil }
        return String(format: "%.0f", hr)
    }

    /// 0–100, used for the bottom load bar width
    private var effortPercent: CGFloat {
        let pace = workout.averagePace ?? 6.5
        let km = (workout.distance ?? 0) / 1000.0
        let pacePart = max(0, min(80, (7.5 - pace) * 30))
        let distancePart = max(0, min(50, km * 1.5))
        return CGFloat(min(100, max(8, pacePart + distancePart)))
    }

    /// 1–5 dots. Priority:
    /// 1. Apple Workout Effort score (iOS 18+ user-rated or Apple-estimated)
    /// 2. Heart-rate intensity vs an estimated FCmax
    /// 3. Session-type heuristic (constant per type)
    private var rpeLevel: Int {
        if let score = workout.effortScore {
            return max(1, min(5, Int(((score + 1) / 2).rounded())))
        }
        if let hr = workout.averageHeartRate, hr > 0 {
            let assumedMax = 190.0
            let pct = hr / assumedMax
            switch pct {
            case ..<0.60: return 1
            case ..<0.70: return 2
            case ..<0.80: return 3
            case ..<0.90: return 4
            default:      return 5
            }
        }
        switch sessionType {
        case .interval: return 5
        case .tempo:    return 4
        case .long:     return 5
        case .easy:     return 2
        }
    }

    /// True when we have a real (user-rated or Apple-estimated) effort score.
    private var hasAppleEffort: Bool { workout.effortScore != nil }

    /// 8-segment trace, deterministic from session type
    private var traceCommands: [CGFloat] {
        switch sessionType {
        case .interval: return [20, 8, 22, 8, 22, 8, 18, 20]
        case .tempo:    return [28, 24, 18, 22, 12, 18, 8, 14]
        case .easy:     return [22, 20, 18, 20, 18, 20, 18, 22]
        case .long:     return [18, 16, 18, 14, 20, 16, 22, 28]
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: Spacing.md) {
                leftBadgeColumn

                VStack(alignment: .leading, spacing: 6) {
                    metaLine
                    titleLine
                    chipsRow
                    statsRow
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 8) {
                    traceShape
                        .frame(width: 46, height: 26)
                        .opacity(0.7)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.irTextSecondary.opacity(0.55))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)

            // bottom load bar
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.04))
                    .frame(height: 3)
                GeometryReader { geo in
                    Rectangle()
                        .fill(sessionType.color.opacity(0.7))
                        .frame(width: geo.size.width * (effortPercent / 100.0), height: 3)
                }
                .frame(height: 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Subviews

    private var leftBadgeColumn: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(sessionType.color.opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(sessionType.color.opacity(0.35), lineWidth: 0.5)
                    )

                Image(systemName: typeGlyph)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(sessionType.color)
            }
            .frame(width: 36, height: 36)
            .overlay(alignment: .bottomTrailing) {
                sourceOverlay
                    .offset(x: 4, y: 4)
            }

            VStack(spacing: 4) {
                Text(String(localized: "EFFORT", comment: "Workout intensity dots label"))
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(Color.irTextSecondary.opacity(0.7))

                HStack(spacing: 3) {
                    ForEach(1...5, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(i <= rpeLevel ? sessionType.color : Color.white.opacity(0.1))
                            .frame(width: 3, height: 8)
                    }
                }
            }
        }
        .frame(width: 44)
    }

    private var typeGlyph: String {
        workout.isIndoor ? "figure.run.treadmill" : "figure.run"
    }

    @ViewBuilder
    private var sourceOverlay: some View {
        let glyph: AnyView = {
            switch source {
            case .strava:
                return AnyView(StravaIconView(size: 9))
            case .suunto:
                return AnyView(SuuntoIconView(size: 9))
            case .apple:
                return AnyView(
                    Image(systemName: "applewatch")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 9, height: 9)
                        .foregroundStyle(.white)
                )
            case .imported:
                return AnyView(
                    Text("I")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                )
            default:
                return AnyView(
                    Text(String(workout.sourceName.prefix(1)).uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                )
            }
        }()

        glyph
            .frame(width: 16, height: 16)
            .background(source.color)
            .clipShape(Circle())
            .overlay(
                Circle().strokeBorder(Color.irCardBackground, lineWidth: 1.5)
            )
    }

    private var metaLine: some View {
        Text("\(dayLabel) \(dateLabel) · \(timeLabel)")
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(0.8)
            .foregroundStyle(Color.irTextSecondary.opacity(0.7))
            .lineLimit(1)
    }

    private var titleLine: some View {
        Text(titleText)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Color.irTextPrimary)
            .lineLimit(1)
    }

    private var titleText: String {
        if workout.isIndoor {
            return String(localized: "Treadmill", comment: "Workout title: indoor / treadmill run")
        }
        return String(localized: "Outdoor run", comment: "Workout title: outdoor run")
    }

    @ViewBuilder
    private var chipsRow: some View {
        if workout.isIndoor {
            HStack(spacing: 4) {
                Text(String(localized: "Indoor", comment: "Workout chip: indoor"))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.irTextSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.05))
                    )
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            stat(icon: "ruler", value: distanceText, unit: "km", mono: false)
            stat(icon: "clock", value: durationCompact, unit: nil, mono: true)
            if let pace = paceText {
                stat(icon: "speedometer", value: pace, unit: "/km", mono: true)
            }
            if let hr = heartRateText {
                stat(icon: "heart.fill", value: hr, unit: "bpm", mono: false, tint: .irError)
            }
        }
    }

    private func stat(icon: String, value: String, unit: String?, mono: Bool, tint: Color = .irTextSecondary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 12, weight: .bold, design: mono ? .monospaced : .rounded))
                    .foregroundStyle(Color.irTextPrimary)
                if let unit {
                    Text(unit)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(Color.irTextSecondary.opacity(0.7))
                }
            }
        }
    }

    private var traceShape: some View {
        GeometryReader { geo in
            let segments = traceCommands
            let width = geo.size.width
            let stepX = width / CGFloat(segments.count - 1)
            Path { path in
                for (i, y) in segments.enumerated() {
                    let pt = CGPoint(x: CGFloat(i) * stepX, y: y)
                    if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
            }
            .stroke(sessionType.color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}

#Preview {
    VStack(spacing: 8) {
        WorkoutRowView(
            workout: WorkoutModel(
                id: UUID(),
                workoutType: .running,
                startDate: Date(),
                endDate: Date().addingTimeInterval(1800),
                duration: 1800,
                distance: 5000,
                totalEnergyBurned: 350,
                sourceName: "Apple Watch",
                sourceVersion: "10.0",
                metadata: nil,
                averageHeartRate: 145,
                maxHeartRate: 165,
                elevationGain: 50,
                hasRoute: false
            )
        )
        WorkoutRowView(
            workout: WorkoutModel(
                id: UUID(),
                workoutType: .running,
                startDate: Date().addingTimeInterval(-86400),
                endDate: Date().addingTimeInterval(-86400 + 2200),
                duration: 2200,
                distance: 6020,
                totalEnergyBurned: 480,
                sourceName: "Strava",
                sourceVersion: "1.0",
                metadata: nil,
                averageHeartRate: 172,
                maxHeartRate: 188,
                elevationGain: 30,
                hasRoute: true
            )
        )
    }
    .padding()
    .background(Color.irBackgroundApp)
    .preferredColorScheme(.dark)
}
