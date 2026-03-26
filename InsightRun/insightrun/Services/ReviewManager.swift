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
        static let lastPositiveAIAnalysis = "reviewManager_lastPositiveAIAnalysis"
    }

    private static let appStoreID = "6754607965"
    private static let minimumWorkouts = 3
    private static let minimumDaysSinceInstall = 2
    private static let minimumDaysBetweenRequests = 30
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

    /// Call this after the user views a positive AI analysis
    /// Triggers a review prompt if all other conditions are met
    func recordPositiveAIAnalysis() {
        defaults.set(Date(), forKey: Keys.lastPositiveAIAnalysis)
        checkAndRequestReview()
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

        // Require a recent positive AI analysis (within last 7 days)
        guard let lastPositive = defaults.object(forKey: Keys.lastPositiveAIAnalysis) as? Date,
              daysSince(lastPositive) <= 7
        else { return false }

        return true
    }

    private var reviewRequestCount: Int {
        defaults.integer(forKey: Keys.reviewRequestCount)
    }

    private func daysSince(_ date: Date) -> Int {
        Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
    }
}
