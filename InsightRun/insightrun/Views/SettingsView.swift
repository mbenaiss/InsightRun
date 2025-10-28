//
//  SettingsView.swift
//  InsightRun
//
//  Settings view
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
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
        }
    }
}

#Preview {
    SettingsView()
}
