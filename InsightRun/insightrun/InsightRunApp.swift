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
    @StateObject private var revenueCatManager = RevenueCatManager.shared

    init() {
        // Configure analytics (PostHog) - non-blocking, won't crash if PostHog is unavailable
        AnalyticsService.shared.configure()

        // Configure RevenueCat on app launch
        Task { @MainActor in
            RevenueCatManager.shared.configure()
        }

        // Track app opened event - non-blocking
        Task { @MainActor in
            AnalyticsService.shared.trackAppOpened()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(themeManager.selectedTheme.colorScheme)
                .environment(themeManager)
                .environmentObject(revenueCatManager)
        }
        .modelContainer(for: [WorkoutAnalysis.self])
    }
}
