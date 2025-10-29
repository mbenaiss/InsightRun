//
//  AnalyticsService.swift
//  InsightRun
//
//  PostHog analytics service for tracking user events
//

import Foundation
import UIKit
import PostHog

/// Centralized analytics service for tracking user events with PostHog
@MainActor
final class AnalyticsService {
    static let shared = AnalyticsService()

    private var sessionID: String
    private var isFirstLaunch: Bool

    private init() {
        // Generate unique session ID
        self.sessionID = UUID().uuidString

        // Check if this is the first launch
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        self.isFirstLaunch = !hasLaunchedBefore

        if !hasLaunchedBefore {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        }
    }

    /// Configure PostHog SDK
    /// Call this once at app launch before tracking any events
    func configure() {
        let POSTHOG_API_KEY = "phc_khr0U4g0Tk1ev5s1a61J4wI8ibkPTnLiqgL3H4xf3ML"
        let POSTHOG_HOST = "https://eu.i.posthog.com"

        let config = PostHogConfig(apiKey: POSTHOG_API_KEY, host: POSTHOG_HOST)

        #if DEBUG
        config.debug = true
        #endif

        PostHogSDK.shared.setup(config)

        // Identify user with UUID from UserIdentityService
        let userID = UserIdentityService.shared.userID
        PostHogSDK.shared.identify(userID)

        print("✅ PostHog: Configured with user ID \(userID)")
    }

    // MARK: - Core Tracking Method

    /// Track an analytics event with optional properties
    func track(_ event: AnalyticsEvent, properties: [String: Any] = [:]) {
        var enrichedProperties = properties

        // Add global properties to every event
        enrichedProperties["session_id"] = sessionID
        enrichedProperties["app_version"] = appVersion
        enrichedProperties["ios_version"] = UIDevice.current.systemVersion
        enrichedProperties["device_model"] = deviceModel
        enrichedProperties["locale"] = Locale.current.identifier
        enrichedProperties["subscription_status"] = subscriptionStatus

        #if DEBUG
        print("📊 Analytics: \(event.rawValue) - \(enrichedProperties)")
        #endif

        PostHogSDK.shared.capture(event.rawValue, properties: enrichedProperties)
    }

    // MARK: - Computed Global Properties

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    private var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }

    private var subscriptionStatus: String {
        if RevenueCatManager.shared.isSubscriptionActive {
            return "premium"
        } else {
            return "free"
        }
    }

    // MARK: - Lifecycle Events

    func trackAppOpened() {
        track(.appOpened, properties: [
            "is_first_launch": isFirstLaunch
        ])
    }

    func trackOnboardingStarted() {
        track(.onboardingStarted)
    }

    func trackOnboardingStepViewed(step: Int, stepName: String) {
        track(.onboardingStepViewed, properties: [
            "step_number": step,
            "step_name": stepName
        ])
    }

    func trackOnboardingStepCompleted(step: Int, stepName: String) {
        track(.onboardingStepCompleted, properties: [
            "step_number": step,
            "step_name": stepName
        ])
    }

    func trackOnboardingCompleted() {
        track(.onboardingCompleted)
    }

    func trackOnboardingSkipped(stepReached: String, timeSpent: TimeInterval) {
        track(.onboardingSkipped, properties: [
            "step_reached": stepReached,
            "time_spent": Int(timeSpent)
        ])
    }

    func trackHealthKitPermissionRequested() {
        track(.healthKitPermissionRequested)
    }

    func trackHealthKitPermissionGranted() {
        track(.healthKitPermissionGranted)
    }

    func trackHealthKitPermissionDenied() {
        track(.healthKitPermissionDenied)
    }

    // MARK: - Workout Events

    func trackWorkoutListViewed(totalWorkouts: Int) {
        track(.workoutListViewed, properties: [
            "total_workouts": totalWorkouts
        ])
    }

    func trackWorkoutDetailViewed() {
        track(.workoutDetailViewed)
    }

    func trackFirstWorkoutSynced(workoutsCount: Int, syncSuccess: Bool) {
        track(.firstWorkoutSynced, properties: [
            "workouts_count": workoutsCount,
            "sync_success": syncSuccess
        ])
    }

    // MARK: - AI Assistant Events

    func trackAIChatOpened() {
        track(.aiChatOpened)
    }

    func trackAIMessageSent(messageLength: Int, contextType: AIContextType) {
        track(.aiMessageSent, properties: [
            "message_length": messageLength,
            "context_type": contextType.rawValue
        ])
    }

    func trackAIResponseReceived(responseTimeMs: Int, responseLength: Int) {
        track(.aiResponseReceived, properties: [
            "response_time_ms": responseTimeMs,
            "response_length": responseLength
        ])
    }

    func trackAIResponseError(errorType: String, errorMessage: String) {
        track(.aiResponseError, properties: [
            "error_type": errorType,
            "error_message": errorMessage
        ])
    }

    // MARK: - Recovery Dashboard Events

    func trackRecoveryDashboardViewed(recoveryScore: Int?, hasRecentWorkouts: Bool) {
        var properties: [String: Any] = [
            "has_recent_workouts": hasRecentWorkouts
        ]

        if let score = recoveryScore {
            properties["recovery_score"] = score
        }

        track(.recoveryDashboardViewed, properties: properties)
    }

    // MARK: - Monetization Events (RevenueCat)

    func trackPaywallViewed(triggerSource: String, availableProducts: [String]) {
        track(.paywallViewed, properties: [
            "trigger_source": triggerSource,
            "available_products": availableProducts
        ])
    }

    func trackPaywallDismissed(timeSpentSeconds: TimeInterval) {
        track(.paywallDismissed, properties: [
            "time_spent_seconds": Int(timeSpentSeconds)
        ])
    }

    func trackSubscriptionPurchaseStarted(productId: String, price: String, billingPeriod: String) {
        track(.subscriptionPurchaseStarted, properties: [
            "product_id": productId,
            "price": price,
            "billing_period": billingPeriod
        ])
    }

    func trackSubscriptionPurchaseCompleted(productId: String, revenue: String, isTrial: Bool) {
        track(.subscriptionPurchaseCompleted, properties: [
            "product_id": productId,
            "revenue": revenue,
            "is_trial": isTrial
        ])
    }

    func trackSubscriptionPurchaseFailed(errorCode: String, errorMessage: String) {
        track(.subscriptionPurchaseFailed, properties: [
            "error_code": errorCode,
            "error_message": errorMessage
        ])
    }

    func trackSubscriptionCancelled() {
        track(.subscriptionCancelled)
    }

    func trackSubscriptionRenewed() {
        track(.subscriptionRenewed)
    }
}

// MARK: - Analytics Event Enum

enum AnalyticsEvent: String {
    // Lifecycle
    case appOpened = "app_opened"
    case onboardingStarted = "onboarding_started"
    case onboardingStepViewed = "onboarding_step_viewed"
    case onboardingStepCompleted = "onboarding_step_completed"
    case onboardingCompleted = "onboarding_completed"
    case onboardingSkipped = "onboarding_skipped"
    case healthKitPermissionRequested = "healthkit_permission_requested"
    case healthKitPermissionGranted = "healthkit_permission_granted"
    case healthKitPermissionDenied = "healthkit_permission_denied"

    // Workouts
    case workoutListViewed = "workout_list_viewed"
    case workoutDetailViewed = "workout_detail_viewed"
    case firstWorkoutSynced = "first_workout_synced"

    // AI Assistant
    case aiChatOpened = "ai_chat_opened"
    case aiMessageSent = "ai_message_sent"
    case aiResponseReceived = "ai_response_received"
    case aiResponseError = "ai_response_error"

    // Recovery Dashboard
    case recoveryDashboardViewed = "recovery_dashboard_viewed"

    // Monetization
    case paywallViewed = "paywall_viewed"
    case paywallDismissed = "paywall_dismissed"
    case subscriptionPurchaseStarted = "subscription_purchase_started"
    case subscriptionPurchaseCompleted = "subscription_purchase_completed"
    case subscriptionPurchaseFailed = "subscription_purchase_failed"
    case subscriptionCancelled = "subscription_cancelled"
    case subscriptionRenewed = "subscription_renewed"
}

// MARK: - Supporting Types

enum AIContextType: String {
    case workout
    case recovery
    case general
}
