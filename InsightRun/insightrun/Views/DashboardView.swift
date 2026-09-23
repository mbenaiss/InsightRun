//
//  DashboardView.swift
//  InsightRun
//
//  Pulse Ring dashboard — single hero (Disponibilité) + numbered sections.
//

import SwiftUI

struct DashboardView: View {
    @StateObject private var recoveryVM = RecoveryViewModel()
    @StateObject private var readinessVM = DailyReadinessViewModel()
    @StateObject private var weeklySummaryVM = WeeklySummaryViewModel()
    @StateObject private var notificationRouter = NotificationRouter.shared
    @ObservedObject private var contextProvider = UnifiedAIContextProvider.shared // swiftlint:disable:this private_state_object
    @StateObject private var trainingLoadService = TrainingLoadService()
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var revenueCatManager: RevenueCatManager

    @StateObject private var refreshCoordinator = DashboardRefreshCoordinator()
    @State private var loadedDate: Date?
    @State private var lastActiveDay = Calendar.current.startOfDay(for: Date())
    @State private var showSettings = false
    @State private var showingCalendar = false
    @State private var showWorkoutPlan = false
    @State private var showSubscriptionPaywall = false
    @State private var selectedScoreType: ScoreType?
    @State private var selectedMetricSheet: MetricSheetItem?
    @State private var currentPage = 1
    @State private var hasForwardPage = false
    @State private var currentNavID = UUID()
    @State private var latestActivityData: DailyActivityData?
    @State private var hrvTrend: [TrendDataPoint] = []
    @State private var rhrTrend: [TrendDataPoint] = []
    @State private var respTrend: [TrendDataPoint] = []
    @State private var spo2Trend: [TrendDataPoint] = []
    @State private var effortTrend: [TrendDataPoint] = []
    @State private var sleepTrend: [TrendDataPoint] = []
    @State private var readinessTrend: [TrendDataPoint] = []
    @State private var caloriesTotalTrend: [TrendDataPoint] = []
    @State private var stepsTrend: [TrendDataPoint] = []
    @State private var caloriesBreakdownTrend: [CaloriesBreakdownPoint] = []
    @State private var todaySession: (goal: RaceGoal, day: TrainingDay)?
    @State private var latestWorkout: WorkoutModel?
    @State private var isActivationLoading = false
    @AppStorage("hasViewedWorkoutDetail") private var hasViewedWorkoutDetail = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            TabView(selection: $currentPage) {
                dayPage.tag(0)
                dayPage.tag(1)
                if hasForwardPage {
                    dayPage.tag(2)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color.irBackgroundApp.ignoresSafeArea())
            .onChange(of: currentPage) { _, newValue in
                handlePageChange(to: newValue)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image("TabProfile")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                            .foregroundStyle(Color.irTextSecondary)
                    }
                    .accessibilityIdentifier("dashboard-settings")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environment(themeManager)
                    .environmentObject(revenueCatManager)
            }
            .sheet(isPresented: $showingCalendar) {
                RecoveryCalendarView(
                    selectedDate: $recoveryVM.selectedDate,
                    isPresented: $showingCalendar,
                    onDateSelected: { date in
                        hasForwardPage = !Calendar.current.isDateInToday(date)
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showWorkoutPlan) {
                WorkoutPlanView()
                    .environmentObject(revenueCatManager)
            }
            .sheet(item: $selectedScoreType) { type in
                let score: Int = {
                    switch type {
                    case .effort: return trainingLoadService.dailyEffortScore
                    case .sleep: return recoveryVM.recoveryMetrics?.sleepData?.qualityScore ?? 0
                    case .readiness: return readinessVM.readinessScore ?? 0
                    case .cardiacLoad: return trainingLoadService.cardiacLoadScore ?? 0
                    case .freshness: return trainingLoadService.freshnessScore ?? 0
                    }
                }()
                let trend: [TrendDataPoint] = {
                    switch type {
                    case .cardiacLoad:
                        return trainingLoadService.cardiacLoadTrendData
                    case .effort:
                        return effortTrend
                    case .sleep:
                        return sleepTrend
                    case .readiness:
                        return readinessTrend
                    case .freshness:
                        return trainingLoadService.freshnessTrendData
                    }
                }()
                ScoreExplanationSheet(
                    scoreType: type,
                    score: score,
                    sleepDurationHours: recoveryVM.recoveryMetrics?.sleepData.map { $0.totalSleepDuration / 3600.0 },
                    sleepEfficiency: recoveryVM.recoveryMetrics?.sleepData?.sleepEfficiency,
                    trendData: trend,
                    cardiacLoadStatus: type == .cardiacLoad ? trainingLoadService.cardiacLoadStatus : nil,
                    recoveryMetrics: recoveryVM.recoveryMetrics,
                    activityData: type == .effort ? latestActivityData : nil,
                    isScoreAvailable: scoreAvailable(for: type),
                    readinessStatus: type == .readiness ? readinessVM.status : nil
                )
                .environmentObject(revenueCatManager)
                .presentationDetents([.large])
            }
            .sheet(item: $selectedMetricSheet) { item in
                ScoreExplanationSheet(
                    metricType: item.metricType,
                    currentValue: metricValue(for: item.metricType) ?? item.value,
                    unit: item.unit,
                    deviationStatus: metricDeviation(for: item.metricType) ?? item.deviationStatus,
                    baseline: recoveryVM.recoveryMetrics?.baseline,
                    trendData: metricTrend(for: item.metricType),
                    recoveryMetrics: recoveryVM.recoveryMetrics,
                    activityData: item.activityData == nil ? nil : latestActivityData,
                    caloriesBreakdown: item.caloriesBreakdown == nil ? nil : caloriesBreakdownTrend,
                    isMetricAvailable: item.metricType != .rmssd || metricValue(for: .rmssd) != nil,
                    refresh: { await recoveryVM.refresh() }
                )
                .environmentObject(revenueCatManager)
                .presentationDetents([.large])
            }
            .navigationDestination(isPresented: $notificationRouter.showWeeklySummary) {
                WeeklySummaryView(viewModel: weeklySummaryVM)
            }
            .fullScreenCover(isPresented: $showSubscriptionPaywall) {
                SubscriptionPaywallView(isInitialFlow: false)
                    .environmentObject(revenueCatManager)
            }
            .sheet(isPresented: $readinessVM.needsConsent) {
                AIConsentSheet(
                    onConsent: {
                        readinessVM.needsConsent = false
                        Task {
                            if await HistoricalSummaryStorage.shared.requiresIndexation() {
                                readinessVM.needsIndexation = true
                            } else {
                                await refreshAll(forceRefresh: true)
                            }
                        }
                    },
                    onDecline: {
                        readinessVM.needsConsent = false
                    }
                )
            }
            .indexationGate(isPresented: $readinessVM.needsIndexation) {
                await refreshAll(forceRefresh: true)
            }
            .task(id: recoveryVM.selectedDate) {
                await refreshAll()
            }
            .onDisappear {
                refreshCoordinator.cancel()
                readinessVM.cancel()
            }
            .onReceive(NotificationCenter.default.publisher(for: .trainingDayCompleted)) { _ in
                loadTodaySession()
            }
            .onReceive(NotificationCenter.default.publisher(for: .healthWorkoutsChanged)) { _ in
                guard scenePhase == .active else { return }
                Task { await refreshAll(forceRefresh: true) }
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                let today = Calendar.current.startOfDay(for: Date())
                let wasShowingToday = recoveryVM.selectedDate == lastActiveDay
                let dayChanged = today != lastActiveDay
                lastActiveDay = today
                if dayChanged && wasShowingToday {
                    recoveryVM.selectedDate = today
                    hasForwardPage = false
                    currentPage = 1
                } else {
                    Task { await refreshAll() }
                }
            }
        }
    }

    // MARK: - Data Loading

    @MainActor
    private func refreshAll(forceRefresh: Bool = false, regenerateCoaching: Bool = false) async {
        let date = recoveryVM.selectedDate
        await refreshCoordinator.refresh(for: date, force: forceRefresh) {
            await loadDashboard(for: date, forceRefresh: forceRefresh, regenerateCoaching: regenerateCoaching)
        }
    }

    @MainActor
    private func loadDashboard(for date: Date, forceRefresh: Bool, regenerateCoaching: Bool) async {
        #if DEBUG
        DashboardDiagnostics.record("dashboard.refresh", date: date)
        #endif
        readinessVM.restoreCachedReadiness(for: date)
        loadTodaySession()
        if forceRefresh || Calendar.current.isDateInToday(date) {
            MetricTrendDataService.shared.invalidateCache(keepingHistoricalData: !forceRefresh)
        }
        async let weekly: Void = weeklySummaryVM.load(for: date, minimumRefreshInterval: forceRefresh ? 0 : 60,
                                                       includeCoaching: false, includeDetails: false)
        async let latest: Void = loadLatestWorkout()
        async let recovery: Void = recoveryVM.loadRecoveryMetrics(for: date)
        async let cardiac: Void = trainingLoadService.analyzeCardiacLoad(for: date)
        let activity = await HealthKitManager.shared.fetchDailyActivityData(for: date)
        await recovery
        await cardiac
        guard !Task.isCancelled, recoveryVM.selectedDate == date else { return }
        latestActivityData = activity
        trainingLoadService.dailyEffortScore = MetricTrendDataService.computeEffortScore(activity: activity)
        MetricTrendDataService.shared.seedActivity(activity, for: date)
        if let metrics = recoveryVM.recoveryMetrics {
            MetricTrendDataService.shared.seedRecovery(metrics, for: date)
        }
        readinessVM.readinessScore = DailyMetricsCache.shared.getReadiness(for: date)?.score
            ?? DailyMetricsCache.shared.getHistoricalReadinessScore(for: date)
        readinessVM.status = DailyMetricsCache.shared.getReadiness(for: date).map { ReadinessStatus(from: $0.status) } ?? .unknown
        if Calendar.current.isDateInToday(date), let metrics = recoveryVM.recoveryMetrics {
            contextProvider.recoveryMetrics = metrics
        }
        if loadedDate != date {
            hrvTrend = []
            rhrTrend = []
            respTrend = []
            spo2Trend = []
            effortTrend = []
            sleepTrend = []
            readinessTrend = []
            caloriesTotalTrend = []
            stepsTrend = []
            caloriesBreakdownTrend = []
        }
        loadedDate = date
        async let trends: Void = loadTrendData(for: date)
        await readinessVM.fetchDailyReadiness(
            for: date,
            recoveryMetrics: recoveryVM.recoveryMetrics,
            activityData: activity,
            effortScore: trainingLoadService.dailyEffortScore,
            cardiacLoadScore: trainingLoadService.cardiacLoadScore,
            cardiacLoadStatus: trainingLoadService.cardiacLoadStatus,
            freshnessAvailable: trainingLoadService.freshnessScore != nil,
            forceRefresh: regenerateCoaching
        )
        if Calendar.current.isDateInToday(date), !Task.isCancelled, recoveryVM.selectedDate == date,
           let score = readinessVM.readinessScore {
            WidgetDataProvider.shared.updateReadiness(
                score: score, status: readinessVM.status, recovery: recoveryVM.recoveryMetrics)
        }
        await trends
        await weekly
        await latest
        guard !Task.isCancelled, recoveryVM.selectedDate == date else { return }
        readinessTrend = await MetricTrendDataService.shared.readinessTrend(endingOn: date)
    }

    @MainActor
    private func loadTrendData(for date: Date) async {
        let service = MetricTrendDataService.shared
        async let hrv = service.metricTrend(for: .hrv, endingOn: date)
        async let rhr = service.metricTrend(for: .restingHeartRate, endingOn: date)
        async let resp = service.metricTrend(for: .respiratoryRate, endingOn: date)
        async let spo2 = service.metricTrend(for: .oxygenSaturation, endingOn: date)
        async let effort = service.effortTrend(endingOn: date)
        async let sleep = service.sleepTrend(endingOn: date)
        async let readiness = service.readinessTrend(endingOn: date)
        async let caloriesTotal = service.caloriesTotalTrend(endingOn: date)
        async let steps = service.stepsTrend(endingOn: date)
        async let caloriesBreakdown = service.caloriesBreakdownTrend(endingOn: date)

        let values = await (hrv, rhr, resp, spo2, effort, sleep, readiness, caloriesTotal, caloriesBreakdown, steps)
        guard !Task.isCancelled, recoveryVM.selectedDate == date else { return }
        let metrics = recoveryVM.recoveryMetrics
        hrvTrend = replacingEndpoint(values.0, value: metrics?.hrvAverage, date: date)
        rhrTrend = replacingEndpoint(values.1, value: metrics?.restingHeartRate, date: date)
        respTrend = replacingEndpoint(values.2, value: metrics?.respiratoryRate, date: date)
        spo2Trend = replacingEndpoint(values.3, value: metrics?.oxygenSaturation, date: date)
        effortTrend = values.4
        sleepTrend = values.5
        readinessTrend = values.6
        caloriesTotalTrend = values.7
        caloriesBreakdownTrend = values.8
        stepsTrend = replacingEndpoint(values.9, value: latestActivityData?.steps, date: date)
    }

    private func replacingEndpoint(_ points: [TrendDataPoint], value: Double?, date: Date) -> [TrendDataPoint] {
        guard let value else { return points }
        return points.filter { !Calendar.current.isDate($0.date, inSameDayAs: date) }
            + [TrendDataPoint(date: date, value: value)]
    }

    private func metricValue(for type: MetricType) -> Double? {
        let metrics = recoveryVM.recoveryMetrics
        switch type {
        case .hrv: return metrics?.hrvAverage
        case .rmssd: return metrics?.rmssd?.currentNight?.median
        case .restingHeartRate: return metrics?.restingHeartRate
        case .respiratoryRate: return metrics?.respiratoryRate
        case .oxygenSaturation: return metrics?.oxygenSaturation
        case .totalCalories: return latestActivityData?.totalCalories
        case .steps: return latestActivityData?.steps
        default: return nil
        }
    }

    private func metricDeviation(for type: MetricType) -> DeviationStatus? {
        guard let value = metricValue(for: type) else { return nil }
        let baseline = recoveryVM.recoveryMetrics?.baseline
        switch type {
        case .hrv: return hrvDeviationStatus(value, baseline: baseline)
        case .restingHeartRate: return rhrDeviationStatus(value, baseline: baseline)
        case .respiratoryRate: return respDeviationStatus(value, baseline: baseline)
        case .oxygenSaturation: return spo2DeviationStatus(value)
        default: return nil
        }
    }

    private func metricTrend(for type: MetricType) -> [TrendDataPoint] {
        switch type {
        case .hrv: return hrvTrend
        case .rmssd: return recoveryVM.recoveryMetrics?.rmssd?.history(endingOn: recoveryVM.selectedDate) ?? []
        case .restingHeartRate: return rhrTrend
        case .respiratoryRate: return respTrend
        case .oxygenSaturation: return spo2Trend
        case .totalCalories: return caloriesTotalTrend
        case .steps: return stepsTrend
        default: return []
        }
    }

    private func scoreAvailable(for type: ScoreType) -> Bool {
        switch type {
        case .readiness: return (readinessVM.readinessScore ?? 0) > 0
        case .sleep: return (recoveryVM.recoveryMetrics?.sleepData?.qualityScore ?? 0) > 0
        case .freshness: return (trainingLoadService.freshnessScore ?? 0) > 0
        case .cardiacLoad: return (trainingLoadService.cardiacLoadScore ?? 0) > 0
        case .effort: return latestActivityData != nil && trainingLoadService.dailyEffortScore > 0
        }
    }

    // MARK: - Day Page

    private var dayPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                dateHeader
                    .padding(.horizontal)

                if loadedDate != recoveryVM.selectedDate {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    if !hasViewedWorkoutDetail {
                        section(title: String(localized: "Next action", comment: "Dashboard activation section title"))
                        {
                            activationActionCard
                        }
                    }

                    // Disponibilité
                    if scoreAvailable(for: .readiness) {
                        section(title: String(localized: "Availability", comment: "Dashboard section: availability")) {
                            PulseRingHero(
                                score: readinessVM.readinessScore,
                                yesterdayScore: yesterdayReadinessScore,
                                statusTitle: readinessVM.status.title,
                                statusColor: readinessVM.status.color,
                                footerSummary: footerSummary,
                                onTap: { selectedScoreType = .readiness }
                            )
                        }

                    }

                    // Charge & récupération
                    if scoreAvailable(for: .effort)
                        || scoreAvailable(for: readinessVM.isNoSleepMode ? .freshness : .sleep)
                    {
                        section(
                            title: String(localized: "Load & recovery", comment: "Dashboard section: load and recovery")
                        ) {
                            HStack(spacing: Spacing.sm) {
                                if scoreAvailable(for: .effort) {
                                    SecondaryScoreCard(
                                        title: String(localized: "Effort", comment: "Dashboard effort label"),
                                        score: trainingLoadService.dailyEffortScore,
                                        baseline: averagePreviousScores(effortTrend),
                                        trend: effortTrend.suffix(7).map(\.value),
                                        onTap: { selectedScoreType = .effort }
                                    )
                                    .accessibilityIdentifier("score-effort")
                                }

                                if readinessVM.isNoSleepMode, let freshness = trainingLoadService.freshnessScore,
                                    freshness > 0
                                {
                                    SecondaryScoreCard(
                                        title: String(
                                            localized: "Freshness",
                                            comment:
                                                "Dashboard TSB-based freshness label, shown when sleep tracking is unavailable"
                                        ),
                                        score: freshness,
                                        baseline: averagePreviousScores(trainingLoadService.freshnessTrendData),
                                        trend: trainingLoadService.freshnessTrendData.suffix(7).map(\.value),
                                        onTap: { selectedScoreType = .freshness }
                                    )
                                    .accessibilityIdentifier("score-freshness")
                                } else if !readinessVM.isNoSleepMode && scoreAvailable(for: .sleep) {
                                    SecondaryScoreCard(
                                        title: String(localized: "Sleep", comment: "Dashboard sleep label"),
                                        score: recoveryVM.recoveryMetrics?.sleepData?.qualityScore,
                                        baseline: averagePreviousScores(sleepTrend),
                                        trend: sleepTrend.suffix(7).map(\.value),
                                        onTap: { selectedScoreType = .sleep }
                                    )
                                    .accessibilityIdentifier("score-sleep")
                                }
                            }
                        }

                    }

                    // Coach (only on today and if AI access)
                    if recoveryVM.isToday {
                        section(
                            title: String(localized: "Coach", comment: "Dashboard section: AI coach")
                        ) {
                            if revenueCatManager.hasAIAccess {
                                PulseCoachingCard(
                                    timestampLabel: coachTimestampLabel,
                                    tldr: coachingRecommendation,
                                    highlightWord: coachingHighlight,
                                    reasons: coachingReasons,
                                    detail: coachingDetail,
                                    isLoading: readinessVM.isLoading,
                                    statusMessage: coachStatusMessage,
                                    onRetry: readinessVM.errorMessage != nil || readinessVM.isFallback
                                        ? {
                                            Task { await refreshAll(forceRefresh: true, regenerateCoaching: true) }
                                        } : nil,
                                    onCreatePlan: { showWorkoutPlan = true }
                                )
                            } else {
                                subscriptionCTACard
                            }
                        }
                    }

                    // Séance recommandée
                    if recoveryVM.isToday, let session = todaySession, let workout = session.day.workout {
                        section(
                            title: String(
                                localized: "Recommended session", comment: "Dashboard section: recommended session")
                        ) {
                            TodaySessionCard(
                                goal: session.goal,
                                workout: workout,
                                onTap: { navigateToGoalSession(session.goal) }
                            )
                        }
                    }

                    // Activité hebdo
                    if hasWeeklyActivity {
                        section(
                            title: String(localized: "Weekly activity", comment: "Dashboard section: weekly activity")
                        ) {
                            WeeklyActivityCard(
                                weekLabel: weeklyActivityWeekLabel,
                                totalDistanceLabel: MetricDisplayValue.positive(weeklySummaryVM.totalDistance).map {
                                    _ in weeklySummaryVM.formattedTotalDistance
                                },
                                totalDurationLabel: MetricDisplayValue.positive(weeklySummaryVM.totalDuration).map {
                                    _ in weeklySummaryVM.formattedTotalDuration
                                },
                                averagePaceLabel: MetricDisplayValue.positive(weeklySummaryVM.averagePace).map { _ in
                                    weeklySummaryVM.formattedAveragePace
                                },
                                dailyEfforts: weeklySummaryVM.dailyRunDistancesKm,
                                highlightedIndex: weeklySummaryVM.todayIndexInWeek,
                                onTap: { notificationRouter.showWeeklySummary = true }
                            )
                        }

                    }

                    // Signaux
                    if hasSignals {
                        section(
                            title: String(localized: "Signals", comment: "Dashboard section: physiological signals")
                        ) {
                            signalsGrid
                        }
                    }
                }
            }
            .padding(.top, Spacing.sm)
            .padding(.bottom, 100)
        }
        .accessibilityIdentifier("dashboard-content")
        .refreshable {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.prepare()
            impact.impactOccurred()
            await refreshAll(forceRefresh: true)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    // MARK: - Section helper

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DashboardEyebrow(title: title)
            content()
        }
        .padding(.horizontal)
    }

    // MARK: - Today Session

    private func loadTodaySession() {
        let goals = GoalStorage.shared.load()
        for goal in goals where goal.isActive && !goal.isPast && goal.hasTrainingPlan {
            if let session = goal.todaySession {
                todaySession = (goal, session.day)
                return
            }
        }
        todaySession = nil
    }

    private func navigateToGoalSession(_ goal: RaceGoal) {
        notificationRouter.pendingGoalId = goal.id
    }

    private var activationActionCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(activationActionDescription)
                .font(IRFont.body)
                .foregroundStyle(Color.irTextSecondary)

            Button {
                performPrimaryActivationAction()
            } label: {
                HStack(spacing: Spacing.sm) {
                    if isActivationLoading {
                        ProgressView()
                            .tint(Color.irTextOnAccent)
                    } else {
                        Image(systemName: activationActionIcon)
                    }
                    Text(activationActionTitle)
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(IRFont.body.weight(.bold))
                .foregroundStyle(Color.irTextOnAccent)
                .padding(Spacing.md)
                .background(Color.irPrimaryAccent)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            }
            .buttonStyle(.plain)
            .disabled(isActivationLoading)
            .accessibilityIdentifier("dashboard-activation-primary")

            if latestWorkout == nil && !HealthKitManager.shared.hasCompletedHealthKitSetup {
                Button {
                    routeToSampleWorkout(source: "dashboard_sample")
                } label: {
                    Label(String(localized: "Try with a sample workout", comment: "Sample workout activation button"), systemImage: "sparkles")
                        .font(IRFont.footnote.weight(.semibold))
                        .foregroundStyle(Color.irPrimaryAccent)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dashboard-activation-sample")
            }
        }
        .padding(Spacing.cardPadding)
        .detailCard()
    }

    private var activationActionTitle: String {
        if latestWorkout != nil {
            return String(localized: "Analyze my latest run", comment: "Dashboard latest run activation button")
        }
        if HealthKitManager.shared.hasCompletedHealthKitSetup {
            return String(localized: "Try with a sample workout", comment: "Sample workout activation button")
        }
        return String(localized: "Import from Apple Health", comment: "HealthKit import button")
    }

    private var activationActionDescription: String {
        if latestWorkout != nil {
            return String(localized: "Open your latest run and get one concrete recommendation.", comment: "Dashboard latest run activation description")
        }
        if HealthKitManager.shared.hasCompletedHealthKitSetup {
            return String(localized: "No run found yet. See how InsightRun analyzes a complete workout.", comment: "Dashboard sample workout activation description")
        }
        return String(localized: "Connect Apple Health to turn your latest run into a clear next action.", comment: "Dashboard HealthKit activation description")
    }

    private var activationActionIcon: String {
        latestWorkout == nil ? "heart.text.square.fill" : "figure.run"
    }

    private func performPrimaryActivationAction() {
        if let latestWorkout {
            routeToWorkout(latestWorkout, source: "dashboard_latest")
        } else if HealthKitManager.shared.hasCompletedHealthKitSetup {
            routeToSampleWorkout(source: "dashboard_sample")
        } else {
            Task { await importLatestWorkout() }
        }
    }

    @MainActor
    private func importLatestWorkout() async {
        isActivationLoading = true
        defer { isActivationLoading = false }

        guard (try? await HealthKitManager.shared.requestAuthorization()) == true else { return }
        await loadLatestWorkout()
        if let latestWorkout {
            routeToWorkout(latestWorkout, source: "dashboard_healthkit")
        }
    }

    @MainActor
    private func loadLatestWorkout() async {
        guard HealthKitManager.shared.hasCompletedHealthKitSetup else {
            latestWorkout = nil
            return
        }
        guard !hasViewedWorkoutDetail else { return }
        let workout = (try? await HealthKitManager.shared.fetchRunningWorkouts(limit: 1))?.workouts.first
        guard !Task.isCancelled else { return }
        latestWorkout = workout
    }

    private func routeToWorkout(_ workout: WorkoutModel, source: String) {
        AnalyticsService.shared.trackActivationStarted(source: source)
        AnalyticsService.shared.trackActivationWorkoutReady(isSample: false)
        notificationRouter.routeToActivationWorkout(workout)
    }

    private func routeToSampleWorkout(source: String) {
        AnalyticsService.shared.trackActivationStarted(source: source)
        AnalyticsService.shared.trackActivationWorkoutReady(isSample: true)
        notificationRouter.routeToActivationWorkout(MockData.activationWorkout)
    }

    // MARK: - Day Navigation

    @MainActor
    private func handlePageChange(to newValue: Int) {
        guard newValue != 1 else { return }

        let dayOffset = newValue == 0 ? -1 : 1
        let calendar = Calendar.current
        let currentDate = recoveryVM.selectedDate

        guard let newDate = calendar.date(byAdding: .day, value: dayOffset, to: currentDate),
              newDate <= Date() else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { currentPage = 1 }
            return
        }

        let navID = UUID()
        currentNavID = navID
        recoveryVM.selectedDate = newDate
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard currentNavID == navID else { return }

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { currentPage = 1 }

            DispatchQueue.main.async {
                hasForwardPage = !calendar.isDateInToday(newDate)
            }
        }
    }

    // MARK: - Subscription CTA Card

    private var subscriptionCTACard: some View {
        VStack(spacing: Spacing.base) {
            Image(systemName: "sparkles")
                .font(IRFont.numLG)
                .foregroundStyle(LinearGradient.irAIAccent)

            VStack(spacing: Spacing.sm) {
                Text(String(localized: "Unlock AI Coaching", comment: "Subscription CTA title"))
                    .font(IRFont.headline.weight(.bold))

                Text(String(localized: "Get personalized insights and coaching powered by AI", comment: "Subscription CTA description"))
                    .font(IRFont.body)
                    .foregroundStyle(Color.irTextSecondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                showSubscriptionPaywall = true
            } label: {
                HStack {
                    Image(systemName: "sparkles")
                    Text(String(localized: "Subscribe Now", comment: "Subscribe CTA button"))
                }
                .font(IRFont.body.weight(.semibold))
                .foregroundStyle(Color.irTextOnAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(LinearGradient.irAIAccent)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            }
        }
        .padding(Spacing.cardPadding)
        .detailCard()
    }

    private var hasWeeklyActivity: Bool {
        [weeklySummaryVM.totalDistance, weeklySummaryVM.totalDuration, weeklySummaryVM.averagePace]
            .contains { MetricDisplayValue.positive($0) != nil }
    }

    private var hasSignals: Bool {
        let recovery = recoveryVM.recoveryMetrics
        return [
            recovery?.hrvAverage, recovery?.rmssd?.currentNight?.median,
            recovery?.restingHeartRate, recovery?.respiratoryRate, recovery?.oxygenSaturation,
            latestActivityData?.totalCalories, latestActivityData?.steps,
        ]
        .contains { MetricDisplayValue.positive($0) != nil } || scoreAvailable(for: .cardiacLoad)
    }

    // MARK: - Signals grid

    @ViewBuilder
    private var signalsGrid: some View {
        let recovery = recoveryVM.recoveryMetrics
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: Spacing.sm), GridItem(.flexible(), spacing: Spacing.sm)],
            spacing: Spacing.sm
        ) {
            if let hrv = MetricDisplayValue.positive(recovery?.hrvAverage) {
                let status = hrvDeviationStatus(hrv, baseline: recovery?.baseline)
                SignalCard(
                    icon: "waveform.path.ecg",
                    label: String(localized: "HRV at rest", comment: "HRV metric title"),
                    value: Formatters.integer(Int(hrv.rounded())),
                    unit: "ms",
                    status: status.localizedDescription(for: .hrv),
                    statusColor: status.color,
                    trend: hrvTrend.suffix(7).map(\.value),
                    onTap: { presentMetricSheet(.hrv, value: hrv, unit: "ms", status: status, trend: hrvTrend) }
                )
            }

            // Without data the card stays as the entry point to the RMSSD access request.
            let rmssd = MetricDisplayValue.positive(recovery?.rmssd?.currentNight?.median)
            if rmssd != nil || HealthInsightReader.rmssdType != nil {
                SignalCard(
                    icon: "waveform.path.ecg",
                    label: String(localized: "insights.rmssd.short", defaultValue: "HRV · RMSSD"),
                    value: rmssd.map { Formatters.integer(Int($0.rounded())) } ?? "—",
                    unit: "ms",
                    status: RMSSDTrend.statusDescription(recovery?.rmssd),
                    statusColor: .irTextSecondary,
                    trend: metricTrend(for: .rmssd).map(\.value),
                    onTap: {
                        presentMetricSheet(
                            .rmssd, value: rmssd ?? 0,
                                           unit: "ms", status: nil, trend: metricTrend(for: .rmssd))
                    }
                )
                .task {
                    if await HealthKitManager.shared.requestAddedReadTypesAuthorizationIfNeeded() {
                        await recoveryVM.refresh()
                    }
                }
            }

            if let rhr = MetricDisplayValue.positive(recovery?.restingHeartRate) {
                let status = rhrDeviationStatus(rhr, baseline: recovery?.baseline)
                SignalCard(
                    icon: "heart.fill",
                    label: String(localized: "Resting HR", comment: "Resting heart rate metric title"),
                    value: Formatters.integer(Int(rhr.rounded())),
                    unit: "bpm",
                    status: status.localizedDescription(for: .restingHeartRate),
                    statusColor: status.color,
                    trend: rhrTrend.suffix(7).map(\.value),
                    onTap: { presentMetricSheet(.restingHeartRate, value: rhr, unit: "bpm", status: status, trend: rhrTrend) }
                )
            }

            if let resp = MetricDisplayValue.positive(recovery?.respiratoryRate) {
                let status = respDeviationStatus(resp, baseline: recovery?.baseline)
                SignalCard(
                    icon: "lungs.fill",
                    label: String(localized: "Respiratory rate", comment: "Respiratory rate metric title"),
                    value: Formatters.decimal(resp, fractionDigits: 1),
                    unit: "rpm",
                    status: status.localizedDescription(for: .respiratoryRate),
                    statusColor: status.color,
                    trend: respTrend.suffix(7).map(\.value),
                    onTap: { presentMetricSheet(.respiratoryRate, value: resp, unit: "rpm", status: status, trend: respTrend) }
                )
            }

            if let spo2 = MetricDisplayValue.positive(recovery?.oxygenSaturation) {
                let status = spo2DeviationStatus(spo2)
                SignalCard(
                    icon: "drop.fill",
                    label: String(localized: "Oxygen saturation", comment: "SpO2 metric title"),
                    value: Formatters.integer(Int(spo2.rounded())),
                    unit: "%",
                    status: status.localizedDescription(for: .oxygenSaturation),
                    statusColor: status.color,
                    trend: spo2Trend.suffix(7).map(\.value),
                    onTap: { presentMetricSheet(.oxygenSaturation, value: spo2, unit: "%", status: status, trend: spo2Trend) }
                )
            }

            cardiacLoadSignalCard

            caloriesSignalCard
            stepsSignalCard

        }
    }

    @ViewBuilder
    private var cardiacLoadSignalCard: some View {
        if let load = trainingLoadService.cardiacLoadScore, load > 0 {
            let status = trainingLoadService.cardiacLoadStatus
            SignalCard(
                icon: "shoe.2.fill",
                label: String(localized: "Cardiac Load", comment: "Cardiac load metric title"),
                value: "\(load)",
                unit: "/20",
                status: status.title,
                statusColor: status.color,
                trend: trainingLoadService.cardiacLoadTrendData.suffix(7).map(\.value),
                onTap: { selectedScoreType = .cardiacLoad }
            )
        }
    }

    @ViewBuilder
    private var caloriesSignalCard: some View {
        if let activity = latestActivityData, MetricDisplayValue.positive(activity.totalCalories) != nil {
            let activeKcal = Formatters.integer(Int(activity.activeCalories.rounded()))
            let activeLabel = String(localized: "active", comment: "Active calories label")
            SignalCard(
                icon: "flame.fill",
                label: String(localized: "Calories", comment: "Calories metric title"),
                value: Formatters.integer(Int(activity.totalCalories.rounded())),
                unit: "kcal",
                status: MetricDisplayValue.positive(activity.activeCalories) == nil
                    ? nil : "\(activeKcal) " + activeLabel,
                statusColor: .irTextSecondary,
                trend: caloriesTotalTrend.suffix(7).map(\.value),
                onTap: {
                    selectedMetricSheet = MetricSheetItem(
                        metricType: .totalCalories,
                        value: activity.totalCalories,
                        unit: "kcal",
                        deviationStatus: nil,
                        baseline: nil,
                        trend: caloriesTotalTrend,
                        activityData: activity,
                        caloriesBreakdown: caloriesBreakdownTrend
                    )
                }
            )
        }
    }

    @ViewBuilder
    private var stepsSignalCard: some View {
        if let activity = latestActivityData, MetricDisplayValue.positive(activity.steps) != nil {
            SignalCard(
                icon: "figure.walk",
                label: String(localized: "Steps"),
                value: Formatters.integer(Int(activity.steps.rounded())),
                unit: String(localized: "steps"),
                status: String(localized: "activity.daily_total", defaultValue: "Daily total"),
                statusColor: .irTextSecondary,
                trend: stepsTrend.suffix(7).map(\.value),
                onTap: {
                    selectedMetricSheet = MetricSheetItem(
                        metricType: .steps, value: activity.steps,
                        unit: String(localized: "steps"), deviationStatus: nil, baseline: nil,
                        trend: stepsTrend, activityData: activity, caloriesBreakdown: nil)
                }
            )
        }
    }

    private func presentMetricSheet(
        _ metricType: MetricType,
        value: Double,
        unit: String,
        status: DeviationStatus?,
        trend: [TrendDataPoint]
    ) {
        selectedMetricSheet = MetricSheetItem(
            metricType: metricType,
            value: value,
            unit: unit,
            deviationStatus: status,
            baseline: recoveryVM.recoveryMetrics?.baseline,
            trend: trend,
            activityData: nil,
            caloriesBreakdown: nil
        )
    }

    // MARK: - Date Header

    private var dateHeader: some View {
        Button {
            showingCalendar = true
        } label: {
            HStack(spacing: Spacing.sm) {
                Text(formattedDateTitle)
                    .font(IRFont.title2.weight(.bold))
                    .kerning(IRTracking.title2)
                    .foregroundStyle(Color.irTextPrimary)

                Image(systemName: "chevron.down")
                    .font(IRFont.caption.weight(.semibold))
                    .foregroundStyle(Color.irTextTertiary)

                Spacer()
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "dashboard.dateHeader.label", defaultValue: "Change date", comment: "Accessibility label for the dashboard date picker button"))
        .accessibilityValue(formattedDateTitle)
        .accessibilityIdentifier("dashboard-calendar")
    }

    private var formattedDateTitle: String {
        let selected = recoveryVM.selectedDate
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale.current

        if calendar.isDateInToday(selected) {
            formatter.setLocalizedDateFormatFromTemplate("d MMMM")
            return String(localized: "Today", comment: "Dashboard date label for today") + ", " + formatter.string(from: selected)
        } else if calendar.isDateInYesterday(selected) {
            formatter.setLocalizedDateFormatFromTemplate("d MMMM")
            return String(localized: "Yesterday", comment: "Dashboard date label for yesterday") + ", " + formatter.string(from: selected)
        } else {
            formatter.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
            return formatter.string(from: selected).capitalized
        }
    }

    // MARK: - Coaching helpers

    private var coachTimestampLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("d MMM jmm")
        return readinessVM.updatedAt.map { formatter.string(from: $0) } ?? ""
    }

    private var coachingRecommendation: String {
        if !readinessVM.recommendationSummary.isEmpty {
            return readinessVM.recommendationSummary
        }
        if !readinessVM.recommendation.isEmpty {
            return readinessVM.recommendation
        }
        if let localAdvice = recoveryVM.recoveryMetrics?.coachingRecommendation { return localAdvice }
        return readinessVM.isLoading
            ? String(localized: "Loading your coaching insights...", comment: "Coaching loading placeholder")
            : String(localized: "dashboard.coach.unavailable", defaultValue: "Your coaching analysis is not available yet.")
    }

    private var coachStatusMessage: String? {
        if readinessVM.isLoading {
            return String(localized: "dashboard.coach.refreshing", defaultValue: "Updating your analysis…")
        }
        if let error = readinessVM.errorMessage {
            return readinessVM.recommendation.isEmpty ? error : String(localized: "dashboard.coach.previous", defaultValue: "Update unavailable. Your last analysis is still displayed.")
        }
        if readinessVM.isFallback {
            return String(localized: "dashboard.coach.fallback", defaultValue: "Advice based on your metrics. AI analysis is temporarily unavailable.")
        }
        return nil
    }

    /// Pick the readiness status title as the highlighted keyword in the TL;DR (e.g. "Mitigée").
    private var coachingHighlight: String? {
        let status = readinessVM.status
        guard status != .unknown else { return nil }
        let title = status.title
        guard !title.isEmpty,
              coachingRecommendation.range(of: title, options: .caseInsensitive) != nil
        else { return nil }
        return title
    }

    private var coachingReasons: [String] {
        var reasons: [String] = []
        if let hrv = MetricDisplayValue.positive(recoveryVM.recoveryMetrics?.hrvAverage) {
            reasons.append(String(localized: "dashboard.coach.reason.hrv", defaultValue: "HRV \(Formatters.integer(Int(hrv.rounded()))) ms", comment: "Coach reason chip: resting HRV value in ms"))
        }
        if let rhr = MetricDisplayValue.positive(recoveryVM.recoveryMetrics?.restingHeartRate) {
            reasons.append(String(localized: "dashboard.coach.reason.rhr", defaultValue: "Resting HR \(Formatters.heartRate(rhr))", comment: "Coach reason chip: resting heart rate"))
        }
        if let sleep = recoveryVM.recoveryMetrics?.sleepData {
            reasons.append(sleep.formattedTotalSleep)
        }
        let load = trainingLoadService.cardiacLoadScore
        if let load, load > 0 {
            reasons.append(String(localized: "dashboard.coach.reason.load", defaultValue: "Load \(Formatters.integer(load))", comment: "Coach reason chip: cardiac load score"))
        }
        return reasons
    }

    private var coachingDetail: String {
        if !readinessVM.recommendation.isEmpty {
            return readinessVM.recommendation
        }
        return recoveryVM.recoveryMetrics?.coachingRecommendation ?? ""
    }

    // MARK: - Pulse Ring helpers

    private var yesterdayReadinessScore: Int? {
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: recoveryVM.selectedDate) else {
            return nil
        }
        return readinessTrend.first { Calendar.current.isDate($0.date, inSameDayAs: yesterday) }.flatMap {
            MetricDisplayValue.positive($0.value).map { Int($0.rounded()) }
        }
    }

    private func averagePreviousScores(_ trend: [TrendDataPoint]) -> Int? {
        let previous = trend.filter {
            $0.date < Calendar.current.startOfDay(for: recoveryVM.selectedDate)
                && MetricDisplayValue.positive($0.value) != nil
        }
        guard !previous.isEmpty else { return nil }
        return Int((previous.map(\.value).reduce(0, +) / Double(previous.count)).rounded())
    }

    private var footerSummary: String? {
        let parts = coachingReasons.prefix(2)
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    // MARK: - Weekly activity helpers

    private var weeklyActivityWeekLabel: String {
        let weekOfYear = Calendar.current.component(.weekOfYear, from: recoveryVM.selectedDate)
        let runs = weeklySummaryVM.dailyRunDistancesKm.filter { $0 > 0 }.count
        let week = String(localized: "Week", comment: "Week prefix in weekly activity card")
        let dayWord = String(localized: "days", comment: "Days suffix in weekly activity card")
        return "\(week) \(weekOfYear) · \(runs)/7 \(dayWord)"
    }

    // MARK: - Deviation Helpers

    private func hrvDeviationStatus(_ hrv: Double, baseline: PersonalBaseline?) -> DeviationStatus {
        guard let baseline, let avg = baseline.hrvAverage else {
            return hrv >= 50 ? .normal : .belowNormal
        }
        let std = baseline.hrvStdDev ?? (avg * 0.15)
        let zScore = (hrv - avg) / max(std, 1)
        if zScore > 0.5 { return .excellent }
        if zScore >= -0.5 { return .normal }
        return .belowNormal
    }

    private func rhrDeviationStatus(_ rhr: Double, baseline: PersonalBaseline?) -> DeviationStatus {
        guard let baseline, let avg = baseline.restingHeartRateAverage else {
            return rhr <= 65 ? .normal : .aboveNormal
        }
        let std = baseline.restingHeartRateStdDev ?? (avg * 0.10)
        let zScore = (rhr - avg) / max(std, 1)
        if zScore < -0.5 { return .excellent }
        if zScore <= 0.5 { return .normal }
        return .aboveNormal
    }

    private func respDeviationStatus(_ rate: Double, baseline: PersonalBaseline?) -> DeviationStatus {
        guard let baseline, let avg = baseline.respiratoryRateAverage else {
            if rate >= 12 && rate <= 16 { return .normal }
            if rate < 12 { return .excellent }
            return .aboveNormal
        }
        let std = baseline.respiratoryRateStdDev ?? 1.5
        let zScore = (rate - avg) / max(std, 0.5)
        if zScore < -0.5 { return .excellent }
        if zScore <= 0.5 { return .normal }
        return .aboveNormal
    }

    private func spo2DeviationStatus(_ spo2: Double) -> DeviationStatus {
        if spo2 >= 98 { return .excellent }
        if spo2 >= 95 { return .normal }
        if spo2 >= 90 { return .belowNormal }
        return .poor
    }
}

// MARK: - Metric Sheet Item

struct MetricSheetItem: Identifiable {
    let metricType: MetricType
    let value: Double
    let unit: String
    let deviationStatus: DeviationStatus?
    let baseline: PersonalBaseline?
    let trend: [TrendDataPoint]
    let activityData: DailyActivityData?
    let caloriesBreakdown: [CaloriesBreakdownPoint]?

    var id: String {
        "\(metricType)"
    }
}

#Preview {
    DashboardView()
        .environment(ThemeManager())
        .environmentObject(RevenueCatManager.shared)
        .preferredColorScheme(.dark)
}
