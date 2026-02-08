//
//  InsightRunWidgetsBundle.swift
//  InsightRunWidgets
//
//  Widget bundle containing all InsightRun widgets
//

import WidgetKit
import SwiftUI

@main
struct InsightRunWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ReadinessWidget()
        WeeklyStatsWidget()
        LastWorkoutWidget()
        HealthVitalsWidget()
        SleepQualityWidget()
        TrainingLoadWidget()
    }
}
