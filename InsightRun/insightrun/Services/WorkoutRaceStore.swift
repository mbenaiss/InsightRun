import Combine
import Foundation

struct OfficialRace: Codable, Identifiable, Equatable {
    let id: UUID
    var identifiers: Set<String>
    var date: Date
    var name: String
    var distance: Double?
    var duration: TimeInterval
}

@MainActor
final class WorkoutRaceStore: ObservableObject {
    static let shared = WorkoutRaceStore()
    @Published private(set) var races: [OfficialRace]

    private let defaults: UserDefaults
    private let storageKey = "officialWorkoutRaces.v1"
    private var identifiers: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode([OfficialRace].self, from: $0) } ?? []
        races = saved
        identifiers = Set(saved.flatMap(\.identifiers))
    }

    func isOfficialRace(_ workout: WorkoutModel) -> Bool {
        !identifiers.isDisjoint(with: workout.raceIdentifiers)
    }

    func isOfficialRace(workoutID: String?) -> Bool {
        guard let workoutID else { return false }
        return identifiers.contains(workoutID.lowercased())
    }

    func officialRaces(from workouts: [WorkoutModel]) -> [WorkoutModel] {
        workouts.filter { isOfficialRace($0) }
    }

    func setOfficialRace(_ isRace: Bool, for workout: WorkoutModel) {
        let matching = races.filter { !$0.identifiers.isDisjoint(with: workout.raceIdentifiers) }
        var updated = races.filter { $0.identifiers.isDisjoint(with: workout.raceIdentifiers) }
        if isRace {
            updated.append(OfficialRace(
                id: matching.first?.id ?? UUID(),
                identifiers: workout.raceIdentifiers.union(matching.flatMap(\.identifiers)),
                date: workout.startDate,
                name: workout.raceDisplayName,
                distance: workout.distance,
                duration: workout.duration
            ))
        }
        save(updated)
    }

    func reconcile(_ workouts: [WorkoutModel]) {
        guard !races.isEmpty else { return }
        var updated = races
        var raceByIdentifier: [String: UUID] = [:]
        for race in updated {
            for identifier in race.identifiers { raceByIdentifier[identifier] = race.id }
        }
        for workout in workouts {
            let matchingIDs = Set(workout.raceIdentifiers.compactMap { raceByIdentifier[$0] })
            guard !matchingIDs.isEmpty else { continue }
            let matching = updated.filter { matchingIDs.contains($0.id) }
            guard let first = matching.first else { continue }
            let aliases = workout.raceIdentifiers.union(matching.flatMap(\.identifiers))
            updated.removeAll { matchingIDs.contains($0.id) }
            updated.append(OfficialRace(
                id: first.id,
                identifiers: aliases,
                date: workout.startDate,
                name: workout.raceDisplayName,
                distance: workout.distance,
                duration: workout.duration
            ))
            for alias in aliases { raceByIdentifier[alias] = first.id }
        }
        save(updated)
    }

    func races(in plan: TrainingPlan, weekIndex: Int, calendar: Calendar = .current) -> [OfficialRace] {
        guard plan.weeks.indices.contains(weekIndex), let start = plan.startDate,
              let lower = calendar.date(byAdding: .day, value: weekIndex * 7, to: calendar.startOfDay(for: start)),
              let upper = calendar.date(byAdding: .day, value: 7, to: lower) else { return [] }
        return races.filter { $0.date >= lower && $0.date < upper }.sorted { $0.date < $1.date }
    }

    private func save(_ updated: [OfficialRace]) {
        let sorted = updated.sorted { $0.date > $1.date }
        guard sorted != races, let data = try? JSONEncoder().encode(sorted) else { return }
        defaults.set(data, forKey: storageKey)
        identifiers = Set(sorted.flatMap(\.identifiers))
        races = sorted
    }
}

extension WorkoutModel {
    var raceIdentifiers: Set<String> {
        var identifiers: Set<String> = [id.uuidString.lowercased()]
        if let rawID = metadata?["strava_id"], let stravaID = Int64(String(describing: rawID)), stravaID > 0 {
            identifiers.insert("strava-\(stravaID)")
        }
        return identifiers
    }

    var raceDisplayName: String {
        for key in ["display_name", "strava_name", "title", "workout_name", "activity_name", "name"] {
            if let value = metadata?[key] as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return String(localized: "workout.race.label", defaultValue: "Official race")
    }
}
