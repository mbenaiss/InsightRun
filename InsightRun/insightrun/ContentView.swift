//  ContentView.swift
//  InsightRun
//
//  Main navigation with tabs
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @StateObject private var onboardingManager = OnboardingManager.shared
    @State private var selectedTab = 0
    @Environment(\.modelContext) private var modelContext

    // File import from share sheet
    @Binding var importedFileURL: URL?
    @State private var showSuuntoImport = false

    init(importedFileURL: Binding<URL?> = .constant(nil)) {
        self._importedFileURL = importedFileURL
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // Workouts Tab - Always visible
            WorkoutListView()
                .tabItem {
                    Label(String(localized: "tab.workouts"), systemImage: "figure.run")
                }
                .tag(0)

            // Statistics Tab
            StatisticsView()
                .tabItem {
                    Label(String(localized: "tab.statistics"), systemImage: "chart.bar.fill")
                }
                .tag(1)

            // Workout Plan Tab (AI Generator)
            WorkoutPlanView()
                .tabItem {
                    Label(String(localized: "tab.plan"), systemImage: "sparkles")
                }
                .tag(2)

            // Recovery Tab
            RecoveryDashboardView()
                .tabItem {
                    Label(String(localized: "tab.recovery"), systemImage: "heart.fill")
                }
                .tag(3)

            // Health Profile Tab
            HealthProfileView()
                .tabItem {
                    Label(String(localized: "tab.health"), systemImage: "person.fill")
                }
                .tag(4)
        }
        .fullScreenCover(isPresented: .constant(!onboardingManager.hasCompletedOnboarding)) {
            OnboardingView()
        }
        .sheet(isPresented: $showSuuntoImport) {
            SuuntoImportFromShareView(fileURL: importedFileURL) {
                // On dismiss, clear the imported file URL
                importedFileURL = nil
            }
        }
        .onChange(of: importedFileURL) { _, newURL in
            if newURL != nil {
                showSuuntoImport = true
            }
        }
        .onAppear {
            // Inject shared ModelContext into cache singletons
            // This ensures all caches use the unified persistent container
            Task { @MainActor in
                StravaCache.shared.setModelContext(modelContext)
                UnifiedWorkoutCache.shared.setModelContext(modelContext)
                SuuntoImportService.shared.setModelContext(modelContext)
            }
        }
    }
}

#Preview {
    ContentView()
}
