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

    // Static accessor for shared container (used by views that need ModelContext in init)
    private(set) static var shared: ModelContainer?

    init() {
        // Configure analytics (PostHog) - non-blocking, won't crash if PostHog is unavailable
        AnalyticsService.shared.configure()

        // Configure RevenueCat on app launch (synchronous - SDK must be ready before UI loads)
        RevenueCatManager.shared.configure()

        // Configure SwiftData with EXPLICIT persistence (ensures data survives app restarts)
        // Note: CachedSuuntoWorkout uses its own separate container (in SuuntoImportService)
        do {
            // Use separate stores to avoid migration issues when adding new models
            let existingSchema = Schema([
                WorkoutAnalysis.self,
                CachedStravaActivity.self,
            ])

            let unifiedCacheSchema = Schema([
                CachedUnifiedWorkout.self
            ])

            // Original store for existing models
            let existingConfig = ModelConfiguration(
                "ExistingData",
                schema: existingSchema,
                isStoredInMemoryOnly: false
            )

            // New separate store for CachedUnifiedWorkout (avoids migration)
            let unifiedCacheConfig = ModelConfiguration(
                "UnifiedWorkoutCache",
                schema: unifiedCacheSchema,
                isStoredInMemoryOnly: false
            )

            // Combined schema for the container
            let fullSchema = Schema([
                WorkoutAnalysis.self,
                CachedStravaActivity.self,
                CachedUnifiedWorkout.self
            ])

            sharedModelContainer = try ModelContainer(
                for: fullSchema,
                configurations: [existingConfig, unifiedCacheConfig]
            )

            // Make container accessible statically for views that need it in init
            InsightRunApp.shared = sharedModelContainer

            print("✅ SwiftData: Unified ModelContainer initialized (persistent storage)")
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }

        // Setup notification tap handling + clean up legacy scheduled notifications
        Task { @MainActor in
            NotificationRouter.shared.setup()
            NotificationManager.shared.removeLegacyNotifications()
        }

        // Track app opened event - non-blocking
        Task { @MainActor in
            AnalyticsService.shared.trackAppOpened()
        }

        // Start background sync if HealthKit is already authorized
        if HealthKitManager.shared.hasCompletedHealthKitSetup {
            WorkoutSyncService.shared.startObserving()
            SleepObserverService.shared.startObserving()
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
        // Check if it's a FIT file
        guard url.pathExtension.lowercased() == "fit" else {
            print("⚠️ Ignoring non-FIT file: \(url.lastPathComponent)")
            return
        }

        // Security: Try to start accessing the security-scoped resource
        // For files from share sheet (copied to app's Inbox), this may return false
        // but the file is still accessible - so we don't guard on this
        let hasSecurityAccess = url.startAccessingSecurityScopedResource()
        if !hasSecurityAccess {
            print("ℹ️ No security-scoped access needed for: \(url.lastPathComponent) (likely in Inbox)")
        }

        print("📥 Received file to import: \(url.lastPathComponent)")
        importedFileURL = url
    }
}
