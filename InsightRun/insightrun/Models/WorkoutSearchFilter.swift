import Foundation

enum WorkoutDistanceFilter: String, CaseIterable {
  case all
  case fiveKilometers
  case tenKilometers
  case halfMarathon
  case marathon

  var title: String {
    switch self {
    case .all: String(localized: "workout.distance.all", defaultValue: "All")
    case .fiveKilometers: "5 km"
    case .tenKilometers: "10 km"
    case .halfMarathon: String(localized: "workout.distance.half", defaultValue: "Half")
    case .marathon: String(localized: "workout.distance.marathon", defaultValue: "Marathon")
    }
  }

  var targetMeters: Double? {
    switch self {
    case .all: nil
    case .fiveKilometers: 5_000
    case .tenKilometers: 10_000
    case .halfMarathon: 21_097.5
    case .marathon: 42_195
    }
  }

  var toleranceMeters: Double {
    switch self {
    case .all, .fiveKilometers, .tenKilometers: 200
    case .halfMarathon, .marathon: 1_000
    }
  }

  func matches(_ distance: Double?) -> Bool {
    guard let targetMeters else { return true }
    guard let distance, distance.isFinite else { return false }
    if self == .halfMarathon && abs(distance - 20_000) <= toleranceMeters { return true }
    return abs(distance - targetMeters) <= toleranceMeters
  }
}

struct WorkoutSearchFilter {
  var query: String = ""
  var distance: WorkoutDistanceFilter = .all

  func apply(
    to workouts: [WorkoutModel], locale: Locale = .current, names: WorkoutNameStore = .shared
  ) -> [WorkoutModel] {
    let query = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.dateFormat = "EEE d MMMM yyyy"
    return workouts.filter { workout in
      guard distance.matches(workout.distance) else { return false }
      guard !query.isEmpty else { return true }
      let context = workout.isIndoor ? "tapis indoor" : "plein air outdoor"
      return formatter.string(from: workout.startDate).lowercased().contains(query)
        || names.name(for: workout)?.lowercased().contains(query) == true
        || workout.raceDisplayName.lowercased().contains(query)
        || workout.sourceName.lowercased().contains(query)
        || context.contains(query)
    }
  }
}
