//
//  NotificationManager.swift
//  InsightRun
//
//  Service for managing proactive coaching notifications
//  Handles daily readiness reminders, weekly summaries, and alerts
//

import Foundation
import UserNotifications
import Combine

@MainActor
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published var isNotificationsEnabled: Bool = false
    @Published var isDailyReadinessEnabled: Bool = false
    @Published var isWeeklySummaryEnabled: Bool = false

    private let userDefaults = UserDefaults.standard
    private let dailyReadinessKey = "com.insightrun.dailyReadinessNotification"
    private let weeklySummaryKey = "com.insightrun.weeklySummaryNotification"
    private let lastOvertrainingAlertKey = "com.insightrun.lastOvertrainingAlert"
    private let lastInactivityReminderKey = "com.insightrun.lastInactivityReminder"
    private let lastLowReadinessAlertKey = "com.insightrun.lastLowReadinessAlert"
    private let lastDailyReadinessKey = "com.insightrun.lastDailyReadiness"
    private let throttleInterval: TimeInterval = 24 * 60 * 60 // 24 hours

    private init() {
        isDailyReadinessEnabled = userDefaults.bool(forKey: dailyReadinessKey)
        isWeeklySummaryEnabled = userDefaults.bool(forKey: weeklySummaryKey)
    }

    // MARK: - Permission Request

    /// Request notification permissions from user
    func requestPermissions() async -> Bool {
        let center = UNUserNotificationCenter.current()

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            self.isNotificationsEnabled = granted
            return granted
        } catch {
            print("⚠️ NotificationManager: Failed to request permissions: \(error)")
            return false
        }
    }

    /// Check current notification permission status
    func checkPermissionStatus() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        self.isNotificationsEnabled = settings.authorizationStatus == .authorized
    }

    // MARK: - Daily Readiness Notification

    /// Enable daily readiness notifications (triggered by SleepObserverService on wake-up)
    func enableDailyReadiness() {
        guard isNotificationsEnabled else {
            print("⚠️ NotificationManager: Notifications not enabled")
            return
        }

        isDailyReadinessEnabled = true
        userDefaults.set(true, forKey: dailyReadinessKey)
        SleepObserverService.shared.startObserving()
    }

    /// Send daily readiness notification immediately (called by SleepObserverService on wake-up)
    /// Throttled to once per day
    func sendDailyReadinessNow() {
        guard isNotificationsEnabled, isDailyReadinessEnabled else { return }
        guard !isThrottled(key: lastDailyReadinessKey) else {
            print("⏱️ NotificationManager: Daily readiness throttled (24h)")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Good morning! 🏃", comment: "Daily readiness notification title")
        content.body = String(localized: "Check your readiness score to plan today's training.", comment: "Daily readiness notification body")
        content.sound = .default
        content.categoryIdentifier = "DAILY_READINESS"

        let request = UNNotificationRequest(
            identifier: "daily-readiness-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        Task {
            do {
                try await UNUserNotificationCenter.current().add(request)
                self.markSent(key: self.lastDailyReadinessKey)
                print("✅ NotificationManager: Daily readiness notification sent")
            } catch {
                print("❌ NotificationManager: Failed to send daily readiness: \(error)")
            }
        }
    }

    /// Cancel daily readiness notifications
    func cancelDailyReadiness() {
        isDailyReadinessEnabled = false
        userDefaults.set(false, forKey: dailyReadinessKey)
    }

    // MARK: - Weekly Summary Notification

    /// Schedule weekly summary notification (default: Sunday 6:00 PM)
    func scheduleWeeklySummary(weekday: Int = 1, hour: Int = 18, minute: Int = 0) {
        guard isNotificationsEnabled else { return }

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["weekly-summary"])

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Weekly Summary 📊", comment: "Weekly summary notification title")
        content.body = String(localized: "Your training week is ready for review. See your progress!", comment: "Weekly summary notification body")
        content.sound = .default
        content.categoryIdentifier = "WEEKLY_SUMMARY"

        var dateComponents = DateComponents()
        dateComponents.weekday = weekday // 1 = Sunday
        dateComponents.hour = hour
        dateComponents.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let request = UNNotificationRequest(identifier: "weekly-summary", content: content, trigger: trigger)

        Task {
            do {
                try await center.add(request)
                isWeeklySummaryEnabled = true
                userDefaults.set(true, forKey: weeklySummaryKey)
                print("✅ NotificationManager: Weekly summary scheduled")
            } catch {
                print("❌ NotificationManager: Failed to schedule weekly summary: \(error)")
            }
        }
    }

    /// Cancel weekly summary notifications
    func cancelWeeklySummary() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["weekly-summary"])
        isWeeklySummaryEnabled = false
        userDefaults.set(false, forKey: weeklySummaryKey)
    }

    // MARK: - Immediate Alerts

    /// Send overtraining alert when volume increases too much (throttled to once per 24h)
    func sendOvertrainingAlert(volumeIncrease: Double) {
        guard isNotificationsEnabled else { return }
        guard !isThrottled(key: lastOvertrainingAlertKey) else {
            print("⏱️ NotificationManager: Overtraining alert throttled (24h)")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Training Load Alert ⚠️", comment: "Overtraining alert notification title")
        content.body = String(
            localized: "Your volume increased \(Int(volumeIncrease))% this week. Consider reducing intensity.",
            comment: "Overtraining alert notification body"
        )
        content.sound = .default
        content.categoryIdentifier = "OVERTRAINING_ALERT"

        let request = UNNotificationRequest(
            identifier: "overtraining-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil // Immediate delivery
        )

        Task {
            do {
                try await UNUserNotificationCenter.current().add(request)
                self.markSent(key: self.lastOvertrainingAlertKey)
            } catch {
                print("❌ NotificationManager: Failed to send overtraining alert: \(error)")
            }
        }
    }

    /// Send inactivity reminder when user hasn't trained recently (throttled to once per 24h)
    func sendInactivityReminder(daysSinceLastRun: Int) {
        guard isNotificationsEnabled else { return }
        guard !isThrottled(key: lastInactivityReminderKey) else {
            print("⏱️ NotificationManager: Inactivity reminder throttled (24h)")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Time to Run! 💪", comment: "Inactivity reminder notification title")
        content.body = String(
            localized: "It's been \(daysSinceLastRun) days since your last run. A light jog could boost your mood!",
            comment: "Inactivity reminder notification body"
        )
        content.sound = .default
        content.categoryIdentifier = "INACTIVITY_REMINDER"

        let request = UNNotificationRequest(
            identifier: "inactivity-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        Task {
            do {
                try await UNUserNotificationCenter.current().add(request)
                self.markSent(key: self.lastInactivityReminderKey)
            } catch {
                print("❌ NotificationManager: Failed to send inactivity reminder: \(error)")
            }
        }
    }

    /// Send low readiness notification (throttled to once per 24h)
    func sendLowReadinessAlert(score: Int, reason: String) {
        guard isNotificationsEnabled else { return }
        guard !isThrottled(key: lastLowReadinessAlertKey) else {
            print("⏱️ NotificationManager: Low readiness alert throttled (24h)")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Rest Day Recommended 😴", comment: "Low readiness notification title")
        content.body = String(
            localized: "Your readiness score is \(score)/100. \(reason)",
            comment: "Low readiness notification body"
        )
        content.sound = .default
        content.categoryIdentifier = "LOW_READINESS"

        let request = UNNotificationRequest(
            identifier: "low-readiness-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        Task {
            do {
                try await UNUserNotificationCenter.current().add(request)
                self.markSent(key: self.lastLowReadinessAlertKey)
            } catch {
                print("❌ NotificationManager: Failed to send low readiness alert: \(error)")
            }
        }
    }

    // MARK: - Throttling

    private func isThrottled(key: String) -> Bool {
        guard let lastSent = userDefaults.object(forKey: key) as? Date else {
            return false
        }
        return Date().timeIntervalSince(lastSent) < throttleInterval
    }

    private func markSent(key: String) {
        userDefaults.set(Date(), forKey: key)
    }

    // MARK: - Cleanup

    /// Remove all pending notifications
    func removeAllPendingNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        isDailyReadinessEnabled = false
        isWeeklySummaryEnabled = false
        userDefaults.set(false, forKey: dailyReadinessKey)
        userDefaults.set(false, forKey: weeklySummaryKey)
    }
}
