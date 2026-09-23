import Foundation
import RevenueCat
import StoreKit
import UIKit

struct PurchaseAttempt {
  let id: UUID
  let productId: String
  let price: Decimal
  let currency: String?
  let priceDisplay: String
  let startedAt: ContinuousClock.Instant
  let msSincePaywallAppear: Int?
  let consentShownInPaywall: Bool
  let appStateAtStart: String
  let sceneActivationStateAtStart: String
}

nonisolated struct PurchaseEnvironment: Sendable {
  var appState: String
  var sceneActivationState: String
  var canMakePayments: Bool
  var storefront: String?
  var storeEnvironment: String?
  var sdkBuild: String?
  var rcVersion: String

  @MainActor
  static func current() -> PurchaseEnvironment {
    let scenes = UIApplication.shared.connectedScenes
    let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    return PurchaseEnvironment(
      appState: UIApplication.shared.applicationState.analyticsValue,
      sceneActivationState: scene?.activationState.analyticsValue ?? "none",
      canMakePayments: AppStore.canMakePayments,
      storefront: Purchases.isConfigured ? Purchases.shared.storeFrontCountryCode : nil,
      storeEnvironment: RevenueCatManager.shared.storeEnvironment,
      sdkBuild: Bundle.main.object(forInfoDictionaryKey: "DTSDKBuild") as? String,
      rcVersion: Purchases.frameworkVersion
    )
  }

  var properties: [String: Any] {
    var properties: [String: Any] = [
      "app_state": appState,
      "scene_activation_state": sceneActivationState,
      "can_make_payments": canMakePayments,
      "rc_version": rcVersion,
    ]
    if let storefront {
      properties["storefront"] = storefront
    }
    if let storeEnvironment {
      properties["store_environment"] = storeEnvironment
    }
    if let sdkBuild {
      properties["sdk_build"] = sdkBuild
    }
    return properties
  }
}

@MainActor
struct SubscriptionOutcomeTracker {
  var capture: (AnalyticsEvent, [String: Any]) -> Void = { event, properties in
    AnalyticsService.shared.track(event, properties: properties)
  }
  var environment: () -> PurchaseEnvironment = { .current() }
  var now: () -> ContinuousClock.Instant = { .now }
  var storeLogLines: () -> [String] = { RevenueCatLogTail.shared.recentLines() }

  private static let maxStoreLogLength = 500
  private static let redactions: [(NSRegularExpression, String)] = [
    (try! NSRegularExpression(pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, options: .caseInsensitive), "<email>"),
    (try! NSRegularExpression(pattern: #"\$RCAnonymousID(?::|%3A)[0-9A-Za-z]+"#), "<user_id>"),
    (try! NSRegularExpression(pattern: #"[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}"#), "<id>"),
    (try! NSRegularExpression(pattern: #"\b[0-9A-Fa-f]{16,}\b"#), "<id>"),
  ]

  func purchaseStarted(
    productId: String, price: Decimal, currency: String?, priceDisplay: String,
    billingPeriod: String, source: String,
    paywallAppearedAt: ContinuousClock.Instant?, consentShownInPaywall: Bool
  ) -> PurchaseAttempt {
    let startedAt = now()
    let current = environment()
    let attempt = PurchaseAttempt(
      id: UUID(), productId: productId, price: price, currency: currency,
      priceDisplay: priceDisplay, startedAt: startedAt,
      msSincePaywallAppear: paywallAppearedAt.map { Self.milliseconds(from: $0, to: startedAt) },
      consentShownInPaywall: consentShownInPaywall,
      appStateAtStart: current.appState,
      sceneActivationStateAtStart: current.sceneActivationState
    )
    var properties = context(productId: productId, source: source)
      .merging(current.properties) { $1 }
      .merging(attemptProperties(attempt, at: startedAt)) { $1 }
    properties["price"] = priceDisplay
    properties["billing_period"] = billingPeriod
    capture(.subscriptionPurchaseStarted, properties)
    return attempt
  }

  func purchaseCompleted(
    _ attempt: PurchaseAttempt?, productId: String?, isTrial: Bool,
    hasActiveSubscription: Bool, source: String
  ) {
    var properties = outcomeContext(attempt, productId: productId, source: source)
    if let attempt {
      let listPrice = Self.revenue(attempt.price)
      // A free-trial start earns nothing yet; revenue arrives with the first renewal.
      properties["revenue"] = isTrial ? 0.0 : listPrice
      properties["list_price"] = listPrice
      properties["price_display"] = attempt.priceDisplay
      if let currency = attempt.currency {
        properties["currency"] = currency
      }
    }
    properties["is_trial"] = isTrial
    properties["has_active_subscription"] = hasActiveSubscription
    capture(.subscriptionPurchaseCompleted, properties)
  }

  func purchaseFailed(_ attempt: PurchaseAttempt?, error: NSError, source: String) {
    var properties = outcomeContext(attempt, productId: nil, source: source)
      .merging(errorProperties(error)) { $1 }
    properties["rc_log_tail"] = storeLogTail()
    capture(.subscriptionPurchaseFailed, properties)
  }

  func purchaseCancelled(_ attempt: PurchaseAttempt?, source: String) {
    var properties = outcomeContext(attempt, productId: nil, source: source)
    properties["rc_log_tail"] = storeLogTail()
    capture(.subscriptionPurchaseCancelled, properties)
  }

  func restored(productId: String?, source: String) {
    var properties = context(productId: productId, source: source)
    properties["has_active_subscription"] = productId != nil
    capture(.subscriptionRestored, properties)
  }

  func restoreFailed(error: NSError, source: String) {
    let properties = context(productId: nil, source: source).merging(errorProperties(error)) { $1 }
    capture(.subscriptionRestoreFailed, properties)
  }

  static func redactedLogTail(_ lines: [String], knownIdentifiers: [String] = []) -> String? {
    guard !lines.isEmpty else { return nil }
    let lineBudget = (maxStoreLogLength - (lines.count - 1)) / lines.count
    return lines.map { line in
      var line = line.replacingOccurrences(of: "\n", with: " ")
      for identifier in knownIdentifiers where !identifier.isEmpty {
        line = line.replacingOccurrences(of: identifier, with: "<user_id>")
      }
      for (regex, template) in redactions {
        let range = NSRange(line.startIndex..., in: line)
        line = regex.stringByReplacingMatches(in: line, range: range, withTemplate: template)
      }
      return String(line.prefix(lineBudget))
    }
    .joined(separator: "\n")
  }

  private func context(productId: String?, source: String) -> [String: Any] {
    var properties: [String: Any] = ["source": source]
    if let productId {
      properties["product_id"] = productId
    }
    return properties
  }

  private func outcomeContext(_ attempt: PurchaseAttempt?, productId: String?, source: String) -> [String: Any] {
    var properties = context(productId: productId ?? attempt?.productId, source: source)
      .merging(environment().properties) { $1 }
    if let attempt {
      properties.merge(attemptProperties(attempt, at: now())) { $1 }
      properties["app_state_at_start"] = attempt.appStateAtStart
      properties["scene_activation_state_at_start"] = attempt.sceneActivationStateAtStart
    }
    return properties
  }

  private func attemptProperties(_ attempt: PurchaseAttempt, at instant: ContinuousClock.Instant) -> [String: Any] {
    var properties: [String: Any] = [
      "attempt_id": attempt.id.uuidString,
      "elapsed_ms": Self.milliseconds(from: attempt.startedAt, to: instant),
      "consent_shown_in_paywall": attempt.consentShownInPaywall,
    ]
    if let msSincePaywallAppear = attempt.msSincePaywallAppear {
      properties["ms_since_paywall_appear"] = msSincePaywallAppear
    }
    return properties
  }

  private func errorProperties(_ error: NSError) -> [String: Any] {
    [
      "error_code": String(error.code),
      "error_domain": error.domain,
      "error_message": String(error.localizedDescription.prefix(500)),
    ]
  }

  private func storeLogTail() -> String? {
    Self.redactedLogTail(storeLogLines(), knownIdentifiers: [UserIdentityService.shared.userID])
  }

  // NSDecimalNumber.doubleValue is not correctly rounded (0.07 becomes 0.06999999999999999).
  private static func revenue(_ price: Decimal) -> Double? {
    Double(price.description)
  }

  private static func milliseconds(from start: ContinuousClock.Instant, to end: ContinuousClock.Instant) -> Int {
    Int((start.duration(to: end) / .milliseconds(1)).rounded())
  }
}

private extension UIApplication.State {
  var analyticsValue: String {
    switch self {
    case .active: "active"
    case .inactive: "inactive"
    case .background: "background"
    @unknown default: "unknown"
    }
  }
}

private extension UIScene.ActivationState {
  var analyticsValue: String {
    switch self {
    case .foregroundActive: "foreground_active"
    case .foregroundInactive: "foreground_inactive"
    case .background: "background"
    case .unattached: "unattached"
    @unknown default: "unknown"
    }
  }
}
