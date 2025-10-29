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

    var body: some View {
        NavigationStack {
            List {
                // Subscription Section
                Section {
                    if revenueCatManager.isSubscriptionActive {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(String(localized: "Abonnement actif"))
                            Spacer()
                        }

                        Button(String(localized: "Gérer l'abonnement")) {
                            showPaywall = true
                        }
                    } else {
                        Button {
                            showPaywall = true
                        } label: {
                            HStack {
                                Image(systemName: "crown.fill")
                                    .foregroundStyle(.yellow)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(String(localized: "Débloquer Premium"))
                                        .font(.headline)
                                    Text(String(localized: "Accédez à toutes les fonctionnalités"))
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
                    }

                    Button(String(localized: "Restaurer les achats")) {
                        Task {
                            do {
                                try await revenueCatManager.restorePurchases()
                            } catch {
                                print("Error restoring purchases: \(error.localizedDescription)")
                            }
                        }
                    }
                } header: {
                    Text(String(localized: "Abonnement"))
                } footer: {
                    if !revenueCatManager.isSubscriptionActive {
                        Text(String(localized: "Débloquez l'accès complet à l'analyse IA avancée, les conseils personnalisés et bien plus encore."))
                    }
                }

                // Appearance Section
                Section {
                    Picker(String(localized: "Apparence"), selection: Bindable(themeManager).selectedTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Label(theme.rawValue, systemImage: theme.icon)
                                .tag(theme)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text(String(localized: "Apparence"))
                } footer: {
                    Text(String(localized: "Choisissez le thème de l'application. Le mode Système s'adapte automatiquement à vos réglages iOS."))
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
        }
        .preferredColorScheme(themeManager.selectedTheme.colorScheme)
    }
}

#Preview {
    SettingsView()
        .environment(ThemeManager())
        .environmentObject(RevenueCatManager.shared)
}
