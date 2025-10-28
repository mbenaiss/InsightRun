//
//  WorkoutAnalysis.swift
//  HealthApp
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
    var model: String

    init(workoutId: UUID, analysisText: String, analyzedAt: Date = Date(), model: String = "grok-4-fast") {
        self.workoutId = workoutId
        self.analysisText = analysisText
        self.analyzedAt = analyzedAt
        self.model = model
    }
}
