//
//  WorkoutListView.swift
//  InsightRun
//
//  Main screen displaying list of running workouts
//  Featuring iOS 26 Liquid Glass design
//

import SwiftUI

struct WorkoutListView: View {
    @StateObject private var viewModel = WorkoutListViewModel()
    @State private var showingAIAssistant = false
    @State private var showInitialPaywall = false
    @State private var isLoadingMetrics = false
    @State private var currentYearWorkouts: [WorkoutModel] = []
    @State private var workoutsMetrics: [UUID: WorkoutMetrics] = [:]
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var revenueCatManager: RevenueCatManager

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    switch viewModel.authorizationStatus {
                    case .notDetermined:
                        authorizationView
                    case .denied:
                        deniedView
                    case .authorized:
                        if viewModel.isLoading && viewModel.workouts.isEmpty {
                            loadingView
                        } else if viewModel.workouts.isEmpty {
                            emptyView
                        } else {
                            workoutList
                        }
                    }
                }
                .navigationTitle(String(localized: "Workouts", comment: "Main list screen title"))
                .navigationBarTitleDisplayMode(.large)
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        // Refresh authorization status when app becomes active
                        viewModel.refreshAuthorizationStatus()
                    }
                }
                .onChange(of: viewModel.authorizationStatus) { oldValue, newValue in
                    // Show paywall when HealthKit is authorized for the first time
                    if oldValue == .notDetermined && newValue == .authorized &&
                       !revenueCatManager.isSubscriptionActive &&
                       !revenueCatManager.hasSeenInitialPaywall {
                        showInitialPaywall = true
                    }
                }
                .onChange(of: revenueCatManager.isSubscriptionActive) { _, isActive in
                    // Refresh view when subscription status changes
                    if viewModel.authorizationStatus == .authorized {
                        Task {
                            await viewModel.refresh()
                        }
                    }
                }
                .task {
                    // Load workouts on first appear if authorized (regardless of subscription)
                    if viewModel.authorizationStatus == .authorized && viewModel.workouts.isEmpty {
                        await viewModel.loadWorkouts()
                    }
                }
                .onAppear {
                    // Track workout list viewed when authorized
                    if viewModel.authorizationStatus == .authorized {
                        AnalyticsService.shared.trackWorkoutListViewed(totalWorkouts: viewModel.workouts.count)
                    }
                }

                // Floating AI Button - Only for users with AI access (subscribers or TestFlight), only on list view
                if viewModel.authorizationStatus == .authorized &&
                   !viewModel.workouts.isEmpty &&
                   revenueCatManager.hasAIAccess {
                    Button(action: {
                        Task {
                            await loadCurrentYearWorkoutsWithMetrics()
                            showingAIAssistant = true
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.blue, .cyan],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 60, height: 60)
                                .shadow(color: .blue.opacity(0.4), radius: 12, y: 6)

                            if isLoadingMetrics {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .disabled(isLoadingMetrics)
                    .padding(.trailing, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .sheet(isPresented: $showingAIAssistant) {
            WorkoutAIAssistantView(
                mode: .recentWorkouts(currentYearWorkouts, workoutsMetrics),
                isPresented: $showingAIAssistant
            )
        }
        .fullScreenCover(isPresented: $showInitialPaywall) {
            SubscriptionPaywallView(isInitialFlow: true)
                .environmentObject(revenueCatManager)
        }
    }

    // MARK: - Helper Functions

    private func loadCurrentYearWorkoutsWithMetrics() async {
        isLoadingMetrics = true

        // Get current year workouts
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let startOfYear = calendar.date(from: DateComponents(year: currentYear, month: 1, day: 1))!

        currentYearWorkouts = viewModel.workouts.filter { workout in
            calendar.component(.year, from: workout.startDate) == currentYear
        }

        // Load metrics for all current year workouts
        await withTaskGroup(of: (UUID, WorkoutMetrics?).self) { group in
            for workout in currentYearWorkouts {
                group.addTask {
                    do {
                        let metrics = try await HealthKitManager.shared.fetchWorkoutMetrics(for: workout)
                        return (workout.id, metrics)
                    } catch {
                        print("Error loading metrics for workout \(workout.id): \(error)")
                        return (workout.id, nil)
                    }
                }
            }

            // Collect results
            for await (id, metrics) in group {
                if let metrics = metrics {
                    workoutsMetrics[id] = metrics
                }
            }
        }

        isLoadingMetrics = false
    }

    // MARK: - Authorization View

    private var authorizationView: some View {
        VStack(spacing: 32) {
            Spacer()

            // Icon with Liquid Glass effect
            ZStack {
                Circle()
                    .fill(.thinMaterial)
                    .frame(width: 120, height: 120)
                    .shadow(color: .black.opacity(0.1), radius: 20, y: 10)

                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.red.gradient)
            }

            VStack(spacing: 12) {
                Text(String(localized: "Health Data Access", comment: "HealthKit permission request title"))
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(String(localized: "This app needs access to your running workouts from HealthKit to display your history.", comment: "HealthKit permission request description"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                Task {
                    await viewModel.requestAuthorization()
                }
            } label: {
                Text(String(localized: "Grant Access", comment: "HealthKit permission button"))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .blue.opacity(0.3), radius: 10, y: 5)
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)

            Spacer()
        }
        .padding()
    }

    // MARK: - Locked Workouts Preview (Non-Subscribers)

    private var lockedWorkoutsPreview: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Global stats card
                combinedStatsCard
                    .padding(.horizontal)
                    .padding(.top, 8)

                // Premium unlock CTA
                VStack(spacing: 16) {
                    // Premium icon
                    Image(systemName: "crown.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.yellow.gradient)

                    VStack(spacing: 8) {
                        Text(String(localized: "Unlock Your Full Training History", comment: "Locked workouts preview title"))
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)

                        Text(String(localized: "Subscribe to access all your workouts, AI coaching, and advanced analytics", comment: "Locked workouts preview description"))
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }

                    // CTA Button
                    Button {
                        showInitialPaywall = true
                    } label: {
                        HStack {
                            Image(systemName: "crown.fill")
                            Text(String(localized: "Subscribe Now", comment: "Subscribe CTA button"))
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue.gradient)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .blue.opacity(0.3), radius: 10, y: 5)
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 8)

                    // Restore purchases link
                    Button {
                        Task {
                            do {
                                try await revenueCatManager.restorePurchases()
                            } catch {
                                print("Error restoring purchases: \(error.localizedDescription)")
                            }
                        }
                    } label: {
                        Text(String(localized: "Restore Purchases", comment: "Restore purchases button"))
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
                .padding(.horizontal)
                .padding(.top, 16)
            }
            .padding(.bottom, 20)
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    // MARK: - Denied View

    private var deniedView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.orange.gradient)

            VStack(spacing: 12) {
                Text(String(localized: "Access Denied", comment: "HealthKit access denied title"))
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(String(localized: "Please enable access in Settings → Privacy → Health → Insight Run", comment: "HealthKit access denied instructions"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text(String(localized: "Open Settings", comment: "Settings button"))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.orange.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .padding()
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)

            Text(String(localized: "Loading...", comment: "Loading indicator"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue.gradient)

            VStack(spacing: 12) {
                Text(String(localized: "No Workouts", comment: "Empty state title"))
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(String(localized: "No running workouts found.\nStart running to see your stats here!", comment: "Empty state description"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Workout List

    private var workoutList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // Combined stats card
                if !viewModel.workouts.isEmpty {
                    combinedStatsCard
                        .padding(.horizontal)
                        .padding(.top, 8)
                }

                // Subscription CTA for non-subscribers
                if !revenueCatManager.isSubscriptionActive {
                    subscriptionCTACard
                        .padding(.horizontal)
                        .padding(.top, 8)
                }

                // Grouped workout list by month
                ForEach(viewModel.groupedWorkouts, id: \.0) { groupTitle, groupWorkouts in
                    VStack(alignment: .leading, spacing: 12) {
                        // Month header with stats
                        monthHeaderView(title: groupTitle, workouts: groupWorkouts)
                            .padding(.horizontal)
                            .padding(.top, 8)

                        // Workouts in this month
                        ForEach(groupWorkouts) { workout in
                            NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                                WorkoutRowView(workout: workout)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.bottom, 20)
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    // MARK: - Combined Stats Card

    private var combinedStatsCard: some View {
        VStack(spacing: 16) {
            // Main title
            Text(String(localized: "Overall Stats", comment: "Combined stats card title"))
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Global stats section
            VStack(spacing: 12) {
                StatsRow(icon: "number", label: String(localized: "Workouts", comment: "Number of workouts stat"), value: "\(viewModel.workoutCount)")
                StatsRow(icon: "ruler", label: String(localized: "Total Distance", comment: "Total distance stat"), value: viewModel.formatTotalDistance())
                StatsRow(icon: "clock", label: String(localized: "Total Time", comment: "Total duration stat"), value: viewModel.formatTotalDuration())
                StatsRow(icon: "gauge", label: String(localized: "Avg Pace", comment: "Average pace stat"), value: viewModel.formatAveragePace())
                StatsRow(icon: "figure.run", label: String(localized: "Avg Distance", comment: "Average distance stat"), value: viewModel.formatAverageDistance())
            }

            // Records section
            if viewModel.longestRun != nil || viewModel.fastestRun != nil {
                Divider()

                Text(String(localized: "Records", comment: "Records section title"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 12) {
                    if let longest = viewModel.longestRun {
                        HStack {
                            Image(systemName: "trophy.fill")
                                .foregroundStyle(.yellow.gradient)
                                .frame(width: 24)
                            Text(String(localized: "Longest Run", comment: "Longest run record label"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.1f km", (longest.distance ?? 0) / 1000.0))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                    }

                    if let fastest = viewModel.fastestRun,
                       let pace = fastest.averagePace,
                       let distance = fastest.distance,
                       distance >= 5000 {
                        HStack {
                            Image(systemName: "bolt.fill")
                                .foregroundStyle(.orange.gradient)
                                .frame(width: 24)
                            Text(String(localized: "Fastest Run", comment: "Fastest run record label"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(viewModel.formatPace(pace) + " /km - " + String(format: "%.1f km", distance / 1000.0))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
    }

    // MARK: - Subscription CTA Card

    private var subscriptionCTACard: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 8) {
                Text(String(localized: "Unlock AI Coaching", comment: "Subscription CTA title"))
                    .font(.headline)
                    .fontWeight(.bold)

                Text(String(localized: "Get personalized insights and coaching powered by AI", comment: "Subscription CTA description"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                showInitialPaywall = true
            } label: {
                HStack {
                    Image(systemName: "sparkles")
                    Text(String(localized: "Subscribe Now", comment: "Subscribe CTA button"))
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
    }

    // MARK: - Month Header View

    private func monthHeaderView(title: String, workouts: [WorkoutModel]) -> some View {
        let stats = viewModel.stats(for: workouts)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Text(String(format: String(localized: "%lld workouts", comment: "Month header workout count"), stats.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if stats.count >= 3 {
                // Show stats only if there are 3 or more workouts
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.formatDistance(stats.totalDistance))
                            .font(.headline)
                            .foregroundStyle(.blue)
                        Text(String(localized: "Distance", comment: "Distance stat label"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Divider()
                        .frame(height: 30)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.formatDuration(stats.totalDuration))
                            .font(.headline)
                            .foregroundStyle(.green)
                        Text(String(localized: "Time", comment: "Time stat label"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Divider()
                        .frame(height: 30)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.formatPace(stats.averagePace))
                            .font(.headline)
                            .foregroundStyle(.orange)
                        Text(String(localized: "Avg Pace", comment: "Average pace stat label"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

// MARK: - Stat Item Component

struct StatItem: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue.gradient)

            Text(value)
                .font(.title3)
                .fontWeight(.semibold)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Stats Row Component

struct StatsRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.blue.gradient)
                .frame(width: 24)

            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
    }
}

#Preview {
    WorkoutListView()
}
