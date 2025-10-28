//
//  InsightRunApp.swift
//  InsightRun
//
//  iOS 26 Running Workouts Tracker
//

import SwiftUI
import SwiftData

@main
struct InsightRunApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [WorkoutAnalysis.self])
    }
}
