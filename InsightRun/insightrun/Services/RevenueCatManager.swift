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

    /// True once both the TestFlight environment check and the first RevenueCat
    /// customer-info fetch have completed. Until then, paywall/free-request decisions
    /// should wait: showing the paywall to a TestFlight tester or a subscriber while
    /// `isSubscriptionActive`/`isTestFlightEnvironment` are still their default `false`
    /// would burn free requests and flash the wrong UI.
    @Published private(set) var isSubscriptionStatusResolved: Bool = false
    private var testFlightResolved = false
    private var customerInfoResolved = false

    // Track if user has seen the initial paywall after HealthKit authorization
    @Published var hasSeenInitialPaywall: Bool = false

    // Free AI requests tracking (allows 3 free requests before requiring subscription)
    @Published private(set) var freeAIRequestsUsed: Int = 0
    private let maxFreeRequests = 3
    private let freeRequestsKey = "com.insightrun.freeAIRequestsUsed"

    // Cache TestFlight environment status
    private var cachedTestFlightStatus: Bool?
    private var entitlementSnapshot: EntitlementSnapshot?
    private let entitlementSnapshotKey = "com.insightrun.revenuecat.entitlementSnapshot"

    private struct EntitlementSnapshot: Codable {
        let productIdentifier: String
        let latestPurchaseDate: Date?
        let willRenew: Bool
        let unsubscribeDetectedAt: Date?
    }

    // Debug override for TestFlight environment (only used in DEBUG builds)
    #if DEBUG
    @Published var debugTestFlightOverride: Bool?
    #endif

    override private init() {
        super.init()
        // Load persisted values
        self.hasSeenInitialPaywall = UserDefaults.standard.bool(forKey: "hasSeenInitialPaywall")
        self.freeAIRequestsUsed = UserDefaults.standard.integer(forKey: freeRequestsKey)
        if let data = UserDefaults.standard.data(forKey: entitlementSnapshotKey) {
            self.entitlementSnapshot = try? JSONDecoder().decode(EntitlementSnapshot.self, from: data)
        }

        // Detect TestFlight environment on initialization
        Task {
            await detectTestFlightEnvironment()
        }
    }

    // MARK: - TestFlight Detection

    /// Detects if the app is running in TestFlight environment asynchronously
    /// Uses StoreKit 2 AppTransaction to determine environment
    private func detectTestFlightEnvironment() async {
        if DemoMode.isEnabled {
            cachedTestFlightStatus = false
            markTestFlightResolved()
            return
        }

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
                self.markTestFlightResolved()
            }
        } catch {
            // If no transaction available (e.g., fresh install), assume not TestFlight
            await MainActor.run {
                self.cachedTestFlightStatus = false
                self.markTestFlightResolved()
            }
        }
    }

    private func markTestFlightResolved() {
        testFlightResolved = true
        updateSubscriptionStatusResolved()
    }

    private func markCustomerInfoResolved() {
        customerInfoResolved = true
        updateSubscriptionStatusResolved()
    }

    private func updateSubscriptionStatusResolved() {
        if testFlightResolved && customerInfoResolved && !isSubscriptionStatusResolved {
            isSubscriptionStatusResolved = true
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
        if DemoMode.isEnabled { return true }
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

    #if DEBUG
    /// Exhaust all free requests (for testing non-subscriber state)
    func debugExhaustFreeRequests() {
        freeAIRequestsUsed = maxFreeRequests
        UserDefaults.standard.set(freeAIRequestsUsed, forKey: freeRequestsKey)
    }
    #endif

    /// Update hasSeenInitialPaywall and persist to UserDefaults
    func markPaywallAsSeen() {
        hasSeenInitialPaywall = true
        UserDefaults.standard.set(true, forKey: "hasSeenInitialPaywall")
    }

    /// Configure RevenueCat SDK with API key and link user identity
    /// Call this method once at app launch (synchronous configuration)
    func configure() {
        if DemoMode.isEnabled {
            isConfigured = true
            isSubscriptionActive = true
            markCustomerInfoResolved()
            return
        }

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
            applyCustomerInfo(customerInfo, trackLifecycleChanges: true)
        } catch {
            print("❌ RevenueCat: Failed to link user identity: \(error.localizedDescription)")
            // Continue without user identity link - not critical for first launch
        }
    }

    /// Fetch current customer subscription info
    func fetchCustomerInfo() async {
        do {
            let info = try await Purchases.shared.customerInfo()
            applyCustomerInfo(info, trackLifecycleChanges: true)
            markCustomerInfoResolved()
        } catch {
            print("Error fetching customer info: \(error.localizedDescription)")
            markCustomerInfoResolved()
        }
    }

    /// Restore previous purchases and sync user identity
    /// If purchases are found with a different UUID, update local identity
    func restorePurchases(source: String) async throws {
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

            applyCustomerInfo(updatedInfo, trackLifecycleChanges: false)
        } else {
            applyCustomerInfo(info, trackLifecycleChanges: false)
        }

        AnalyticsService.shared.trackSubscriptionRestored(
            productId: customerInfo?.entitlements.active.values.first?.productIdentifier,
            source: source
        )
    }

    func applyCustomerInfo(_ info: CustomerInfo, trackLifecycleChanges: Bool) {
        let previous = entitlementSnapshot
        let current = info.entitlements.active.values.first.map {
            EntitlementSnapshot(
                productIdentifier: $0.productIdentifier,
                latestPurchaseDate: $0.latestPurchaseDate,
                willRenew: $0.willRenew,
                unsubscribeDetectedAt: $0.unsubscribeDetectedAt
            )
        }

        customerInfo = info
        isSubscriptionActive = current != nil
        entitlementSnapshot = current
        persistEntitlementSnapshot(current)

        guard trackLifecycleChanges, let previous, let current else { return }

        if previous.willRenew && !current.willRenew && current.unsubscribeDetectedAt != nil {
            AnalyticsService.shared.trackSubscriptionCancelled(productId: current.productIdentifier)
        }

        if previous.productIdentifier == current.productIdentifier,
           let previousPurchase = previous.latestPurchaseDate,
           let currentPurchase = current.latestPurchaseDate,
           currentPurchase > previousPurchase {
            AnalyticsService.shared.trackSubscriptionRenewed(productId: current.productIdentifier)
        }
    }

    private func persistEntitlementSnapshot(_ snapshot: EntitlementSnapshot?) {
        guard let snapshot, let data = try? JSONEncoder().encode(snapshot) else {
            UserDefaults.standard.removeObject(forKey: entitlementSnapshotKey)
            return
        }
        UserDefaults.standard.set(data, forKey: entitlementSnapshotKey)
    }
}

// MARK: - PurchasesDelegate
extension RevenueCatManager: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            self.applyCustomerInfo(customerInfo, trackLifecycleChanges: true)
        }
    }
}
