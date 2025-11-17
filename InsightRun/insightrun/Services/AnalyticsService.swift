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
    /// Non-blocking: errors are logged but don't crash the app
    func configure() {
        Task.detached {
            do {
                let POSTHOG_API_KEY = "phc_khr0U4g0Tk1ev5s1a61J4wI8ibkPTnLiqgL3H4xf3ML"
                let POSTHOG_HOST = "https://eu.i.posthog.com"

                let config = PostHogConfig(apiKey: POSTHOG_API_KEY, host: POSTHOG_HOST)

                #if DEBUG
                config.debug = true
                #endif

                PostHogSDK.shared.setup(config)

                // Identify user with UUID from UserIdentityService
                let userID = await UserIdentityService.shared.userID
                PostHogSDK.shared.identify(userID)

                print("✅ PostHog: Configured with user ID \(userID)")
            }
        }
    }

    // MARK: - Core Tracking Method

    /// Track an analytics event with optional properties
    /// Non-blocking: runs in background and doesn't crash the app if PostHog fails
    func track(_ event: AnalyticsEvent, properties: [String: Any] = [:]) {
        Task.detached { @MainActor in
            var enrichedProperties = properties

            // Add global properties to every event
            enrichedProperties["session_id"] = self.sessionID
            enrichedProperties["app_version"] = self.appVersion
            enrichedProperties["ios_version"] = UIDevice.current.systemVersion
            enrichedProperties["device_model"] = self.deviceModel
            enrichedProperties["locale"] = Locale.current.identifier
            enrichedProperties["subscription_status"] = self.subscriptionStatus

            #if DEBUG
            print("📊 Analytics: \(event.rawValue) - \(enrichedProperties)")
            #endif

            PostHogSDK.shared.capture(event.rawValue, properties: enrichedProperties)
        }
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

    func trackWorkoutExported() {
        track(.workoutExported)
    }

    func trackWorkoutExportFailed(errorMessage: String) {
        track(.workoutExportFailed, properties: [
            "error_message": errorMessage
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

    func trackAIMessageSentWithoutContext(contextType: AIContextType) {
        track(.aiMessageSentWithoutContext, properties: [
            "context_type": contextType.rawValue
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

    // MARK: - Historical Indexation Events

    func trackIndexationBannerShown() {
        track(.indexationBannerShown)
    }

    func trackIndexationBannerSyncTapped() {
        track(.indexationBannerSyncTapped)
    }

    func trackIndexationBannerDismissed() {
        track(.indexationBannerDismissed)
    }

    func trackIndexationStarted(workoutsCount: Int, totalBatches: Int) {
        track(.indexationStarted, properties: [
            "workouts_count": workoutsCount,
            "total_batches": totalBatches
        ])
    }

    func trackIndexationBatchProcessed(batchNumber: Int, totalBatches: Int, progress: Double) {
        track(.indexationBatchProcessed, properties: [
            "batch_number": batchNumber,
            "total_batches": totalBatches,
            "progress_percentage": Int(progress * 100)
        ])
    }

    func trackIndexationCompleted(workoutsCount: Int, durationSeconds: TimeInterval, totalBatches: Int) {
        track(.indexationCompleted, properties: [
            "workouts_count": workoutsCount,
            "duration_seconds": Int(durationSeconds),
            "total_batches": totalBatches
        ])
    }

    func trackIndexationFailed(errorType: String, errorMessage: String, failedAtBatch: Int?, totalBatches: Int?) {
        var properties: [String: Any] = [
            "error_type": errorType,
            "error_message": errorMessage
        ]

        if let batch = failedAtBatch {
            properties["failed_at_batch"] = batch
        }

        if let total = totalBatches {
            properties["total_batches"] = total
        }

        track(.indexationFailed, properties: properties)
    }

    func trackIndexationCancelled(cancelledAtBatch: Int, totalBatches: Int, progress: Double) {
        track(.indexationCancelled, properties: [
            "cancelled_at_batch": cancelledAtBatch,
            "total_batches": totalBatches,
            "progress_percentage": Int(progress * 100)
        ])
    }

    func trackIndexationRetryTapped(previousErrorType: String) {
        track(.indexationRetryTapped, properties: [
            "previous_error_type": previousErrorType
        ])
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
    case aiMessageSentWithoutContext = "ai_message_sent_without_context"

    // Recovery Dashboard
    case recoveryDashboardViewed = "recovery_dashboard_viewed"

    // Historical Indexation
    case indexationBannerShown = "indexation_banner_shown"
    case indexationBannerSyncTapped = "indexation_banner_sync_tapped"
    case indexationBannerDismissed = "indexation_banner_dismissed"
    case indexationStarted = "indexation_started"
    case indexationBatchProcessed = "indexation_batch_processed"
    case indexationCompleted = "indexation_completed"
    case indexationFailed = "indexation_failed"
    case indexationCancelled = "indexation_cancelled"
    case indexationRetryTapped = "indexation_retry_tapped"

    // Monetization
    case paywallViewed = "paywall_viewed"
    case paywallDismissed = "paywall_dismissed"
    case subscriptionPurchaseStarted = "subscription_purchase_started"
    case subscriptionPurchaseCompleted = "subscription_purchase_completed"
    case subscriptionPurchaseFailed = "subscription_purchase_failed"
    case subscriptionCancelled = "subscription_cancelled"
    case subscriptionRenewed = "subscription_renewed"

    // Workout Generation
    case workoutGenerationRequested = "workout_generation_requested"
    case workoutGenerated = "workout_generated"

    // AI Consent (Apple 5.1.2(i) compliance)
    case aiConsentGranted = "ai_consent_granted"
    case aiConsentRevoked = "ai_consent_revoked"
    case workoutGenerationFailed = "workout_generation_failed"
    case workoutExported = "workout_exported"
    case workoutExportFailed = "workout_export_failed"
}

// MARK: - Supporting Types

enum AIContextType: String {
    case workout
    case recovery
    case general
}
