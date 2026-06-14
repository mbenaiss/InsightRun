//
//  HistoricalIndexationSheet.swift
//  InsightRun
//
//  Sheet for historical indexation with simple loading, success, and error states
//

import SwiftUI

struct HistoricalIndexationSheet: View {
    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @ObservedObject private var manager = BatchIndexationManager.shared
    @State private var indexationTask: Task<Void, Never>?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient matching app style
                LinearGradient(
                    colors: [
                        Color.irPrimaryAccent.opacity(0.05),
                        Color.irBackgroundApp
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                // Main content based on state
                VStack(spacing: Spacing.xxl) {
                    Spacer()

                    switch manager.state {
                    case .idle, .loading:
                        loadingStateView
                    case .completed:
                        successStateView
                    case .failed:
                        errorStateView
                    case .cancelled:
                        // Dismiss immediately on cancel
                        EmptyView()
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle(String(localized: "Update Profile", comment: "Navigation title for indexation sheet"))
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isIndexing)
        }
        .onAppear {
            // Reset manager state to allow new indexation
            manager.reset()

            // Start indexation automatically
            indexationTask = Task {
                do {
                    try await manager.startIndexation()
                    // Trigger haptic feedback on success
                    let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
                    impactFeedback.impactOccurred()
                } catch is CancellationError {
                    print("🛑 HistoricalIndexationSheet: Indexation cancelled")
                } catch {
                    print("❌ HistoricalIndexationSheet: Indexation failed: \(error)")
                    // Trigger error haptic feedback
                    let notificationFeedback = UINotificationFeedbackGenerator()
                    notificationFeedback.notificationOccurred(.error)
                }
            }
        }
        .onChange(of: manager.state) { _, newState in
            if newState == .completed {
                HistoricalSummaryStorage.shared.resetBannerDismiss()
            }

            // Auto-dismiss on cancelled state
            if newState == .cancelled {
                dismiss()
            }
        }
        .sheet(isPresented: $manager.needsConsent) {
            AIConsentSheet(
                onConsent: {
                    manager.needsConsent = false
                    indexationTask = Task {
                        do {
                            try await manager.startIndexation()
                            let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
                            impactFeedback.impactOccurred()
                        } catch is CancellationError {
                            print("🛑 HistoricalIndexationSheet: Indexation cancelled")
                        } catch {
                            print("❌ HistoricalIndexationSheet: Indexation failed: \(error)")
                            let notificationFeedback = UINotificationFeedbackGenerator()
                            notificationFeedback.notificationOccurred(.error)
                        }
                    }
                },
                onDecline: {
                    manager.needsConsent = false
                    dismiss()
                }
            )
        }
        .onDisappear {
            // Clean up task if view disappears
            indexationTask?.cancel()
            indexationTask = nil
        }
    }

    // MARK: - Loading State View

    private var loadingStateView: some View {
        VStack(spacing: Spacing.xl) {
            // Animated icon
            ZStack {
                Circle()
                    .fill(Color.irCardBackground)
                    .frame(width: 100, height: 100)
                    .shadow(color: Color.irShadowStrong, radius: 10, y: 5)

                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(IRFont.numLG)
                    .foregroundStyle(LinearGradient.irAIAccent)
                    .symbolEffect(.pulse, options: .repeating)
            }

            // Title
            Text(String(localized: "Analyzing workouts...", comment: "Loading title during indexation"))
                .font(IRFont.title3)
                .foregroundStyle(Color.irTextPrimary)

            // Progress bar
            VStack(spacing: Spacing.md) {
                ProgressView(value: manager.progress)
                    .progressViewStyle(.linear)
                    .tint(Color.irPrimaryAccent)
                    .scaleEffect(x: 1, y: 2, anchor: .center)

                // Progress text
                HStack {
                    Text(statusText)
                        .font(IRFont.caption)
                        .foregroundStyle(Color.irTextSecondary)

                    Spacer()

                    if case .loading = manager.state, manager.totalBatches > 0 {
                        Text("\(manager.currentBatch) / \(manager.totalBatches)")
                            .font(IRFont.caption)
                            .foregroundStyle(Color.irTextSecondary)
                    }
                }
            }
            .padding(.horizontal, Spacing.xxl)

            // Cancel button
            Button(action: {
                indexationTask?.cancel()
                manager.cancel()
            }) {
                Text(String(localized: "Cancel", comment: "Cancel button during indexation"))
                    .font(IRFont.body)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.irTextPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.dash)
                    .background(
                        Color.irError.opacity(0.9)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.top, Spacing.sm)
        }
    }

    // MARK: - Success State View

    private var successStateView: some View {
        VStack(spacing: Spacing.xl) {
            // Success icon with animation
            ZStack {
                Circle()
                    .fill(Color.irSuccess.opacity(0.15))
                    .frame(width: 120, height: 120)

                Image(systemName: "checkmark.circle.fill")
                    .font(IRFont.numLG)
                    .foregroundStyle(Color.irSuccess.gradient)
                    .symbolEffect(.bounce)
            }

            // Success message
            VStack(spacing: Spacing.sm) {
                Text(String(localized: "Profile Updated!", comment: "Success title after indexation"))
                    .font(IRFont.title2)
                    .foregroundStyle(Color.irTextPrimary)

                Text(String(localized: "Your athletic profile has been successfully updated with your latest workouts.", comment: "Success message after indexation"))
                    .font(IRFont.body)
                    .foregroundStyle(Color.irTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xxl)
            }

            // Continue button
            Button(action: {
                dismiss()
            }) {
                Text(String(localized: "Continue", comment: "Continue button after successful indexation"))
                    .font(IRFont.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.irTextOnAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.dash)
                    .background(Color.irPrimaryAccent)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.top, Spacing.sm)
        }
    }

    // MARK: - Error State View

    private var errorStateView: some View {
        VStack(spacing: Spacing.xl) {
            // Error icon
            ZStack {
                Circle()
                    .fill(Color.irWarning.opacity(0.15))
                    .frame(width: 100, height: 100)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(IRFont.numLG)
                    .foregroundStyle(Color.irWarning.gradient)
            }

            // Error message
            VStack(spacing: Spacing.sm) {
                Text(String(localized: "Update Failed", comment: "Error title when indexation fails"))
                    .font(IRFont.title3)
                    .foregroundStyle(Color.irTextPrimary)

                if case .failed(let errorMessage) = manager.state {
                    Text(errorMessage)
                        .font(IRFont.body)
                        .foregroundStyle(Color.irTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.xxl)
                }
            }

            // Open Settings button (when HealthKit access is needed or iOS dialog crashed)
            if !HealthKitManager.shared.isHealthDataAvailable || !HealthKitManager.shared.isHealthKitAuthorized || manager.needsManualHealthKitSetup {
                Button(action: {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "gear")
                        Text(String(localized: "Open Settings", comment: "Button to open app settings for HealthKit access"))
                    }
                    .font(IRFont.body)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.irPrimaryAccent)
                }
                .padding(.top, Spacing.xxs)
            }

            // Action buttons
            VStack(spacing: Spacing.md) {
                // Retry button
                Button(action: {
                    // Track retry tapped
                    if case .failed(let errorMessage) = manager.state {
                        let errorType = String(describing: type(of: errorMessage))
                        AnalyticsService.shared.trackIndexationRetryTapped(previousErrorType: errorType)
                    }

                    indexationTask = Task {
                        do {
                            try await manager.retry()
                            // Trigger haptic feedback on success
                            let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
                            impactFeedback.impactOccurred()
                        } catch is CancellationError {
                            print("🛑 HistoricalIndexationSheet: Indexation cancelled")
                        } catch {
                            print("❌ HistoricalIndexationSheet: Retry failed: \(error)")
                            // Trigger error haptic feedback
                            let notificationFeedback = UINotificationFeedbackGenerator()
                            notificationFeedback.notificationOccurred(.error)
                        }
                    }
                }) {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "arrow.clockwise")
                        Text(String(localized: "Retry", comment: "Retry button after indexation failure"))
                    }
                    .font(IRFont.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.irTextOnAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.dash)
                    .background(Color.irPrimaryAccent)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                    .opacity(manager.retryDisabled ? 0.5 : 1.0)
                }
                .disabled(manager.retryDisabled)

                // Retry info (backoff or max retries)
                if manager.retryDisabled && manager.retryCount >= BatchIndexationManager.maxRetries {
                    Text(String(localized: "Too many attempts. Please try again later.", comment: "Max retry info"))
                        .font(IRFont.caption)
                        .foregroundStyle(Color.irTextSecondary)
                        .multilineTextAlignment(.center)
                } else if manager.retryDisabled {
                    HStack(spacing: Spacing.xxs) {
                        ProgressView()
                            .controlSize(.mini)
                        Text(String(localized: "Waiting before retry...", comment: "Retry backoff info"))
                            .font(IRFont.caption)
                            .foregroundStyle(Color.irTextSecondary)
                    }
                }

                // Cancel / Dismiss button
                Button(action: {
                    dismiss()
                }) {
                    Text(manager.retryCount >= BatchIndexationManager.maxRetries
                        ? String(localized: "Close", comment: "Close button after max indexation retries")
                        : String(localized: "Cancel", comment: "Cancel button after indexation failure"))
                        .font(IRFont.body)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.irTextSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.dash)
                        .background(Color.irCardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                }
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.top, Spacing.sm)
        }
    }

    // MARK: - Computed Properties

    private var isIndexing: Bool {
        manager.state.isActive
    }

    private var statusText: String {
        switch manager.state {
        case .idle:
            return String(localized: "Ready", comment: "Status: ready")
        case .loading(let progress):
            if progress < 0.70 {
                return String(localized: "Analyzing workouts...", comment: "Status: analyzing")
            } else {
                return String(localized: "Generating insights...", comment: "Status: generating insights")
            }
        case .completed:
            return String(localized: "Completed", comment: "Status: completed")
        case .failed:
            return String(localized: "Failed", comment: "Status: failed")
        case .cancelled:
            return String(localized: "Cancelled", comment: "Status: cancelled")
        }
    }
}

// MARK: - Preview

#Preview {
    HistoricalIndexationSheet()
}
