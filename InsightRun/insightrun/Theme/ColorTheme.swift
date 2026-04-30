//
//  ColorTheme.swift
//  InsightRun
//
//  Color theme system with support for Light/Dark modes
//  Following Apple Human Interface Guidelines
//

import SwiftUI

extension Color {
    // MARK: - Custom Adaptive Colors

    /// App background color - main screen background
    /// Light: #EBEBF0 (medium light gray) | Dark: #000000 (black)
    static let irBackgroundApp = Color("BackgroundApp", bundle: nil)

    /// Background color for cards - adapts to light/dark mode
    /// Light: #FFFFFF (white) | Dark: #2D2D2D (dark gray)
    static let irCardBackground = Color("CardBackground", bundle: nil)

    /// Surface color for elevated elements
    /// Light: #F5F5F7 (soft gray) | Dark: #1C1C1C (very dark gray)
    static let irSurface = Color("Surface", bundle: nil)

    /// Primary accent color with adaptive brightness
    /// Light: #007AFF (iOS blue) | Dark: #64B0FF (lighter blue for better visibility)
    static let irPrimaryAccent = Color("PrimaryAccent", bundle: nil)

    /// AI accent color — lime green used for any AI-powered UI element
    /// (Coach IA pill, coaching glyph, AI CTA buttons). #96FF70.
    static let irAIAccent = Color("AIAccent", bundle: nil)

    /// AI accent secondary color — lavender used as the gradient end-stop
    /// when pairing with `irAIAccent`. #B48DFF.
    static let irAIAccentSecondary = Color("AIAccentSecondary", bundle: nil)

    // MARK: - Text Colors

    /// Primary text color - main readable text
    /// Light: #1C1E21 (soft black) | Dark: #FFFFFF (white)
    static let irTextPrimary = Color("TextPrimary", bundle: nil)

    /// Secondary text color - less prominent text
    /// Light: #8E8E93 (iOS secondary label gray) | Dark: #B0B3B8 (light gray)
    static let irTextSecondary = Color("TextSecondary", bundle: nil)

    // MARK: - Border & Dividers

    /// Border color for elements
    /// Light: #E4E4E7 (light gray) | Dark: #3A3A3C (dark gray)
    static let irBorder = Color("Border", bundle: nil)

    // MARK: - Semantic Colors

    /// Success state color
    /// Light: #34C759 (iOS green) | Dark: #30D158 (lighter green)
    static let irSuccess = Color("Success", bundle: nil)

    /// Warning state color
    /// Light: #FF9500 (iOS orange) | Dark: #FF9F0A (lighter orange)
    static let irWarning = Color("Warning", bundle: nil)

    /// Error state color
    /// Light: #FF3B30 (iOS red) | Dark: #FF453A (lighter red)
    static let irError = Color("Error", bundle: nil)

    // MARK: - Shadow Colors

    /// Adaptive shadow color for cards and elevated elements
    /// Light: black 8% opacity | Dark: white 6% opacity
    static let irShadow = Color("Shadow", bundle: nil)

    /// Stronger adaptive shadow for prominent elements
    /// Light: black 12% opacity | Dark: white 9% opacity
    static let irShadowStrong = Color("ShadowStrong", bundle: nil)
}

// MARK: - Theme Guidelines
/*
 # InsightRun Color Theme System

 ## Apple Human Interface Guidelines Compliance

 This app follows Apple's recommendations for supporting Light and Dark modes:

 ### Custom Adaptive Colors (Preferred)
 Always use InsightRun's `ir*` colors for consistency:
 - `Color.irTextPrimary` instead of `.primary`
 - `Color.irTextSecondary` instead of `.secondary`
 - `.blue`, `.green`, `.red`, etc. - System colors with gradients (OK for accents)

 ### Materials (Preferred for Overlays)
 - `.ultraThinMaterial` - For toolbars and overlay headers
 - `.thinMaterial` - For suggestion bars and floating panels
 - `.regularMaterial`, `.thickMaterial` - For more opacity

 ### Shadows (Adaptive)
 - `Color.irShadow` - Light shadow for cards
 - `Color.irShadowStrong` - Stronger shadow for prominent elements

 ### Color Definitions
 All colors defined in Assets.xcassets/Colors/:

 **Backgrounds:**
 - `Color.irBackgroundApp` - For main app background (#EBEBF0 light)
 - `Color.irCardBackground` - For card backgrounds (#FFFFFF light)
 - `Color.irSurface` - For elevated surfaces (#F5F5F7 light)

 **Accent:**
 - `Color.irPrimaryAccent` - For primary accent elements (#007AFF light)

 **Text:**
 - `Color.irTextPrimary` - For primary text (#1C1E21 light)
 - `Color.irTextSecondary` - For secondary text (#8E8E93 light)

 **Borders:**
 - `Color.irBorder` - For borders and dividers (#E4E4E7 light)

 **Semantic:**
 - `Color.irSuccess` - For success states (#34C759 light)
 - `Color.irWarning` - For warning states (#FF9500 light)
 - `Color.irError` - For error states (#FF3B30 light)

 ### Best Practices
 1. **Never use** `Color.white` or `Color.black` directly
 2. **Always use** `Color.ir*` colors — not `.primary`/`.secondary`
 3. **Use** `.ultraThinMaterial` for overlay headers, `.thinMaterial` for floating panels
 4. **Use** `Color.irShadow`/`Color.irShadowStrong` for shadows — not `.black.opacity()`
 5. **Use** `.foregroundStyle()` instead of `.foregroundColor()`
 6. **Test** your UI in both Light and Dark modes

 ### Testing Dark Mode
 - In SwiftUI Preview: Use `.preferredColorScheme(.dark)`
 - In Simulator: Settings → Developer → Dark Appearance
 - In Xcode: Environment Overrides button in Debug bar

 ### Automatic Mode Detection
 The app automatically detects and responds to system appearance changes.
 No additional code needed - SwiftUI handles this automatically!

 Example:
 ```swift
 Text("Hello")
     .foregroundStyle(Color.irTextPrimary) // ✅ Adapts automatically

 VStack {
     // Content
 }
 .background(.ultraThinMaterial) // ✅ Adapts automatically

 Circle()
     .fill(Color.irCardBackground) // ✅ Uses adaptive color from Assets
 ```
 */
