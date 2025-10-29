//
//  SettingsView.swift
//  InsightRun
//
//  Settings view
//

import SwiftUI

struct SettingsView: View {
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        NavigationStack {
            List {
                // Appearance Section
                Section {
                    Picker("Apparence", selection: Bindable(themeManager).selectedTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Label(theme.rawValue, systemImage: theme.icon)
                                .tag(theme)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Apparence")
                } footer: {
                    Text("Choisissez le thème de l'application. Le mode Système s'adapte automatiquement à vos réglages iOS.")
                }

                // App Information Section
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Build")
                        Spacer()
                        Text("1")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("À propos")
                }
            }
            .navigationTitle("Paramètres")
        }
        .preferredColorScheme(themeManager.selectedTheme.colorScheme)
    }
}

#Preview {
    SettingsView()
        .environment(ThemeManager())
}
