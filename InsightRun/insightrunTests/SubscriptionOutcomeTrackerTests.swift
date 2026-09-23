import Foundation
import XCTest

@testable import insightrun

@MainActor
final class SubscriptionOutcomeTrackerTests: XCTestCase {
  private var events: [(AnalyticsEvent, [String: Any])] = []
  private var clock = ContinuousClock.now
  private var environment = PurchaseEnvironment(
    appState: "active", sceneActivationState: "foreground_active", canMakePayments: true,
    storefront: "FRA", storeEnvironment: "production", sdkBuild: "24A335", rcVersion: "5.90.2"
  )
  private var storeLogLines: [String] = []

  private var tracker: SubscriptionOutcomeTracker {
    SubscriptionOutcomeTracker(
      capture: { [unowned self] event, properties in events.append((event, properties)) },
      environment: { [unowned self] in environment },
      now: { [unowned self] in clock },
      storeLogLines: { [unowned self] in storeLogLines }
    )
  }

  private func startAttempt(
    productId: String, price: String = "4.99", currency: String? = "EUR",
    priceDisplay: String = "4,99 €", source: String
  ) -> PurchaseAttempt {
    tracker.purchaseStarted(
      productId: productId, price: Decimal(string: price)!, currency: currency,
      priceDisplay: priceDisplay, billingPeriod: "monthly", source: source,
      paywallAppearedAt: nil, consentShownInPaywall: false
    )
  }

  func testPurchaseCancellationIsNeitherChurnNorFailure() async throws {
    let attempt = startAttempt(productId: "monthly", source: "onboarding")
    tracker.purchaseCancelled(attempt, source: "onboarding")

    let event = try XCTUnwrap(events.last)
    XCTAssertEqual(events.count, 2)
    XCTAssertEqual(event.0.rawValue, "subscription_purchase_cancelled")
    XCTAssertEqual(event.1["product_id"] as? String, "monthly")
    XCTAssertEqual(event.1["source"] as? String, "onboarding")
    XCTAssertNil(event.1["error_code"])
  }

  func testPurchaseFailureIncludesContextWithoutExportingErrorUserInfo() async throws {
    let error = NSError(
      domain: "RevenueCat.ErrorCode", code: 10,
      userInfo: [NSLocalizedDescriptionKey: "Network unavailable", "receipt": "private receipt"]
    )
    let attempt = startAttempt(productId: "annual", source: "locked_content")
    tracker.purchaseFailed(attempt, error: error, source: "locked_content")

    let event = try XCTUnwrap(events.last)
    XCTAssertEqual(event.0.rawValue, "subscription_purchase_failed")
    XCTAssertEqual(event.1["error_code"] as? String, "10")
    XCTAssertEqual(event.1["error_domain"] as? String, error.domain)
    XCTAssertEqual(event.1["error_message"] as? String, "Network unavailable")
    XCTAssertEqual(event.1["product_id"] as? String, "annual")
    XCTAssertEqual(event.1["source"] as? String, "locked_content")
    XCTAssertNil(event.1["receipt"])
    XCTAssertNil(event.1["userInfo"])
  }

  func testUnknownProductDoesNotPreventFailureReporting() async throws {
    tracker.purchaseFailed(
      nil, error: URLError(.notConnectedToInternet) as NSError, source: "onboarding")

    let event = try XCTUnwrap(events.first)
    XCTAssertEqual(event.0.rawValue, "subscription_purchase_failed")
    XCTAssertNil(event.1["product_id"])
    XCTAssertNil(event.1["attempt_id"])
    XCTAssertEqual(event.1["error_code"] as? String, "-1009")
    XCTAssertEqual(event.1["app_state"] as? String, "active")
  }

  func testRestoreFailuresAreSeparateFromPurchaseFailures() async throws {
    for source in ["settings", "onboarding", "locked_content"] {
      tracker.restoreFailed(error: URLError(.timedOut) as NSError, source: source)
    }

    XCTAssertEqual(events.count, 3)
    XCTAssertTrue(events.allSatisfy { $0.0.rawValue == "subscription_restore_failed" })
    XCTAssertEqual(
      events.compactMap { $0.1["source"] as? String }, ["settings", "onboarding", "locked_content"])
    XCTAssertTrue(events.allSatisfy { $0.1["product_id"] == nil })
  }

  func testRestoreDistinguishesEmptyAccountFromActiveSubscription() async throws {
    tracker.restored(productId: nil, source: "settings")
    tracker.restored(productId: "annual", source: "settings")

    XCTAssertEqual(events.count, 2)
    XCTAssertTrue(events.allSatisfy { $0.0.rawValue == "subscription_restored" })
    XCTAssertEqual(events[0].1["has_active_subscription"] as? Bool, false)
    XCTAssertNil(events[0].1["product_id"])
    XCTAssertEqual(events[1].1["has_active_subscription"] as? Bool, true)
    XCTAssertEqual(events[1].1["product_id"] as? String, "annual")
  }

  func testCompletedPurchaseWithoutEntitlementStillClosesTheFunnel() async throws {
    let attempt = startAttempt(productId: "monthly", source: "locked_content")
    tracker.purchaseCompleted(
      attempt, productId: nil, isTrial: false,
      hasActiveSubscription: false, source: "locked_content"
    )

    let event = try XCTUnwrap(events.last)
    XCTAssertEqual(events.count, 2)
    XCTAssertEqual(event.0.rawValue, "subscription_purchase_completed")
    XCTAssertEqual(event.1["has_active_subscription"] as? Bool, false)
    XCTAssertEqual(event.1["product_id"] as? String, "monthly")
  }

  func testActiveTrialPreservesPurchaseProperties() async throws {
    let attempt = startAttempt(
      productId: "annual", price: "29.99", currency: "EUR", priceDisplay: "29,99 €", source: "onboarding")
    tracker.purchaseCompleted(
      attempt, productId: "annual", isTrial: true,
      hasActiveSubscription: true, source: "onboarding"
    )

    let event = try XCTUnwrap(events.last)
    XCTAssertEqual(event.1["has_active_subscription"] as? Bool, true)
    XCTAssertEqual(event.1["is_trial"] as? Bool, true)
    XCTAssertEqual(event.1["revenue"] as? Double, 29.99)
    XCTAssertEqual(event.1["currency"] as? String, "EUR")
    XCTAssertEqual(event.1["price_display"] as? String, "29,99 €")
    XCTAssertEqual(event.1["source"] as? String, "onboarding")
    XCTAssertNil(event.1["rc_log_tail"])
  }

  func testRevenueKeepsTheStorePriceExactly() async throws {
    let attempt = startAttempt(productId: "monthly", price: "0.07", currency: "USD", priceDisplay: "$0.07", source: "locked_content")
    tracker.purchaseCompleted(attempt, productId: nil, isTrial: false, hasActiveSubscription: true, source: "locked_content")

    let event = try XCTUnwrap(events.last)
    XCTAssertEqual(event.1["revenue"] as? Double, 0.07)
    XCTAssertEqual(event.1["currency"] as? String, "USD")
  }

  func testPurchaseAttemptLinksStartAndCancellationDiagnostics() async throws {
    let paywallAppearedAt = clock
    clock = clock.advanced(by: .milliseconds(1_250))
    let attempt = tracker.purchaseStarted(
      productId: "annual", price: Decimal(string: "59.99")!, currency: "EUR",
      priceDisplay: "59,99 €", billingPeriod: "annual", source: "locked_content",
      paywallAppearedAt: paywallAppearedAt, consentShownInPaywall: true
    )
    clock = clock.advanced(by: .milliseconds(87))
    environment.appState = "inactive"
    environment.sceneActivationState = "foreground_inactive"
    storeLogLines = ["INFO: 💰 Purchasing Product 'annual'", "ERROR: 🍎‼️ Purchase was cancelled."]
    tracker.purchaseCancelled(attempt, source: "locked_content")

    XCTAssertEqual(events.map { $0.0.rawValue }, ["subscription_purchase_started", "subscription_purchase_cancelled"])
    let started = events[0].1
    let cancelled = events[1].1
    for properties in [started, cancelled] {
      XCTAssertEqual(properties["attempt_id"] as? String, attempt.id.uuidString)
      XCTAssertEqual(properties["product_id"] as? String, "annual")
      XCTAssertEqual(properties["ms_since_paywall_appear"] as? Int, 1_250)
      XCTAssertEqual(properties["consent_shown_in_paywall"] as? Bool, true)
      XCTAssertEqual(properties["can_make_payments"] as? Bool, true)
      XCTAssertEqual(properties["storefront"] as? String, "FRA")
      XCTAssertEqual(properties["store_environment"] as? String, "production")
      XCTAssertEqual(properties["sdk_build"] as? String, "24A335")
      XCTAssertEqual(properties["rc_version"] as? String, "5.90.2")
    }
    XCTAssertEqual(started["elapsed_ms"] as? Int, 0)
    XCTAssertEqual(started["price"] as? String, "59,99 €")
    XCTAssertEqual(started["billing_period"] as? String, "annual")
    XCTAssertEqual(started["app_state"] as? String, "active")
    XCTAssertEqual(started["scene_activation_state"] as? String, "foreground_active")
    XCTAssertNil(started["rc_log_tail"])
    XCTAssertEqual(cancelled["elapsed_ms"] as? Int, 87)
    XCTAssertEqual(cancelled["app_state_at_start"] as? String, "active")
    XCTAssertEqual(cancelled["scene_activation_state_at_start"] as? String, "foreground_active")
    XCTAssertEqual(cancelled["app_state"] as? String, "inactive")
    XCTAssertEqual(cancelled["scene_activation_state"] as? String, "foreground_inactive")
    XCTAssertEqual(
      cancelled["rc_log_tail"] as? String,
      "INFO: 💰 Purchasing Product 'annual'\nERROR: 🍎‼️ Purchase was cancelled.")
  }

  func testStoreLogTailRedactsIdentifiersAndStaysBounded() throws {
    let lines = [
      "DEBUG: " + String(repeating: "x", count: 400),
      "INFO: Logged in 3F2504E0-4F89-11D3-9A0C-0305E82C3301 as custom-user",
      "DEBUG: GET /v1/subscribers/$RCAnonymousID%3Aa1b2c3d4e5f60718293a4b5c6d7e8f90/offerings",
      "ERROR: Receipt for runner@example.com, transaction 2000000912345678",
      "ERROR: 🍎‼️ Purchase was cancelled.",
    ]

    let tail = try XCTUnwrap(
      SubscriptionOutcomeTracker.redactedLogTail(lines, knownIdentifiers: ["custom-user"]))

    XCTAssertLessThanOrEqual(tail.count, 500)
    XCTAssertEqual(tail.split(separator: "\n").count, 5)
    for secret in ["3F2504E0", "custom-user", "a1b2c3d4e5f6", "runner@example.com", "2000000912345678"] {
      XCTAssertFalse(tail.contains(secret), secret)
    }
    XCTAssertTrue(tail.contains("INFO: Logged in <id> as <user_id>"))
    XCTAssertTrue(tail.contains("DEBUG: GET /v1/subscribers/<user_id>/offerings"))
    XCTAssertTrue(tail.contains("ERROR: Receipt for <email>, transaction <id>"))
    XCTAssertTrue(tail.hasSuffix("ERROR: 🍎‼️ Purchase was cancelled."))
    XCTAssertNil(SubscriptionOutcomeTracker.redactedLogTail([]))
  }

  func testLogTailKeepsOnlyTheLastFiveLines() {
    let logTail = RevenueCatLogTail()
    for index in 1...7 {
      logTail.record(.info, "line \(index)")
    }

    XCTAssertEqual(logTail.recentLines(), (3...7).map { "INFO: line \($0)" })
  }

  func testOversizedErrorMessagesAreBounded() async throws {
    let error = NSError(
      domain: "test", code: 42,
      userInfo: [NSLocalizedDescriptionKey: String(repeating: "x", count: 4_000)])
    tracker.restoreFailed(error: error, source: "settings")

    let event = try XCTUnwrap(events.first)
    XCTAssertEqual((event.1["error_message"] as? String)?.count, 500)
  }
}
