//
//  BatchSummary.swift
//  InsightRun
//
//  Model representing a partial summary from batch indexation
//  Used during incremental indexation to store intermediate results
//

import Foundation

struct BatchSummary: Codable, Identifiable {
    /// Unique identifier for the batch
    let id: UUID

    /// Batch number in the indexation sequence
    let batchNumber: Int

    /// Total number of batches in the indexation
    let totalBatches: Int

    /// AI-generated summary for this batch of workouts
    let summary: String

    /// Number of workouts in this batch
    let workoutCount: Int

    /// Date range of workouts in this batch
    let dateRangeStart: Date
    let dateRangeEnd: Date

    /// When this batch was processed
    let processedAt: Date

    /// User ID associated with this batch (for validation)
    let userId: String

    /// Status of the batch processing
    var status: BatchStatus

    enum BatchStatus: String, Codable {
        case pending
        case processing
        case completed
        case failed
    }
}

// MARK: - Convenience Initializer

extension BatchSummary {
    /// Create a new batch summary
    init(
        batchNumber: Int,
        totalBatches: Int,
        summary: String,
        workoutCount: Int,
        dateRangeStart: Date,
        dateRangeEnd: Date,
        userId: String,
        status: BatchStatus = .completed
    ) {
        self.id = UUID()
        self.batchNumber = batchNumber
        self.totalBatches = totalBatches
        self.summary = summary
        self.workoutCount = workoutCount
        self.dateRangeStart = dateRangeStart
        self.dateRangeEnd = dateRangeEnd
        self.processedAt = Date()
        self.userId = userId
        self.status = status
    }
}

// MARK: - Computed Properties

extension BatchSummary {
    /// Check if batch is still valid (not older than 24 hours)
    var isValid: Bool {
        let twentyFourHoursAgo = Calendar.current.date(byAdding: .hour, value: -24, to: Date()) ?? Date()
        return processedAt > twentyFourHoursAgo
    }

    /// Hours since batch was processed
    var hoursSinceProcessing: Int {
        let components = Calendar.current.dateComponents([.hour], from: processedAt, to: Date())
        return components.hour ?? 0
    }

    /// Human-readable batch position
    var batchPositionFormatted: String {
        return "Batch \(batchNumber)/\(totalBatches)"
    }

    /// Date range formatted
    var dateRangeFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        let start = formatter.string(from: dateRangeStart)
        let end = formatter.string(from: dateRangeEnd)
        return "\(start) - \(end)"
    }
}
