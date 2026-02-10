//
//  ColorTheme.swift
//  InsightRun
//
//  Color theme system with support for Light/Dark modes
//  Inspired by Whoop & Bevel design language
//

import SwiftUI

extension Color {
    // MARK: - Custom Adaptive Colors

    /// App background color - main screen background
    /// Light: #F5F5F7 (clean light gray) | Dark: #000000 (pure black, OLED)
    static let irBackgroundApp = Color("BackgroundApp", bundle: nil)

    /// Background color for cards
    /// Light: #FFFFFF (white) | Dark: #1C1C1E (elevated dark)
    static let irCardBackground = Color("CardBackground", bundle: nil)

    /// Surface color for elevated elements
    /// Light: #EEEEF0 (subtle gray) | Dark: #0D0D0F (near-black)
    static let irSurface = Color("Surface", bundle: nil)

    /// Primary accent color - teal inspired by Whoop/Bevel
    /// Light: #00B4D8 (teal) | Dark: #00D4AA (green-teal)
    static let irPrimaryAccent = Color("PrimaryAccent", bundle: nil)

    // MARK: - Text Colors

    /// Primary text color
    /// Light: #111827 (near-black) | Dark: #F9FAFB (near-white)
    static let irTextPrimary = Color("TextPrimary", bundle: nil)

    /// Secondary text color
    /// Light: #6B7280 (medium gray) | Dark: #9CA3AF (soft gray)
    static let irTextSecondary = Color("TextSecondary", bundle: nil)

    // MARK: - Border & Dividers

    /// Border color
    /// Light: #E5E7EB (light gray) | Dark: #2D2D30 (dark border)
    static let irBorder = Color("Border", bundle: nil)

    // MARK: - Semantic Colors

    /// Success state color (emerald)
    /// Light: #10B981 | Dark: #34D399
    static let irSuccess = Color("Success", bundle: nil)

    /// Warning state color (amber)
    /// Light: #F59E0B | Dark: #FBBF24
    static let irWarning = Color("Warning", bundle: nil)

    /// Error state color
    /// Light: #EF4444 | Dark: #F87171
    static let irError = Color("Error", bundle: nil)

    // MARK: - Shadow Colors

    /// Light shadow (transparent in dark mode for flat look)
    static let irShadow = Color("Shadow", bundle: nil)

    /// Stronger shadow (transparent in dark mode)
    static let irShadowStrong = Color("ShadowStrong", bundle: nil)
}

// MARK: - Theme Guidelines
/*
 # InsightRun Color Theme System
 # Inspired by Whoop & Bevel design language

 ## Design Principles
 - Dark mode: Pure black backgrounds, subtle borders instead of shadows
 - Light mode: Clean whites and light grays with minimal shadows
 - Accent: Teal/green tones for a distinctive, premium feel
 - Typography: .rounded design for numbers, clean hierarchy

 ## Color Definitions (Assets.xcassets/Colors/)

 **Backgrounds:**
 - `Color.irBackgroundApp` - Main background (#F5F5F7 light / #000000 dark)
 - `Color.irCardBackground` - Card surfaces (#FFFFFF light / #1C1C1E dark)
 - `Color.irSurface` - Elevated surfaces (#EEEEF0 light / #0D0D0F dark)

 **Accent:**
 - `Color.irPrimaryAccent` - Primary teal (#00B4D8 light / #00D4AA dark)

 **Text:**
 - `Color.irTextPrimary` - Primary text (#111827 light / #F9FAFB dark)
 - `Color.irTextSecondary` - Secondary text (#6B7280 light / #9CA3AF dark)

 **Borders:**
 - `Color.irBorder` - Borders/dividers (#E5E7EB light / #2D2D30 dark)

 **Semantic:**
 - `Color.irSuccess` - Success (#10B981 light / #34D399 dark)
 - `Color.irWarning` - Warning (#F59E0B light / #FBBF24 dark)
 - `Color.irError` - Error (#EF4444 light / #F87171 dark)

 ## Best Practices
 1. Never use `Color.white` or `Color.black` directly
 2. Always use `Color.ir*` colors
 3. In dark mode, prefer borders over shadows for depth
 4. Use `.foregroundStyle()` instead of `.foregroundColor()`
 5. Use `.rounded` design for numeric displays
 */
