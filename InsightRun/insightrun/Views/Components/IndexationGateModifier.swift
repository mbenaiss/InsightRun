//
//  IndexationGateModifier.swift
//  InsightRun
//
//  ViewModifier that presents the HistoricalIndexationSheet when needed
//  and retries an action after indexation completes.
//

import SwiftUI

struct IndexationGateModifier: ViewModifier {
    @Binding var needsIndexation: Bool
    var onComplete: (() async -> Void)?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $needsIndexation) {
                HistoricalIndexationSheet()
            }
            .onChange(of: needsIndexation) { _, newValue in
                if !newValue, let action = onComplete {
                    Task { await action() }
                }
            }
    }
}

extension View {
    func indexationGate(
        isPresented: Binding<Bool>,
        onComplete: (() async -> Void)? = nil
    ) -> some View {
        modifier(IndexationGateModifier(
            needsIndexation: isPresented,
            onComplete: onComplete
        ))
    }
}
