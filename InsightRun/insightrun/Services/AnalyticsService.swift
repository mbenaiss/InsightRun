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
final class AnalyticsService: WorkoutAnalysisTracking {
    static let shared = AnalyticsService()

    private var sessionID: String
    private var isFirstLaunch: Bool
    private var isConfigured = false
    private var isTrackingEnabled = true
    private var pendingEvents: [(AnalyticsEvent, [String: Any])] = []

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
        guard !isConfigured else { return }

        isTrackingEnabled = !shouldExcludeFromAnalytics
        guard isTrackingEnabled else {
            isConfigured = true
            pendingEvents.removeAll()
            print("ℹ️ PostHog: Disabled for internal, debug, demo, or TestFlight builds")
            return
        }

        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "POSTHOG_API_KEY") as? String,
              let host = Bundle.main.object(forInfoDictionaryKey: "POSTHOG_HOST") as? String else {
            print("❌ AnalyticsService: Missing POSTHOG_API_KEY or POSTHOG_HOST in Info.plist")
            return
        }

        let config = PostHogConfig(projectToken: apiKey, host: host)
        PostHogSDK.shared.setup(config)

        let userID = UserIdentityService.shared.userID
        PostHogSDK.shared.identify(userID, userProperties: [
            "is_internal_user": false,
            "distribution_channel": "app_store"
        ])

        isConfigured = true
        let queuedEvents = pendingEvents
        pendingEvents.removeAll()
        queuedEvents.forEach { capture($0.0, properties: $0.1) }

        print("✅ PostHog: Configured with user ID \(userID)")
    }

    // MARK: - Core Tracking Method

    /// Track an analytics event with optional properties
    /// Non-blocking: runs in background and doesn't crash the app if PostHog fails
    func track(_ event: AnalyticsEvent, properties: [String: Any] = [:]) {
        guard isTrackingEnabled else { return }
        guard isConfigured else {
            pendingEvents.append((event, properties))
            return
        }

        capture(event, properties: properties)
    }

    private func capture(_ event: AnalyticsEvent, properties: [String: Any]) {
        var enrichedProperties = properties
        enrichedProperties["session_id"] = sessionID
        enrichedProperties["app_version"] = appVersion
        enrichedProperties["ios_version"] = UIDevice.current.systemVersion
        enrichedProperties["device_model"] = deviceModel
        enrichedProperties["locale"] = Locale.current.identifier
        enrichedProperties["subscription_status"] = subscriptionStatus
        enrichedProperties["distribution_channel"] = "app_store"
        enrichedProperties["is_internal_user"] = false

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

    private var shouldExcludeFromAnalytics: Bool {
        if DemoMode.isEnabled || UserDefaults.standard.bool(forKey: "com.insightrun.analytics.internalUser") {
            return true
        }

        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
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

    func trackHealthKitPermissionRequested(properties: [String: Any] = [:]) {
        track(.healthKitPermissionRequested, properties: properties)
    }

    func trackHealthKitPermissionGranted(properties: [String: Any] = [:]) {
        track(.healthKitPermissionGranted, properties: properties)
    }

    func trackHealthKitPermissionDenied(properties: [String: Any] = [:]) {
        track(.healthKitPermissionDenied, properties: properties)
    }

    // MARK: - Notification Permission Events

    func trackNotificationPermissionGranted() {
        track(.notificationPermissionGranted)
    }

    func trackNotificationPermissionDenied() {
        track(.notificationPermissionDenied)
    }

    func trackNotificationPermissionSkipped() {
        track(.notificationPermissionSkipped)
    }

    /// A local notification was actually handed to the system (weekly progress, inactivity...).
    func trackNotificationSent(type: String) {
        track(.notificationSent, properties: ["notification_type": type])
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

    /// Intermediate step of a chat request, used to locate where the app dies when a
    /// message is sent but no response is ever recorded.
    func trackAIChatStep(_ step: String, properties: [String: Any] = [:]) {
        var enriched = properties
        enriched["step"] = step
        if let memoryMB = MemoryFootprint.currentMB() {
            enriched["memory_mb"] = memoryMB
        }
        track(.aiChatStep, properties: enriched)
    }

    // MARK: - Stability Events (MetricKit)

    func trackAppCrashDetected(properties: [String: Any]) {
        track(.appCrashDetected, properties: properties)
    }

    func trackAppHangDetected(properties: [String: Any]) {
        track(.appHangDetected, properties: properties)
    }

    func trackAppExitMetrics(properties: [String: Any]) {
        track(.appExitMetrics, properties: properties)
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

    func trackIndexationGateTriggered(source: String) {
        track(.indexationGateTriggered, properties: [
            "source": source
        ])
    }

    func trackWorkoutExportAuthDenied(permanent: Bool) {
        track(.workoutExportAuthDenied, properties: [
            "permanent": permanent
        ])
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

    func trackSubscriptionCancelled(productId: String?) {
        var properties: [String: Any] = [:]
        if let productId {
            properties["product_id"] = productId
        }
        track(.subscriptionCancelled, properties: properties)
    }

    func trackSubscriptionRenewed(productId: String) {
        track(.subscriptionRenewed, properties: ["product_id": productId])
    }

    func trackActivationStarted(source: String) {
        track(.activationStarted, properties: ["source": source])
    }

    func trackActivationWorkoutReady(isSample: Bool) {
        track(.activationWorkoutReady, properties: ["is_sample": isSample])
    }

    func trackWorkoutAnalysisCompleted(isSample: Bool) {
        guard !isSample else { return }
        track(.workoutAnalysisCompleted, properties: [
            "is_sample": false,
            "analysis_source": WorkoutAnalysisSource.generated.rawValue
        ])
    }

    func trackWorkoutAnalysisStarted() {
        track(.workoutAnalysisStarted)
    }

    func trackWorkoutAnalysisViewed(source: WorkoutAnalysisSource) {
        track(.workoutAnalysisViewed, properties: [
            "analysis_source": source.rawValue,
            "is_sample": source == .sample
        ])
    }

    func trackWorkoutAnalysisFailed(reason: WorkoutAnalysisFailureReason) {
        track(.workoutAnalysisFailed, properties: ["reason": reason.rawValue])
    }

    func trackWorkoutAnalysisConsentShown() {
        track(.workoutAnalysisConsentShown)
    }

    func trackWorkoutAnalysisConsentResult(_ result: WorkoutAnalysisConsentResult) {
        track(.workoutAnalysisConsentResult, properties: ["result": result.rawValue])
    }

    func trackAnalysisConfidenceShown(_ confidence: WorkoutAnalysisConfidence, isIndoor: Bool) {
        track(.analysisConfidenceShown, properties: [
            "level": confidence.level.rawValue,
            "coverage_percentage": Int((confidence.coverage * 100).rounded()),
            "available_signals": confidence.availableSignals.map(\.rawValue),
            "missing_signals": confidence.missingSignals.map(\.rawValue),
            "is_indoor": isIndoor
        ])
    }

    // MARK: - Strava Integration Events

    func trackStravaConnectionSuccess(athleteId: Int64) {
        track(.stravaConnectionSuccess, properties: [
            "athlete_id": athleteId
        ])
    }

    func trackStravaConnectionFailed(errorType: String, errorMessage: String) {
        track(.stravaConnectionFailed, properties: [
            "error_type": errorType,
            "error_message": errorMessage
        ])
    }

    func trackStravaConnectionSkipped() {
        track(.stravaConnectionSkipped)
    }

    func trackStravaSyncStarted(initiatedBy: String) {
        track(.stravaSyncStarted, properties: [
            "initiated_by": initiatedBy
        ])
    }

    func trackStravaSyncCompleted(newActivitiesCount: Int, totalActivitiesCount: Int) {
        track(.stravaSyncCompleted, properties: [
            "new_activities": newActivitiesCount,
            "total_activities": totalActivitiesCount
        ])
    }

    func trackStravaSyncFailed(errorType: String, errorMessage: String) {
        track(.stravaSyncFailed, properties: [
            "error_type": errorType,
            "error_message": errorMessage
        ])
    }

    func trackStravaDisconnected() {
        track(.stravaDisconnected)
    }

    func trackStravaInitialSyncTriggered() {
        track(.stravaInitialSyncTriggered)
    }

    // MARK: - Smart Suggestion Events

    func trackSmartSuggestionRequested() {
        track(.smartSuggestionRequested)
    }

    func trackSmartSuggestionGenerated(suggestionLength: Int, generationTimeMs: Int) {
        track(.smartSuggestionGenerated, properties: [
            "suggestion_length": suggestionLength,
            "generation_time_ms": generationTimeMs
        ])
    }

    func trackSmartSuggestionFailed(errorType: String, errorMessage: String) {
        track(.smartSuggestionFailed, properties: [
            "error_type": errorType,
            "error_message": errorMessage
        ])
    }

    func trackSmartSuggestionApplied() {
        track(.smartSuggestionApplied)
    }

    // MARK: - Workout Editing Events

    func trackWorkoutEditingStarted(workoutName: String) {
        track(.workoutEditingStarted, properties: [
            "workout_name": workoutName
        ])
    }

    func trackWorkoutEditingCancelled() {
        track(.workoutEditingCancelled)
    }

    func trackWorkoutEditingSaved(workoutName: String, stepsCount: Int) {
        track(.workoutEditingSaved, properties: [
            "workout_name": workoutName,
            "steps_count": stepsCount
        ])
    }

    func trackWorkoutStepEdited(stepIndex: Int, fieldChanged: String) {
        track(.workoutStepEdited, properties: [
            "step_index": stepIndex,
            "field_changed": fieldChanged
        ])
    }

    // MARK: - Statistics Events

    func trackStatisticsViewed() {
        track(.statisticsViewed)
    }

    func trackStatisticsPeriodChanged(period: String) {
        track(.statisticsPeriodChanged, properties: [
            "period": period
        ])
    }

    func trackStatisticsYearChanged(year: Int) {
        track(.statisticsYearChanged, properties: [
            "year": year
        ])
    }

    // MARK: - Settings Events

    func trackSettingsAppearanceChanged(oldTheme: String, newTheme: String) {
        track(.settingsAppearanceChanged, properties: [
            "old_theme": oldTheme,
            "new_theme": newTheme
        ])
    }

    func trackSettingsMedicalSourcesViewed() {
        track(.settingsMedicalSourcesViewed)
    }

    func trackSettingsRefreshDataClicked() {
        track(.settingsRefreshDataClicked)
    }

    // MARK: - Review Events

    func trackReviewPromptShown() {
        track(.reviewPromptShown)
    }

    func trackReviewManualTap() {
        track(.reviewManualTap)
    }

    // MARK: - Medical Sources Events

    func trackMedicalSourcesViewed() {
        track(.medicalSourcesViewed)
    }

    // MARK: - Daily Readiness Events

    /// Fires once per backend-computed readiness (cache hits are skipped) so we
    /// can monitor how the no-sleep adaptive mode is rolled out in production.
    func trackDailyReadinessComputed(noSleepMode: Bool, freshnessAvailable: Bool) {
        track(.dailyReadinessComputed, properties: [
            "no_sleep_mode": noSleepMode,
            "freshness_available": freshnessAvailable
        ])
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
    case healthKitPermissionRequested = "healthkit_permission_requested"
    case healthKitPermissionGranted = "healthkit_permission_granted"
    case healthKitPermissionDenied = "healthkit_permission_denied"
    case healthKitPermissionSkipped = "healthkit_permission_skipped"

    // Notification Permission
    case notificationPermissionGranted = "notification_permission_granted"
    case notificationPermissionDenied = "notification_permission_denied"
    case notificationPermissionSkipped = "notification_permission_skipped"
    case notificationSent = "notification_sent"

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
    case aiChatStep = "ai_chat_step"

    // Stability (MetricKit)
    case appCrashDetected = "app_crash_detected"
    case appHangDetected = "app_hang_detected"
    case appExitMetrics = "app_exit_metrics"

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
    case indexationGateTriggered = "indexation_gate_triggered"

    // Workout Export
    case workoutExportAuthDenied = "workout_export_auth_denied"

    // Monetization
    case paywallViewed = "paywall_viewed"
    case paywallDismissed = "paywall_dismissed"
    case subscriptionPurchaseStarted = "subscription_purchase_started"
    case subscriptionPurchaseCompleted = "subscription_purchase_completed"
    case subscriptionPurchaseFailed = "subscription_purchase_failed"
    case subscriptionPurchaseCancelled = "subscription_purchase_cancelled"
    case subscriptionRestoreFailed = "subscription_restore_failed"
    case subscriptionRestored = "subscription_restored"
    case subscriptionCancelled = "subscription_cancelled"
    case subscriptionRenewed = "subscription_renewed"

    // Activation
    case activationStarted = "activation_started"
    case activationWorkoutReady = "activation_workout_ready"
    case workoutAnalysisCompleted = "workout_analysis_completed"
    case workoutAnalysisStarted = "workout_analysis_started"
    case workoutAnalysisViewed = "workout_analysis_viewed"
    case workoutAnalysisFailed = "workout_analysis_failed"
    case workoutAnalysisConsentShown = "workout_analysis_consent_shown"
    case workoutAnalysisConsentResult = "workout_analysis_consent_result"
    case analysisConfidenceShown = "analysis_confidence_shown"

    // Workout Generation
    case workoutGenerationRequested = "workout_generation_requested"
    case workoutGenerated = "workout_generated"
    case workoutGenerationFailed = "workout_generation_failed"
    case workoutExported = "workout_exported"
    case workoutExportFailed = "workout_export_failed"

    // AI Consent (Apple 5.1.2(i) compliance)
    case aiConsentGranted = "ai_consent_granted"
    case aiConsentRevoked = "ai_consent_revoked"

    // Strava Integration
    case stravaConnectionSuccess = "strava_connection_success"
    case stravaConnectionFailed = "strava_connection_failed"
    case stravaConnectionSkipped = "strava_connection_skipped"
    case stravaSyncStarted = "strava_sync_started"
    case stravaSyncCompleted = "strava_sync_completed"
    case stravaSyncFailed = "strava_sync_failed"
    case stravaDisconnected = "strava_disconnected"
    case stravaInitialSyncTriggered = "strava_initial_sync_triggered"

    // Smart Suggestion
    case smartSuggestionRequested = "smart_suggestion_requested"
    case smartSuggestionGenerated = "smart_suggestion_generated"
    case smartSuggestionFailed = "smart_suggestion_failed"
    case smartSuggestionApplied = "smart_suggestion_applied"

    // Workout Editing
    case workoutEditingStarted = "workout_editing_started"
    case workoutEditingCancelled = "workout_editing_cancelled"
    case workoutEditingSaved = "workout_editing_saved"
    case workoutStepEdited = "workout_step_edited"

    // Statistics
    case statisticsViewed = "statistics_viewed"
    case statisticsPeriodChanged = "statistics_period_changed"
    case statisticsYearChanged = "statistics_year_changed"

    // Settings
    case settingsAppearanceChanged = "settings_appearance_changed"
    case settingsMedicalSourcesViewed = "settings_medical_sources_viewed"
    case settingsRefreshDataClicked = "settings_refresh_data_clicked"

    // Review
    case reviewPromptShown = "review_prompt_shown"
    case reviewManualTap = "review_manual_tap"

    // AI Teaser
    case aiTeaserShown = "ai_teaser_shown"
    case aiTeaserSubscribeTapped = "ai_teaser_subscribe_tapped"

    // Medical Sources
    case medicalSourcesViewed = "medical_sources_viewed"

    // Daily Readiness
    case dailyReadinessComputed = "daily_readiness_computed"
}

// MARK: - Supporting Types

@MainActor
protocol WorkoutAnalysisTracking: AnyObject {
    func trackWorkoutAnalysisStarted()
    func trackWorkoutAnalysisViewed(source: WorkoutAnalysisSource)
    func trackWorkoutAnalysisFailed(reason: WorkoutAnalysisFailureReason)
    func trackWorkoutAnalysisCompleted(isSample: Bool)
}

enum WorkoutAnalysisSource: String {
    case sample
    case cache
    case generated
}

enum WorkoutAnalysisFailureReason: String {
    case serviceError = "service_error"
    case emptyResponse = "empty_response"
    case incompleteResponse = "incomplete_response"
    case cacheReadFailed = "cache_read_failed"
    case cacheSaveFailed = "cache_save_failed"
}

enum WorkoutAnalysisConsentResult: String {
    case accepted
    case declined
    case dismissed
}

enum AIContextType: String {
    case workout
    case recovery
    case general
}
