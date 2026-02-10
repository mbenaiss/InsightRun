//  ContentView.swift
//  InsightRun
//
//  Main navigation with 3 tabs: Dashboard, Courses, Statistics
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
                // Dashboard Tab - Recovery, health & coaching merged
                DashboardView()
                    .tabItem {
                        Label(String(localized: "tab.dashboard", comment: "Dashboard tab"), systemImage: "gauge.open.with.lines.needle.33percent.and.arrowtriangle")
                    }
                    .tag(0)

                // Courses Tab (Runs)
                WorkoutListView()
                    .tabItem {
                        Label(String(localized: "tab.courses", comment: "Courses tab"), systemImage: "figure.run")
                    }
                    .tag(1)

                // Statistics Tab
                StatisticsView()
                    .tabItem {
                        Label(String(localized: "tab.statistics", comment: "Statistics tab"), systemImage: "chart.bar.fill")
                    }
                    .tag(2)
            }
            .onChange(of: selectedTab) { _, newTab in
                let page: AIContextPage = switch newTab {
                case 0: .recovery
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
            Task { @MainActor in
                StravaCache.shared.setModelContext(modelContext)
                UnifiedWorkoutCache.shared.setModelContext(modelContext)
                SuuntoImportService.shared.setModelContext(modelContext)
            }
        }
        .task {
            ReviewManager.shared.checkAndRequestReview()

            if revenueCatManager.hasAIAccess {
                await contextProvider.loadAllData()
            }

            let notificationManager = NotificationManager.shared
            await notificationManager.checkPermissionStatus()

            if notificationManager.isNotificationsEnabled {
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
