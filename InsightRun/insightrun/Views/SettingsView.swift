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

    var body: some View {
        NavigationStack {
            List {
                // Subscription Section
                Section {
                    // TestFlight environment - show TestFlight badge
                    if revenueCatManager.isTestFlightEnvironment {
                        HStack {
                            Image(systemName: "airplane.circle.fill")
                                .foregroundStyle(.blue)
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
                                .foregroundStyle(.green)
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
                                    .foregroundStyle(.yellow)
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
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(localized: "Medical Sources", comment: "Medical sources settings button"))
                                    .font(.body)
                                    .foregroundStyle(.primary)
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

                // Debug Section (for testing)
                #if DEBUG
                Section {
                    Button(String(localized: "Réinitialiser le paywall")) {
                        UserDefaults.standard.removeObject(forKey: "hasSeenInitialPaywall")
                        revenueCatManager.hasSeenInitialPaywall = false
                    }
                    .foregroundStyle(.orange)

                    Button(String(localized: "Réinitialiser l'onboarding")) {
                        OnboardingManager.shared.resetOnboarding()
                    }
                    .foregroundStyle(.purple)

                    Button(String(localized: "Simuler non-abonné")) {
                        revenueCatManager.isSubscriptionActive = false
                    }
                    .foregroundStyle(.red)

                    Button(String(localized: "Simuler abonné")) {
                        revenueCatManager.isSubscriptionActive = true
                    }
                    .foregroundStyle(.green)

                    Button(String(localized: "Afficher paywall")) {
                        showPaywall = true
                    }
                    .foregroundStyle(.blue)
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
        }
        .preferredColorScheme(themeManager.selectedTheme.colorScheme)
    }
}

#Preview {
    SettingsView()
        .environment(ThemeManager())
        .environmentObject(RevenueCatManager.shared)
}
