//
//  DesignSystem.swift
//  InsightRun
//
//  Single source of truth for the Insight Run Design System.
//  Pour changer le design system, c'est ICI — pas ailleurs.
//
//  Mode: dark-first (light mode kept for compat). Tokens follow the
//  shared.css schema documented in `Insight Run Design System.html`.
//

import SwiftUI
import UIKit

// MARK: - Helper: adaptive Color from sRGB hex

private extension UIColor {
    nonisolated convenience init(rgb: UInt32, alpha: CGFloat = 1.0) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    /// Adaptive color: hex `0xRRGGBB` per appearance, optional alpha.
    nonisolated static func adaptive(
        light: UInt32,
        dark: UInt32,
        lightAlpha: CGFloat = 1.0,
        darkAlpha: CGFloat = 1.0
    ) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(rgb: dark, alpha: darkAlpha)
                : UIColor(rgb: light, alpha: lightAlpha)
        })
    }

    /// Adaptive color, single hex value reused for both appearances.
    nonisolated static func universal(_ rgb: UInt32, alpha: CGFloat = 1.0) -> Color {
        Color(UIColor(rgb: rgb, alpha: alpha))
    }
}

// MARK: - Colors (DS tokens)

extension Color {
    // MARK: Surfaces — DS `--ir-bg`, `--ir-surface`, `--ir-card`, `--ir-card-2`
    static let irBackgroundApp   = Color.adaptive(light: 0xEBEBF0, dark: 0x000000)
    static let irSurface         = Color.adaptive(light: 0xF5F5F7, dark: 0x0C0C0E)
    static let irCardBackground  = Color.adaptive(light: 0xFFFFFF, dark: 0x141416)
    static let irCard2           = Color.adaptive(light: 0xF5F5F7, dark: 0x1C1C1F)

    // MARK: Accent — DS `--ir-accent` (Lime), `--ir-accent-soft`
    /// Primary accent: iOS green in light, Lime #96FF70 in dark.
    nonisolated static let irPrimaryAccent   = Color.adaptive(light: 0x4FBF35, dark: 0x96FF70)
    /// Soft accent fill (14% alpha).
    static let irAccentSoft      = Color.adaptive(
        light: 0x4FBF35, dark: 0x96FF70,
        lightAlpha: 0.14, darkAlpha: 0.14
    )
    /// AI accent — alias of primary accent in current Lime variant.
    static let irAIAccent        = Color.universal(0x96FF70)
    /// AI gradient end-stop (lavender).
    nonisolated static let irAIAccentSecondary = Color.universal(0xB48DFF)
    /// Expressive purple — DS `--ir-purple` (#BF5AF2).
    static let irPurple          = Color.universal(0xBF5AF2)

    /// Canonical ink for text/icons sitting on an accent fill.
    /// The accent is lime (#96FF70) in both light and dark, so a fixed very-dark
    /// ink keeps AA contrast in every appearance — do not use white/black/text
    /// tokens directly on accent.
    static let irTextOnAccent    = Color.universal(0x0A0E07)

    // MARK: Text — DS `--ir-text`, `--ir-text-2`, `--ir-text-3`
    static let irTextPrimary     = Color.adaptive(light: 0x1C1E21, dark: 0xFFFFFF)
    /// rgba(235,235,245,0.60) in dark.
    static let irTextSecondary   = Color.adaptive(
        light: 0x8E8E93, dark: 0xEBEBF5,
        lightAlpha: 1.0, darkAlpha: 0.60
    )
    /// rgba(235,235,245,0.38) in dark.
    static let irTextTertiary    = Color.adaptive(
        light: 0x38393A, dark: 0xEBEBF5,
        lightAlpha: 0.38, darkAlpha: 0.38
    )

    // MARK: Borders — DS `--ir-border` (0.5pt hairline), `--ir-border-strong`
    static let irBorder          = Color.adaptive(
        light: 0xE4E4E7, dark: 0xFFFFFF,
        lightAlpha: 1.0, darkAlpha: 0.08
    )
    static let irBorderStrong    = Color.adaptive(
        light: 0xCDCDD1, dark: 0xFFFFFF,
        lightAlpha: 1.0, darkAlpha: 0.14
    )

    // MARK: Semantic — DS `--ir-success`, `--ir-warn`, `--ir-error`
    static let irSuccess         = Color.adaptive(light: 0x34C759, dark: 0x30D158)
    static let irWarning         = Color.adaptive(light: 0xFF9500, dark: 0xFF9F0A)
    static let irError           = Color.adaptive(light: 0xFF3B30, dark: 0xFF453A)

    // MARK: Shadows
    static let irShadow          = Color.adaptive(
        light: 0x000000, dark: 0xFFFFFF,
        lightAlpha: 0.08, darkAlpha: 0.06
    )
    static let irShadowStrong    = Color.adaptive(
        light: 0x000000, dark: 0xFFFFFF,
        lightAlpha: 0.12, darkAlpha: 0.09
    )
}

// MARK: - Brand colors (third-party / platform branding, non-adaptive by design)
//
// Official brand hex values — these must stay constant across appearances so
// providers remain recognizable. Use these instead of inline literals.

extension Color {
    static let brandStrava       = Color.universal(0xFC5200)
    static let brandSuunto       = Color.universal(0xE84545)
    static let brandHealthKit    = Color.universal(0xFF6B00)
    static let brandAppleWatch   = Color.universal(0xFF2D55)
    static let brandGarmin       = Color.universal(0x007CC3)
    static let brandPolar        = Color.universal(0xD32F2F)
    static let brandCoros        = Color.universal(0xFF9500)
}

// MARK: - AI gradient token

extension LinearGradient {
    /// Canonical AI gradient: lime accent → lavender end-stop.
    static let irAIAccent = LinearGradient(
        colors: [Color.irPrimaryAccent, Color.irAIAccentSecondary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Animation tokens

enum IRAnimation {
    static let standard = Animation.easeInOut(duration: 0.3)
    static let quick = Animation.easeInOut(duration: 0.2)
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.8)
}

// MARK: - Spacing — DS 4pt grid

enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 6
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    /// Dashboard sections gap (DS `.dash` gap-14).
    static let dash: CGFloat = 14
    static let base: CGFloat = 16
    /// Padding interne card par défaut (DS card padding 18).
    static let cardPadding: CGFloat = 18
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

// MARK: - Corner Radius — DS 8 / 12 / 18 / 24 / 32

enum Radius {
    /// Tags, tuiles imbriquées (DS custom 8px).
    static let xs: CGFloat = 8
    /// Chips, pills, segmented control (DS `--ir-radius-sm`).
    static let sm: CGFloat = 12
    /// Cards par défaut (DS `--ir-radius`).
    static let md: CGFloat = 18
    /// Sheets, hero cards (DS `--ir-radius-lg`).
    static let lg: CGFloat = 24
    /// Hero / shells (DS `--ir-radius-xl`).
    static let xl: CGFloat = 32
}

// MARK: - Typography — DS échelle complète
//
// Familles (DS) :
//   --ir-font     : SF Pro Display/Text (system default)
//   --ir-font-num : SF Pro Rounded — pour valeurs numériques héros
//   --ir-font-mono: SF Mono — allures, dates abrégées, eyebrows numérotés

enum IRFont {
    // MARK: Scaling core
    //
    // Dynamic Type keystone: every style maps a fixed DS base size to a
    // reference `UIFont.TextStyle`, then lets `UIFontMetrics` scale it with the
    // user's accessibility text size. Base sizes below stay identical to the DS
    // spec at the default content size; only the scaling behavior is added.

    private static func scaled(
        size: CGFloat,
        weight: UIFont.Weight,
        relativeTo textStyle: UIFont.TextStyle,
        design: UIFontDescriptor.SystemDesign = .default,
        monospacedDigit: Bool = false
    ) -> Font {
        var base = UIFont.systemFont(ofSize: size, weight: weight)
        if monospacedDigit {
            base = UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        }
        if design != .default, let descriptor = base.fontDescriptor.withDesign(design) {
            base = UIFont(descriptor: descriptor, size: size)
        }
        return Font(UIFontMetrics(forTextStyle: textStyle).scaledFont(for: base))
    }

    // MARK: Échelle textuelle (DS section 03)
    /// 56 / 800 / -0.04em — titres de page (rare).
    static let display          = scaled(size: 56, weight: .heavy, relativeTo: .largeTitle)
    /// 34 / 800 / -0.03em — titre d'écran (Objectifs, Statistiques).
    static let title1           = scaled(size: 34, weight: .heavy, relativeTo: .largeTitle)
    /// 26 / 700 / -0.02em — hero numérique, date du jour.
    static let title2           = scaled(size: 26, weight: .bold, relativeTo: .title1)
    /// 22 / 800 / -0.02em — titre de card hero.
    static let title3           = scaled(size: 22, weight: .heavy, relativeTo: .title2)
    /// 17 / 700 / -0.01em — section dans un screen long.
    static let headline         = scaled(size: 17, weight: .bold, relativeTo: .headline)
    /// 15 / 600 — item principal de liste.
    static let bodyEmphasized   = scaled(size: 15, weight: .semibold, relativeTo: .body)
    /// 14 / 500 — texte courant, descriptions.
    static let body             = scaled(size: 14, weight: .medium, relativeTo: .callout)
    /// 13 / 600 — tabs, boutons secondaires.
    static let footnote         = scaled(size: 13, weight: .semibold, relativeTo: .subheadline)
    /// 12 / 500 — sous-titres, descriptions sous icône.
    static let caption          = scaled(size: 12, weight: .medium, relativeTo: .caption1)
    /// 11 / 700 / 0.12em uppercase — sections, en-têtes numérotés.
    static let eyebrow          = scaled(size: 11, weight: .bold, relativeTo: .caption2)
    /// 10 / 700 / 0.14em uppercase — labels sous KPI, metadata.
    static let microLabel       = scaled(size: 10, weight: .bold, relativeTo: .caption2)

    // MARK: Numéros (SF Pro Rounded — toujours tabular-nums)
    /// 64 / 700 — `.num-xl` (DS).
    static let numXL = scaled(size: 64, weight: .bold, relativeTo: .largeTitle, design: .rounded, monospacedDigit: true)
    /// 44 / 700 — `.num-lg`.
    static let numLG = scaled(size: 44, weight: .bold, relativeTo: .largeTitle, design: .rounded, monospacedDigit: true)
    /// 28 / 700 — `.num-md`.
    static let numMD = scaled(size: 28, weight: .bold, relativeTo: .title1, design: .rounded, monospacedDigit: true)
    /// 18 / 600 — `.num-sm`.
    static let numSM = scaled(size: 18, weight: .semibold, relativeTo: .title3, design: .rounded, monospacedDigit: true)
    /// 14 / 600 — nombres compacts dans les micro-cards.
    static let numXS = scaled(size: 14, weight: .semibold, relativeTo: .callout, design: .rounded, monospacedDigit: true)

    static func numeric(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        scaled(size: size, weight: uiWeight(weight), relativeTo: .body, design: .rounded, monospacedDigit: true)
    }

    // MARK: Mono (SF Mono — allures, eyebrows numérotés)
    static let monoSM = scaled(size: 11, weight: .semibold, relativeTo: .caption2, design: .monospaced)
    static let monoMD = scaled(size: 13, weight: .semibold, relativeTo: .subheadline, design: .monospaced)
    static let monoLG = scaled(size: 18, weight: .semibold, relativeTo: .title3, design: .monospaced, monospacedDigit: true)
    static let monoXL = scaled(size: 22, weight: .semibold, relativeTo: .title2, design: .monospaced, monospacedDigit: true)

    // MARK: Responsive / symbols
    static func text(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        scaled(size: size, weight: uiWeight(weight), relativeTo: .body)
    }

    static func icon(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        scaled(size: size, weight: uiWeight(weight), relativeTo: .body)
    }

    private static func uiWeight(_ weight: Font.Weight) -> UIFont.Weight {
        switch weight {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }

    static func markdownHeader(for level: Int) -> Font {
        switch level {
        case 1: return title2
        case 2: return headline
        case 3: return body
        default: return body
        }
    }
}

// MARK: - Tracking (kerning) presets — convert em → pt

enum IRTracking {
    static let display: CGFloat = -2.24      // -0.04em × 56pt
    static let title1: CGFloat = -1.02       // -0.03em × 34pt
    static let title2: CGFloat = -0.52       // -0.02em × 26pt
    static let title3: CGFloat = -0.44       // -0.02em × 22pt
    static let headline: CGFloat = -0.17     // -0.01em × 17pt
    static let eyebrow: CGFloat = 1.32       // 0.12em × 11pt — uppercase eyebrow
    static let microLabel: CGFloat = 1.4     // 0.14em × 10pt — uppercase micro
    /// -0.03em on numerical heroes (apply to font size in use).
    static func num(_ size: CGFloat) -> CGFloat { -0.03 * size }
}

// MARK: - Card style modifier

struct CardStyle: ViewModifier {
    var padding: CGFloat = Spacing.cardPadding
    var cornerRadius: CGFloat = Radius.md

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.irCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: Color.irShadow, radius: 10, y: 5)
    }
}

extension View {
    func cardStyle(
        padding: CGFloat = Spacing.cardPadding,
        cornerRadius: CGFloat = Radius.md
    ) -> some View {
        modifier(CardStyle(padding: padding, cornerRadius: cornerRadius))
    }

    /// DS card container (no internal padding, just bg + 0.5pt border + 18pt radius).
    func detailCard() -> some View {
        background(Color.irCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .strokeBorder(Color.irBorder, lineWidth: 0.5)
            )
    }
}
