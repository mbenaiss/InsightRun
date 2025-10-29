//
//  ThemeManager.swift
//  InsightRun
//
//  Manages app appearance (Light/Dark/System)
//

import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "Système"
    case light = "Clair"
    case dark = "Sombre"

    var id: String { rawValue }

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
            self.selectedTheme = .system
        }
    }
}
