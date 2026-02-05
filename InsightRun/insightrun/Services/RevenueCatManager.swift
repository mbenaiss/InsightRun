//
//  RevenueCatManager.swift
//  InsightRun
//
//  RevenueCat configuration and subscription management
//

import Foundation
import Combine
import RevenueCat
import StoreKit

/// Manages RevenueCat SDK configuration and subscription state
@MainActor
class RevenueCatManager: NSObject, ObservableObject {
    static let shared = RevenueCatManager()

    @Published var isSubscriptionActive: Bool = false
    @Published var customerInfo: CustomerInfo?
    @Published var isConfigured: Bool = false

    // Track if user has seen the initial paywall after HealthKit authorization
    @Published var hasSeenInitialPaywall: Bool = false

    // Free AI requests tracking (allows 3 free requests before requiring subscription)
    @Published private(set) var freeAIRequestsUsed: Int = 0
    private let maxFreeRequests = 3
    private let freeRequestsKey = "com.insightrun.freeAIRequestsUsed"

    // Cache TestFlight environment status
    private var cachedTestFlightStatus: Bool?

    // Debug override for TestFlight environment (only used in DEBUG builds)
    #if DEBUG
    @Published var debugTestFlightOverride: Bool?
    #endif

    override private init() {
        super.init()
        // Load persisted values
        self.hasSeenInitialPaywall = UserDefaults.standard.bool(forKey: "hasSeenInitialPaywall")
        self.freeAIRequestsUsed = UserDefaults.standard.integer(forKey: freeRequestsKey)

        // Detect TestFlight environment on initialization
        Task {
            await detectTestFlightEnvironment()
        }
    }

    // MARK: - TestFlight Detection

    /// Detects if the app is running in TestFlight environment asynchronously
    /// Uses StoreKit 2 AppTransaction to determine environment
    private func detectTestFlightEnvironment() async {
        do {
            // Get app transaction using StoreKit 2 (iOS 15+)
            // AppTransaction.shared returns a VerificationResult that needs to be unwrapped
            let verificationResult = try await AppTransaction.shared

            // Extract the verified transaction
            let transaction: AppTransaction
            switch verificationResult {
            case .verified(let appTransaction):
                transaction = appTransaction
            case .unverified(let appTransaction, _):
                // Even if unverified, we can still check the environment
                transaction = appTransaction
            }

            // TestFlight builds run in sandbox environment
            // Production App Store builds run in production environment
            let isTestFlight = transaction.environment == .sandbox || transaction.environment == .xcode

            await MainActor.run {
                self.cachedTestFlightStatus = isTestFlight
            }
        } catch {
            // If no transaction available (e.g., fresh install), assume not TestFlight
            await MainActor.run {
                self.cachedTestFlightStatus = false
            }
        }
    }

    /// Synchronous access to TestFlight environment status
    /// Returns cached value, or false if not yet determined
    /// In DEBUG mode, can be overridden using debugTestFlightOverride
    var isTestFlightEnvironment: Bool {
        #if DEBUG
        // Allow debug override to take precedence
        if let override = debugTestFlightOverride {
            return override
        }
        #endif
        return cachedTestFlightStatus ?? false
    }

    /// Determines if the user has access to AI features
    /// Returns true if user is subscribed, running in TestFlight, OR has free requests remaining
    var hasAIAccess: Bool {
        return isSubscriptionActive || isTestFlightEnvironment || hasFreeRequestsRemaining
    }

    /// Check if user has free AI requests remaining
    var hasFreeRequestsRemaining: Bool {
        return freeAIRequestsUsed < maxFreeRequests
    }

    /// Number of free requests remaining
    var freeRequestsRemaining: Int {
        return max(0, maxFreeRequests - freeAIRequestsUsed)
    }

    /// Increment free AI request counter (call this after each AI request for non-subscribers)
    func incrementFreeRequestCount() {
        guard !isSubscriptionActive && !isTestFlightEnvironment else { return }
        freeAIRequestsUsed += 1
        UserDefaults.standard.set(freeAIRequestsUsed, forKey: freeRequestsKey)
    }

    /// Reset free request counter (useful for testing or promotions)
    func resetFreeRequestCount() {
        freeAIRequestsUsed = 0
        UserDefaults.standard.set(0, forKey: freeRequestsKey)
    }

    /// Update hasSeenInitialPaywall and persist to UserDefaults
    func markPaywallAsSeen() {
        hasSeenInitialPaywall = true
        UserDefaults.standard.set(true, forKey: "hasSeenInitialPaywall")
    }

    /// Configure RevenueCat SDK with API key and link user identity
    /// Call this method once at app launch (synchronous configuration)
    func configure() {
        // TODO: Replace with your actual RevenueCat API key from dashboard
        // Get it from: https://app.revenuecat.com/settings/api-keys
        Purchases.logLevel = .debug // Remove in production
        Purchases.configure(withAPIKey: "appl_LfJkFupqchBoMuDUTNsdmmGsEzQ")

        // Set up delegate to listen for customer info updates
        Purchases.shared.delegate = self

        // Mark as configured immediately (SDK is ready)
        isConfigured = true

        // Link user identity from UserIdentityService to RevenueCat
        // This ensures purchases are tied to the same UUID across devices
        // These calls are async but don't block the SDK from working
        Task {
            await linkUserIdentity()
            await fetchCustomerInfo()
        }
    }

    /// Link the user's UUID from UserIdentityService to RevenueCat
    /// This enables cross-device purchase synchronization and restore
    private func linkUserIdentity() async {
        let userID = UserIdentityService.shared.userID

        do {
            let (customerInfo, created) = try await Purchases.shared.logIn(userID)
            print("✅ RevenueCat: Linked user identity \(userID) (created: \(created))")

            await MainActor.run {
                self.customerInfo = customerInfo
                self.isSubscriptionActive = !customerInfo.entitlements.active.isEmpty
            }
        } catch {
            print("❌ RevenueCat: Failed to link user identity: \(error.localizedDescription)")
            // Continue without user identity link - not critical for first launch
        }
    }

    /// Fetch current customer subscription info
    func fetchCustomerInfo() async {
        do {
            let info = try await Purchases.shared.customerInfo()
            await MainActor.run {
                self.customerInfo = info
                self.isSubscriptionActive = !info.entitlements.active.isEmpty
            }
        } catch {
            print("Error fetching customer info: \(error.localizedDescription)")
        }
    }

    /// Restore previous purchases and sync user identity
    /// If purchases are found with a different UUID, update local identity
    func restorePurchases() async throws {
        let info = try await Purchases.shared.restorePurchases()

        // Check if the restored account has a different app user ID
        let currentUserID = UserIdentityService.shared.userID
        let restoredUserID = info.originalAppUserId

        // If restored user ID is different and has active subscriptions,
        // update local identity to match the restored account
        if restoredUserID != currentUserID && !info.entitlements.active.isEmpty {
            print("🔄 RevenueCat: Restoring identity from \(currentUserID) to \(restoredUserID)")
            UserIdentityService.shared.updateUserID(restoredUserID)

            // Re-login with the restored user ID to sync
            let (updatedInfo, _) = try await Purchases.shared.logIn(restoredUserID)

            await MainActor.run {
                self.customerInfo = updatedInfo
                self.isSubscriptionActive = !updatedInfo.entitlements.active.isEmpty
            }
        } else {
            await MainActor.run {
                self.customerInfo = info
                self.isSubscriptionActive = !info.entitlements.active.isEmpty
            }
        }
    }
}

// MARK: - PurchasesDelegate
extension RevenueCatManager: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            let wasActive = self.isSubscriptionActive
            let isNowActive = !customerInfo.entitlements.active.isEmpty

            self.customerInfo = customerInfo
            self.isSubscriptionActive = isNowActive

            // Track subscription state changes
            if wasActive && !isNowActive {
                // Subscription was cancelled
                AnalyticsService.shared.trackSubscriptionCancelled()
            } else if !wasActive && isNowActive {
                // Subscription was renewed/activated
                AnalyticsService.shared.trackSubscriptionRenewed()
            }
        }
    }
}
