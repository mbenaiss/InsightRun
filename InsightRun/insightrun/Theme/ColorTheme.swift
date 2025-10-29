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

    /// Background color for cards - adapts to light/dark mode
    /// Light: White | Dark: Dark gray
    static let irCardBackground = Color("CardBackground", bundle: nil)

    /// Surface color for elevated elements
    /// Light: Light gray | Dark: Very dark gray
    static let irSurface = Color("Surface", bundle: nil)

    /// Primary accent color with adaptive brightness
    /// Light: Vibrant blue | Dark: Lighter blue for better visibility
    static let irPrimaryAccent = Color("PrimaryAccent", bundle: nil)
}

// MARK: - Theme Guidelines
/*
 # InsightRun Color Theme System

 ## Apple Human Interface Guidelines Compliance

 This app follows Apple's recommendations for supporting Light and Dark modes:

 ### System Colors (Preferred)
 Use these whenever possible - they automatically adapt:
 - `.primary` - Primary text
 - `.secondary` - Secondary text
 - `.tertiary` - Tertiary text
 - `.blue`, `.green`, `.red`, etc. - System colors with gradients

 ### Materials (Preferred for Backgrounds)
 - `.ultraThinMaterial` - Used for cards and overlays
 - `.thinMaterial` - For lighter backgrounds
 - `.regularMaterial`, `.thickMaterial` - For more opacity

 ### Custom Adaptive Colors
 Use the colors defined in Assets.xcassets/Colors/:
 - `Color.irCardBackground` - For card backgrounds
 - `Color.irSurface` - For elevated surfaces
 - `Color.irPrimaryAccent` - For primary accent elements

 ### Best Practices
 1. **Never use** `Color.white` or `Color.black` directly
 2. **Always use** semantic colors like `.primary`, `.secondary`
 3. **Prefer** `.ultraThinMaterial` for glass morphism effects
 4. **Test** your UI in both Light and Dark modes
 5. **Use** `.foregroundStyle()` instead of `.foregroundColor()`

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
     .foregroundStyle(.primary) // ✅ Adapts automatically

 VStack {
     // Content
 }
 .background(.ultraThinMaterial) // ✅ Adapts automatically

 Circle()
     .fill(Color.irCardBackground) // ✅ Uses adaptive color from Assets
 ```
 */
