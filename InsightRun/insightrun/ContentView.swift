//  ContentView.swift
//  InsightRun
//
//  Main navigation with tabs
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @StateObject private var onboardingManager = OnboardingManager.shared
    @StateObject private var contextProvider = UnifiedAIContextProvider.shared
    @StateObject private var notificationRouter = NotificationRouter.shared
    @State private var selectedTab = 0
    @State private var showingAIAssistant = false
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var revenueCatManager: RevenueCatManager

    // File import from share sheet
    @Binding var importedFileURL: URL?
    @State private var showSuuntoImport = false

    init(importedFileURL: Binding<URL?> = .constant(nil)) {
        self._importedFileURL = importedFileURL
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $selectedTab) {
            // Dashboard Tab
            DashboardView()
                .tabItem {
                    Label(String(localized: "tab.dashboard", defaultValue: "Dashboard"), systemImage: "house.fill")
                }
                .tag(0)

            // Workouts Tab
            WorkoutListView()
                .tabItem {
                    Label(String(localized: "tab.workouts"), systemImage: "figure.run")
                }
                .tag(1)

            // Statistics Tab
            StatisticsView()
                .tabItem {
                    Label(String(localized: "tab.statistics"), systemImage: "chart.bar.fill")
                }
                .tag(2)
            }
            .onChange(of: selectedTab) { _, newTab in
                // Update context provider's current page based on selected tab
                let page: AIContextPage = switch newTab {
                case 0: .recovery  // Dashboard is recovery-focused
                case 1: .workouts
                case 2: .statistics
                default: .workouts
                }
                contextProvider.currentPage = page
            }

            // Floating AI Button (global across all tabs)
            FloatingAIButton(showingAIAssistant: $showingAIAssistant)
                .environmentObject(revenueCatManager)
        }
        .sheet(isPresented: $showingAIAssistant) {
            WorkoutAIAssistantView(
                mode: .unified,
                isPresented: $showingAIAssistant
            )
        }
        .onChange(of: notificationRouter.pendingTab) { _, tab in
            if let tab {
                selectedTab = tab
                notificationRouter.pendingTab = nil
            }
        }
        .fullScreenCover(isPresented: .constant(!onboardingManager.hasCompletedOnboarding)) {
            OnboardingView()
        }
        .sheet(isPresented: $showSuuntoImport) {
            SuuntoImportFromShareView(fileURL: importedFileURL) {
                // On dismiss, stop security-scoped resource access and clear URL
                if let url = importedFileURL {
                    url.stopAccessingSecurityScopedResource()
                }
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
        .task {
            // Check if we should prompt for App Store review
            ReviewManager.shared.checkAndRequestReview()

            // Pre-load AI context data in background for faster AI assistant access
            if revenueCatManager.hasAIAccess {
                await contextProvider.loadAllData()
            }

            // Check notification permissions and trigger proactive alerts
            let notificationManager = NotificationManager.shared
            await notificationManager.checkPermissionStatus()

            if notificationManager.isNotificationsEnabled {
                // Start sleep observer for wake-up based notifications
                if notificationManager.isDailyReadinessEnabled {
                    SleepObserverService.shared.startObserving()
                }

                let trainingLoad = TrainingLoadService.shared
                await trainingLoad.analyzeTrainingLoad()

                if trainingLoad.isOvertrainingRisk, let volumeChange = trainingLoad.weeklyVolumeChange {
                    notificationManager.sendOvertrainingAlert(volumeIncrease: volumeChange)
                }

                if trainingLoad.isInactive, let days = trainingLoad.daysSinceLastWorkout {
                    notificationManager.sendInactivityReminder(daysSinceLastRun: days)
                }

                // Update training load widget
                let calendar = Calendar.current
                if let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())),
                   let prevWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: weekStart) {
                    let thisWeekWorkouts = try? await HealthKitManager.shared.fetchRunningWorkouts(from: weekStart, to: Date())
                    let prevWeekWorkouts = try? await HealthKitManager.shared.fetchRunningWorkouts(from: prevWeekStart, to: weekStart)
                    let thisWeekDist = (thisWeekWorkouts ?? []).compactMap { $0.distance }.reduce(0, +)
                    let lastWeekDist = (prevWeekWorkouts ?? []).compactMap { $0.distance }.reduce(0, +)
                    WidgetDataProvider.shared.updateTrainingLoad(
                        volumeChange: trainingLoad.weeklyVolumeChange,
                        daysSinceLastWorkout: trainingLoad.daysSinceLastWorkout,
                        status: trainingLoad.trainingStatus,
                        thisWeekDistance: thisWeekDist,
                        lastWeekDistance: lastWeekDist
                    )
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
