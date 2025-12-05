//
//  WorkoutAnalysis.swift
//  InsightRun
//
//  SwiftData model for storing AI workout analyses locally
//

import Foundation
import SwiftData

@Model
class WorkoutAnalysis {
    @Attribute(.unique) var workoutId: UUID
    var analysisText: String
    var analyzedAt: Date

    init(workoutId: UUID, analysisText: String, analyzedAt: Date = Date()) {
        self.workoutId = workoutId
        self.analysisText = analysisText
        self.analyzedAt = analyzedAt
    }
}
