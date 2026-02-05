//
//  ThemeManager.swift
//  InsightRun
//
//  Manages app appearance (Light/Dark/System)
//

import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .system:
            return String(localized: "System", comment: "System theme option")
        case .light:
            return String(localized: "Light", comment: "Light theme option")
        case .dark:
            return String(localized: "Dark", comment: "Dark theme option")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    var icon: String {
        switch self {
        case .system:
            return "circle.lefthalf.filled"
        case .light:
            return "sun.max.fill"
        case .dark:
            return "moon.fill"
        }
    }
}

@Observable
class ThemeManager {
    var selectedTheme: AppTheme {
        didSet {
            UserDefaults.standard.set(selectedTheme.rawValue, forKey: "selectedTheme")
        }
    }

    init() {
        // Load saved theme or default to system
        if let savedTheme = UserDefaults.standard.string(forKey: "selectedTheme"),
           let theme = AppTheme(rawValue: savedTheme) {
            self.selectedTheme = theme
        } else {
            // Migration: handle old French rawValues
            if let oldSaved = UserDefaults.standard.string(forKey: "selectedTheme") {
                switch oldSaved {
                case "Système": self.selectedTheme = .system
                case "Clair": self.selectedTheme = .light
                case "Sombre": self.selectedTheme = .dark
                default: self.selectedTheme = .system
                }
                // Re-save with new key
                UserDefaults.standard.set(self.selectedTheme.rawValue, forKey: "selectedTheme")
            } else {
                self.selectedTheme = .system
            }
        }
    }
}
