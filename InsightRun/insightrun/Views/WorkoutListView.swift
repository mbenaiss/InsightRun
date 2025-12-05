//
//  WorkoutListView.swift
//  InsightRun
//
//  Main screen displaying list of running workouts
//  Featuring iOS 26 Liquid Glass design
//

import SwiftUI

struct WorkoutListView: View {
    @StateObject private var healthKitViewModel = WorkoutListViewModel()
    @StateObject private var unifiedViewModel = UnifiedWorkoutViewModel()
    @State private var showingAIAssistant = false
    @State private var showInitialPaywall = false
    @State private var isLoadingMetrics = false
    @State private var currentYearWorkouts: [WorkoutModel] = []
    @State private var workoutsMetrics: [UUID: WorkoutMetrics] = [:]
    @State private var showIndexationBanner = false
    @State private var showIndexationSheet = false
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var revenueCatManager: RevenueCatManager
    @ObservedObject private var remoteConfig = RemoteConfigService.shared
    @ObservedObject private var stravaAuth = StravaAuthService.shared

    // Use unified workouts if Strava is enabled and available (HealthKit + Strava), fallback to HealthKit only
    private var viewModel: WorkoutListViewModel { healthKitViewModel }

    // Check if Strava-only mode is available (Strava enabled + authenticated, but HealthKit not authorized)
    private var isStravaOnlyMode: Bool {
        remoteConfig.isFeatureEnabled(.strava) &&
        stravaAuth.isAuthenticated &&
        viewModel.authorizationStatus != .authorized
    }

    // Check if we can show workouts (either HealthKit authorized OR Strava-only mode)
    private var canShowWorkouts: Bool {
        viewModel.authorizationStatus == .authorized || isStravaOnlyMode
    }

    private var displayWorkouts: [WorkoutModel] {
        // Use unified workouts only if Strava feature is enabled and unified workouts are loaded
        if remoteConfig.isFeatureEnabled(.strava) && !unifiedViewModel.unifiedWorkouts.isEmpty {
            return unifiedViewModel.unifiedWorkouts.map { $0.toWorkoutModel() }
        } else {
            return healthKitViewModel.workouts
        }
    }

    // Grouped workouts for display (unified when Strava enabled, HealthKit otherwise)
    private var displayGroupedWorkouts: [(String, [WorkoutModel])] {
        if remoteConfig.isFeatureEnabled(.strava) && !unifiedViewModel.unifiedWorkouts.isEmpty {
            // Convert unified grouped workouts to WorkoutModel
            return unifiedViewModel.groupedWorkouts.map { (title, unifiedWorkouts) in
                (title, unifiedWorkouts.map { $0.toWorkoutModel() })
            }
        } else {
            return healthKitViewModel.groupedWorkouts
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    // Support 3 modes: HealthKit only, Strava only, or Both
                    if canShowWorkouts {
                        // Mode: HealthKit authorized OR Strava-only mode
                        let hasWorkouts = !viewModel.workouts.isEmpty ||
                            (remoteConfig.isFeatureEnabled(.strava) && !unifiedViewModel.unifiedWorkouts.isEmpty)
                        let isLoading = viewModel.isLoading ||
                            (remoteConfig.isFeatureEnabled(.strava) && unifiedViewModel.isLoading)

                        if isLoading && !hasWorkouts {
                            loadingView
                        } else if !hasWorkouts {
                            emptyView
                        } else {
                            workoutList
                        }
                    } else {
                        // No data source available - show appropriate view
                        switch viewModel.authorizationStatus {
                        case .notDetermined:
                            authorizationView
                        case .denied:
                            deniedView
                        case .authorized:
                            // Should not reach here (canShowWorkouts would be true)
                            emptyView
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
                    // Load HealthKit workouts on first appear if authorized
                    if viewModel.authorizationStatus == .authorized && viewModel.workouts.isEmpty {
                        await viewModel.loadWorkouts()
                    }
                }
                .task {
                    // Load unified workouts when Strava is enabled (works in all 3 modes)
                    // - HealthKit only: unified will contain only HealthKit data
                    // - Strava only: unified will contain only Strava data
                    // - Both: unified will merge HealthKit + Strava
                    if remoteConfig.isFeatureEnabled(.strava) && (canShowWorkouts || stravaAuth.isAuthenticated) {
                        await unifiedViewModel.loadUnifiedWorkouts()
                    }
                }
                .onAppear {
                    // Track workout list viewed when data available
                    if canShowWorkouts {
                        AnalyticsService.shared.trackWorkoutListViewed(totalWorkouts: displayWorkouts.count)

                        // Check if indexation banner should be shown
                        if revenueCatManager.hasAIAccess {
                            let needsRefresh = HistoricalSummaryStorage.shared.needsRefresh()
                            showIndexationBanner = needsRefresh
                        }
                    }
                }

                // Floating AI Button - Only for users with AI access (subscribers or TestFlight), only on list view
                if canShowWorkouts &&
                   !displayWorkouts.isEmpty &&
                   revenueCatManager.hasAIAccess {
                    Button(action: {
                        Task {
                            // Open AI assistant directly
                            // Indexation is handled via IndexationBannerView or SettingsView
                            await loadRecentWorkoutsForAI()
                            showingAIAssistant = true
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
        .sheet(isPresented: $showIndexationSheet) {
            HistoricalIndexationSheet()
        }
    }

    // MARK: - Helper Functions

    private func loadRecentWorkoutsForAI() async {
        isLoadingMetrics = true

        // Get last 10 workouts for AI context (much faster than loading entire year)
        // Use displayWorkouts to support all 3 modes (HealthKit only, Strava only, Both)
        let last10 = Array(displayWorkouts.prefix(10))
        currentYearWorkouts = last10

        print("📊 WorkoutListView: Loading metrics for last \(last10.count) workouts for AI context")

        // Load metrics for last 10 workouts only
        await withTaskGroup(of: (UUID, WorkoutMetrics?).self) { group in
            for workout in last10 {
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
                    .fill(Color.irCardBackground)
                    .frame(width: 120, height: 120)
                    .shadow(color: .black.opacity(0.1), radius: 20, y: 10)

                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.blue.gradient)
            }

            VStack(spacing: 12) {
                Text(String(localized: "Connect Your Data", comment: "Data source connection title"))
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(String(localized: "Connect at least one data source to see your running workouts.", comment: "Data source connection description"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 16) {
                // HealthKit button (red with HealthKit icon)
                Button {
                    Task {
                        await viewModel.requestAuthorization()
                    }
                } label: {
                    HStack {
                        Image(systemName: "heart.text.square.fill")
                        Text(String(localized: "Connect HealthKit", comment: "HealthKit permission button"))
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: Color.red.opacity(0.3), radius: 10, y: 5)
                }

                // Strava button (only if feature enabled)
                if remoteConfig.isFeatureEnabled(.strava) {
                    Button {
                        Task {
                            try? await stravaAuth.authenticate()
                        }
                    } label: {
                        HStack {
                            StravaIconView(size: 20, color: .white)
                            Text(String(localized: "Connect Strava", comment: "Strava connection button"))
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(hex: "FC5200").gradient)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: Color(hex: "FC5200").opacity(0.3), radius: 10, y: 5)
                    }
                }
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
                        .background(Color.irPrimaryAccent.gradient)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: Color.irPrimaryAccent.opacity(0.3), radius: 10, y: 5)
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
                            .foregroundStyle(Color.irPrimaryAccent)
                    }
                }
                .padding()
                .background(Color.irCardBackground)
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
                    .background(Color.irWarning.gradient)
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
                // Indexation banner for premium users who need to refresh their profile
                if showIndexationBanner && revenueCatManager.hasAIAccess {
                    IndexationBannerView(
                        onSyncTapped: {
                            AnalyticsService.shared.trackIndexationBannerSyncTapped()
                            showIndexationBanner = false
                            showIndexationSheet = true
                        },
                        onDismiss: {
                            AnalyticsService.shared.trackIndexationBannerDismissed()
                            showIndexationBanner = false
                        }
                    )
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .onAppear {
                        // Track banner shown (only once when it appears)
                        AnalyticsService.shared.trackIndexationBannerShown()
                    }
                }

                // Subscription CTA for non-subscribers (hide for TestFlight and subscribers)
                if !revenueCatManager.hasAIAccess {
                    subscriptionCTACard
                        .padding(.horizontal)
                        .padding(.top, 8)
                }

                // Grouped workout list by month
                ForEach(displayGroupedWorkouts, id: \.0) { groupTitle, groupWorkouts in
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
                            .onAppear {
                                // INFINITE SCROLL: Load more when user reaches near the end
                                // Only for HealthKit workouts (unified workouts load all at once)
                                if !remoteConfig.isFeatureEnabled(.strava) || unifiedViewModel.unifiedWorkouts.isEmpty {
                                    if workout.id == viewModel.workouts.dropLast(10).last?.id {
                                        Task {
                                            await viewModel.loadMoreWorkouts()
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                // Loading indicator for pagination
                if viewModel.isLoadingMore {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text(String(localized: "Loading more workouts...", comment: "Pagination loading indicator"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding()
                }

                // End of list indicator
                if !viewModel.hasMoreWorkouts && !displayWorkouts.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.green)
                            Text(String(localized: "All workouts loaded", comment: "End of list indicator"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding()
                }
            }
            .padding(.bottom, 20)
        }
        .refreshable {
            await viewModel.refresh()
            // Also refresh unified workouts when Strava is enabled
            if remoteConfig.isFeatureEnabled(.strava) {
                await unifiedViewModel.refresh()
            }
        }
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
                        colors: [Color.irPrimaryAccent, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
        .background(Color.irCardBackground)
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

            HStack(spacing: 0) {
                VStack(alignment: .center, spacing: 4) {
                    Text(viewModel.formatDistance(stats.totalDistance))
                        .font(.headline)
                        .foregroundStyle(Color.irPrimaryAccent)
                    Text(String(localized: "Distance", comment: "Distance stat label"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Divider()
                    .frame(height: 30)

                VStack(alignment: .center, spacing: 4) {
                    Text(viewModel.formatDuration(stats.totalDuration))
                        .font(.headline)
                        .foregroundStyle(Color.irSuccess)
                    Text(String(localized: "Time", comment: "Time stat label"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Divider()
                    .frame(height: 30)

                VStack(alignment: .center, spacing: 4) {
                    Text(viewModel.formatPace(stats.averagePace))
                        .font(.headline)
                        .foregroundStyle(Color.irWarning)
                    Text(String(localized: "Avg Pace", comment: "Average pace stat label"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
            .background(Color.irCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
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
                .foregroundStyle(Color.irPrimaryAccent.gradient)

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
                .foregroundStyle(Color.irPrimaryAccent.gradient)
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
