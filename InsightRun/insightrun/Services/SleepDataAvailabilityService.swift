//
//  SleepDataAvailabilityService.swift
//  InsightRun
//
//  Detects whether the user tracks sleep so the rest of the app can switch to a
//  "no-sleep" presentation (showing Training Stress Balance / freshness in place
//  of sleep-derived cards) without ever asking the user.
//

import Foundation

@MainActor
final class SleepDataAvailabilityService {
    static let shared = SleepDataAvailabilityService()

    private let cacheKey = "com.insightrun.noSleepModeCache"
    private let cacheTTL: TimeInterval = 12 * 3600 // 12 hours
    private let lookbackDays = 14
    private let minNightsForNormalMode = 3

    private(set) var defaults: UserDefaults

    private init() {
        self.defaults = .standard
    }

    #if DEBUG
    static func createForTesting(defaults: UserDefaults) -> SleepDataAvailabilityService {
        let s = SleepDataAvailabilityService()
        s.defaults = defaults
        return s
    }
    #endif

    private struct CachedAvailability: Codable {
        let isNoSleepMode: Bool
        let timestamp: Date
    }

    /// Returns true when the user has tracked fewer than `minNightsForNormalMode`
    /// nights over the last `lookbackDays` days. Cached 12h to avoid hammering
    /// HealthKit on every dashboard refresh.
    func isNoSleepMode() async -> Bool {
        if let cached = readCache() { return cached }
        let mode = await detectFromHealthKit()
        writeCache(mode)
        return mode
    }

    /// Force re-detection (e.g. after the user grants HealthKit permissions
    /// post-onboarding, or if the cache might be stale).
    @discardableResult
    func refresh() async -> Bool {
        let mode = await detectFromHealthKit()
        writeCache(mode)
        return mode
    }

    private func detectFromHealthKit() async -> Bool {
        let calendar = Calendar.current
        let end = Date()
        guard let start = calendar.date(byAdding: .day, value: -lookbackDays, to: end) else {
            return false
        }
        let history = await HealthKitManager.shared.fetchSleepHistory(start: start, end: end)
        return history.count < minNightsForNormalMode
    }

    private func readCache() -> Bool? {
        guard let data = defaults.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode(CachedAvailability.self, from: data),
              Date().timeIntervalSince(cached.timestamp) < cacheTTL else {
            return nil
        }
        return cached.isNoSleepMode
    }

    private func writeCache(_ isNoSleepMode: Bool) {
        let cache = CachedAvailability(isNoSleepMode: isNoSleepMode, timestamp: Date())
        if let data = try? JSONEncoder().encode(cache) {
            defaults.set(data, forKey: cacheKey)
        }
    }
}
