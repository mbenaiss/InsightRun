//
//  WorkoutSyncService.swift
//  InsightRun
//
//  Background sync service that detects new workouts via HealthKit
//  and sends local notifications when a workout completes.
//

import Foundation
import HealthKit
import UserNotifications

@MainActor
final class WorkoutSyncService {
    static let shared = WorkoutSyncService()

    private let healthStore = HKHealthStore()
    private let anchorKey = "com.insightrun.workoutSyncAnchor"
    private let seededKey = "com.insightrun.workoutSyncSeeded"
    private var observerQuery: HKObserverQuery?

    private init() {}

    // MARK: - Public

    func startObserving() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard observerQuery == nil else { return }

        enableBackgroundDelivery()
        startObserverQuery()
    }

    func stopObserving() {
        if let query = observerQuery {
            healthStore.stop(query)
            observerQuery = nil
            print("✅ WorkoutSyncService: ObserverQuery stopped")
        }
    }

    // MARK: - Background Delivery

    private func enableBackgroundDelivery() {
        healthStore.enableBackgroundDelivery(
            for: .workoutType(),
            frequency: .immediate
        ) { success, error in
            if let error {
                print("❌ WorkoutSyncService: enableBackgroundDelivery failed: \(error)")
            } else if success {
                print("✅ WorkoutSyncService: Background delivery enabled")
            }
        }
    }

    // MARK: - Observer Query

    private func startObserverQuery() {
        let query = HKObserverQuery(sampleType: .workoutType(), predicate: nil) { [weak self] _, completionHandler, error in
            if let error {
                print("❌ WorkoutSyncService: ObserverQuery error: \(error)")
                completionHandler()
                return
            }

            guard let self else {
                completionHandler()
                return
            }
            Task { @MainActor in
                self.fetchNewWorkouts {
                    completionHandler()
                }
            }
        }

        healthStore.execute(query)
        observerQuery = query
        print("✅ WorkoutSyncService: ObserverQuery started")
    }

    // MARK: - Anchored Object Query

    private func fetchNewWorkouts(completion: @escaping () -> Void) {
        let isSeeded = UserDefaults.standard.bool(forKey: seededKey)
        let anchor = loadAnchor()

        let query = HKAnchoredObjectQuery(
            type: .workoutType(),
            predicate: nil,
            anchor: anchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, newAnchor, error in
            if let error {
                print("❌ WorkoutSyncService: AnchoredObjectQuery error: \(error)")
                completion()
                return
            }

            guard let self else {
                completion()
                return
            }
            Task { @MainActor in

                if let newAnchor {
                    self.saveAnchor(newAnchor)
                }

                // First launch: seed anchor without sending notifications
                guard isSeeded else {
                    UserDefaults.standard.set(true, forKey: self.seededKey)
                    print("✅ WorkoutSyncService: Anchor seeded (skipping \(samples?.count ?? 0) existing workouts)")
                    completion()
                    return
                }

                let workouts = (samples as? [HKWorkout])?.filter {
                    $0.workoutActivityType == .running
                } ?? []

                guard !workouts.isEmpty else {
                    completion()
                    return
                }

                print("🏃 WorkoutSyncService: \(workouts.count) new running workout(s) detected")

                self.sendNotifications(for: workouts) {
                    completion()
                }
            }
        }

        healthStore.execute(query)
    }

    // MARK: - Notifications

    private func sendNotifications(for workouts: [HKWorkout], completion: @escaping () -> Void) {
        let center = UNUserNotificationCenter.current()
        let total = workouts.count
        let group = DispatchGroup()

        for (index, workout) in workouts.enumerated() {
            group.enter()

            let content = UNMutableNotificationContent()
            content.title = String(localized: "Sync \(index + 1) / \(total)", comment: "Workout sync notification title showing current/total count")
            content.body = notificationBody(for: workout)
            content.sound = .default
            content.categoryIdentifier = "WORKOUT_SYNC"
            content.userInfo = ["workoutUUID": workout.uuid.uuidString]

            let identifier = "workout-sync-\(workout.uuid.uuidString)"
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

            center.add(request) { error in
                if let error {
                    print("❌ WorkoutSyncService: Failed to send notification: \(error)")
                }
                group.leave()
            }
        }

        group.notify(queue: .global()) {
            completion()
        }
    }

    private func notificationBody(for workout: HKWorkout) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .short

        let dateLine = dateFormatter.string(from: workout.startDate)
        let typeLine = localizedWorkoutType(for: workout)
        let deviceLine = workout.sourceRevision.source.name

        return "\(dateLine)\n\(typeLine)\n\(deviceLine)"
    }

    private func localizedWorkoutType(for workout: HKWorkout) -> String {
        let isIndoor = workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool ?? false

        switch workout.workoutActivityType {
        case .running:
            return isIndoor
                ? String(localized: "Running (indoor)", comment: "Indoor running workout type for notification")
                : String(localized: "Running (outdoor)", comment: "Outdoor running workout type for notification")
        case .walking:
            return String(localized: "Walking", comment: "Walking workout type for notification")
        case .cycling:
            return String(localized: "Cycling", comment: "Cycling workout type for notification")
        case .swimming:
            return String(localized: "Swimming", comment: "Swimming workout type for notification")
        default:
            return String(localized: "Workout", comment: "Generic workout type for notification")
        }
    }

    // MARK: - Anchor Persistence

    private func loadAnchor() -> HKQueryAnchor? {
        guard let data = UserDefaults.standard.data(forKey: anchorKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private func saveAnchor(_ anchor: HKQueryAnchor) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) else { return }
        UserDefaults.standard.set(data, forKey: anchorKey)
    }
}
