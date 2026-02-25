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

    @StateObject private var manager = BatchIndexationManager.shared
    @State private var indexationTask: Task<Void, Never>?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient matching app style
                LinearGradient(
                    colors: [
                        Color.blue.opacity(0.05),
                        Color(.systemBackground)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                // Main content based on state
                VStack(spacing: 32) {
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
            // Auto-dismiss on cancelled state
            if newState == .cancelled {
                dismiss()
            }
        }
        .sheet(isPresented: $manager.needsConsent) {
            AIConsentSheet(
                onConsent: {
                    manager.needsConsent = false
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
        VStack(spacing: 24) {
            // Animated icon
            ZStack {
                Circle()
                    .fill(Color.irCardBackground)
                    .frame(width: 100, height: 100)
                    .shadow(color: Color.irShadowStrong, radius: 10, y: 5)

                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 40))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolEffect(.pulse, options: .repeating)
            }

            // Title
            Text(String(localized: "Analyzing workouts...", comment: "Loading title during indexation"))
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(Color.irTextPrimary)

            // Progress bar
            VStack(spacing: 12) {
                ProgressView(value: manager.progress)
                    .progressViewStyle(.linear)
                    .tint(.blue)
                    .scaleEffect(x: 1, y: 2, anchor: .center)

                // Progress text
                HStack {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(Color.irTextSecondary)

                    Spacer()

                    if case .loading = manager.state, manager.totalBatches > 0 {
                        Text("\(manager.currentBatch) / \(manager.totalBatches)")
                            .font(.caption)
                            .foregroundStyle(Color.irTextSecondary)
                    }
                }
            }
            .padding(.horizontal, 32)

            // Cancel button
            Button(action: {
                indexationTask?.cancel()
                manager.cancel()
            }) {
                Text(String(localized: "Cancel", comment: "Cancel button during indexation"))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Color.irError.opacity(0.9)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)
        }
    }

    // MARK: - Success State View

    private var successStateView: some View {
        VStack(spacing: 24) {
            // Success icon with animation
            ZStack {
                Circle()
                    .fill(.green.opacity(0.15))
                    .frame(width: 120, height: 120)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.green.gradient)
                    .symbolEffect(.bounce)
            }

            // Success message
            VStack(spacing: 8) {
                Text(String(localized: "Profile Updated!", comment: "Success title after indexation"))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.irTextPrimary)

                Text(String(localized: "Your athletic profile has been successfully updated with your latest workouts.", comment: "Success message after indexation"))
                    .font(.body)
                    .foregroundStyle(Color.irTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // Continue button
            Button(action: {
                dismiss()
            }) {
                Text(String(localized: "Continue", comment: "Continue button after successful indexation"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)
        }
    }

    // MARK: - Error State View

    private var errorStateView: some View {
        VStack(spacing: 24) {
            // Error icon
            ZStack {
                Circle()
                    .fill(.orange.opacity(0.15))
                    .frame(width: 100, height: 100)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.orange.gradient)
            }

            // Error message
            VStack(spacing: 8) {
                Text(String(localized: "Update Failed", comment: "Error title when indexation fails"))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.irTextPrimary)

                if case .failed(let errorMessage) = manager.state {
                    Text(errorMessage)
                        .font(.body)
                        .foregroundStyle(Color.irTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }

            // Open Settings button (when HealthKit access is needed)
            if !HealthKitManager.shared.isHealthDataAvailable || !HealthKitManager.shared.isHealthKitAuthorized {
                Button(action: {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "gear")
                        Text(String(localized: "Open Settings", comment: "Button to open app settings for HealthKit access"))
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.blue)
                }
                .padding(.top, 4)
            }

            // Action buttons
            VStack(spacing: 12) {
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
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text(String(localized: "Retry", comment: "Retry button after indexation failure"))
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Cancel button
                Button(action: {
                    dismiss()
                }) {
                    Text(String(localized: "Cancel", comment: "Cancel button after indexation failure"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.irTextSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.irCardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)
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
