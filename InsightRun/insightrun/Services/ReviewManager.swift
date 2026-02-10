//
//  ReviewManager.swift
//  InsightRun
//
//  App Store review request manager
//

import StoreKit
import UIKit

@MainActor
final class ReviewManager {
    static let shared = ReviewManager()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let appInstallDate = "reviewManager_appInstallDate"
        static let lastReviewRequestDate = "reviewManager_lastReviewRequestDate"
        static let reviewRequestCount = "reviewManager_reviewRequestCount"
    }

    private static let appStoreID = "6754607965"
    private static let minimumWorkouts = 5
    private static let minimumDaysSinceInstall = 3
    private static let minimumDaysBetweenRequests = 90
    private static let maximumRequests = 3

    private init() {
        if defaults.object(forKey: Keys.appInstallDate) == nil {
            defaults.set(Date(), forKey: Keys.appInstallDate)
        }
    }

    // MARK: - Automatic Review Prompt

    func checkAndRequestReview() {
        guard canRequestReview() else { return }

        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return }

        AppStore.requestReview(in: scene)

        defaults.set(Date(), forKey: Keys.lastReviewRequestDate)
        defaults.set(reviewRequestCount + 1, forKey: Keys.reviewRequestCount)

        AnalyticsService.shared.trackReviewPromptShown()
    }

    // MARK: - Manual Review (opens App Store page)

    var reviewURL: URL? {
        URL(string: "https://apps.apple.com/app/id\(Self.appStoreID)?action=write-review")
    }

    // MARK: - Conditions

    private func canRequestReview() -> Bool {
        guard reviewRequestCount < Self.maximumRequests else { return false }

        guard let installDate = defaults.object(forKey: Keys.appInstallDate) as? Date,
              daysSince(installDate) >= Self.minimumDaysSinceInstall
        else { return false }

        if let lastRequest = defaults.object(forKey: Keys.lastReviewRequestDate) as? Date,
           daysSince(lastRequest) < Self.minimumDaysBetweenRequests {
            return false
        }

        let workoutCount = HistoricalSummaryStorage.shared.load()?.workoutCount ?? 0
        guard workoutCount >= Self.minimumWorkouts else { return false }

        return true
    }

    private var reviewRequestCount: Int {
        defaults.integer(forKey: Keys.reviewRequestCount)
    }

    private func daysSince(_ date: Date) -> Int {
        Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
    }
}
