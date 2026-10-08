import Foundation

struct PendingPlanJob: Codable, Equatable {
    let jobID: UUID
    let goalID: UUID
    let start: Date
    let target: Date
    let createdAt: Date
}

// Persisted rather than kept in memory: a plan finished while the app was closed is still applied.
@MainActor
final class PendingPlanJobStore {
    static let defaultsKey = "pendingTrainingPlanJobs"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var jobs: [PendingPlanJob] {
        guard let data = defaults.data(forKey: Self.defaultsKey) else { return [] }
        return (try? JSONDecoder().decode([PendingPlanJob].self, from: data)) ?? []
    }

    func save(_ job: PendingPlanJob) {
        store(jobs.filter { $0.goalID != job.goalID } + [job])
    }

    func remove(jobID: UUID) {
        store(jobs.filter { $0.jobID != jobID })
    }

    private func store(_ jobs: [PendingPlanJob]) {
        defaults.set(try? JSONEncoder().encode(jobs), forKey: Self.defaultsKey)
    }
}
