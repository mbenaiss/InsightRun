//
//  WorkoutListView.swift
//  InsightRun
//
//  Pulse-Ring redesign: editorial hero, month summary card with mini bar
//  chart, type filter chips, dense session cards.
//

import SwiftUI

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? date
    }
}

struct WorkoutListView: View {
    @StateObject private var healthKitViewModel = WorkoutListViewModel()
    @StateObject private var unifiedViewModel = UnifiedWorkoutViewModel()
    @ObservedObject private var contextProvider = UnifiedAIContextProvider.shared
    @State private var showInitialPaywall = false
    @State private var showIndexationBanner = false
    @State private var showIndexationSheet = false
    @State private var selectedMonth: Date = Calendar.current.startOfMonth(for: Date())
    @State private var isSearching: Bool = false
    @State private var searchText: String = ""
    @FocusState private var searchFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var revenueCatManager: RevenueCatManager
    @ObservedObject private var remoteConfig = RemoteConfigService.shared
    @ObservedObject private var stravaAuth = StravaAuthService.shared
    @ObservedObject private var notificationRouter = NotificationRouter.shared
    @State private var navigationPath = NavigationPath()

    private var viewModel: WorkoutListViewModel { healthKitViewModel }

    private var isStravaOnlyMode: Bool {
        remoteConfig.isFeatureEnabled(.strava) &&
        stravaAuth.isAuthenticated &&
        viewModel.authorizationStatus != .authorized
    }

    private var canShowWorkouts: Bool {
        viewModel.authorizationStatus == .authorized || isStravaOnlyMode
    }

    private var displayWorkouts: [WorkoutModel] {
        if !unifiedViewModel.unifiedWorkouts.isEmpty {
            return unifiedViewModel.unifiedWorkouts.map { $0.toWorkoutModel() }
        } else {
            return healthKitViewModel.workouts
        }
    }

    private var displayGroupedWorkouts: [(String, [WorkoutModel])] {
        if !unifiedViewModel.unifiedWorkouts.isEmpty {
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
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .navigationBar)
                .background(Color.irBackgroundApp)
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
                    if viewModel.authorizationStatus == .authorized {
                        // One-shot prompt for the new iOS 18 effort score types,
                        // for users who authorized before the migration.
                        if #available(iOS 18.0, *) {
                            await HealthKitManager.shared.requestEffortAuthorizationIfNeeded()
                        }
                        if viewModel.workouts.isEmpty {
                            await viewModel.loadWorkouts()
                        }
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
                            if let summary = HistoricalSummaryStorage.shared.load() {
                                showIndexationBanner = summary.needsRefresh && HistoricalSummaryStorage.shared.shouldShowBanner()
                            } else {
                                showIndexationBanner = false
                            }
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
                    WorkoutDetailView(workout: workout, allWorkouts: displayWorkouts)
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

    private func filterWorkouts(_ workouts: [WorkoutModel]) -> [WorkoutModel] {
        let q = searchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if isSearching && !q.isEmpty {
            // Search bypasses the month filter and looks across all workouts
            let f = DateFormatter()
            f.locale = Locale.current
            f.dateFormat = "EEE d MMMM yyyy"
            return workouts.filter { w in
                let dateStr = f.string(from: w.startDate).lowercased()
                let context = w.isIndoor ? "tapis indoor" : "plein air outdoor"
                return dateStr.contains(q)
                    || w.sourceName.lowercased().contains(q)
                    || context.contains(q)
            }
        }

        let cal = Calendar.current
        return workouts.filter {
            cal.isDate($0.startDate, equalTo: selectedMonth, toGranularity: .month)
        }
    }

    private var monthLabel: String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "MMMM yyyy"
        return f.string(from: selectedMonth).capitalized
    }

    private func adjustMonth(by delta: Int) {
        let cal = Calendar.current
        if let next = cal.date(byAdding: .month, value: delta, to: selectedMonth) {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedMonth = cal.startOfMonth(for: next)
            }
        }
    }

    private var canGoForward: Bool {
        let cal = Calendar.current
        let today = cal.startOfMonth(for: Date())
        return selectedMonth < today
    }

    private var availableYears: [Int] {
        let cal = Calendar.current
        let years = Set(displayWorkouts.map { cal.component(.year, from: $0.startDate) })
        return years.sorted(by: >)
    }

    private func selectYear(_ year: Int) {
        let cal = Calendar.current
        var components = cal.dateComponents([.year, .month], from: selectedMonth)
        components.year = year
        guard let date = cal.date(from: components) else { return }
        let today = cal.startOfMonth(for: Date())
        withAnimation(.easeInOut(duration: 0.15)) {
            selectedMonth = min(cal.startOfMonth(for: date), today)
        }
    }

    // MARK: - Authorization View

    private var authorizationView: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.irCardBackground)
                    .frame(width: 120, height: 120)
                    .shadow(color: Color.irShadowStrong, radius: 20, y: 10)

                Image(systemName: "figure.run.circle.fill")
                    .font(IRFont.display)
                    .foregroundStyle(Color.irPrimaryAccent.gradient)
            }

            VStack(spacing: Spacing.md) {
                Text(String(localized: "Connect Your Data", comment: "Data source connection title"))
                    .font(IRFont.title2.weight(.semibold))

                Text(String(localized: "Connect at least one data source to see your running workouts.", comment: "Data source connection description"))
                    .font(IRFont.body)
                    .foregroundStyle(Color.irTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xxl)
            }

            VStack(spacing: Spacing.base) {
                Button {
                    Task {
                        await viewModel.requestAuthorization()
                    }
                } label: {
                    HStack {
                        Image(systemName: "heart.text.square.fill")
                        Text(String(localized: "Connect HealthKit", comment: "HealthKit permission button"))
                    }
                    .font(IRFont.headline)
                    .foregroundStyle(Color.irCardBackground)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    .shadow(color: Color.red.opacity(0.3), radius: 10, y: 5)
                }

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
                        .font(IRFont.headline)
                        .foregroundStyle(Color.irCardBackground)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(hex: "FC5200").gradient)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                        .shadow(color: Color(hex: "FC5200").opacity(0.3), radius: 10, y: 5)
                    }
                }
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.top, Spacing.base)

            Spacer()
        }
        .padding()
    }

    // MARK: - Denied View

    private var deniedView: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(IRFont.numXL)
                .foregroundStyle(Color.irWarning.gradient)

            VStack(spacing: Spacing.md) {
                Text(String(localized: "Access Denied", comment: "HealthKit access denied title"))
                    .font(IRFont.title2.weight(.semibold))

                Text(String(localized: "Please enable access in Settings → Privacy → Health → Insight Run", comment: "HealthKit access denied instructions"))
                    .font(IRFont.body)
                    .foregroundStyle(Color.irTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xxl)
            }

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text(String(localized: "Open Settings", comment: "Settings button"))
                    .font(IRFont.headline)
                    .foregroundStyle(Color.irTextPrimary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.irWarning.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            }
            .padding(.horizontal, Spacing.xxl)

            Spacer()
        }
        .padding()
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: Spacing.lg) {
            ProgressView()
                .scaleEffect(1.5)

            Text(String(localized: "Loading...", comment: "Loading indicator"))
                .font(IRFont.body)
                .foregroundStyle(Color.irTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.irBackgroundApp)
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            Image(systemName: "figure.run.circle.fill")
                .font(IRFont.numLG)
                .foregroundStyle(Color.irPrimaryAccent.gradient)

            VStack(spacing: Spacing.md) {
                Text(String(localized: "No Workouts", comment: "Empty state title"))
                    .font(IRFont.title2.weight(.semibold))

                Text(String(localized: "No running workouts found.\nStart running to see your stats here!", comment: "Empty state description"))
                    .font(IRFont.body)
                    .foregroundStyle(Color.irTextSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding()
        .background(Color.irBackgroundApp)
    }

    // MARK: - Workout List (Pulse-Ring layout)

    private var workoutList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.dash) {
                heroSection

                if showIndexationBanner && revenueCatManager.hasAIAccess {
                    IndexationBannerView(
                        onSyncTapped: {
                            AnalyticsService.shared.trackIndexationBannerSyncTapped()
                            showIndexationBanner = false
                            showIndexationSheet = true
                        },
                        onDismiss: {
                            AnalyticsService.shared.trackIndexationBannerDismissed()
                            HistoricalSummaryStorage.shared.dismissBanner()
                            showIndexationBanner = false
                        }
                    )
                    .onAppear {
                        AnalyticsService.shared.trackIndexationBannerShown()
                    }
                }

                if !revenueCatManager.hasAIAccess {
                    subscriptionCTACard
                }

                let visibleWorkouts = filterWorkouts(displayWorkouts)
                if !visibleWorkouts.isEmpty {
                    if !isSearching {
                        monthSummaryCard(workouts: visibleWorkouts)
                    }

                    VStack(spacing: Spacing.sm) {
                        ForEach(Array(visibleWorkouts.enumerated()), id: \.element.id) { index, workout in
                            NavigationLink(value: workout) {
                                WorkoutRowView(workout: workout)
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityIdentifier("workout-row-\(index)")
                        }
                    }
                } else {
                    if isSearching && !searchText.isEmpty {
                        searchEmptyState
                    } else {
                        monthEmptyState
                    }
                }
            }
            .padding(.horizontal, Spacing.cardPadding)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.lg)
        }
        .background(Color.irBackgroundApp)
        .accessibilityIdentifier("workout-list")
        .refreshable {
            await viewModel.refresh()
            if remoteConfig.isFeatureEnabled(.strava) {
                await unifiedViewModel.refresh()
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(String(localized: "Workouts", comment: "Workout list large title"))
                .font(IRFont.title1.weight(.heavy))
                .kerning(-0.5)
                .foregroundStyle(Color.irTextPrimary)

            if isSearching {
                searchBar
            } else {
                HStack(spacing: Spacing.sm) {
                    monthPicker
                    Text("·")
                        .font(IRFont.footnote)
                        .foregroundStyle(Color.irTextSecondary.opacity(0.5))
                    Text(String(format: String(localized: "%lld sessions", comment: "Workout list session count"), filterWorkouts(displayWorkouts).count))
                        .font(IRFont.footnote)
                        .foregroundStyle(Color.irTextSecondary)
                    Spacer()
                    searchToggleButton
                }
            }
        }
    }

    private var searchToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isSearching = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                searchFocused = true
            }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(IRFont.caption.weight(.semibold))
                .foregroundStyle(Color.irTextSecondary)
                .frame(width: 28, height: 28)
                .background(Capsule().fill(Color.irCardBackground))
                .overlay(Capsule().strokeBorder(Color.irBorder, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("workout-list-search")
    }

    private var searchBar: some View {
        HStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(IRFont.caption.weight(.semibold))
                    .foregroundStyle(Color.irTextSecondary.opacity(0.7))
                TextField(
                    String(localized: "Search by date or source", comment: "Workout list search placeholder"),
                    text: $searchText
                )
                .font(IRFont.footnote)
                .foregroundStyle(Color.irTextPrimary)
                .focused($searchFocused)
                .submitLabel(.search)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(IRFont.footnote)
                            .foregroundStyle(Color.irTextSecondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(Capsule().fill(Color.irCardBackground))
            .overlay(Capsule().strokeBorder(Color.irBorder, lineWidth: 0.5))

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isSearching = false
                    searchText = ""
                    searchFocused = false
                }
            } label: {
                Text(String(localized: "Cancel", comment: "Cancel search button"))
                    .font(IRFont.footnote.weight(.semibold))
                    .foregroundStyle(Color.irTextSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var monthPicker: some View {
        HStack(spacing: Spacing.sm) {
            Button {
                adjustMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(IRFont.microLabel.weight(.bold))
                    .foregroundStyle(Color.irTextSecondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)

            Menu {
                ForEach(availableYears, id: \.self) { year in
                    Button {
                        selectYear(year)
                    } label: {
                        if Calendar.current.component(.year, from: selectedMonth) == year {
                            Label(String(year), systemImage: "checkmark")
                        } else {
                            Text(String(year))
                        }
                    }
                }
            } label: {
                Text(monthLabel)
                    .font(IRFont.caption.weight(.semibold))
                    .foregroundStyle(Color.irTextPrimary)
                    .frame(minWidth: 88)
                    .contentShape(Rectangle())
            }

            Button {
                adjustMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(IRFont.microLabel.weight(.bold))
                    .foregroundStyle(canGoForward ? Color.irTextSecondary : Color.irTextSecondary.opacity(0.3))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .disabled(!canGoForward)
        }
        .padding(.horizontal, Spacing.xxs)
        .padding(.vertical, Spacing.xxs)
        .background(
            Capsule().fill(Color.irCardBackground)
        )
        .overlay(
            Capsule().strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Filter chips

    // MARK: - Month summary card

    private struct WeekVolume {
        let weekNumber: Int
        let kilometers: Double
    }

    private func monthSummaryCard(workouts: [WorkoutModel]) -> some View {
        let totalDistance = workouts.compactMap { $0.distance }.reduce(0, +)
        let totalDuration = workouts.map { $0.duration }.reduce(0, +)
        let totalCalories = workouts.compactMap { $0.totalEnergyBurned }.reduce(0, +)
        let totalElevation = workouts.compactMap { $0.elevationGain }.reduce(0, +)
        let paces = workouts.compactMap { $0.averagePace }
        let avgPace = paces.isEmpty ? nil : paces.reduce(0, +) / Double(paces.count)
        let weeks = weeklyVolumes(in: workouts)
        let lastIndex = max(0, weeks.count - 1)

        return VStack(alignment: .leading, spacing: Spacing.dash) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(String(localized: "Volume", comment: "Month volume label"))
                        .font(IRFont.eyebrow)
                        .foregroundStyle(Color.irTextSecondary)
                    HStack(alignment: .lastTextBaseline, spacing: Spacing.xxs) {
                        Text(formattedKilometers(totalDistance))
                            .font(IRFont.numMD.weight(.heavy))
                            .kerning(-0.5)
                            .foregroundStyle(Color.irTextPrimary)
                        Text("km")
                            .font(IRFont.footnote.weight(.semibold))
                            .foregroundStyle(Color.irTextSecondary)
                    }
                }
                Spacer()
                weeklyMiniBars(weeks: weeks, lastIndex: lastIndex)
            }

            Divider().background(Color.irBorder)

            HStack(spacing: 0) {
                summaryStat(
                    label: String(localized: "Time", comment: "Weekly time label"),
                    value: formatHoursMinutes(totalDuration)
                )
                summaryStat(
                    label: String(localized: "Avg Pace", comment: "Average pace stat label"),
                    value: formatPaceShort(avgPace),
                    showsLeftBorder: true
                )
                summaryStat(
                    label: "D+",
                    value: formatElevation(totalElevation),
                    showsLeftBorder: true
                )
                summaryStat(
                    label: String(localized: "Calories", comment: "Calories stat label"),
                    value: formatCalories(totalCalories),
                    showsLeftBorder: true
                )
            }
        }
        .padding(Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }

    private var monthEmptyState: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "figure.run.circle")
                .font(IRFont.title3)
                .foregroundStyle(Color.irTextSecondary.opacity(0.5))
            Text(String(localized: "No sessions this month", comment: "Empty state when selected month has no workouts"))
                .font(IRFont.footnote)
                .foregroundStyle(Color.irTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var searchEmptyState: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(IRFont.title3)
                .foregroundStyle(Color.irTextSecondary.opacity(0.5))
            Text(String(localized: "No results", comment: "Empty state when search returns no workouts"))
                .font(IRFont.footnote)
                .foregroundStyle(Color.irTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func summaryStat(label: String, value: String, showsLeftBorder: Bool = false) -> some View {
        HStack(spacing: 0) {
            if showsLeftBorder {
                Rectangle().fill(Color.irBorder).frame(width: 0.5, height: 28)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(IRFont.body.weight(.bold))
                    .foregroundStyle(Color.irTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label.uppercased())
                    .font(IRFont.eyebrow.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color.irTextSecondary.opacity(0.7))
            }
            .padding(.leading, showsLeftBorder ? 8 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func weeklyMiniBars(weeks: [WeekVolume], lastIndex: Int) -> some View {
        let peak = max(weeks.map { $0.kilometers }.max() ?? 1, 1)
        return HStack(alignment: .bottom, spacing: Spacing.xs) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { idx, week in
                let h = max(CGFloat(week.kilometers / peak) * 36, 2)
                let isCurrent = idx == lastIndex
                VStack(spacing: Spacing.xxs) {
                    Text(String(format: "%.0f", week.kilometers))
                        .font(IRFont.eyebrow.weight(.semibold))
                        .foregroundStyle(isCurrent ? Color.irPrimaryAccent : Color.irTextSecondary.opacity(0.7))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isCurrent ? Color.irPrimaryAccent : Color.irTextPrimary.opacity(0.18))
                        .frame(width: 12, height: h)
                    Text("S\(week.weekNumber)")
                        .font(IRFont.monoSM)
                        .foregroundStyle(Color.irTextSecondary.opacity(0.55))
                }
            }
        }
        .frame(height: 64, alignment: .bottom)
    }

    private func weeklyVolumes(in workouts: [WorkoutModel]) -> [WeekVolume] {
        let calendar = Calendar.current
        var byWeek: [Int: Double] = [:]

        for w in workouts {
            guard let km = w.distance.map({ $0 / 1000.0 }) else { continue }
            let week = calendar.component(.weekOfYear, from: w.startDate)
            byWeek[week, default: 0] += km
        }

        // Compute the 4-5 weeks of the selected month so we always show a chart
        let monthStart = calendar.startOfMonth(for: selectedMonth)
        guard let range = calendar.range(of: .weekOfYear, in: .month, for: monthStart) else {
            return byWeek.keys.sorted().map { WeekVolume(weekNumber: $0, kilometers: byWeek[$0] ?? 0) }
        }

        let firstWeek = calendar.component(.weekOfYear, from: monthStart)
        let weekCount = range.count
        return (0..<weekCount).map { offset in
            let w = firstWeek + offset
            return WeekVolume(weekNumber: w, kilometers: byWeek[w] ?? 0)
        }
    }

    private func formattedKilometers(_ meters: Double) -> String {
        let km = meters / 1000.0
        if km < 10 {
            return String(format: "%.1f", km)
        } else {
            return String(format: "%.0f", km)
        }
    }

    private func formatHoursMinutes(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return String(format: "%dh %02d", h, m) }
        return String(format: "%dm", m)
    }

    private func formatPaceShort(_ pace: Double?) -> String {
        guard let pace, pace > 0 else { return "—" }
        let m = Int(pace)
        let s = Int((pace - Double(m)) * 60)
        return String(format: "%d'%02d\"", m, s)
    }

    private func formatElevation(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1fk", meters / 1000.0)
        }
        return String(format: "%.0fm", meters)
    }

    private func formatCalories(_ kcal: Double) -> String {
        if kcal >= 1000 {
            return String(format: "%.1fk", kcal / 1000.0)
        }
        return String(format: "%.0f", kcal)
    }

    // MARK: - Subscription CTA Card

    private var subscriptionCTACard: some View {
        VStack(spacing: Spacing.dash) {
            HStack(spacing: Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(
                            LinearGradient(
                                colors: [Color.irPrimaryAccent, Color.irPrimaryAccent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "sparkles")
                        .font(IRFont.eyebrow.weight(.bold))
                        .foregroundStyle(Color.irCardBackground)
                }
                .frame(width: 22, height: 22)

                Text(String(localized: "AI COACH", comment: "Subscription CTA eyebrow on workout list"))
                    .font(IRFont.eyebrow.weight(.bold))
                    .tracking(1.0)
                    .foregroundStyle(Color.irTextPrimary)
                Spacer()
            }

            Text(String(localized: "Unlock personalized insights and coaching powered by AI.", comment: "Subscription CTA description"))
                .font(IRFont.body)
                .lineSpacing(2)
                .foregroundStyle(Color.irTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                showInitialPaywall = true
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "sparkles")
                        .font(IRFont.footnote.weight(.bold))
                    Text(String(localized: "Subscribe Now", comment: "Subscribe CTA button"))
                        .font(IRFont.body.weight(.bold))
                }
                .foregroundStyle(Color.irCardBackground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(Color.irPrimaryAccent)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }
}

// MARK: - Stat Item Component (kept for compatibility)

struct StatItem: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(IRFont.title3)
                .foregroundStyle(Color.irPrimaryAccent.gradient)

            Text(value)
                .font(IRFont.title3.weight(.semibold))

            Text(label)
                .font(IRFont.caption)
                .foregroundStyle(Color.irTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

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
                .font(IRFont.body)
                .foregroundStyle(Color.irTextSecondary)

            Spacer()

            Text(value)
                .font(IRFont.body.weight(.semibold))
        }
    }
}

#Preview {
    WorkoutListView()
}
