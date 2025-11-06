//
//  HistoricalIndexationView.swift
//  InsightRun
//
//  Dedicated indexation screen with informative UI and animations
//

import SwiftUI

struct HistoricalIndexationView: View {
    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @StateObject private var manager = HistoricalIndexationManager.shared
    @State private var animateSymbol = false
    @State private var showDetails = false

    // MARK: - Configuration

    let reason: IndexationReason
    let onComplete: () -> Void

    enum IndexationReason {
        case initial
        case refresh
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background gradient - Match AI Assistant theme
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.15),
                    Color.cyan.opacity(0.1),
                    Color(.systemBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Accent gradient for visual depth
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.08),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Main content
            VStack(spacing: 32) {
                Spacer()

                // Icon with animation
                iconView

                // Title
                Text(titleText)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)

                // Description
                Text(descriptionText)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                // Progress section
                if manager.state != .idle && manager.state != .completed && manager.state != .failed {
                    progressView
                    loaderView
                }

                // Error message
                if let errorMessage = manager.errorMessage {
                    errorView(message: errorMessage)
                }

                // Completion message
                if manager.state == .completed {
                    completionView
                }

                Spacer()

            }
            .padding()
        }
        .interactiveDismissDisabled(isIndexing)
        .onChange(of: manager.state) { _, newState in
            // Auto-dismiss after completion or error
            switch newState {
            case .completed:
                // Show success checkmark for 1.5s before dismissing
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    dismiss()
                }
            case .failed:
                // Show error for 1s before dismissing and opening chat
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    dismiss()
                    // Open chat even after failure (retry button will be shown)
                    onComplete()
                }
            default:
                break
            }
        }
        .task {
            // Start indexation automatically
            if manager.state == .idle {
                do {
                    try await manager.performIndexation()
                    onComplete()
                } catch {
                    print("❌ HistoricalIndexationView: Indexation failed: \(error)")
                    // onComplete() will be called in onChange when state becomes .failed
                }
            }
        }
    }

    // MARK: - Subviews

    private var iconView: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 120, height: 120)

            // Icon
            Image(systemName: iconName)
                .font(.system(size: 50))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, .white.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .symbolEffect(.pulse, options: .repeating, value: animateSymbol)
        }
        .onAppear {
            animateSymbol = true
        }
    }

    private var progressView: some View {
        VStack(spacing: 16) {
            // Progress bar
            VStack(spacing: 8) {
                ProgressView(value: manager.progress)
                    .progressViewStyle(.linear)
                    .tint(.blue)
                    .scaleEffect(x: 1, y: 2, anchor: .center)

                // Progress text
                HStack {
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    if manager.state == .indexing && manager.totalWorkouts > 0 {
                        Text("\(manager.currentWorkout) / \(manager.totalWorkouts)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 32)

            // Estimated time
            if manager.state == .indexing || manager.state == .generating {
                Text(estimatedTimeText)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)

            VStack(spacing: 4) {
                Text(String(localized: "Failed to index your data", comment: "Error title when indexation fails"))
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
        }
        .padding()
        .background(Color(.systemBackground).opacity(0.5))
        .cornerRadius(16)
        .padding(.horizontal, 32)
    }

    private var completionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
                .symbolEffect(.bounce, value: manager.state == .completed)

            Text(completionText)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
        }
    }

    private var loaderView: some View {
        VStack(spacing: 16) {
            if manager.state == .preparing || manager.state == .indexing || manager.state == .generating {
                // Animated loader
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(.blue)
                            .frame(width: 8, height: 8)
                            .scaleEffect(animateSymbol ? 1.0 : 0.6)
                            .animation(
                                Animation.easeInOut(duration: 0.6)
                                    .repeatForever()
                                    .delay(Double(index) * 0.15),
                                value: animateSymbol
                            )
                    }
                }
            }
        }
        .onAppear {
            animateSymbol = true
        }
    }

    // MARK: - Computed Properties

    private var isIndexing: Bool {
        manager.state == .preparing || manager.state == .indexing || manager.state == .generating
    }

    private var iconName: String {
        switch manager.state {
        case .idle, .preparing:
            return "brain.head.profile"
        case .indexing:
            return "chart.line.uptrend.xyaxis"
        case .generating:
            return "wand.and.stars"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .retrying:
            return "arrow.clockwise"
        }
    }

    private var titleText: String {
        switch reason {
        case .initial:
            return String(localized: "Setting up your AI Coach", comment: "Title for initial indexation")
        case .refresh:
            return String(localized: "Refreshing your training data", comment: "Title for refresh indexation")
        }
    }

    private var descriptionText: String {
        switch reason {
        case .initial:
            return String(localized: "We're analyzing your training history to provide personalized insights. This will only happen once.", comment: "Description for initial indexation")
        case .refresh:
            return String(localized: "Updating your training analysis with the latest data to keep your insights accurate.", comment: "Description for refresh indexation")
        }
    }

    private var statusText: String {
        switch manager.state {
        case .idle:
            return String(localized: "Ready", comment: "Status: ready")
        case .preparing:
            return String(localized: "Preparing...", comment: "Status: preparing")
        case .indexing:
            return String(localized: "Indexing workouts...", comment: "Status: indexing")
        case .generating:
            return String(localized: "Generating AI insights...", comment: "Status: generating")
        case .completed:
            return String(localized: "Completed", comment: "Status: completed")
        case .failed:
            return String(localized: "Failed", comment: "Status: failed")
        case .retrying:
            return String(localized: "Retrying...", comment: "Status: retrying")
        }
    }

    private var estimatedTimeText: String {
        switch manager.state {
        case .preparing, .indexing:
            return String(localized: "Estimated time: 10-15 seconds", comment: "Estimated time for indexing")
        case .generating:
            return String(localized: "Estimated time: 5-10 seconds", comment: "Estimated time for generating")
        default:
            return ""
        }
    }

    private var completionText: String {
        switch reason {
        case .initial:
            return String(localized: "Your AI Coach is ready! 🎉\nStart asking questions about your training.", comment: "Completion message for initial indexation")
        case .refresh:
            return String(localized: "Your training data has been updated! ✅", comment: "Completion message for refresh indexation")
        }
    }
}

// MARK: - Preview

#Preview {
    HistoricalIndexationView(reason: .initial) {
        print("Indexation completed")
    }
}
