//
//  HistoricalSummaryStorage.swift
//  InsightRun
//
//  Service for persisting and loading historical workout summaries
//  Implements local storage using UserDefaults with JSON encoding
//

import Foundation

@MainActor
class HistoricalSummaryStorage {
    static let shared = HistoricalSummaryStorage()

    private let userDefaults = UserDefaults.standard
    private let storageKey = "com.insightrun.historicalSummary"

    private init() {}

    // MARK: - Public Methods

    /// Save a historical summary to UserDefaults
    func save(_ summary: HistoricalSummary) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(summary)
            userDefaults.set(data, forKey: storageKey)
            print("✅ HistoricalSummaryStorage: Saved summary (\(summary.workoutCount) workouts)")
        } catch {
            print("❌ HistoricalSummaryStorage: Failed to save summary: \(error)")
        }
    }

    /// Load the historical summary from UserDefaults
    func load() -> HistoricalSummary? {
        guard let data = userDefaults.data(forKey: storageKey) else {
            print("⚠️ HistoricalSummaryStorage: No saved summary found")
            return nil
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let summary = try decoder.decode(HistoricalSummary.self, from: data)
            print("✅ HistoricalSummaryStorage: Loaded summary (\(summary.workoutCount) workouts, generated \(summary.daysSinceGeneration) days ago)")
            return summary
        } catch {
            print("❌ HistoricalSummaryStorage: Failed to load summary: \(error)")
            return nil
        }
    }

    /// Check if a summary needs to be generated (either doesn't exist or needs refresh)
    func needsGeneration() -> Bool {
        guard let summary = load() else {
            print("📊 HistoricalSummaryStorage: No summary exists, generation needed")
            return true
        }

        if summary.needsRefresh {
            print("📊 HistoricalSummaryStorage: Summary is \(summary.daysSinceGeneration) days old, refresh needed")
            return true
        }

        print("✅ HistoricalSummaryStorage: Summary is up to date (\(summary.daysSinceGeneration) days old)")
        return false
    }

    /// Delete the stored summary (useful for testing or resetting)
    func clear() {
        userDefaults.removeObject(forKey: storageKey)
        print("🗑️ HistoricalSummaryStorage: Cleared stored summary")
    }

    /// Check if a summary exists (async for consistency with other methods)
    var hasSummary: Bool {
        get async {
            return userDefaults.data(forKey: storageKey) != nil
        }
    }

    // MARK: - Refresh Management

    /// Check if the summary needs to be refreshed (older than 3 months)
    func needsRefresh() -> Bool {
        guard let summary = load() else {
            print("📊 HistoricalSummaryStorage: No summary exists, refresh needed")
            return true
        }

        if summary.needsRefresh {
            print("📊 HistoricalSummaryStorage: Summary indexed \(summary.daysSinceGeneration) days ago, refresh needed")
            return true
        }

        print("✅ HistoricalSummaryStorage: Summary is fresh (\(summary.daysSinceGeneration) days since indexation)")
        return false
    }

    /// Calculate days until a refresh is required (based on 3-month policy)
    func daysUntilRefresh() -> Int {
        guard let summary = load() else {
            return 0 // No summary = refresh needed now
        }

        let calendar = Calendar.current
        let threeMonthsAfterIndex = calendar.date(byAdding: .month, value: 3, to: summary.indexedAt) ?? Date()
        let components = calendar.dateComponents([.day], from: Date(), to: threeMonthsAfterIndex)
        let daysLeft = components.day ?? 0

        return max(0, daysLeft) // Never return negative
    }

    /// Check if a manual refresh is allowed (summary is at least 1 month old)
    func canManualRefresh() -> Bool {
        guard let summary = load() else {
            print("📊 HistoricalSummaryStorage: No summary exists, manual refresh allowed")
            return true
        }

        let oneMonthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        let canRefresh = summary.indexedAt < oneMonthAgo

        if canRefresh {
            print("✅ HistoricalSummaryStorage: Manual refresh allowed (indexed \(summary.daysSinceGeneration) days ago)")
        } else {
            print("⚠️ HistoricalSummaryStorage: Manual refresh not allowed yet (indexed \(summary.daysSinceGeneration) days ago)")
        }

        return canRefresh
    }
}
