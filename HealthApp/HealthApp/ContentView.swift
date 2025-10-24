//  ContentView.swift
//  healthapp
//
//  Main navigation with tabs
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Workouts Tab
            WorkoutListView()
                .tabItem {
                    Label("Courses", systemImage: "figure.run")
                }
                .tag(0)

            // Recovery Tab
            RecoveryDashboardView()
                .tabItem {
                    Label("Récupération", systemImage: "heart.fill")
                }
                .tag(1)

            // Health Profile Tab
            HealthProfileView()
                .tabItem {
                    Label("Santé", systemImage: "person.fill")
                }
                .tag(2)

            // Settings Tab
            SettingsView()
                .tabItem {
                    Label("Paramètres", systemImage: "gear")
                }
                .tag(3)
        }
    }
}

#Preview {
    ContentView()
}
