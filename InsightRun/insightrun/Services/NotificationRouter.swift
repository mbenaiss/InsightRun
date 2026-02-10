//
//  NotificationRouter.swift
//  InsightRun
//
//  Handles notification tap actions and routes to the appropriate view.
//

import Combine
import Foundation
import UserNotifications

@MainActor
class NotificationRouter: NSObject, ObservableObject {
    static let shared = NotificationRouter()

    @Published var pendingTab: Int?
    @Published var showWeeklySummary = false

    override private init() {
        super.init()
    }

    func setup() {
        UNUserNotificationCenter.current().delegate = self
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationRouter: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let category = response.notification.request.content.categoryIdentifier

        Task { @MainActor in
            switch category {
            case "DAILY_READINESS", "LOW_READINESS":
                pendingTab = 0 // Dashboard tab (recovery merged)
            case "OVERTRAINING_ALERT", "INACTIVITY_REMINDER":
                pendingTab = 1 // Courses tab
            case "WEEKLY_SUMMARY":
                pendingTab = 0 // Dashboard tab
                showWeeklySummary = true
            default:
                break
            }
            completionHandler()
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
