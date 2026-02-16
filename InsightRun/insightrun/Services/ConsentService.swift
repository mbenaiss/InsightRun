//
//  ConsentService.swift
//  InsightRun
//
//  Service to manage user consent for AI data sharing (Apple 5.1.2(i) compliance)
//

import Foundation

@MainActor
class ConsentService {
    static let shared = ConsentService()

    // UserDefaults keys
    private let consentKey = "com.insightrun.aiConsent.hasConsented"
    private let consentDateKey = "com.insightrun.aiConsent.date"
    private let consentVersionKey = "com.insightrun.aiConsent.version"

    private let currentConsentVersion = "1.0"

    // Computed properties that read directly from UserDefaults
    var hasConsentedToAIDataSharing: Bool {
        if DemoMode.isEnabled { return true }
        return UserDefaults.standard.bool(forKey: consentKey)
    }

    var consentDate: Date? {
        UserDefaults.standard.object(forKey: consentDateKey) as? Date
    }

    private init() {}

    // MARK: - Public Methods

    /// Grant consent for AI data sharing
    func grantAIConsent() {
        let now = Date()
        UserDefaults.standard.set(true, forKey: consentKey)
        UserDefaults.standard.set(now, forKey: consentDateKey)
        UserDefaults.standard.set(currentConsentVersion, forKey: consentVersionKey)

        // Track consent event
        AnalyticsService.shared.track(.aiConsentGranted, properties: [
            "consent_version": currentConsentVersion,
            "timestamp": now.timeIntervalSince1970
        ])
    }

    /// Revoke consent for AI data sharing
    func revokeAIConsent() {
        UserDefaults.standard.set(false, forKey: consentKey)
        UserDefaults.standard.removeObject(forKey: consentDateKey)

        // Track revocation event
        AnalyticsService.shared.track(.aiConsentRevoked, properties: [
            "consent_version": currentConsentVersion
        ])
    }

    /// Check if consent is required (not yet given)
    func isConsentRequired() -> Bool {
        return !hasConsentedToAIDataSharing
    }

    /// Get consent version (for audit purposes)
    var consentVersion: String? {
        return UserDefaults.standard.string(forKey: consentVersionKey)
    }

    // MARK: - Debug/Testing

    #if DEBUG
    /// Reset consent state (for testing only)
    func resetConsentState() {
        UserDefaults.standard.removeObject(forKey: consentKey)
        UserDefaults.standard.removeObject(forKey: consentDateKey)
        UserDefaults.standard.removeObject(forKey: consentVersionKey)
    }
    #endif
}
