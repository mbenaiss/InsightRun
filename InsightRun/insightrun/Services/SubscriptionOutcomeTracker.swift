import Foundation

@MainActor
struct SubscriptionOutcomeTracker {
  var capture: (AnalyticsEvent, [String: Any]) -> Void = { event, properties in
    AnalyticsService.shared.track(event, properties: properties)
  }

  func purchaseCompleted(
    productId: String?, revenue: String, isTrial: Bool,
    hasActiveSubscription: Bool, source: String
  ) {
    var properties = context(productId: productId, source: source)
    properties["revenue"] = revenue
    properties["is_trial"] = isTrial
    properties["has_active_subscription"] = hasActiveSubscription
    capture(.subscriptionPurchaseCompleted, properties)
  }

  func purchaseFailed(error: NSError, productId: String?, source: String) {
    capture(.subscriptionPurchaseFailed, failure(error, productId: productId, source: source))
  }

  func purchaseCancelled(productId: String?, source: String) {
    capture(.subscriptionPurchaseCancelled, context(productId: productId, source: source))
  }

  func restored(productId: String?, source: String) {
    var properties = context(productId: productId, source: source)
    properties["has_active_subscription"] = productId != nil
    capture(.subscriptionRestored, properties)
  }

  func restoreFailed(error: NSError, source: String) {
    capture(.subscriptionRestoreFailed, failure(error, productId: nil, source: source))
  }

  private func context(productId: String?, source: String) -> [String: Any] {
    var properties: [String: Any] = ["source": source]
    if let productId {
      properties["product_id"] = productId
    }
    return properties
  }

  private func failure(_ error: NSError, productId: String?, source: String) -> [String: Any] {
    var properties = context(productId: productId, source: source)
    properties["error_code"] = String(error.code)
    properties["error_domain"] = error.domain
    properties["error_message"] = String(error.localizedDescription.prefix(500))
    return properties
  }
}
