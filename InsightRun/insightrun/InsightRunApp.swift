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
    @State private var importedFileURL: URL?

    // Unified ModelContainer for all SwiftData models (WorkoutAnalysis + CachedStravaActivity)
    let sharedModelContainer: ModelContainer

    init() {
        // Configure analytics (PostHog) - non-blocking, won't crash if PostHog is unavailable
        AnalyticsService.shared.configure()

        // Configure RevenueCat on app launch (synchronous - SDK must be ready before UI loads)
        RevenueCatManager.shared.configure()

        // Configure SwiftData with EXPLICIT persistence (ensures data survives app restarts)
        // Note: CachedSuuntoWorkout uses its own separate container (in SuuntoImportService)
        do {
            let schema = Schema([
                WorkoutAnalysis.self,
                CachedStravaActivity.self,
                CachedUnifiedWorkout.self
            ])

            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false  // CRITICAL: Explicitly persist to disk
            )

            sharedModelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )

            print("✅ SwiftData: Unified ModelContainer initialized (persistent storage)")
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }

        // Track app opened event - non-blocking
        Task { @MainActor in
            AnalyticsService.shared.trackAppOpened()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(importedFileURL: $importedFileURL)
                .preferredColorScheme(themeManager.selectedTheme.colorScheme)
                .environment(themeManager)
                .environmentObject(revenueCatManager)
                .onOpenURL { url in
                    handleIncomingFile(url)
                }
        }
        .modelContainer(sharedModelContainer)  // Use unified persistent container
    }

    private func handleIncomingFile(_ url: URL) {
        // Check if it's a JSON file
        guard url.pathExtension.lowercased() == "json" else {
            print("⚠️ Ignoring non-JSON file: \(url.lastPathComponent)")
            return
        }

        // Security: Start accessing the security-scoped resource
        // This is required for files received via share sheet or open-in
        guard url.startAccessingSecurityScopedResource() else {
            print("⚠️ Could not access security-scoped resource: \(url.lastPathComponent)")
            return
        }

        print("📥 Received file to import: \(url.lastPathComponent)")
        importedFileURL = url
    }
}
