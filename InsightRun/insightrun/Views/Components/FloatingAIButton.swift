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
                HStack(spacing: 6) {
                    if isLoading || contextProvider.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.black)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .bold))
                    }

                    Text(String(localized: "AI Coach", comment: "Floating AI button label"))
                        .font(.system(size: 13, weight: .bold))
                        .kerning(-0.1)
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.irAIAccent, Color.irAIAccentSecondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                )
                .shadow(color: Color.irAIAccent.opacity(0.45), radius: 14, y: 6)
            }
            .buttonStyle(.plain)
            .disabled(isLoading || contextProvider.isLoading)
            .accessibilityIdentifier("floating-ai-button")
            .padding(.trailing, 18)
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
        Color.gray.opacity(0.2)
            .ignoresSafeArea()

        FloatingAIButton(showingAIAssistant: .constant(false))
            .environmentObject(RevenueCatManager.shared)
    }
}
