//
//  FloatingAIButton.swift
//  InsightRun
//
//  Unified floating AI button component that appears across all tabs.
//  Loads contextual data from UnifiedAIContextProvider.
//

import SwiftUI

struct FloatingAIButton: View {
    @Binding var showingAIAssistant: Bool
    @StateObject private var contextProvider = UnifiedAIContextProvider.shared
    @EnvironmentObject private var revenueCatManager: RevenueCatManager
    @State private var isLoading = false

    var body: some View {
        if revenueCatManager.hasAIAccess {
            Button {
                Task { await loadContextAndShowAssistant() }
            } label: {
                HStack(spacing: Spacing.xs) {
                    if isLoading || contextProvider.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.irTextOnAccent)
                    } else {
                        Image(systemName: "sparkles")
                            .font(IRFont.footnote.weight(.bold))
                    }

                    Text(String(localized: "AI Coach", comment: "Floating AI button label"))
                        .font(IRFont.footnote.weight(.bold))
                        .kerning(-0.1)
                }
                .foregroundStyle(Color.irTextOnAccent)
                .padding(.horizontal, Spacing.dash)
                .padding(.vertical, Spacing.md)
                .background(Capsule().fill(LinearGradient.irAIAccent))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.irBorderStrong, lineWidth: 0.5)
                )
                .shadow(color: Color.irPrimaryAccent.opacity(0.45), radius: 14, y: 6)
            }
            .buttonStyle(.plain)
            .disabled(isLoading || contextProvider.isLoading)
            .accessibilityIdentifier("floating-ai-button")
            .padding(.trailing, Spacing.cardPadding)
            .padding(.bottom, 100)
        }
    }

    private func loadContextAndShowAssistant() async {
        isLoading = true

        // Load all data if not already loaded
        if !contextProvider.hasData {
            await contextProvider.loadAllData()
        }

        isLoading = false
        showingAIAssistant = true
    }
}

#Preview {
    ZStack(alignment: .bottomTrailing) {
        Color.irTextTertiary.opacity(0.5)
            .ignoresSafeArea()

        FloatingAIButton(showingAIAssistant: .constant(false))
            .environmentObject(RevenueCatManager.shared)
    }
}
