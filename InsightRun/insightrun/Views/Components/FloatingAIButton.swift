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
        // Only show if user has AI access (subscriber or TestFlight)
        if revenueCatManager.hasAIAccess {
            Button(action: {
                Task {
                    await loadContextAndShowAssistant()
                }
            }) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.irPrimaryAccent, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 60, height: 60)
                        .shadow(color: Color.irPrimaryAccent.opacity(0.4), radius: 12, y: 6)

                    if isLoading || contextProvider.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
            }
            .disabled(isLoading || contextProvider.isLoading)
            .padding(.trailing, 20)
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
