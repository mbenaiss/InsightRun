//
//  WorkoutRowView.swift
//  InsightRun
//
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
        case .long:     return Color.irPurple
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
        case .strava: return .brandStrava
        case .apple: return .brandAppleWatch
        case .suunto: return .brandSuunto
        case .garmin: return .brandGarmin
        case .polar: return .brandPolar
        case .coros: return .brandCoros
        case .imported: return .brandHealthKit
        case .other: return Color.irPrimaryAccent
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
    @ObservedObject private var raceStore = WorkoutRaceStore.shared
    @ObservedObject private var nameStore = WorkoutNameStore.shared

    private var sessionType: WorkoutSessionType { WorkoutSessionType.classify(workout) }
    private var source: RowWorkoutSource { RowWorkoutSource.classify(sourceName: workout.sourceName) }

    private var dayLabel: String {
        workout.startDate.formatted(.dateTime.weekday(.abbreviated)).capitalized
    }

    private var dateLabel: String {
        workout.startDate.formatted(.dateTime.day().month(.abbreviated).year())
    }

    private var timeLabel: String {
        workout.startDate.formatted(date: .omitted, time: .shortened)
    }

    private var distanceText: String {
        guard let distance = workout.distance else { return "—" }
        return Formatters.decimal(Formatters.distanceValue(km: distance / 1000.0), fractionDigits: 2)
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
        let secondsPerUnit = UnitPreference.current == .imperial
            ? pace * 60.0 / Formatters.kmToMiles
            : pace * 60.0
        return Formatters.paceClock(secondsPerUnit)
    }

    private var heartRateText: String? {
        guard let hr = workout.averageHeartRate else { return nil }
        return Formatters.integer(Int(hr.rounded()))
    }

    private var effortScore: Double? {
        guard let score = workout.effortScore, score.isFinite, (1...10).contains(score) else { return nil }
        return score
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: Spacing.md) {
                leftBadgeColumn

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    metaLine
                    titleLine
                    chipsRow
                    statsRow
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(IRFont.eyebrow.weight(.bold))
                    .foregroundStyle(Color.irTextSecondary.opacity(0.55))
                    .padding(.top, Spacing.xs)
            }
            .padding(.horizontal, Spacing.dash)
            .padding(.top, Spacing.dash)
            .padding(.bottom, Spacing.md)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .detailCard()
    }

    // MARK: - Subviews

    private var leftBadgeColumn: some View {
        VStack(spacing: Spacing.xs) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.xs)
                    .fill(sessionType.color.opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.xs)
                            .strokeBorder(sessionType.color.opacity(0.35), lineWidth: 0.5)
                    )

                Image(systemName: typeGlyph)
                    .font(IRFont.body.weight(.semibold))
                    .foregroundStyle(sessionType.color)
            }
            .frame(width: 36, height: 36)
            .overlay(alignment: .bottomTrailing) {
                sourceOverlay
                    .offset(x: 4, y: 4)
            }

            if let effortScore {
                VStack(spacing: Spacing.xxs) {
                    Text(String(localized: "EFFORT", comment: "Workout intensity dots label"))
                        .font(IRFont.monoSM.weight(.bold))
                        .tracking(0.5)
                        .foregroundStyle(Color.irTextSecondary.opacity(0.7))
                    Text("\(Formatters.decimal(effortScore, fractionDigits: 0))/10")
                        .font(IRFont.monoSM.weight(.bold))
                        .foregroundStyle(Color.irTextSecondary)
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
                        .foregroundStyle(Color.irTextPrimary)
                )
            case .imported:
                return AnyView(
                    Text("I")
                        .font(IRFont.monoSM.weight(.bold))
                        .foregroundStyle(Color.irTextPrimary)
                )
            default:
                return AnyView(
                    Text(String(workout.sourceName.prefix(1)).uppercased())
                        .font(IRFont.monoSM.weight(.bold))
                        .foregroundStyle(Color.irTextPrimary)
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
            .font(IRFont.microLabel.weight(.bold))
            .tracking(0.8)
            .foregroundStyle(Color.irTextSecondary.opacity(0.7))
            .lineLimit(1)
    }

    private var titleLine: some View {
        Text(titleText)
            .font(IRFont.bodyEmphasized.weight(.bold))
            .foregroundStyle(Color.irTextPrimary)
            .lineLimit(1)
    }

    private var titleText: String {
        if let name = nameStore.name(for: workout) { return name }
        if raceStore.isOfficialRace(workout) {
            return workout.raceDisplayName
        }
        if workout.isIndoor {
            return String(localized: "Treadmill", comment: "Workout title: indoor / treadmill run")
        }
        return String(localized: "Outdoor run", comment: "Workout title: outdoor run")
    }

    @ViewBuilder
    private var chipsRow: some View {
        if raceStore.isOfficialRace(workout) {
            OfficialRaceBadge()
        }
    }

    private var statsRow: some View {
        HStack(spacing: Spacing.md) {
            stat(icon: "ruler", value: distanceText, unit: Formatters.distanceUnitLabel(), mono: false)
            stat(icon: "clock", value: durationCompact, unit: nil, mono: true)
            if let pace = paceText {
                stat(icon: "speedometer", value: pace, unit: Formatters.paceUnitSuffix(), mono: true)
            }
            if let hr = heartRateText {
                stat(icon: "heart.fill", value: hr, unit: String(localized: "bpm", comment: "Heart rate unit"), mono: false, tint: .irError)
            }
        }
    }

    private func stat(icon: String, value: String, unit: String?, mono: Bool, tint: Color = .irTextSecondary) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Image(systemName: icon)
                .font(IRFont.microLabel.weight(.semibold))
                .foregroundStyle(tint)

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(mono ? IRFont.monoSM.weight(.bold) : IRFont.caption.weight(.bold))
                    .foregroundStyle(Color.irTextPrimary)
                if let unit {
                    Text(unit)
                        .font(IRFont.monoSM.weight(.medium))
                        .foregroundStyle(Color.irTextSecondary.opacity(0.7))
                }
            }
        }
    }

}

#Preview {
    VStack(spacing: Spacing.sm) {
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
