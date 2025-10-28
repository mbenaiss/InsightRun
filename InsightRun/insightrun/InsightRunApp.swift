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
    @State private var themeManager = ThemeManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(themeManager.selectedTheme.colorScheme)
                .environment(themeManager)
        }
        .modelContainer(for: [WorkoutAnalysis.self])
    }
}
