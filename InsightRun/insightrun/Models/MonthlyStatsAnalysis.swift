//
//  MonthlyStatsAnalysis.swift
//  InsightRun
//
//  SwiftData model for caching the monthly "Lecture du mois" coach insight.
//

import Foundation
import SwiftData

@Model
final class MonthlyStatsAnalysis {
    /// Stable key combining month + locale (e.g. "2026-04-fr") so we regenerate when
    /// the user switches language and avoid stale carry-over across months.
    @Attribute(.unique) var monthKey: String

    /// The narrative body produced by the LLM. Plain prose, no markdown headers.
    var body: String

    /// Number of workouts present when the cache was written. Lets us invalidate the
    /// entry as soon as the user logs another session in the same month.
    var workoutCount: Int

    var analyzedAt: Date

    init(monthKey: String, body: String, workoutCount: Int, analyzedAt: Date = Date()) {
        self.monthKey = monthKey
        self.body = body
        self.workoutCount = workoutCount
        self.analyzedAt = analyzedAt
    }
}
