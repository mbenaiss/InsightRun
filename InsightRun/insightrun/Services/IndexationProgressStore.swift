//
//  IndexationProgressStore.swift
//  InsightRun
//
//  Service for persisting indexation progress and partial batch summaries
//  Implements local storage using UserDefaults with JSON encoding
//  Validates userId and enforces 24-hour TTL for security
//

import Foundation

@MainActor
class IndexationProgressStore {
    static let shared = IndexationProgressStore()

    private let userDefaults = UserDefaults.standard
    private let batchSummariesKey = "com.insightrun.batchSummaries"
    private let progressKey = "com.insightrun.indexationProgress"

    private init() {}

    // MARK: - Batch Summaries Management

    /// Save a batch summary to persistent storage
    func saveBatchSummary(_ summary: BatchSummary) {
        var summaries = loadAllBatchSummaries()

        // Validate userId matches existing batches
        if let firstSummary = summaries.first, firstSummary.userId != summary.userId {
            print("⚠️ IndexationProgressStore: UserId mismatch, clearing old batches")
            clearAll()
            summaries = []
        }

        // Check if batch already exists (by batchNumber)
        if let existingIndex = summaries.firstIndex(where: { $0.batchNumber == summary.batchNumber }) {
            summaries[existingIndex] = summary
            print("🔄 IndexationProgressStore: Updated batch \(summary.batchNumber)")
        } else {
            summaries.append(summary)
            print("✅ IndexationProgressStore: Saved batch \(summary.batchNumber)/\(summary.totalBatches)")
        }

        // Remove invalid batches (older than 24h)
        let validSummaries = summaries.filter { $0.isValid }
        if validSummaries.count < summaries.count {
            print("🗑️ IndexationProgressStore: Removed \(summaries.count - validSummaries.count) expired batches")
        }

        saveSummaries(validSummaries)
    }

    /// Load all batch summaries from storage
    func loadAllBatchSummaries() -> [BatchSummary] {
        guard let data = userDefaults.data(forKey: batchSummariesKey) else {
            print("⚠️ IndexationProgressStore: No batch summaries found")
            return []
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let summaries = try decoder.decode([BatchSummary].self, from: data)

            // Filter out invalid batches (TTL check)
            let validSummaries = summaries.filter { $0.isValid }
            if validSummaries.count < summaries.count {
                print("🗑️ IndexationProgressStore: Filtered out \(summaries.count - validSummaries.count) expired batches")
                saveSummaries(validSummaries)
            }

            print("✅ IndexationProgressStore: Loaded \(validSummaries.count) valid batch summaries")
            return validSummaries
        } catch {
            print("❌ IndexationProgressStore: Failed to load batch summaries: \(error)")
            return []
        }
    }

    /// Get batch summaries for a specific user (with userId validation)
    func loadBatchSummaries(forUserId userId: String) -> [BatchSummary] {
        let allSummaries = loadAllBatchSummaries()
        let userSummaries = allSummaries.filter { $0.userId == userId }

        if userSummaries.count < allSummaries.count {
            print("⚠️ IndexationProgressStore: Filtered \(allSummaries.count - userSummaries.count) batches from other users")
        }

        return userSummaries
    }

    /// Private helper to save summaries
    private func saveSummaries(_ summaries: [BatchSummary]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(summaries)
            userDefaults.set(data, forKey: batchSummariesKey)
        } catch {
            print("❌ IndexationProgressStore: Failed to save batch summaries: \(error)")
        }
    }

    // MARK: - Progress Management

    struct IndexationProgress: Codable {
        let totalBatches: Int
        let lastCompletedBatch: Int
        let batchStatuses: [Int: BatchSummary.BatchStatus]
        let userId: String
        let startedAt: Date
        let lastUpdatedAt: Date

        /// Check if progress is still valid (not older than 24 hours)
        var isValid: Bool {
            let twentyFourHoursAgo = Calendar.current.date(byAdding: .hour, value: -24, to: Date()) ?? Date()
            return lastUpdatedAt > twentyFourHoursAgo
        }

        /// Progress percentage (0-100)
        var progressPercentage: Int {
            guard totalBatches > 0 else { return 0 }
            return Int((Double(lastCompletedBatch) / Double(totalBatches)) * 100)
        }

        /// Check if indexation is complete
        var isComplete: Bool {
            return lastCompletedBatch >= totalBatches
        }
    }

    /// Save indexation progress
    func saveProgress(
        totalBatches: Int,
        lastCompletedBatch: Int,
        batchStatuses: [Int: BatchSummary.BatchStatus],
        userId: String
    ) {
        let existingProgress = loadProgress()
        let startedAt = existingProgress?.startedAt ?? Date()

        let progress = IndexationProgress(
            totalBatches: totalBatches,
            lastCompletedBatch: lastCompletedBatch,
            batchStatuses: batchStatuses,
            userId: userId,
            startedAt: startedAt,
            lastUpdatedAt: Date()
        )

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(progress)
            userDefaults.set(data, forKey: progressKey)
            print("✅ IndexationProgressStore: Saved progress (\(progress.progressPercentage)% complete)")
        } catch {
            print("❌ IndexationProgressStore: Failed to save progress: \(error)")
        }
    }

    /// Load indexation progress
    func loadProgress() -> IndexationProgress? {
        guard let data = userDefaults.data(forKey: progressKey) else {
            print("⚠️ IndexationProgressStore: No progress found")
            return nil
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let progress = try decoder.decode(IndexationProgress.self, from: data)

            // Check validity (24h TTL)
            if !progress.isValid {
                print("🗑️ IndexationProgressStore: Progress expired, clearing")
                clearProgress()
                return nil
            }

            print("✅ IndexationProgressStore: Loaded progress (\(progress.progressPercentage)% complete)")
            return progress
        } catch {
            print("❌ IndexationProgressStore: Failed to load progress: \(error)")
            return nil
        }
    }

    /// Load progress for a specific user (with userId validation)
    func loadProgress(forUserId userId: String) -> IndexationProgress? {
        guard let progress = loadProgress() else {
            return nil
        }

        if progress.userId != userId {
            print("⚠️ IndexationProgressStore: UserId mismatch in progress, clearing")
            clearProgress()
            return nil
        }

        return progress
    }

    // MARK: - Cleanup Methods

    /// Clear all batch summaries
    func clearBatchSummaries() {
        userDefaults.removeObject(forKey: batchSummariesKey)
        print("🗑️ IndexationProgressStore: Cleared all batch summaries")
    }

    /// Clear indexation progress
    func clearProgress() {
        userDefaults.removeObject(forKey: progressKey)
        print("🗑️ IndexationProgressStore: Cleared indexation progress")
    }

    /// Clear all stored data (summaries + progress)
    func clearAll() {
        clearBatchSummaries()
        clearProgress()
        print("🗑️ IndexationProgressStore: Cleared all indexation data")
    }

    // MARK: - Status Checks

    /// Check if there's an ongoing indexation
    func hasOngoingIndexation(forUserId userId: String) -> Bool {
        guard let progress = loadProgress(forUserId: userId) else {
            return false
        }

        return !progress.isComplete && progress.isValid
    }

    /// Get completion status for current indexation
    func getCompletionStatus(forUserId userId: String) -> (completed: Int, total: Int)? {
        guard let progress = loadProgress(forUserId: userId) else {
            return nil
        }

        return (completed: progress.lastCompletedBatch, total: progress.totalBatches)
    }

    /// Check if can resume an interrupted indexation
    func canResumeIndexation(forUserId userId: String) -> Bool {
        guard let progress = loadProgress(forUserId: userId) else {
            return false
        }

        return !progress.isComplete && progress.isValid && progress.lastCompletedBatch > 0
    }
}
