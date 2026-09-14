import Foundation
import XCTest

@testable import insightrun

@MainActor
final class SubscriptionOutcomeTrackerTests: XCTestCase {
  private var events: [(AnalyticsEvent, [String: Any])] = []

  private var tracker: SubscriptionOutcomeTracker {
    SubscriptionOutcomeTracker { [unowned self] event, properties in
      events.append((event, properties))
    }
  }

  func testPurchaseCancellationIsNeitherChurnNorFailure() async throws {
    tracker.purchaseCancelled(productId: "monthly", source: "onboarding")

    let event = try XCTUnwrap(events.first)
    XCTAssertEqual(events.count, 1)
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
    tracker.purchaseFailed(error: error, productId: "annual", source: "locked_content")

    let event = try XCTUnwrap(events.first)
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
      error: URLError(.notConnectedToInternet) as NSError, productId: nil, source: "onboarding")

    let event = try XCTUnwrap(events.first)
    XCTAssertEqual(event.0.rawValue, "subscription_purchase_failed")
    XCTAssertNil(event.1["product_id"])
    XCTAssertEqual(event.1["error_code"] as? String, "-1009")
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
    tracker.purchaseCompleted(
      productId: "monthly", revenue: "4.99", isTrial: false,
      hasActiveSubscription: false, source: "locked_content"
    )

    let event = try XCTUnwrap(events.first)
    XCTAssertEqual(events.count, 1)
    XCTAssertEqual(event.0.rawValue, "subscription_purchase_completed")
    XCTAssertEqual(event.1["has_active_subscription"] as? Bool, false)
    XCTAssertEqual(event.1["product_id"] as? String, "monthly")
  }

  func testActiveTrialPreservesPurchaseProperties() async throws {
    tracker.purchaseCompleted(
      productId: "annual", revenue: "29.99", isTrial: true,
      hasActiveSubscription: true, source: "onboarding"
    )

    let event = try XCTUnwrap(events.first)
    XCTAssertEqual(event.1["has_active_subscription"] as? Bool, true)
    XCTAssertEqual(event.1["is_trial"] as? Bool, true)
    XCTAssertEqual(event.1["revenue"] as? String, "29.99")
    XCTAssertEqual(event.1["source"] as? String, "onboarding")
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
