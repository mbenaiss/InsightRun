//
//  DesignTokens.swift
//  InsightRun
//
//  Centralized design tokens for consistent spacing, sizing, and styling
//  Inspired by Whoop & Bevel design language
//

import SwiftUI

// MARK: - Spacing

enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 6
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let base: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 40
}

// MARK: - Corner Radius

enum Radius {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
}

// MARK: - Card Style ViewModifier (border-based, no shadows in dark mode)

struct CardStyle: ViewModifier {
    var padding: CGFloat = Spacing.lg
    var cornerRadius: CGFloat = Radius.xl

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.irCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.irBorder, lineWidth: 0.5)
            )
    }
}

extension View {
    func cardStyle(
        padding: CGFloat = Spacing.lg,
        cornerRadius: CGFloat = Radius.xl
    ) -> some View {
        modifier(CardStyle(padding: padding, cornerRadius: cornerRadius))
    }
}
