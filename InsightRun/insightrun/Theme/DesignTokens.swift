//
//  DesignTokens.swift
//  InsightRun
//
//  Centralized design tokens for consistent spacing, sizing, and styling
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
}

// MARK: - Corner Radius

enum Radius {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
}

// MARK: - Card Style ViewModifier

struct CardStyle: ViewModifier {
    var padding: CGFloat = Spacing.lg
    var cornerRadius: CGFloat = Radius.xl

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
        padding: CGFloat = Spacing.lg,
        cornerRadius: CGFloat = Radius.xl
    ) -> some View {
        modifier(CardStyle(padding: padding, cornerRadius: cornerRadius))
    }

    /// Container style for the metric detail sheet — matches the pulse-ring design
    /// (deep card background + 0.5pt border + xl radius). Apply on already-padded
    /// content; this modifier does not add internal padding.
    func detailCard() -> some View {
        background(Color.irCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xl)
                    .strokeBorder(Color.irBorder, lineWidth: 0.5)
            )
    }
}
