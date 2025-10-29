//  ContentView.swift
//  InsightRun
//
//  Main navigation with tabs
//

import SwiftUI

struct ContentView: View {
    @StateObject private var onboardingManager = OnboardingManager.shared
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Workouts Tab - Always visible
            WorkoutListView()
                .tabItem {
                    Label(String(localized: "tab.workouts"), systemImage: "figure.run")
                }
                .tag(0)

            // Recovery Tab
            RecoveryDashboardView()
                .tabItem {
                    Label(String(localized: "tab.recovery"), systemImage: "heart.fill")
                }
                .tag(1)

            // Health Profile Tab
            HealthProfileView()
                .tabItem {
                    Label(String(localized: "tab.health"), systemImage: "person.fill")
                }
                .tag(2)
        }
        .fullScreenCover(isPresented: .constant(!onboardingManager.hasCompletedOnboarding)) {
            OnboardingView()
        }
    }
}

#Preview {
    ContentView()
}
