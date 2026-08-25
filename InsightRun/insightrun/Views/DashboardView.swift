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
    @ObservedObject private var trainingLoadService = TrainingLoadService.shared // swiftlint:disable:this private_state_object
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var revenueCatManager: RevenueCatManager

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
    @State private var caloriesBreakdownTrend: [CaloriesBreakdownPoint] = []
    @State private var todaySession: (goal: RaceGoal, day: TrainingDay)?
    @State private var latestWorkout: WorkoutModel?
    @State private var isActivationLoading = false

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
                        Task {
                            await recoveryVM.loadRecoveryMetrics(for: date)
                            await TrainingLoadService.shared.analyzeDailyEffort(for: date)
                        }
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
                    activityData: type == .effort ? latestActivityData : nil
                )
                .environmentObject(revenueCatManager)
                .presentationDetents([.large])
            }
            .sheet(item: $selectedMetricSheet) { item in
                ScoreExplanationSheet(
                    metricType: item.metricType,
                    currentValue: item.value,
                    unit: item.unit,
                    deviationStatus: item.deviationStatus,
                    baseline: item.baseline,
                    trendData: item.trend,
                    recoveryMetrics: recoveryVM.recoveryMetrics,
                    activityData: item.activityData,
                    caloriesBreakdown: item.caloriesBreakdown
                )
                .environmentObject(revenueCatManager)
                .presentationDetents([.large])
            }
            .navigationDestination(isPresented: $notificationRouter.showWeeklySummary) {
                WeeklySummaryView()
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
                                await refreshAll()
                            }
                        }
                    },
                    onDecline: {
                        readinessVM.needsConsent = false
                    }
                )
            }
            .indexationGate(isPresented: $readinessVM.needsIndexation) {
                await refreshAll()
            }
            .task {
                await refreshAll()
                await loadTrendData()
                await loadLatestWorkout()
                loadTodaySession()

                if let recovery = recoveryVM.recoveryMetrics {
                    contextProvider.recoveryMetrics = recovery
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .trainingDayCompleted)) { _ in
                loadTodaySession()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                let today = Calendar.current.startOfDay(for: Date())
                if recoveryVM.selectedDate != today {
                    recoveryVM.selectedDate = today
                    recoveryVM.metricsCache.removeAll()
                    hasForwardPage = false
                    currentPage = 1
                    Task { await refreshAll(forceRefresh: true) }
                } else {
                    Task { await refreshCoaching() }
                }
            }
        }
    }

    // MARK: - Data Loading

    @MainActor
    private func refreshAll(forceRefresh: Bool = false) async {
        let tls = trainingLoadService
        let selectedDate = recoveryVM.selectedDate

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await recoveryVM.loadRecoveryMetrics() }
            group.addTask { await weeklySummaryVM.load() }
            group.addTask { await tls.analyzeCardiacLoad() }
            group.addTask { await tls.analyzeDailyEffort(for: selectedDate) }
        }

        let activityData = await HealthKitManager.shared.fetchDailyActivityData(for: selectedDate)
        latestActivityData = activityData
        await readinessVM.fetchDailyReadiness(
            activityData: activityData,
            effortScore: tls.dailyEffortScore,
            cardiacLoadScore: tls.cardiacLoadScore,
            cardiacLoadStatus: tls.cardiacLoadStatus,
            forceRefresh: forceRefresh
        )
    }

    @MainActor
    private func refreshCoaching(forceRefresh: Bool = false) async {
        let tls = trainingLoadService
        let selectedDate = recoveryVM.selectedDate

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await recoveryVM.loadRecoveryMetrics() }
            group.addTask { await tls.analyzeDailyEffort(for: selectedDate) }
            group.addTask { await tls.analyzeCardiacLoad() }
        }

        let activityData = await HealthKitManager.shared.fetchDailyActivityData(for: selectedDate)
        latestActivityData = activityData
        await readinessVM.fetchDailyReadiness(
            activityData: activityData,
            effortScore: tls.dailyEffortScore,
            cardiacLoadScore: tls.cardiacLoadScore,
            cardiacLoadStatus: tls.cardiacLoadStatus,
            forceRefresh: forceRefresh
        )
    }

    @MainActor
    private func loadTrendData() async {
        let service = MetricTrendDataService.shared
        async let hrv = service.metricTrend(for: .hrv)
        async let rhr = service.metricTrend(for: .restingHeartRate)
        async let resp = service.metricTrend(for: .respiratoryRate)
        async let spo2 = service.metricTrend(for: .oxygenSaturation)
        async let effort = service.effortTrend()
        async let sleep = service.sleepTrend()
        async let readiness = service.readinessTrend()
        async let caloriesTotal = service.caloriesTotalTrend()
        async let caloriesBreakdown = service.caloriesBreakdownTrend()

        hrvTrend = await hrv
        rhrTrend = await rhr
        respTrend = await resp
        spo2Trend = await spo2
        effortTrend = await effort
        sleepTrend = await sleep
        readinessTrend = await readiness
        caloriesTotalTrend = await caloriesTotal
        caloriesBreakdownTrend = await caloriesBreakdown
    }

    // MARK: - Day Page

    private var dayPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                dateHeader
                    .padding(.horizontal)

                section(title: String(localized: "Next action", comment: "Dashboard activation section title")) {
                    activationActionCard
                }

                // Disponibilité
                section(title: String(localized: "Availability", comment: "Dashboard section: availability")) {
                    PulseRingHero(
                        score: readinessVM.readinessScore ?? 0,
                        yesterdayScore: yesterdayReadinessScore,
                        statusTitle: readinessVM.status.title,
                        statusColor: readinessVM.status.color,
                        footerSummary: footerSummary,
                        onTap: { selectedScoreType = .readiness }
                    )
                }

                // Charge & récupération
                section(
                    title: String(localized: "Load & recovery", comment: "Dashboard section: load and recovery")
                ) {
                    HStack(spacing: Spacing.sm) {
                        SecondaryScoreCard(
                            title: String(localized: "Effort", comment: "Dashboard effort label"),
                            score: trainingLoadService.dailyEffortScore,
                            baseline: 55,
                            accent: .irWarning,
                            trend: effortTrend.suffix(7).map(\.value),
                            onTap: { selectedScoreType = .effort }
                        )
                        .accessibilityIdentifier("score-effort")

                        // Three-way pick to keep the second slot meaningful:
                        // 1. No-sleep mode + enough training history → freshness (TSB) card.
                        // 2. No-sleep mode + CTL too low for a reliable TSB → neutral baseline card,
                        //    avoids falling back to a Sleep 0/100 that actively misinforms users
                        //    who have explicitly opted out of sleep tracking.
                        // 3. Otherwise → legacy Sleep card (its 0/100 empty state is fine for users
                        //    who do track sleep but happen to be missing one night).
                        if readinessVM.isNoSleepMode, let freshness = trainingLoadService.freshnessScore {
                            SecondaryScoreCard(
                                title: String(localized: "Freshness", comment: "Dashboard TSB-based freshness label, shown when sleep tracking is unavailable"),
                                score: freshness,
                                baseline: 55,
                                accent: .irSuccess,
                                trend: trainingLoadService.freshnessTrendData.suffix(7).map(\.value),
                                onTap: { selectedScoreType = .freshness }
                            )
                            .accessibilityIdentifier("score-freshness")
                        } else if readinessVM.isNoSleepMode {
                            BuildingBaselineCard(
                                title: String(localized: "Freshness", comment: "Dashboard freshness label, shown when sleep tracking is unavailable"),
                                message: String(localized: "Building your baseline. Log a few weeks of training to unlock your freshness score.", comment: "Empty-state message shown on the freshness card while we don't have enough training history"),
                                onTap: { selectedScoreType = .freshness }
                            )
                            .accessibilityIdentifier("score-freshness-building")
                        } else {
                            SecondaryScoreCard(
                                title: String(localized: "Sleep", comment: "Dashboard sleep label"),
                                score: recoveryVM.recoveryMetrics?.sleepData?.qualityScore ?? 0,
                                baseline: 75,
                                accent: .irSuccess,
                                trend: sleepTrend.suffix(7).map(\.value),
                                onTap: { selectedScoreType = .sleep }
                            )
                            .accessibilityIdentifier("score-sleep")
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
                        title: String(localized: "Recommended session", comment: "Dashboard section: recommended session")
                    ) {
                        TodaySessionCard(
                            goal: session.goal,
                            workout: workout,
                            onTap: { navigateToGoalSession(session.goal) }
                        )
                    }
                }

                // Activité hebdo
                section(
                    title: String(localized: "Weekly activity", comment: "Dashboard section: weekly activity")
                ) {
                    WeeklyActivityCard(
                        weekLabel: weeklyActivityWeekLabel,
                        totalDistanceLabel: weeklySummaryVM.formattedTotalDistance,
                        totalDurationLabel: weeklySummaryVM.formattedTotalDuration,
                        averagePaceLabel: weeklySummaryVM.formattedAveragePace,
                        dailyEfforts: weeklySummaryVM.dailyRunDistancesKm,
                        highlightedIndex: weeklySummaryVM.todayIndexInWeek,
                        onTap: { notificationRouter.showWeeklySummary = true }
                    )
                }

                // Signaux
                section(
                    title: String(localized: "Signals", comment: "Dashboard section: physiological signals")
                ) {
                    signalsGrid
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
        latestWorkout = (try? await HealthKitManager.shared.fetchRunningWorkouts(limit: 1))?.workouts.first
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
        Task { await refreshAll() }

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

    // MARK: - Signals grid

    @ViewBuilder
    private var signalsGrid: some View {
        let recovery = recoveryVM.recoveryMetrics
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: Spacing.sm), GridItem(.flexible(), spacing: Spacing.sm)],
            spacing: Spacing.sm
        ) {
            if let hrv = recovery?.hrvAverage {
                let status = hrvDeviationStatus(hrv, baseline: recovery?.baseline)
                SignalCard(
                    icon: "waveform.path.ecg",
                    color: Color.irPrimaryAccent,
                    label: String(localized: "HRV at rest", comment: "HRV metric title"),
                    value: Formatters.integer(Int(hrv.rounded())),
                    unit: "ms",
                    status: status.localizedDescription(for: .hrv),
                    statusColor: status.color,
                    trend: hrvTrend.suffix(7).map(\.value),
                    onTap: { presentMetricSheet(.hrv, value: hrv, unit: "ms", status: status, trend: hrvTrend) }
                )
            }

            if let rhr = recovery?.restingHeartRate {
                let status = rhrDeviationStatus(rhr, baseline: recovery?.baseline)
                SignalCard(
                    icon: "heart.fill",
                    color: .irWarning,
                    label: String(localized: "Resting HR", comment: "Resting heart rate metric title"),
                    value: Formatters.integer(Int(rhr.rounded())),
                    unit: "bpm",
                    status: status.localizedDescription(for: .restingHeartRate),
                    statusColor: status.color,
                    trend: rhrTrend.suffix(7).map(\.value),
                    onTap: { presentMetricSheet(.restingHeartRate, value: rhr, unit: "bpm", status: status, trend: rhrTrend) }
                )
            }

            if let resp = recovery?.respiratoryRate {
                let status = respDeviationStatus(resp, baseline: recovery?.baseline)
                SignalCard(
                    icon: "lungs.fill",
                    color: .irSuccess,
                    label: String(localized: "Respiratory rate", comment: "Respiratory rate metric title"),
                    value: Formatters.decimal(resp, fractionDigits: 1),
                    unit: "rpm",
                    status: status.localizedDescription(for: .respiratoryRate),
                    statusColor: status.color,
                    trend: respTrend.suffix(7).map(\.value),
                    onTap: { presentMetricSheet(.respiratoryRate, value: resp, unit: "rpm", status: status, trend: respTrend) }
                )
            }

            if let spo2 = recovery?.oxygenSaturation {
                let status = spo2DeviationStatus(spo2)
                SignalCard(
                    icon: "drop.fill",
                    color: .irPrimaryAccent,
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
        }
    }

    @ViewBuilder
    private var cardiacLoadSignalCard: some View {
        if let load = trainingLoadService.cardiacLoadScore {
            let status = trainingLoadService.cardiacLoadStatus
            SignalCard(
                icon: "shoe.2.fill",
                color: status.color,
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
        if let activity = latestActivityData {
            let activeKcal = Formatters.integer(Int(activity.activeCalories.rounded()))
            let activeLabel = String(localized: "active", comment: "Active calories label")
            SignalCard(
                icon: "flame.fill",
                color: .irWarning,
                label: String(localized: "Calories", comment: "Calories metric title"),
                value: Formatters.integer(Int(activity.totalCalories.rounded())),
                unit: "kcal",
                status: "\(activeKcal) " + activeLabel,
                statusColor: .irWarning,
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

    private func presentMetricSheet(
        _ metricType: MetricType,
        value: Double,
        unit: String,
        status: DeviationStatus,
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
        return formatter.string(from: Date())
    }

    private var coachingRecommendation: String {
        if !readinessVM.recommendationSummary.isEmpty {
            return readinessVM.recommendationSummary
        }
        if !readinessVM.recommendation.isEmpty {
            return readinessVM.recommendation
        }
        return recoveryVM.recoveryMetrics?.recoveryStatus.recommendation
            ?? String(localized: "Loading your coaching insights...", comment: "Coaching loading placeholder")
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
        if let hrv = recoveryVM.recoveryMetrics?.hrvAverage {
            reasons.append(String(localized: "dashboard.coach.reason.hrv", defaultValue: "HRV \(Formatters.integer(Int(hrv.rounded()))) ms", comment: "Coach reason chip: resting HRV value in ms"))
        }
        if let rhr = recoveryVM.recoveryMetrics?.restingHeartRate {
            reasons.append(String(localized: "dashboard.coach.reason.rhr", defaultValue: "Resting HR \(Formatters.heartRate(rhr))", comment: "Coach reason chip: resting heart rate"))
        }
        if let sleep = recoveryVM.recoveryMetrics?.sleepData {
            reasons.append(sleep.formattedTotalSleep)
        }
        let load = trainingLoadService.cardiacLoadScore
        if let load {
            reasons.append(String(localized: "dashboard.coach.reason.load", defaultValue: "Load \(Formatters.integer(load))", comment: "Coach reason chip: cardiac load score"))
        }
        return reasons
    }

    private var coachingDetail: String {
        if !readinessVM.recommendation.isEmpty {
            return readinessVM.recommendation
        }
        return recoveryVM.recoveryMetrics?.recoveryStatus.recommendation ?? ""
    }

    // MARK: - Pulse Ring helpers

    private var yesterdayReadinessScore: Int? {
        let trend = readinessTrend
        guard trend.count >= 2 else { return nil }
        let yesterday = trend[trend.count - 2]
        let value = Int(yesterday.value.rounded())
        return value > 0 ? value : nil
    }

    private var footerSummary: String? {
        let parts = coachingReasons.prefix(2)
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    // MARK: - Weekly activity helpers

    private var weeklyActivityWeekLabel: String {
        let weekOfYear = Calendar.current.component(.weekOfYear, from: Date())
        let runs = weeklySummaryVM.runCount
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
