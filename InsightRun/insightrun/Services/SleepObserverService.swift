//
//  SleepObserverService.swift
//  InsightRun
//
//  Background service that observes HealthKit sleep data updates
//  and triggers the daily readiness notification when the user wakes up.
//

import Foundation
import HealthKit

@MainActor
final class SleepObserverService {
    static let shared = SleepObserverService()

    private let healthStore = HKHealthStore()
    private let lastWakeUpNotificationKey = "com.insightrun.lastWakeUpNotificationDate"
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
            print("✅ SleepObserverService: ObserverQuery stopped")
        }
    }

    // MARK: - Background Delivery

    private func enableBackgroundDelivery() {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return }

        healthStore.enableBackgroundDelivery(
            for: sleepType,
            frequency: .immediate
        ) { success, error in
            if let error {
                print("❌ SleepObserverService: enableBackgroundDelivery failed: \(error)")
            } else if success {
                print("✅ SleepObserverService: Background delivery enabled for sleep")
            }
        }
    }

    // MARK: - Observer Query

    private func startObserverQuery() {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return }

        let query = HKObserverQuery(sampleType: sleepType, predicate: nil) { [weak self] _, completionHandler, error in
            if let error {
                print("❌ SleepObserverService: ObserverQuery error: \(error)")
                completionHandler()
                return
            }

            Task { @MainActor in
                guard let self else {
                    completionHandler()
                    return
                }
                self.handleSleepUpdate {
                    completionHandler()
                }
            }
        }

        healthStore.execute(query)
        observerQuery = query
        print("✅ SleepObserverService: ObserverQuery started")
    }

    // MARK: - Wake-Up Detection

    private func handleSleepUpdate(completion: @escaping () -> Void) {
        guard !hasAlreadyNotifiedToday() else {
            completion()
            return
        }

        // Only trigger between 4 AM and 2 PM (reasonable wake-up window)
        let hour = Calendar.current.component(.hour, from: Date())
        guard hour >= 4 && hour < 14 else {
            completion()
            return
        }

        // Fetch today's sleep data to confirm wake-up
        Task {
            defer { completion() }

            let today = Date()
            guard let sleepData = try? await HealthKitManager.shared.fetchSleepData(for: today) else {
                // Also check yesterday (sleep session that ended this morning)
                guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today),
                      let yesterdaySleep = try? await HealthKitManager.shared.fetchSleepData(for: yesterday) else {
                    return
                }

                // Confirm the sleep session ended recently (within the last 2 hours)
                let timeSinceWakeUp = today.timeIntervalSince(yesterdaySleep.sleepEnd)
                guard timeSinceWakeUp >= 0 && timeSinceWakeUp < 2 * 60 * 60 else {
                    return
                }

                self.triggerDailyReadiness()
                return
            }

            let timeSinceWakeUp = today.timeIntervalSince(sleepData.sleepEnd)
            guard timeSinceWakeUp >= 0 && timeSinceWakeUp < 2 * 60 * 60 else {
                return
            }

            self.triggerDailyReadiness()
        }
    }

    private func triggerDailyReadiness() {
        markNotifiedToday()

        Task { @MainActor in
            NotificationManager.shared.sendDailyReadinessNow()
        }

        print("✅ SleepObserverService: Wake-up detected, daily readiness notification sent")
    }

    // MARK: - Daily Throttle

    private func hasAlreadyNotifiedToday() -> Bool {
        guard let lastDate = UserDefaults.standard.object(forKey: lastWakeUpNotificationKey) as? Date else {
            return false
        }
        return Calendar.current.isDateInToday(lastDate)
    }

    private func markNotifiedToday() {
        UserDefaults.standard.set(Date(), forKey: lastWakeUpNotificationKey)
    }
}
