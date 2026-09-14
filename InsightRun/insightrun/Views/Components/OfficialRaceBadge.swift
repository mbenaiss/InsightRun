import SwiftUI

struct OfficialRaceBadge: View {
    var body: some View {
        Label(String(localized: "workout.race.label", defaultValue: "Official race"), systemImage: "flag.checkered")
            .font(IRFont.caption.weight(.semibold))
            .foregroundStyle(Color.irPrimaryAccent)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs)
            .background(Color.irAccentSoft, in: RoundedRectangle(cornerRadius: Radius.xs))
    }
}

struct OfficialRacesInPlanView: View {
    let plan: TrainingPlan
    let weekIndex: Int
    @ObservedObject private var raceStore = WorkoutRaceStore.shared

    var body: some View {
        let races = raceStore.races(in: plan, weekIndex: weekIndex)
        if !races.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label(String(localized: "workout.race.completed", defaultValue: "Completed official races"), systemImage: "flag.checkered")
                    .font(IRFont.caption.weight(.semibold))
                    .foregroundStyle(Color.irPrimaryAccent)

                ForEach(races) { race in
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(race.name)
                            .font(IRFont.bodyEmphasized)
                            .foregroundStyle(Color.irTextPrimary)
                        Text(race.date.formatted(date: .abbreviated, time: .omitted))
                            .font(IRFont.caption)
                            .foregroundStyle(Color.irTextSecondary)
                        HStack(spacing: Spacing.md) {
                            if let distance = race.distance {
                                Label(Formatters.distance(km: distance / 1000), systemImage: "ruler")
                            }
                            Label(Duration.seconds(race.duration).formatted(.time(pattern: .hourMinuteSecond)), systemImage: "clock")
                        }
                        .font(IRFont.caption)
                        .foregroundStyle(Color.irTextSecondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("plan-official-race-\(race.id)")
                }
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.irAccentSoft, in: RoundedRectangle(cornerRadius: Radius.sm))
            .padding(.top, Spacing.md)
        }
    }
}
