//
//  RemoteConfigService.swift
//  InsightRun
//
//  Manages remote feature flags with offline-first support
//  1. Load hardcoded defaults on init
//  2. Load cached config from UserDefaults
//  3. Fetch fresh config from backend in background
//  4. Always fallback to cache or defaults if offline
//

import Foundation
import Combine

@MainActor
class RemoteConfigService: ObservableObject {
    static let shared = RemoteConfigService()

    /// Current feature flags as dynamic dictionary
    @Published private(set) var features: [String: Bool]
    @Published private(set) var lastFetchDate: Date?
    @Published private(set) var isFetching: Bool = false

    /// Error from last fetch attempt
    @Published private(set) var lastError: Error?

    /// Cache interval (5 minutes)
    private let cacheInterval: TimeInterval = 300

    /// UserDefaults keys
    private let cacheKey = "com.insightrun.remoteConfig"
    private let lastFetchKey = "com.insightrun.remoteConfigLastFetch"

    private init() {
        // Step 1: Start with hardcoded defaults
        self.features = DEFAULT_FEATURES

        // Step 2: Load cached config from UserDefaults (if available)
        loadCachedConfig()

        // Step 3: Fetch fresh config in background
        Task {
            await fetchConfigIfNeeded()
        }
    }

    // MARK: - Public Methods

    /// Check if a specific feature is enabled (type-safe with FeatureKey)
    func isFeatureEnabled(_ feature: FeatureKey) -> Bool {
        return features[feature.rawValue] ?? DEFAULT_FEATURES[feature.rawValue] ?? false
    }

    /// Check if a feature is enabled by string key (for dynamic features)
    func isFeatureEnabled(_ key: String) -> Bool {
        return features[key] ?? DEFAULT_FEATURES[key] ?? false
    }

    /// Fetch config from backend (can be called manually)
    func fetchConfig() async {
        await fetchConfigFromBackend()
    }

    /// Fetch config if cache is stale
    func fetchConfigIfNeeded() async {
        if let lastFetch = lastFetchDate, Date().timeIntervalSince(lastFetch) < cacheInterval {
            return
        }
        await fetchConfigFromBackend()
    }

    // MARK: - Private Methods

    private func loadCachedConfig() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return }

        do {
            let decoder = JSONDecoder()
            let config = try decoder.decode(RemoteConfig.self, from: data)
            // Merge with defaults (cached values override defaults)
            self.features = DEFAULT_FEATURES.merging(config.features) { _, new in new }

            if let timestamp = UserDefaults.standard.object(forKey: lastFetchKey) as? Date {
                self.lastFetchDate = timestamp
            }

            print("RemoteConfig: Loaded cached config")
        } catch {
            print("RemoteConfig: Failed to decode cached config: \(error)")
        }
    }

    private func saveConfigToCache(_ config: RemoteConfig) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(config)
            UserDefaults.standard.set(data, forKey: cacheKey)
            UserDefaults.standard.set(Date(), forKey: lastFetchKey)
            print("RemoteConfig: Saved config to cache")
        } catch {
            print("RemoteConfig: Failed to save config to cache: \(error)")
        }
    }

    private func fetchConfigFromBackend() async {
        guard !isFetching else { return }

        isFetching = true
        lastError = nil

        do {
            let config = try await BackendAPIClient.shared.getConfig()

            // Merge with defaults (server values override defaults)
            self.features = DEFAULT_FEATURES.merging(config.features) { _, new in new }
            self.lastFetchDate = Date()

            saveConfigToCache(config)

            print("RemoteConfig: Fetched fresh config from backend")

        } catch {
            lastError = error
            print("RemoteConfig: Failed to fetch config, using cached/defaults: \(error)")
        }

        isFetching = false
    }
}
