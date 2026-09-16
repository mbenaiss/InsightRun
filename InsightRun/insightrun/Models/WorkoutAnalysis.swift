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
    static let currentContextVersion = 5

    @Attribute(.unique) var workoutId: UUID
    var analysisText: String
    var analyzedAt: Date
    var contextVersion: Int?
    var estimatedMaxHR: Int?

    init(workoutId: UUID, analysisText: String, analyzedAt: Date = Date(), estimatedMaxHR: Int? = nil) {
        self.workoutId = workoutId
        self.analysisText = analysisText
        self.analyzedAt = analyzedAt
        self.contextVersion = Self.currentContextVersion
        self.estimatedMaxHR = estimatedMaxHR
    }
}
