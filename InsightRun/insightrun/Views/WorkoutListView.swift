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
    @ObservedObject private var contextProvider = UnifiedAIContextProvider.shared
    @State private var showInitialPaywall = false
    @State private var showIndexationBanner = false
    @State private var showIndexationSheet = false
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var revenueCatManager: RevenueCatManager
    @ObservedObject private var remoteConfig = RemoteConfigService.shared
    @ObservedObject private var stravaAuth = StravaAuthService.shared
    @ObservedObject private var notificationRouter = NotificationRouter.shared
    @State private var navigationPath = NavigationPath()

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
        // Use unified workouts if available (includes Strava and/or Suunto merge)
        if !unifiedViewModel.unifiedWorkouts.isEmpty {
            return unifiedViewModel.unifiedWorkouts.map { $0.toWorkoutModel() }
        } else {
            return healthKitViewModel.workouts
        }
    }

    // Grouped workouts for display (unified includes Strava and Suunto merge)
    private var displayGroupedWorkouts: [(String, [WorkoutModel])] {
        if !unifiedViewModel.unifiedWorkouts.isEmpty {
            // Convert unified grouped workouts to WorkoutModel
            return unifiedViewModel.groupedWorkouts.map { (title, unifiedWorkouts) in
                (title, unifiedWorkouts.map { $0.toWorkoutModel() })
            }
        } else {
            return healthKitViewModel.groupedWorkouts
        }
    }

    private var hasWorkouts: Bool {
        !viewModel.workouts.isEmpty ||
        (remoteConfig.isFeatureEnabled(.strava) && !unifiedViewModel.unifiedWorkouts.isEmpty)
    }

    private var isLoadingWorkouts: Bool {
        viewModel.isLoading ||
        (remoteConfig.isFeatureEnabled(.strava) && unifiedViewModel.isLoading)
    }

    @ViewBuilder
    private var mainContent: some View {
        if canShowWorkouts {
            if hasWorkouts {
                workoutList
            } else if isLoadingWorkouts || viewModel.errorMessage == nil {
                loadingView
            } else {
                emptyView
            }
        } else {
            switch viewModel.authorizationStatus {
            case .notDetermined:
                authorizationView
            case .denied:
                deniedView
            case .authorized:
                emptyView
            }
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            mainContent
                .navigationTitle(String(localized: "Workouts", comment: "Main list screen title"))
                .navigationBarTitleDisplayMode(.large)
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        viewModel.refreshAuthorizationStatus()
                    }
                }
                .onChange(of: viewModel.authorizationStatus) { oldValue, newValue in
                    if oldValue == .notDetermined && newValue == .authorized &&
                       !revenueCatManager.isSubscriptionActive &&
                       !revenueCatManager.hasSeenInitialPaywall {
                        showInitialPaywall = true
                    }
                }
                .onChange(of: revenueCatManager.isSubscriptionActive) { _, _ in
                    if viewModel.authorizationStatus == .authorized {
                        Task {
                            await viewModel.refresh()
                        }
                    }
                }
                .onChange(of: viewModel.isLoading) { _, isLoading in
                    if !isLoading { updateContextProvider() }
                }
                .onChange(of: unifiedViewModel.isLoading) { _, isLoading in
                    if !isLoading { updateContextProvider() }
                }
                .task(id: viewModel.authorizationStatus) {
                    if viewModel.authorizationStatus == .authorized && viewModel.workouts.isEmpty {
                        await viewModel.loadWorkouts()
                    }
                }
                .task(id: viewModel.authorizationStatus) {
                    if canShowWorkouts || stravaAuth.isAuthenticated {
                        await unifiedViewModel.loadUnifiedWorkouts()
                    }
                }
                .onAppear {
                    if canShowWorkouts {
                        AnalyticsService.shared.trackWorkoutListViewed(totalWorkouts: displayWorkouts.count)
                        if revenueCatManager.hasAIAccess && HealthKitManager.shared.isHealthKitAuthorized {
                            let needsRefresh = HistoricalSummaryStorage.shared.needsRefresh()
                            showIndexationBanner = needsRefresh
                        }
                    }
                    updateContextProvider()
                }
                .onChange(of: notificationRouter.pendingWorkoutUUID) { _, uuid in
                    guard let uuid else { return }
                    navigateToWorkout(uuid: uuid)
                }
                .onChange(of: displayWorkouts) { _, _ in
                    if let uuid = notificationRouter.pendingWorkoutUUID {
                        navigateToWorkout(uuid: uuid)
                    }
                }
                .navigationDestination(for: WorkoutModel.self) { workout in
                    WorkoutDetailView(workout: workout)
                }
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

    private func updateContextProvider() {
        // Get last 10 workouts for AI context
        let last10 = Array(displayWorkouts.prefix(10))
        contextProvider.recentWorkouts = last10
    }

    private func navigateToWorkout(uuid: String) {
        guard let targetUUID = UUID(uuidString: uuid),
              let workout = displayWorkouts.first(where: { $0.id == targetUUID }) else {
            return
        }
        notificationRouter.pendingWorkoutUUID = nil
        navigationPath.append(workout)
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
                    .shadow(color: Color.irShadowStrong, radius: 20, y: 10)

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
                    .foregroundStyle(Color.irTextSecondary)
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
                            .foregroundStyle(Color.irTextSecondary)
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
                .shadow(color: Color.irShadow, radius: 10, y: 5)
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
                    .foregroundStyle(Color.irTextSecondary)
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
                .foregroundStyle(Color.irTextSecondary)
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
                    .foregroundStyle(Color.irTextSecondary)
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
                        ForEach(Array(groupWorkouts.enumerated()), id: \.element.id) { index, workout in
                            NavigationLink(value: workout) {
                                WorkoutRowView(workout: workout)
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityIdentifier("workout-row-\(index)")
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
                                .foregroundStyle(Color.irTextSecondary)
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
                                .foregroundStyle(Color.irTextSecondary)
                        }
                        Spacer()
                    }
                    .padding()
                }
            }
            .padding(.bottom, 20)
        }
        .accessibilityIdentifier("workout-list")
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
                    .foregroundStyle(Color.irTextSecondary)
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
        .shadow(color: Color.irShadow, radius: 10, y: 5)
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
                    .foregroundStyle(Color.irTextSecondary)
            }

            HStack(spacing: 0) {
                VStack(alignment: .center, spacing: 4) {
                    Text(viewModel.formatDistance(stats.totalDistance))
                        .font(.headline)
                        .foregroundStyle(Color.irPrimaryAccent)
                    Text(String(localized: "Distance", comment: "Distance stat label"))
                        .font(.caption2)
                        .foregroundStyle(Color.irTextSecondary)
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
                        .foregroundStyle(Color.irTextSecondary)
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
                        .foregroundStyle(Color.irTextSecondary)
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
                .foregroundStyle(Color.irTextSecondary)
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
                .foregroundStyle(Color.irTextSecondary)

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
