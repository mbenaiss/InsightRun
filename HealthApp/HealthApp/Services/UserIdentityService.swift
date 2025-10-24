//
//  UserIdentityService.swift
//  HealthApp
//
//  Service for managing user identity with a unique, persistent ID
//  Used for backend tracking, rate limiting, and analytics
//

import Foundation

class UserIdentityService {
    static let shared = UserIdentityService()

    private let userDefaultsKey = "com.insightrun.userID"

    // Unique user ID that persists across app launches
    private(set) var userID: String

    private init() {
        // Try to load existing user ID from UserDefaults
        if let existingID = UserDefaults.standard.string(forKey: userDefaultsKey) {
            self.userID = existingID
            print("✅ UserIdentityService: Loaded existing user ID: \(existingID)")
        } else {
            // Generate new UUID for first-time users
            let newID = UUID().uuidString
            UserDefaults.standard.set(newID, forKey: userDefaultsKey)
            self.userID = newID
            print("🆕 UserIdentityService: Generated new user ID: \(newID)")
        }
    }

    // MARK: - Public Methods

    /// Reset user ID (for debugging or testing purposes)
    func resetUserID() {
        let newID = UUID().uuidString
        UserDefaults.standard.set(newID, forKey: userDefaultsKey)
        self.userID = newID
        print("🔄 UserIdentityService: Reset user ID to: \(newID)")
    }

    /// Check if user ID exists
    var hasUserID: Bool {
        return !userID.isEmpty
    }
}
