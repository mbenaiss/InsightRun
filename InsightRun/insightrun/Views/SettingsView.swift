//
//  SettingsView.swift
//  InsightRun
//
//  Settings view
//

import SwiftUI

struct SettingsView: View {
    @Environment(ThemeManager.self) private var themeManager
    @EnvironmentObject private var revenueCatManager: RevenueCatManager
    @State private var showPaywall = false
    @State private var showingMedicalSources = false
    @State private var showRefreshSheet = false

    var body: some View {
        NavigationStack {
            List {
                // Subscription Section
                Section {
                    // TestFlight environment - show TestFlight badge
                    if revenueCatManager.isTestFlightEnvironment {
                        HStack {
                            Image(systemName: "airplane.circle.fill")
                                .foregroundStyle(Color.irPrimaryAccent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(localized: "TestFlight - Premium Access"))
                                    .font(.headline)
                                Text(String(localized: "All features unlocked for testing"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    } else if revenueCatManager.isSubscriptionActive {
                        // Production with active subscription
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.irSuccess)
                            Text(String(localized: "Active subscription"))
                            Spacer()
                        }

                        Button(String(localized: "Manage subscription")) {
                            if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                                UIApplication.shared.open(url)
                            }
                        }
                    } else {
                        // Production without subscription - show subscribe button
                        Button {
                            showPaywall = true
                        } label: {
                            HStack {
                                Image(systemName: "crown.fill")
                                    .foregroundStyle(Color.irWarning)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(String(localized: "Unlock Premium"))
                                        .font(.headline)
                                    Text(String(localized: "Access all features"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)

                        Button(String(localized: "Restore Purchases")) {
                            Task {
                                do {
                                    try await revenueCatManager.restorePurchases()
                                } catch {
                                    print("Error restoring purchases: \(error.localizedDescription)")
                                }
                            }
                        }
                    }
                } header: {
                    Text(String(localized: "Subscription"))
                } footer: {
                    if !revenueCatManager.hasAIAccess {
                        Text(String(localized: "Unlock full access to advanced AI analysis, personalized advice and more."))
                    }
                }

                // Appearance Section
                Section {
                    Picker(String(localized: "Appearance"), selection: Bindable(themeManager).selectedTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Label(theme.rawValue, systemImage: theme.icon)
                                .tag(theme)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text(String(localized: "Appearance"))
                } footer: {
                    Text(String(localized: "Choose the app theme. System mode automatically adapts to your iOS settings."))
                }

                // Medical Information Section
                Section {
                    Button {
                        showingMedicalSources = true
                    } label: {
                        HStack {
                            Image(systemName: "book.closed.fill")
                                .foregroundStyle(Color.irPrimaryAccent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(localized: "Medical Sources", comment: "Medical sources settings button"))
                                    .font(.body)
                                    .foregroundStyle(Color.irTextPrimary)
                                Text(String(localized: "View scientific references", comment: "Medical sources subtitle"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text(String(localized: "Medical Information", comment: "Medical information section header"))
                } footer: {
                    Text(String(localized: "Health metrics and recovery recommendations are based on published scientific research. Tap to view all sources.", comment: "Medical information footer"))
                }

                // Training Data Section
                Section {
                    if let summary = HistoricalSummaryStorage.shared.load() {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.irSuccess)
                                Text("\(summary.workoutCount) " + String(localized: "workouts indexed", comment: "Number of indexed workouts"))
                                    .font(.body)
                            }

                            Text(String(localized: "Last updated:", comment: "Last update label") + " \(formatDate(summary.indexedAt))")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            // Refresh indicator
                            let days = HistoricalSummaryStorage.shared.daysUntilRefresh()
                            if days > 0 {
                                Text(String(localized: "Next update in", comment: "Next update prefix") + " \(days) " + String(localized: "days", comment: "days unit"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(String(localized: "Update recommended", comment: "Update recommended message"))
                                    .font(.caption)
                                    .foregroundStyle(Color.irWarning)
                            }
                        }

                        // Refresh button
                        Button {
                            showRefreshSheet = true
                        } label: {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text(String(localized: "Refresh data", comment: "Refresh data button"))
                            }
                        }
                        .disabled(!HistoricalSummaryStorage.shared.canManualRefresh())

                        if !HistoricalSummaryStorage.shared.canManualRefresh() {
                            Text(String(localized: "Available 1 month after last update", comment: "Refresh cooldown message"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        VStack(alignment: .leading) {
                            HStack {
                                Image(systemName: "exclamationmark.circle")
                                    .foregroundStyle(Color.irWarning)
                                Text(String(localized: "No data indexed", comment: "No indexed data message"))
                                    .font(.body)
                            }

                            Button {
                                showRefreshSheet = true
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text(String(localized: "Index now", comment: "Index now button"))
                                }
                            }
                        }
                    }
                } header: {
                    Text(String(localized: "Training Data", comment: "Training data section header"))
                }

                // Debug Section (for testing)
                #if DEBUG
                Section {
                    // Environment simulation
                    Button(String(localized: "Simuler TestFlight")) {
                        revenueCatManager.debugTestFlightOverride = true
                    }
                    .foregroundStyle(Color.irPrimaryAccent)

                    Button(String(localized: "Simuler Production")) {
                        revenueCatManager.debugTestFlightOverride = false
                    }
                    .foregroundStyle(.indigo)

                    Button(String(localized: "Reset environnement")) {
                        revenueCatManager.debugTestFlightOverride = nil
                    }
                    .foregroundStyle(.gray)

                    // Subscription simulation
                    Button(String(localized: "Simuler non-abonné")) {
                        revenueCatManager.debugTestFlightOverride = false
                        revenueCatManager.isSubscriptionActive = false
                    }
                    .foregroundStyle(.red)

                    Button(String(localized: "Simuler abonné")) {
                        revenueCatManager.debugTestFlightOverride = false
                        revenueCatManager.isSubscriptionActive = true
                    }
                    .foregroundStyle(Color.irSuccess)

                    // Paywall & Onboarding
                    Button(String(localized: "Afficher paywall")) {
                        showPaywall = true
                    }
                    .foregroundStyle(Color.irPrimaryAccent)

                    Button(String(localized: "Réinitialiser le paywall")) {
                        UserDefaults.standard.removeObject(forKey: "hasSeenInitialPaywall")
                        revenueCatManager.hasSeenInitialPaywall = false
                    }
                    .foregroundStyle(Color.irWarning)

                    Button(String(localized: "Réinitialiser l'onboarding")) {
                        OnboardingManager.shared.resetOnboarding()
                    }
                    .foregroundStyle(.purple)

                    // Data management
                    Button(String(localized: "Delete LLM History", comment: "Debug button to clear historical summary storage")) {
                        HistoricalSummaryStorage.shared.clear()
                    }
                    .foregroundStyle(Color.irError)

                    Button(String(localized: "Réinitialiser consentement IA")) {
                        ConsentService.shared.resetConsentState()
                    }
                    .foregroundStyle(Color.irError)
                } header: {
                    Text(String(localized: "Debug"))
                } footer: {
                    Text(String(localized: "Outils de test pour simuler différents états d'abonnement. Redémarrez l'app après avoir réinitialisé."))
                }
                #endif

                // App Information Section
                Section {
                    HStack {
                        Text(String(localized: "Version", comment: "Label for app version"))
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text(String(localized: "Build", comment: "Label for app build number"))
                        Spacer()
                        Text("1")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(String(localized: "About", comment: "Section header for app information"))
                }
            }
            .navigationTitle(String(localized: "Settings", comment: "Navigation title for settings view"))
            .fullScreenCover(isPresented: $showPaywall) {
                SubscriptionPaywallView()
            }
            .sheet(isPresented: $showingMedicalSources) {
                MedicalSourcesView()
            }
            .sheet(isPresented: $showRefreshSheet) {
                HistoricalIndexationSheet()
            }
        }
        .preferredColorScheme(themeManager.selectedTheme.colorScheme)
    }

    // MARK: - Helper Methods

    /// Format date for display in settings
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

#Preview {
    SettingsView()
        .environment(ThemeManager())
        .environmentObject(RevenueCatManager.shared)
}
