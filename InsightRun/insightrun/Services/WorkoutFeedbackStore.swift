import Combine
import Foundation

struct WorkoutFeedback: Codable, Equatable {
  var effort: Int?
  var intent: String?
  var legs: String?
  var goalAchieved: String?

  var isEmpty: Bool { effort == nil && intent == nil && legs == nil && goalAchieved == nil }
}

@MainActor
final class WorkoutFeedbackStore: ObservableObject {
  static let shared = WorkoutFeedbackStore()
  private struct Entry: Codable {
    let identifiers: Set<String>
    let feedback: WorkoutFeedback
  }

  @Published private(set) var revision = 0
  private let defaults: UserDefaults
  private var entries: [Entry]
  private let key = "workoutFeedback.v1"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    entries =
      defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
  }

  func feedback(for workout: WorkoutModel) -> WorkoutFeedback? {
    entries.last { !$0.identifiers.isDisjoint(with: workout.raceIdentifiers) }?.feedback
  }

  func save(_ feedback: WorkoutFeedback, for workout: WorkoutModel) {
    var feedback = feedback
    feedback.effort = feedback.effort.flatMap { (1...10).contains($0) ? $0 : nil }
    let matching = entries.filter { !$0.identifiers.isDisjoint(with: workout.raceIdentifiers) }
    entries.removeAll { !$0.identifiers.isDisjoint(with: workout.raceIdentifiers) }
    if !feedback.isEmpty {
      entries.append(
        Entry(
          identifiers: workout.raceIdentifiers.union(matching.flatMap(\.identifiers)),
          feedback: feedback))
    }
    if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: key) }
    revision += 1
  }
}
