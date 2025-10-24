//
//  HealthAppApp.swift
//  HealthApp
//
//  iOS 26 Running Workouts Tracker
//

import SwiftUI
import SwiftData

@main
struct HealthAppApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [WorkoutAnalysis.self])
    }
}
