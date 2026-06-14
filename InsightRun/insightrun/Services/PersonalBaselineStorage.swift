//
//  PersonalBaselineStorage.swift
//  InsightRun
//
//  Service for persisting and loading personal baseline metrics
//  Implements local storage using UserDefaults with JSON encoding
//

import Foundation

class PersonalBaselineStorage {
    static let shared = PersonalBaselineStorage()

    private let userDefaults = UserDefaults.standard
    private let storageKey = "com.insightrun.personalBaseline"

    private init() {}

    // MARK: - Public Methods

    /// Save a personal baseline to UserDefaults
    func save(_ baseline: PersonalBaseline) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(baseline)
            userDefaults.set(data, forKey: storageKey)
        } catch {
            print("PersonalBaselineStorage: Failed to save baseline: \(error)")
        }
    }

    /// Load the personal baseline from UserDefaults
    func load() -> PersonalBaseline? {
        guard let data = userDefaults.data(forKey: storageKey) else {
            return nil
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(PersonalBaseline.self, from: data)
        } catch {
            return nil
        }
    }

    /// Check if baseline needs to be refreshed.
    /// Refresh only when missing or older than 24h. An unreliable baseline is NOT
    /// refreshed on every call: that made a single dashboard load recompute the
    /// baseline 14× (once per recovery-metrics fetch) for users without enough
    /// history. The 24h window bounds recomputation to once per day until reliable.
    func needsRefresh() -> Bool {
        guard let baseline = load() else { return true }
        return baseline.needsRefresh
    }

    /// Delete the stored baseline
    func clear() {
        userDefaults.removeObject(forKey: storageKey)
    }

    /// Check if a baseline exists
    var hasBaseline: Bool {
        userDefaults.data(forKey: storageKey) != nil
    }
}
