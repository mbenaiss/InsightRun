import Combine
import Foundation

struct WorkoutNameOverride: Codable, Equatable, Identifiable {
  let id: UUID
  var identifiers: Set<String>
  var name: String
  var updatedAt: Date
}

@MainActor
final class WorkoutNameStore: ObservableObject {
  static let shared = WorkoutNameStore()
  @Published private(set) var overrides: [WorkoutNameOverride]

  private let defaults: UserDefaults
  private let storageKey = "workoutNames.v1"
  private var byIdentifier: [String: WorkoutNameOverride] = [:]

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    overrides =
      defaults.data(forKey: storageKey)
      .flatMap { try? JSONDecoder().decode([WorkoutNameOverride].self, from: $0) } ?? []
    rebuildIndex(overrides)
  }

  func name(for workout: WorkoutModel) -> String? {
    name(for: workout.raceIdentifiers)
  }

  func name(for identifiers: Set<String>) -> String? {
    latest(identifiers.compactMap { byIdentifier[$0] })?.name
  }

  func rename(_ workout: WorkoutModel, to name: String) {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return }
    let matching = overrides.filter { !$0.identifiers.isDisjoint(with: workout.raceIdentifiers) }
    var updated = overrides.filter { $0.identifiers.isDisjoint(with: workout.raceIdentifiers) }
    updated.append(
      WorkoutNameOverride(
        id: latest(matching)?.id ?? UUID(),
        identifiers: workout.raceIdentifiers.union(matching.flatMap(\.identifiers)),
        name: name,
        updatedAt: Date()
      ))
    save(updated)
  }

  func resetName(for workout: WorkoutModel) {
    save(overrides.filter { $0.identifiers.isDisjoint(with: workout.raceIdentifiers) })
  }

  func reconcile(_ workouts: [WorkoutModel]) {
    guard !overrides.isEmpty else { return }
    var updated = overrides
    for workout in workouts {
      let matching = updated.filter { !$0.identifiers.isDisjoint(with: workout.raceIdentifiers) }
      guard var current = latest(matching) else { continue }
      current.identifiers.formUnion(workout.raceIdentifiers)
      current.identifiers.formUnion(matching.flatMap(\.identifiers))
      updated.removeAll { !$0.identifiers.isDisjoint(with: current.identifiers) }
      updated.append(current)
    }
    save(updated)
  }

  private func latest(_ names: [WorkoutNameOverride]) -> WorkoutNameOverride? {
    names.max { ($0.updatedAt, $0.id.uuidString) < ($1.updatedAt, $1.id.uuidString) }
  }

  private func rebuildIndex(_ overrides: [WorkoutNameOverride]) {
    byIdentifier = [:]
    for override in overrides {
      for identifier in override.identifiers {
        byIdentifier[identifier] = latest([override, byIdentifier[identifier]].compactMap { $0 })
      }
    }
  }

  private func save(_ updated: [WorkoutNameOverride]) {
    let sorted = updated.sorted { $0.id.uuidString < $1.id.uuidString }
    guard sorted != overrides, let data = try? JSONEncoder().encode(sorted) else { return }
    defaults.set(data, forKey: storageKey)
    rebuildIndex(sorted)
    overrides = sorted
  }
}
