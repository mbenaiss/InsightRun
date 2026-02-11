//
//  DashboardView.swift
//  InsightRun
//
//  Main dashboard combining recovery, readiness, coaching, and weekly activity
//

import SwiftUI

struct DashboardView: View {
    @StateObject private var recoveryVM = RecoveryViewModel()
    @StateObject private var readinessVM = DailyReadinessViewModel()
    @StateObject private var weeklySummaryVM = WeeklySummaryViewModel()
    @StateObject private var notificationRouter = NotificationRouter.shared
    @ObservedObject private var contextProvider = UnifiedAIContextProvider.shared
    @ObservedObject private var trainingLoadService = TrainingLoadService.shared
    @Environment(ThemeManager.self) private var themeManager
    @EnvironmentObject private var revenueCatManager: RevenueCatManager

    @State private var showSettings = false
    @State private var showingCalendar = false
    @State private var showWorkoutPlan = false
    @State private var showSubscriptionPaywall = false
    @State private var selectedScoreType: ScoreType?

    // MARK: - Computed Properties

    private var effortPercentage: Int {
        let weeklyMinutes = weeklySummaryVM.totalDuration / 60.0
        let target: Double = 150
        return Int(min(weeklyMinutes / target * 100, 100))
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.irBackgroundApp.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        dateHeader
                            .padding(.horizontal)

                        recoveryHeader
                            .padding(.horizontal)

                        if revenueCatManager.hasAIAccess {
                            coachingSection
                                .padding(.horizontal)
                        } else {
                            subscriptionCTACard
                                .padding(.horizontal)
                        }

                        weeklyActivitySection

                        weeklySummaryLink

                        cardiacLoadSection
                            .padding(.horizontal)

                        trendsSection
                            .padding(.horizontal)

                        sleepSection
                            .padding(.horizontal)
                    }
                    .padding(.top, Spacing.sm)
                    .padding(.bottom, 100)
                }
                .refreshable {
                    await refreshAll()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "person.circle")
                            .font(.title3)
                            .foregroundStyle(Color.irTextSecondary)
                    }
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
                        Task { await recoveryVM.loadRecoveryMetrics(for: date) }
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
                    case .effort: return effortPercentage
                    case .sleep: return recoveryVM.recoveryMetrics?.sleepData?.qualityScore ?? 0
                    case .readiness: return readinessVM.readinessScore ?? 0
                    case .cardiacLoad: return trainingLoadService.cardiacLoadScore ?? 0
                    }
                }()
                let trend: [TrendDataPoint] = {
                    switch type {
                    case .cardiacLoad:
                        return trainingLoadService.cardiacLoadTrendData
                    case .effort:
                        return generateTrendData(baseValue: Double(effortPercentage), variance: 15)
                    case .sleep:
                        let sleepScore = Double(recoveryVM.recoveryMetrics?.sleepData?.qualityScore ?? 0)
                        return generateTrendData(baseValue: sleepScore, variance: 10)
                    case .readiness:
                        let readiness = Double(readinessVM.readinessScore ?? 0)
                        return generateTrendData(baseValue: readiness, variance: 12)
                    }
                }()
                ScoreExplanationSheet(
                    scoreType: type,
                    score: score,
                    sleepDurationHours: recoveryVM.recoveryMetrics?.sleepData.map { $0.totalSleepDuration / 3600.0 },
                    sleepEfficiency: recoveryVM.recoveryMetrics?.sleepData?.sleepEfficiency,
                    trendData: trend,
                    cardiacLoadStatus: type == .cardiacLoad ? trainingLoadService.cardiacLoadStatus : nil,
                    recoveryMetrics: recoveryVM.recoveryMetrics
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
            .task {
                await refreshAll()

                if let recovery = recoveryVM.recoveryMetrics {
                    contextProvider.recoveryMetrics = recovery
                }
            }
        }
    }

    // MARK: - Data Loading

    private func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await recoveryVM.loadRecoveryMetrics() }
            group.addTask { await readinessVM.fetchDailyReadiness() }
            group.addTask { await weeklySummaryVM.load() }
            group.addTask { await TrainingLoadService.shared.analyzeCardiacLoad() }
        }
    }

    // MARK: - Recovery Header (3 Circles)

    private var recoveryHeader: some View {
        HStack(spacing: Spacing.lg) {
            Button {
                selectedScoreType = .effort
            } label: {
                circleColumn(
                    score: effortPercentage,
                    label: String(localized: "Effort", comment: "Dashboard effort circle label")
                )
            }
            .buttonStyle(.plain)

            Button {
                selectedScoreType = .sleep
            } label: {
                circleColumn(
                    score: recoveryVM.recoveryMetrics?.sleepData?.qualityScore ?? 0,
                    label: String(localized: "Sleep", comment: "Dashboard sleep circle label")
                )
            }
            .buttonStyle(.plain)

            Button {
                selectedScoreType = .readiness
            } label: {
                circleColumn(
                    score: readinessVM.readinessScore ?? 0,
                    label: String(localized: "Readiness", comment: "Dashboard readiness circle label")
                )
            }
            .buttonStyle(.plain)
        }
        .cardStyle()
    }

    private func circleColumn(score: Int, label: String) -> some View {
        let progress = Double(score) / 100.0
        let colors: [Color] = switch score {
        case 80...100: [.green.opacity(0.7), .green]
        case 60..<80: [.yellow.opacity(0.7), .yellow]
        case 40..<60: [.orange.opacity(0.7), .orange]
        default: [.red.opacity(0.7), .red]
        }

        return VStack(spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 8)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: colors),
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 1), value: progress)

                Text("\(score)%")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.irTextPrimary)
            }
            .frame(width: 80, height: 80)

            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Color.irTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Coaching Section

    private var coachingSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Label(
                String(localized: "AI Coaching", comment: "Dashboard coaching section title"),
                systemImage: "sparkles"
            )
            .font(.headline)
            .foregroundStyle(Color.irPrimaryAccent.gradient)

            Text(coachingRecommendation)
                .font(.body)
                .lineSpacing(4)
                .foregroundStyle(Color.irTextPrimary)

            if readinessVM.readinessScore != nil {
                Divider()

                HStack(spacing: Spacing.sm) {
                    Image(systemName: readinessVM.suggestedWorkoutType.icon)
                        .font(.title3)
                        .foregroundStyle(readinessVM.status.color)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Suggested Workout", comment: "Suggested workout label"))
                            .font(.caption)
                            .foregroundStyle(Color.irTextSecondary)
                        Text(readinessVM.suggestedWorkoutType.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.irTextPrimary)
                    }
                }
            }

            Button {
                showWorkoutPlan = true
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .foregroundStyle(.white)

                    Text(String(localized: "Create a training plan", comment: "Dashboard create plan button"))
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(Spacing.md)
                .background(
                    LinearGradient(
                        colors: [Color.irPrimaryAccent, .cyan],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            }
            .buttonStyle(.plain)
        }
        .cardStyle()
    }

    private var coachingRecommendation: String {
        if !readinessVM.recommendation.isEmpty {
            return readinessVM.recommendation
        }
        return recoveryVM.recoveryMetrics?.recoveryStatus.recommendation
            ?? String(localized: "Loading your coaching insights...", comment: "Coaching loading placeholder")
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
                showSubscriptionPaywall = true
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

    // MARK: - Cardiac Load Section

    @ViewBuilder
    private var cardiacLoadSection: some View {
        if let score = trainingLoadService.cardiacLoadScore {
            CardiacLoadCard(
                score: score,
                status: trainingLoadService.cardiacLoadStatus,
                trendData: trainingLoadService.cardiacLoadTrendData,
                onTap: {
                    selectedScoreType = .cardiacLoad
                }
            )
        }
    }

    // MARK: - Trends Section

    @ViewBuilder
    private var trendsSection: some View {
        if let recovery = recoveryVM.recoveryMetrics {
            if let hrv = recovery.hrvAverage {
                MetricTrendCard(
                    icon: "waveform.path.ecg",
                    iconColor: .blue,
                    title: String(localized: "HRV at rest", comment: "HRV metric title"),
                    value: hrv,
                    unit: "ms",
                    deviationStatus: getHRVDeviationStatus(hrv, baseline: recovery.baseline),
                    metricType: .hrv,
                    trendData: generateTrendData(baseValue: hrv),
                    baseline: recovery.baseline,
                    recoveryMetrics: recovery
                )
            }

            if let rhr = recovery.restingHeartRate {
                MetricTrendCard(
                    icon: "heart.fill",
                    iconColor: .red,
                    title: String(localized: "Resting HR", comment: "Resting heart rate metric title"),
                    value: rhr,
                    unit: "bpm",
                    deviationStatus: getRHRDeviationStatus(rhr, baseline: recovery.baseline),
                    metricType: .restingHeartRate,
                    trendData: generateTrendData(baseValue: rhr),
                    baseline: recovery.baseline,
                    recoveryMetrics: recovery
                )
            }

            if let respRate = recovery.respiratoryRate {
                MetricTrendCard(
                    icon: "lungs.fill",
                    iconColor: .teal,
                    title: String(localized: "Respiratory rate", comment: "Respiratory rate metric title"),
                    value: respRate,
                    unit: "rpm",
                    deviationStatus: getRespiratoryDeviationStatus(respRate, baseline: recovery.baseline),
                    metricType: .respiratoryRate,
                    trendData: generateTrendData(baseValue: respRate),
                    baseline: recovery.baseline,
                    recoveryMetrics: recovery
                )
            }

            if let spo2 = recovery.oxygenSaturation {
                MetricTrendCard(
                    icon: "drop.fill",
                    iconColor: .cyan,
                    title: String(localized: "Oxygen saturation", comment: "SpO2 metric title"),
                    value: spo2,
                    unit: "%",
                    deviationStatus: getSpO2DeviationStatus(spo2),
                    metricType: .oxygenSaturation,
                    trendData: generateTrendData(baseValue: spo2, variance: 2),
                    baseline: recovery.baseline,
                    recoveryMetrics: recovery
                )
            }
        }
    }

    // MARK: - Sleep Section

    @ViewBuilder
    private var sleepSection: some View {
        if let sleep = recoveryVM.recoveryMetrics?.sleepData {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label(
                    String(localized: "Sleep", comment: "Section header for sleep metrics"),
                    systemImage: "moon.fill"
                )
                .font(.headline)
                .foregroundStyle(Color.irTextPrimary)

                HealthMetricRow(
                    icon: "moon.fill",
                    iconColor: .indigo,
                    title: String(localized: "Sleep session", comment: "Label for time of sleep session"),
                    value: sleep.formattedSleepTime
                )

                HealthMetricRow(
                    icon: "bed.double.fill",
                    iconColor: .blue,
                    title: String(localized: "Sleep duration", comment: "Label for total sleep duration"),
                    value: sleep.formattedTotalSleep
                )

                if let napDuration = sleep.formattedNapDuration {
                    HealthMetricRow(
                        icon: "powersleep",
                        iconColor: .orange,
                        title: String(localized: "Naps", comment: "Label for nap duration"),
                        value: napDuration
                    )
                }

                HealthMetricRow(
                    icon: "chart.bar.fill",
                    iconColor: .teal,
                    title: String(localized: "Efficiency", comment: "Label for sleep efficiency percentage"),
                    value: String(format: "%.0f%%", sleep.sleepEfficiency)
                )

                if let deep = sleep.deepSleepDuration,
                   let core = sleep.coreSleepDuration,
                   let rem = sleep.remSleepDuration {
                    Divider()
                        .padding(.vertical, Spacing.xxs)

                    Text(String(localized: "Sleep stages", comment: "Section header for sleep stages breakdown"))
                        .font(.subheadline)
                        .foregroundStyle(Color.irTextSecondary)

                    SleepStageRow(
                        stage: String(localized: "Deep", comment: "Deep sleep stage label"),
                        duration: deep,
                        color: .blue
                    )
                    SleepStageRow(
                        stage: String(localized: "Light", comment: "Light sleep stage label"),
                        duration: core,
                        color: .cyan
                    )
                    SleepStageRow(
                        stage: String(localized: "REM", comment: "REM sleep stage label"),
                        duration: rem,
                        color: .indigo
                    )
                }
            }
            .cardStyle()
        }
    }

    // MARK: - Weekly Activity Stats

    private var weeklyActivitySection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Label(
                String(localized: "Weekly Activity", comment: "Section header for weekly activity"),
                systemImage: "figure.run"
            )
            .font(.headline)
            .foregroundStyle(Color.irTextPrimary)

            HStack(spacing: Spacing.lg) {
                statColumn(
                    title: String(localized: "Distance", comment: "Weekly distance label"),
                    value: weeklySummaryVM.formattedTotalDistance
                )

                statColumn(
                    title: String(localized: "Time", comment: "Weekly time label"),
                    value: weeklySummaryVM.formattedTotalDuration
                )

                statColumn(
                    title: String(localized: "Pace", comment: "Weekly pace label"),
                    value: weeklySummaryVM.formattedAveragePace
                )
            }
        }
        .cardStyle()
        .padding(.horizontal)
    }

    private func statColumn(title: String, value: String) -> some View {
        VStack(spacing: Spacing.xxs) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(Color.irTextPrimary)

            Text(title)
                .font(.caption)
                .foregroundStyle(Color.irTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Weekly Summary Link

    private var weeklySummaryLink: some View {
        NavigationLink {
            WeeklySummaryView()
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: "calendar")
                    .font(.title3)
                    .foregroundStyle(Color.irPrimaryAccent.gradient)

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Weekly Summary", comment: "Weekly summary link title"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.irTextPrimary)

                    Text(String(localized: "Review your performance & recovery", comment: "Weekly summary link subtitle"))
                        .font(.caption2)
                        .foregroundStyle(Color.irTextSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(Color.irTextSecondary)
            }
            .cardStyle(padding: Spacing.md)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    // MARK: - Date Header

    private var dateHeader: some View {
        Button {
            showingCalendar = true
        } label: {
            HStack(spacing: Spacing.sm) {
                Text(formattedDateTitle)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.irTextPrimary)

                Image(systemName: "chevron.down")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.irTextSecondary)

                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private var formattedDateTitle: String {
        let selected = recoveryVM.selectedDate
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale.current

        if calendar.isDateInToday(selected) {
            formatter.dateFormat = "d MMMM"
            return String(localized: "Today", comment: "Dashboard date label for today") + ", " + formatter.string(from: selected)
        } else if calendar.isDateInYesterday(selected) {
            formatter.dateFormat = "d MMMM"
            return String(localized: "Yesterday", comment: "Dashboard date label for yesterday") + ", " + formatter.string(from: selected)
        } else {
            formatter.dateFormat = "EEEE, d MMMM"
            return formatter.string(from: selected).capitalized
        }
    }

    // MARK: - Deviation Helpers

    private func getHRVDeviationStatus(_ hrv: Double, baseline: PersonalBaseline?) -> DeviationStatus {
        guard let baseline = baseline, let avg = baseline.hrvAverage else {
            return hrv >= 50 ? .normal : .belowNormal
        }
        let std = baseline.hrvStdDev ?? (avg * 0.15)
        let zScore = (hrv - avg) / max(std, 1)
        if zScore > 0.5 { return .excellent }
        if zScore >= -0.5 { return .normal }
        return .belowNormal
    }

    private func getRHRDeviationStatus(_ rhr: Double, baseline: PersonalBaseline?) -> DeviationStatus {
        guard let baseline = baseline, let avg = baseline.restingHeartRateAverage else {
            return rhr <= 65 ? .normal : .aboveNormal
        }
        let std = baseline.restingHeartRateStdDev ?? (avg * 0.10)
        let zScore = (rhr - avg) / max(std, 1)
        if zScore < -0.5 { return .excellent }
        if zScore <= 0.5 { return .normal }
        return .aboveNormal
    }

    private func getRespiratoryDeviationStatus(_ rate: Double, baseline: PersonalBaseline?) -> DeviationStatus {
        guard let baseline = baseline, let avg = baseline.respiratoryRateAverage else {
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

    private func getSpO2DeviationStatus(_ spo2: Double) -> DeviationStatus {
        if spo2 >= 98 { return .excellent }
        if spo2 >= 95 { return .normal }
        if spo2 >= 90 { return .belowNormal }
        return .poor
    }

    private func generateTrendData(baseValue: Double, variance: Double? = nil) -> [TrendDataPoint] {
        let actualVariance = variance ?? (baseValue * 0.15)
        return (0..<7).map { day in
            let randomVariation = Double.random(in: -actualVariance...actualVariance)
            let value = day == 6 ? baseValue : baseValue + randomVariation
            return TrendDataPoint(
                date: Calendar.current.date(byAdding: .day, value: -6 + day, to: Date())!,
                value: max(0, value)
            )
        }
    }
}

#Preview {
    DashboardView()
        .environment(ThemeManager())
        .environmentObject(RevenueCatManager.shared)
}
