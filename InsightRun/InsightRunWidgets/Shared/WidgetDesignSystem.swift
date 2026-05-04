//
//  WidgetDesignSystem.swift
//  InsightRunWidgets
//
//  Design tokens used by the InsightRun widgets, mirroring the main app's
//  Insight Run Design System where applicable. Keep this in sync with
//  insightrun/Theme/DesignSystem.swift — this file exists because widget
//  targets can't directly reference files from the app target.
//

import SwiftUI
import UIKit

// MARK: - Colors (DS tokens for widgets)

extension Color {
    /// Widget surface background (#0F0F12 — slightly darker than the main card token,
    /// matches the iOS widget convention of pure-black-on-wallpaper).
    static let wgSurface         = Color(uiColor: UIColor(rgb: 0x0F0F12))
    /// Slightly lifted surface used for elevated tiles inside a widget.
    static let wgCard            = Color(uiColor: UIColor(rgb: 0x1A1A1D))
    static let wgBorder          = Color.white.opacity(0.08)
    static let wgBorderStrong    = Color.white.opacity(0.14)

    static let wgTextPrimary     = Color.white
    static let wgTextSecondary   = Color(uiColor: UIColor(rgb: 0xEBEBF5, alpha: 0.60))
    static let wgTextTertiary    = Color(uiColor: UIColor(rgb: 0xEBEBF5, alpha: 0.38))

    /// Lime accent — DS `--ir-accent` in the dark variant (#96FF70).
    static let wgAccent          = Color(uiColor: UIColor(rgb: 0x96FF70))
    static let wgSuccess         = Color(uiColor: UIColor(rgb: 0x30D158))
    static let wgWarning         = Color(uiColor: UIColor(rgb: 0xFF9F0A))
    static let wgError           = Color(uiColor: UIColor(rgb: 0xFF453A))
    static let wgPurple          = Color(uiColor: UIColor(rgb: 0xBF5AF2))
}

private extension UIColor {
    convenience init(rgb: UInt32, alpha: CGFloat = 1.0) {
        self.init(
            red:   CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >>  8) & 0xFF) / 255.0,
            blue:  CGFloat( rgb        & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}

// MARK: - Typography

enum WGFont {
    /// 9.5 / 700 / 0.10em uppercase — widget eyebrows.
    static let eyebrow = Font.system(size: 10, weight: .bold)
    /// 9 / 700 / 0.12em uppercase — micro labels under values.
    static let microLabel = Font.system(size: 9, weight: .bold)

    /// Big number with SF Pro Rounded + tabular nums.
    static func num(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        Font.system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    /// Mono digits — used for "4'48", "07:42", etc.
    static func mono(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        Font.system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Tracking

enum WGTracking {
    /// 0.10em on 10pt → 1.0pt
    static let eyebrow: CGFloat = 1.0
    /// 0.12em on 9pt → 1.08pt
    static let microLabel: CGFloat = 1.08
    /// -0.04em scale for hero numbers
    static func numHero(_ size: CGFloat) -> CGFloat { -0.04 * size }
    /// -0.02em for body numbers
    static func numBody(_ size: CGFloat) -> CGFloat { -0.02 * size }
}
