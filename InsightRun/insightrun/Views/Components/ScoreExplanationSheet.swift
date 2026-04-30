//
//  ScoreExplanationSheet.swift
//  InsightRun
//
//  Unified detail sheet for dashboard scores and health metrics
//

import SwiftUI
import Charts

// MARK: - Score Type Enum

enum ScoreType: Identifiable {
    case effort
    case sleep
    case readiness
    case cardiacLoad

    var id: String {
        switch self {
        case .effort: return "effort"
        case .sleep: return "sleep"
        case .readiness: return "readiness"
        case .cardiacLoad: return "cardiacLoad"
        }
    }
}

// MARK: - Score Explanation Sheet

struct ScoreExplanationSheet: View {

    private enum DetailMode {
        case score(ScoreType)
        case metric(MetricType)
    }

    // Mode
    private let mode: DetailMode

    // Score properties
    private let score: Int
    private let sleepDurationHours: Double?
    private let sleepEfficiency: Double?
    private let cardiacLoadStatus: CardiacLoadStatus?
    private let activityData: DailyActivityData?

    // Metric properties
    private let metricValue: Double
    private let metricUnit: String
    private let deviationStatus: DeviationStatus?
    private let baseline: PersonalBaseline?
    private let caloriesBreakdown: [CaloriesBreakdownPoint]?

    // Shared
    var trendData: [TrendDataPoint]?
    var recoveryMetrics: RecoveryMetrics?

    // State
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var revenueCatManager: RevenueCatManager
    @StateObject private var analysisVM = ScoreAnalysisViewModel()
    @State private var selectedDate: Date?
    @State private var showSubscriptionPaywall = false
    @State private var showMedicalSources = false
    @State private var historyData: [TrendDataPoint] = []
    @State private var lastTrackedAnalysis: String?

    // MARK: - Score Init

    init(
        scoreType: ScoreType,
        score: Int,
        sleepDurationHours: Double? = nil,
        sleepEfficiency: Double? = nil,
        trendData: [TrendDataPoint]? = nil,
        cardiacLoadStatus: CardiacLoadStatus? = nil,
        recoveryMetrics: RecoveryMetrics? = nil,
        activityData: DailyActivityData? = nil
    ) {
        self.mode = .score(scoreType)
        self.score = score
        self.sleepDurationHours = sleepDurationHours
        self.sleepEfficiency = sleepEfficiency
        self.trendData = trendData
        self.cardiacLoadStatus = cardiacLoadStatus
        self.recoveryMetrics = recoveryMetrics
        self.activityData = activityData
        self.metricValue = 0
        self.metricUnit = ""
        self.deviationStatus = nil
        self.baseline = nil
        self.caloriesBreakdown = nil
    }

    // MARK: - Metric Init

    init(
        metricType: MetricType,
        currentValue: Double,
        unit: String,
        deviationStatus: DeviationStatus?,
        baseline: PersonalBaseline?,
        trendData: [TrendDataPoint]? = nil,
        recoveryMetrics: RecoveryMetrics? = nil,
        activityData: DailyActivityData? = nil,
        caloriesBreakdown: [CaloriesBreakdownPoint]? = nil
    ) {
        self.mode = .metric(metricType)
        self.metricValue = currentValue
        self.metricUnit = unit
        self.deviationStatus = deviationStatus
        self.baseline = baseline
        self.recoveryMetrics = recoveryMetrics
        self.trendData = trendData
        self.score = 0
        self.sleepDurationHours = nil
        self.sleepEfficiency = nil
        self.cardiacLoadStatus = nil
        self.activityData = activityData
        self.caloriesBreakdown = caloriesBreakdown
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                switch mode {
                case .score(let scoreType):
                    if scoreType == .cardiacLoad {
                        cardiacLoadBody
                    } else {
                        scoreBody(scoreType)
                    }
                case .metric:
                    metricBody
                }
            }
            .background(Color.irBackgroundApp)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.irTextSecondary)
                    }
                    .accessibilityIdentifier("sheet-close")
                }
            }
            .onAppear {
                if case .metric = mode, historyData.isEmpty, let data = trendData, !data.isEmpty {
                    historyData = data
                }
            }
            .task {
                guard revenueCatManager.hasAIAccess, let metrics = recoveryMetrics else { return }
                switch mode {
                case .score(let scoreType):
                    await analysisVM.analyze(scoreType: scoreType, score: score, recoveryMetrics: metrics, trendData: trendData)
                case .metric(let metricType):
                    await analysisVM.analyzeMetric(
                        metricType: metricType,
                        value: metricValue,
                        unit: metricUnit,
                        recoveryMetrics: metrics,
                        activityData: activityData
                    )
                }
            }
            .sheet(isPresented: $analysisVM.needsConsent) {
                AIConsentSheet(
                    onConsent: {
                        analysisVM.needsConsent = false
                        Task {
                            if await HistoricalSummaryStorage.shared.requiresIndexation() {
                                analysisVM.needsIndexation = true
                            } else {
                                await analysisVM.resumePendingAnalysis()
                            }
                        }
                    },
                    onDecline: {
                        analysisVM.needsConsent = false
                    }
                )
            }
            .indexationGate(isPresented: $analysisVM.needsIndexation) {
                await analysisVM.resumePendingAnalysis()
            }
        }
    }

    // MARK: - Navigation Title

    private var navigationTitle: String {
        switch mode {
        case .score(let scoreType):
            switch scoreType {
            case .effort: return String(localized: "Effort", comment: "Sheet title for effort")
            case .sleep: return String(localized: "Sleep", comment: "Sheet title for sleep")
            case .readiness: return String(localized: "Readiness", comment: "Sheet title for readiness")
            case .cardiacLoad: return String(localized: "Cardiac Load", comment: "Sheet title for cardiac load")
            }
        case .metric(let metricType):
            switch metricType {
            case .hrv: return String(localized: "Heart Rate Variability", comment: "HRV title")
            case .restingHeartRate: return String(localized: "Resting Heart Rate", comment: "RHR title")
            case .respiratoryRate: return String(localized: "Respiratory Rate", comment: "Respiratory rate title")
            case .oxygenSaturation: return String(localized: "Oxygen Saturation", comment: "SpO2 title")
            case .recoveryScore: return String(localized: "Recovery Score", comment: "Recovery score title")
            case .sleepDuration: return String(localized: "Sleep Duration", comment: "Sleep duration title")
            case .sleepEfficiency: return String(localized: "Sleep Efficiency", comment: "Sleep efficiency title")
            case .totalCalories: return String(localized: "Total calories", comment: "Total calories metric title")
            }
        }
    }

    // MARK: - Score Body (Effort, Sleep, Readiness)

    private func scoreBody(_ scoreType: ScoreType) -> some View {
        // Order: Hero → AI analysis → Trend → Components → Calculation → References.
        VStack(spacing: Spacing.dash) {
            scoreValueCard(scoreType)

            aiInsightCard

            if let data = trendData, !data.isEmpty {
                scoreTrendChart(data, scoreType: scoreType)
            }

            if scoreType == .effort, let activity = activityData {
                effortActivityCard(activity)
            }

            if scoreType == .sleep, let sleep = recoveryMetrics?.sleepData {
                sleepDataCard(sleep)
            }

            if scoreType == .readiness, let metrics = recoveryMetrics {
                readinessMetricsCard(metrics)
            }

            calculationSection(scoreType)
            scoreReferencesSection(scoreType)
        }
        .padding()
    }

    // MARK: - Cardiac Load Body

    private var cardiacLoadBody: some View {
        VStack(spacing: Spacing.dash) {
            cardiacLoadValueCard

            aiInsightCard

            if let data = trendData, !data.isEmpty {
                cardiacLoadChartCard(data)
            }

            scoreExplanationCard(.cardiacLoad)
            calculationSection(.cardiacLoad)
            scoreReferencesSection(.cardiacLoad)
        }
        .padding()
    }

    // MARK: - Metric Body (HRV, RHR, SpO2, Respiratory)

    private var metricBody: some View {
        VStack(spacing: Spacing.dash) {
            metricValueCard

            aiInsightCard

            if case .metric(.totalCalories) = mode,
               let breakdown = caloriesBreakdown,
               !breakdown.isEmpty {
                caloriesStackedHistoryChart(breakdown)
            } else {
                metricHistoryChart
            }

            if case .metric(.totalCalories) = mode, let activity = activityData {
                caloriesBreakdownCard(activity)
            }

            if let baseline = baseline {
                baselineComparisonCard(baseline)
            }

            metricExplanationCard
            metricReferenceCard
        }
        .padding()
    }

    // MARK: - Calories Breakdown Card

    private func caloriesBreakdownCard(_ activity: DailyActivityData) -> some View {
        DetailComponentsCard(
            title: String(localized: "Calories breakdown", comment: "Calories breakdown card header"),
            rows: [
                DetailComponentRow(
                    label: String(localized: "Resting", comment: "Basal/resting calories label"),
                    value: String(format: "%.0f", activity.basalCalories),
                    unit: "kcal"
                ),
                DetailComponentRow(
                    label: String(localized: "Active", comment: "Active calories label"),
                    value: String(format: "%.0f", activity.activeCalories),
                    unit: "kcal"
                ),
                DetailComponentRow(
                    label: String(localized: "Total calories", comment: "Total calories metric title"),
                    value: String(format: "%.0f", activity.totalCalories),
                    unit: "kcal"
                )
            ]
        )
    }

    // MARK: - Effort Activity Card

    private func effortActivityCard(_ activity: DailyActivityData) -> some View {
        DetailComponentsCard(
            title: String(localized: "Today's Activity", comment: "Effort activity card header"),
            rows: [
                DetailComponentRow(
                    label: String(localized: "Steps", comment: "Steps metric label"),
                    value: String(format: "%.0f", activity.steps)
                ),
                DetailComponentRow(
                    label: String(localized: "Active Calories", comment: "Active calories metric label"),
                    value: String(format: "%.0f", activity.activeCalories),
                    unit: "kcal"
                ),
                DetailComponentRow(
                    label: String(localized: "Exercise Minutes", comment: "Exercise minutes metric label"),
                    value: String(format: "%.0f", activity.exerciseMinutes),
                    unit: "min"
                )
            ]
        )
    }

    // MARK: - Sleep Data Card

    private func sleepDataCard(_ sleep: SleepData) -> some View {
        DetailComponentsCard(
            title: String(localized: "Sleep Details", comment: "Sleep data card header"),
            rows: sleepRows(for: sleep)
        )
    }

    private func sleepRows(for sleep: SleepData) -> [DetailComponentRow] {
        var rows: [DetailComponentRow] = [
            DetailComponentRow(
                label: String(localized: "Sleep session", comment: "Label for time of sleep session"),
                value: sleep.formattedSleepTime
            ),
            DetailComponentRow(
                label: String(localized: "Sleep duration", comment: "Label for total sleep duration"),
                value: sleep.formattedTotalSleep
            )
        ]

        if let napDuration = sleep.formattedNapDuration {
            rows.append(DetailComponentRow(
                label: String(localized: "Naps", comment: "Label for nap duration"),
                value: napDuration
            ))
        }

        rows.append(DetailComponentRow(
            label: String(localized: "Efficiency", comment: "Label for sleep efficiency percentage"),
            value: String(format: "%.0f", sleep.sleepEfficiency),
            unit: "%"
        ))

        if let deep = sleep.deepSleepDuration {
            rows.append(DetailComponentRow(
                label: String(localized: "Deep", comment: "Deep sleep stage label"),
                value: formatSleepStageDuration(deep)
            ))
        }
        if let core = sleep.coreSleepDuration {
            rows.append(DetailComponentRow(
                label: String(localized: "Light", comment: "Light sleep stage label"),
                value: formatSleepStageDuration(core)
            ))
        }
        if let rem = sleep.remSleepDuration {
            rows.append(DetailComponentRow(
                label: String(localized: "REM", comment: "REM sleep stage label"),
                value: formatSleepStageDuration(rem)
            ))
        }
        return rows
    }

    private func formatSleepStageDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 {
            return "\(h)h\(String(format: "%02d", m))"
        }
        return "\(m) min"
    }

    // MARK: - Readiness Metrics Card

    private func readinessMetricsCard(_ metrics: RecoveryMetrics) -> some View {
        DetailComponentsCard(
            title: String(localized: "Today's Metrics", comment: "Readiness metrics card header"),
            rows: readinessRows(for: metrics)
        )
    }

    private func readinessRows(for metrics: RecoveryMetrics) -> [DetailComponentRow] {
        var rows: [DetailComponentRow] = []
        if let hrv = metrics.hrvAverage {
            rows.append(DetailComponentRow(
                label: String(localized: "HRV", comment: "HRV metric label"),
                value: String(format: "%.0f", hrv),
                unit: "ms"
            ))
        }
        if let rhr = metrics.restingHeartRate {
            rows.append(DetailComponentRow(
                label: String(localized: "Resting HR", comment: "Resting heart rate label"),
                value: String(format: "%.0f", rhr),
                unit: "bpm"
            ))
        }
        if let respRate = metrics.respiratoryRate {
            rows.append(DetailComponentRow(
                label: String(localized: "Respiratory Rate", comment: "Respiratory rate label"),
                value: String(format: "%.1f", respRate),
                unit: "rpm"
            ))
        }
        if let spo2 = metrics.oxygenSaturation {
            rows.append(DetailComponentRow(
                label: String(localized: "SpO2", comment: "Oxygen saturation label"),
                value: String(format: "%.0f", spo2),
                unit: "%"
            ))
        }
        if let sleep = metrics.sleepData {
            rows.append(DetailComponentRow(
                label: String(localized: "Sleep", comment: "Sleep metric label"),
                value: sleep.formattedTotalSleep
            ))
            rows.append(DetailComponentRow(
                label: String(localized: "Sleep Efficiency", comment: "Sleep efficiency label"),
                value: String(format: "%.0f", sleep.sleepEfficiency),
                unit: "%"
            ))
        }
        return rows
    }

    // MARK: - Shared AI Insight Card

    private var aiInsightCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            aiInsightHeader

            aiInsightBody
        }
        .padding(Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .detailCard()
        .sheet(isPresented: $showSubscriptionPaywall) {
            SubscriptionPaywallView(isInitialFlow: false)
                .environmentObject(revenueCatManager)
        }
    }

    private var aiInsightHeader: some View {
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

            Text(String(localized: "Coach", comment: "Detail sheet AI analysis label").uppercased())
                .font(IRFont.eyebrow.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(Color.irTextSecondary)

            Spacer()
        }
    }

    @ViewBuilder
    private var aiInsightBody: some View {
        if !revenueCatManager.hasAIAccess {
            aiInsightPaywallContent
        } else if analysisVM.isLoading {
            aiInsightLoading(label: String(localized: "Analyzing...", comment: "AI analysis loading"))
        } else if let analysis = analysisVM.analysisText, !analysis.isEmpty {
            Text(analysis)
                .font(IRFont.body)
                .lineSpacing(3)
                .foregroundStyle(Color.irTextPrimary)
                .onAppear {
                    if lastTrackedAnalysis != analysis {
                        ReviewManager.shared.recordAIEngagement()
                        lastTrackedAnalysis = analysis
                    }
                }
        } else if let error = analysisVM.error {
            VStack(spacing: Spacing.md) {
                Image(systemName: "exclamationmark.triangle")
                    .font(IRFont.title2)
                    .foregroundStyle(Color.irWarning)

                Text(error)
                    .font(IRFont.body)
                    .foregroundStyle(Color.irTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
        } else {
            aiInsightLoading(label: String(localized: "Loading analysis...", comment: "AI analysis loading"))
        }
    }

    private var aiInsightPaywallContent: some View {
        VStack(spacing: Spacing.dash) {
            Image(systemName: "sparkles")
                .font(IRFont.title1)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.irPrimaryAccent, Color.irPrimaryAccent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(String(localized: "Subscribe to unlock AI analysis", comment: "AI locked message"))
                .font(IRFont.body)
                .foregroundStyle(Color.irTextSecondary)
                .multilineTextAlignment(.center)

            Button {
                showSubscriptionPaywall = true
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "sparkles")
                    Text(String(localized: "Subscribe Now", comment: "Subscribe CTA button"))
                }
                .font(IRFont.body.weight(.bold))
                .foregroundStyle(Color.irCardBackground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(
                    LinearGradient(
                        colors: [Color.irPrimaryAccent, Color.irPrimaryAccent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xxs)
    }

    private func aiInsightLoading(label: String) -> some View {
        HStack(spacing: Spacing.sm) {
            ProgressView().controlSize(.small)

            Text(label)
                .font(IRFont.body)
                .foregroundStyle(Color.irTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, Spacing.md)
    }

    // MARK: - Score Value Cards

    private func scoreValueCard(_ scoreType: ScoreType) -> some View {
        DetailHeroCard(
            valueLabel: "\(score)",
            unitLabel: "/100",
            statusLabel: scoreLabel,
            accent: scoreAccentColor,
            progress: Double(score) / 100.0
        )
    }

    private var cardiacLoadValueCard: some View {
        DetailHeroCard(
            valueLabel: "\(score)",
            unitLabel: "/20",
            statusLabel: cardiacLoadStatus?.title ?? "—",
            accent: cardiacLoadStatus?.color ?? Color.irPrimaryAccent,
            progress: Double(score) / 20.0
        )
    }

    // MARK: - Metric Value Card

    private var metricValueCard: some View {
        guard case .metric(let metricType) = mode else { return AnyView(EmptyView()) }

        let accent = metricColor(metricType)
        let statusText = deviationStatus?.localizedDescription(for: metricType) ?? metricUnit
        // Most physiological metrics don't use a 0–100 scale — render the raw value
        // without a gauge unless we get a meaningful baseline-relative progress.
        let progress: Double? = nil

        let formatted: String
        switch metricType {
        case .respiratoryRate:
            formatted = String(format: "%.1f", metricValue)
        case .totalCalories, .hrv, .restingHeartRate, .oxygenSaturation, .sleepDuration, .sleepEfficiency, .recoveryScore:
            formatted = String(format: "%.0f", metricValue)
        }

        return AnyView(
            DetailHeroCard(
                valueLabel: formatted,
                unitLabel: metricUnit.isEmpty ? nil : metricUnit,
                statusLabel: statusText,
                accent: accent,
                progress: progress
            )
        )
    }

    // MARK: - Score Charts

    private func scoreTrendChart(_ data: [TrendDataPoint], scoreType: ScoreType) -> some View {
        let accent = scoreAccentColor
        let selected = selectedPoint(in: data)

        return VStack(alignment: .leading, spacing: Spacing.base) {
            HStack {
                Text(String(localized: "7-Day Trend", comment: "Score trend chart title"))
                    .font(IRFont.headline)
                    .foregroundStyle(Color.irTextPrimary)

                Spacer()

                if let selected {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.0f%%", selected.value))
                            .font(IRFont.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(accent)

                        Text(selected.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                            .font(IRFont.microLabel)
                            .foregroundStyle(Color.irTextSecondary)
                    }
                    .animation(.easeInOut(duration: 0.15), value: selected.id)
                }
            }

            interactiveChart(data: data, accent: accent)

            chartLegend(color: accent, label: String(localized: "Daily score", comment: "Chart legend - daily score"))
        }
        .padding(Spacing.lg)
        .detailCard()
    }

    private func cardiacLoadChartCard(_ data: [TrendDataPoint]) -> some View {
        let accent = cardiacLoadStatus?.color ?? Color.irPrimaryAccent
        let selected = selectedPoint(in: data)

        return VStack(alignment: .leading, spacing: Spacing.base) {
            HStack {
                Text(String(localized: "14-Day Trend", comment: "Cardiac load trend chart title"))
                    .font(IRFont.headline)
                    .foregroundStyle(Color.irTextPrimary)

                Spacer()

                if let selected {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.0f", selected.value))
                            .font(IRFont.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(accent)

                        Text(selected.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                            .font(IRFont.microLabel)
                            .foregroundStyle(Color.irTextSecondary)
                    }
                    .animation(.easeInOut(duration: 0.15), value: selected.id)
                }
            }

            Chart {
                ForEach(data) { point in
                    AreaMark(x: .value("Date", point.date), y: .value("Load", point.value))
                        .foregroundStyle(LinearGradient(colors: [accent.opacity(0.3), accent.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)

                    LineMark(x: .value("Date", point.date), y: .value("Load", point.value))
                        .foregroundStyle(accent)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                }

                if let selected {
                    PointMark(x: .value("Date", selected.date), y: .value("Load", selected.value))
                        .foregroundStyle(accent).symbolSize(60)
                    RuleMark(x: .value("Date", selected.date))
                        .foregroundStyle(accent.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                }
            }
            .chartXSelection(value: $selectedDate)
            .frame(height: 200)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(IRFont.microLabel)
                        .foregroundStyle(Color.irTextSecondary)
                    AxisGridLine().foregroundStyle(Color.irBorder.opacity(0.5))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel().font(IRFont.microLabel)
                    AxisGridLine().foregroundStyle(Color.irBorder.opacity(0.3))
                }
            }

            chartLegend(color: accent, label: String(localized: "Daily load", comment: "Chart legend - daily load"))
        }
        .padding(Spacing.lg)
        .detailCard()
    }

    // MARK: - Metric Chart

    private var metricHistoryChart: some View {
        guard case .metric(let metricType) = mode else { return AnyView(EmptyView()) }

        let accent = metricColor(metricType)
        let selected: TrendDataPoint? = {
            guard !historyData.isEmpty else { return nil }
            guard let selectedDate else { return historyData.last }
            return historyData.min(by: { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) })
        }()

        return AnyView(VStack(alignment: .leading, spacing: Spacing.base) {
            HStack {
                Text(String(localized: "7-Day History", comment: "History chart header"))
                    .font(IRFont.headline)
                    .foregroundStyle(Color.irTextPrimary)

                Spacer()

                if let selected {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: Spacing.xxs) {
                            Text(String(format: "%.1f", selected.value))
                                .font(IRFont.title3)
                                .fontWeight(.bold)
                                .foregroundStyle(accent)

                            Text(metricUnit)
                                .font(IRFont.caption)
                                .foregroundStyle(Color.irTextSecondary)
                        }

                        Text(selected.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                            .font(IRFont.microLabel)
                            .foregroundStyle(Color.irTextSecondary)
                    }
                    .animation(.easeInOut(duration: 0.15), value: selected.id)
                }
            }

            Chart {
                ForEach(historyData) { point in
                    AreaMark(x: .value("Date", point.date), y: .value("Value", point.value))
                        .foregroundStyle(LinearGradient(colors: [accent.opacity(0.3), accent.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)

                    LineMark(x: .value("Date", point.date), y: .value("Value", point.value))
                        .foregroundStyle(accent)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                }

                if let selected {
                    PointMark(x: .value("Date", selected.date), y: .value("Value", selected.value))
                        .foregroundStyle(accent).symbolSize(60)
                    RuleMark(x: .value("Date", selected.date))
                        .foregroundStyle(accent.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                }

                if let avg = getBaselineAverage(metricType) {
                    RuleMark(y: .value("Baseline", avg))
                        .foregroundStyle(Color.irTextTertiary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text(String(localized: "Avg", comment: "Average baseline label"))
                                .font(IRFont.microLabel)
                                .foregroundStyle(Color.irTextSecondary)
                        }
                }
            }
            .chartXSelection(value: $selectedDate)
            .frame(height: 200)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 1)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated)).font(IRFont.microLabel)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel().font(IRFont.microLabel)
                    AxisGridLine()
                }
            }

            HStack(spacing: Spacing.base) {
                chartLegend(color: accent, label: String(localized: "Daily value", comment: "Chart legend - daily value"))

                if getBaselineAverage(metricType) != nil {
                    HStack(spacing: Spacing.xxs) {
                        Rectangle().fill(Color.irTextTertiary.opacity(0.5)).frame(width: 16, height: 2)
                        Text(String(localized: "Personal average", comment: "Chart legend - personal average"))
                            .font(IRFont.caption)
                            .foregroundStyle(Color.irTextSecondary)
                    }
                }

                Spacer()
            }
        }
        .padding(Spacing.lg)
        .detailCard())
    }

    // MARK: - Calories Stacked Bar Chart

    private func caloriesStackedHistoryChart(_ data: [CaloriesBreakdownPoint]) -> some View {
        let activeColor = Color.irSuccess
        let restingColor = Color.irWarning
        let activeLabel = String(localized: "Active", comment: "Active calories label")
        let restingLabel = String(localized: "Resting", comment: "Basal/resting calories label")

        let selected: CaloriesBreakdownPoint? = {
            guard !data.isEmpty else { return nil }
            guard let selectedDate else { return data.last }
            return data.min(by: { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) })
        }()

        return VStack(alignment: .leading, spacing: Spacing.base) {
            HStack {
                Text(String(localized: "7-Day History", comment: "History chart header"))
                    .font(IRFont.headline)
                    .foregroundStyle(Color.irTextPrimary)

                Spacer()

                if let selected {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: Spacing.xxs) {
                            Text(String(format: "%.0f", selected.total))
                                .font(IRFont.title3)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.irTextPrimary)

                            Text("kcal")
                                .font(IRFont.caption)
                                .foregroundStyle(Color.irTextSecondary)
                        }

                        Text(selected.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                            .font(IRFont.microLabel)
                            .foregroundStyle(Color.irTextSecondary)
                    }
                    .animation(.easeInOut(duration: 0.15), value: selected.id)
                }
            }

            Chart {
                ForEach(data) { point in
                    BarMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Calories", point.resting)
                    )
                    .foregroundStyle(by: .value("Type", restingLabel))

                    BarMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Calories", point.active)
                    )
                    .foregroundStyle(by: .value("Type", activeLabel))
                }

                if let selected {
                    RuleMark(x: .value("Date", selected.date, unit: .day))
                        .foregroundStyle(Color.irTextSecondary.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                }
            }
            .chartForegroundStyleScale([
                restingLabel: restingColor,
                activeLabel: activeColor,
            ])
            .chartLegend(position: .bottom, alignment: .leading)
            .chartXSelection(value: $selectedDate)
            .frame(height: 220)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 1)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated)).font(IRFont.microLabel)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel().font(IRFont.microLabel)
                    AxisGridLine()
                }
            }

            if let selected {
                HStack(spacing: Spacing.base) {
                    breakdownLegendItem(color: activeColor, label: activeLabel, value: selected.active)
                    breakdownLegendItem(color: restingColor, label: restingLabel, value: selected.resting)
                    Spacer()
                }
            }
        }
        .padding(Spacing.lg)
        .detailCard()
    }

    private func breakdownLegendItem(color: Color, label: String, value: Double) -> some View {
        HStack(spacing: Spacing.xs) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(IRFont.microLabel)
                    .foregroundStyle(Color.irTextSecondary)
                Text(String(format: "%.0f kcal", value))
                    .font(IRFont.monoMD)
                    .foregroundStyle(Color.irTextPrimary)
            }
        }
    }

    // MARK: - Shared Chart Helpers

    private func selectedPoint(in data: [TrendDataPoint]) -> TrendDataPoint? {
        guard let selectedDate else { return data.last }
        return data.min(by: { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) })
    }

    private func interactiveChart(data: [TrendDataPoint], accent: Color) -> some View {
        let selected = selectedPoint(in: data)

        return Chart {
            ForEach(data) { point in
                AreaMark(x: .value("Date", point.date), y: .value("Value", point.value))
                    .foregroundStyle(LinearGradient(colors: [accent.opacity(0.3), accent.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)

                LineMark(x: .value("Date", point.date), y: .value("Value", point.value))
                    .foregroundStyle(accent)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
            }

            if let selected {
                PointMark(x: .value("Date", selected.date), y: .value("Value", selected.value))
                    .foregroundStyle(accent).symbolSize(60)
                RuleMark(x: .value("Date", selected.date))
                    .foregroundStyle(accent.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
            }
        }
        .chartXSelection(value: $selectedDate)
        .frame(height: 200)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 1)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.abbreviated)).font(IRFont.microLabel)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisValueLabel().font(IRFont.microLabel)
                AxisGridLine()
            }
        }
    }

    private func chartLegend(color: Color, label: String) -> some View {
        HStack(spacing: Spacing.xxs) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(IRFont.caption)
                .foregroundStyle(Color.irTextSecondary)
        }
    }

    // MARK: - Score Explanation Card

    private func scoreExplanationCard(_ scoreType: ScoreType) -> some View {
        VStack(alignment: .leading, spacing: Spacing.base) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Color.irPrimaryAccent.gradient)

                Text(String(localized: "What does this mean?", comment: "Explanation header"))
                    .font(IRFont.headline)
                    .foregroundStyle(Color.irTextPrimary)

                Spacer()
            }

            Text(scoreDescription(scoreType))
                .font(IRFont.body)
                .foregroundStyle(Color.irTextSecondary)
                .lineSpacing(4)
        }
        .padding(Spacing.lg)
        .detailCard()
    }

    // MARK: - Metric Explanation Card

    @ViewBuilder
    private var metricExplanationCard: some View {
        if case .metric(let metricType) = mode {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(metricExplanationText(metricType))
                    .font(IRFont.body)
                    .lineSpacing(3)
                    .foregroundStyle(Color.irTextPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let status = deviationStatus {
                    Divider().background(Color.irBorder)

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(String(localized: "Recommendation", comment: "Recommendation header").uppercased())
                            .font(IRFont.eyebrow.weight(.bold))
                            .tracking(1.4)
                            .foregroundStyle(Color.irTextSecondary)

                        Text(metricRecommendation(metricType, status: status))
                            .font(IRFont.footnote)
                            .lineSpacing(2)
                            .foregroundStyle(Color.irTextSecondary)
                    }
                }
            }
            .padding(Spacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .detailCard()
        }
    }

    // MARK: - Baseline Comparison Card

    @ViewBuilder
    private func baselineComparisonCard(_ baseline: PersonalBaseline) -> some View {
        if case .metric(let metricType) = mode, let avg = getBaselineAverage(metricType) {
            VStack(alignment: .leading, spacing: 0) {
                baselineRow(
                    label: String(localized: "Your average", comment: "Average label"),
                    value: String(format: "%.1f", avg),
                    unit: metricUnit,
                    color: Color.irTextPrimary
                )

                Divider().background(Color.irBorder)

                deviationRow(metricType: metricType, average: avg)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .detailCard()
        }
    }

    private func baselineRow(label: String, value: String, unit: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(IRFont.footnote)
                .foregroundStyle(Color.irTextPrimary)

            Spacer()

            HStack(alignment: .lastTextBaseline, spacing: Spacing.xxs) {
                Text(value)
                    .font(IRFont.numSM)
                    .foregroundStyle(color)

                if !unit.isEmpty {
                    Text(unit)
                        .font(IRFont.eyebrow)
                        .foregroundStyle(Color.irTextSecondary)
                }
            }
        }
        .padding(.horizontal, Spacing.cardPadding)
        .padding(.vertical, Spacing.dash)
    }

    private func deviationRow(metricType: MetricType, average: Double) -> some View {
        let deviation = metricValue - average
        let deviationPercent = average == 0 ? 0 : (deviation / average) * 100
        let isPositive = deviation >= 0

        let isGood: Bool = {
            switch metricType {
            case .hrv, .oxygenSaturation: return isPositive
            case .restingHeartRate, .respiratoryRate: return !isPositive
            default: return true
            }
        }()

        let accent: Color = isGood ? .irSuccess : .irWarning
        let arrow = isPositive ? "arrow.up" : "arrow.down"

        return HStack {
            Text(String(localized: "Current deviation", comment: "Deviation label"))
                .font(IRFont.footnote)
                .foregroundStyle(Color.irTextPrimary)

            Spacer()

            HStack(spacing: Spacing.xxs) {
                Image(systemName: arrow)
                    .font(IRFont.eyebrow.weight(.bold))
                    .foregroundStyle(accent)

                Text(String(format: "%.1f", abs(deviationPercent)))
                    .font(IRFont.numSM)
                    .foregroundStyle(accent)

                Text("%")
                    .font(IRFont.eyebrow)
                    .foregroundStyle(Color.irTextSecondary)
            }
        }
        .padding(.horizontal, Spacing.cardPadding)
        .padding(.vertical, Spacing.dash)
    }

    // MARK: - Score Calculation Section

    @ViewBuilder
    private func calculationSection(_ scoreType: ScoreType) -> some View {
        switch scoreType {
        case .effort, .sleep, .readiness:
            DetailFormulaCard(
                slices: formulaSlices(for: scoreType),
                explanation: scoreCalculationExplanation(scoreType)
            )
        case .cardiacLoad:
            VStack(alignment: .leading, spacing: Spacing.base) {
                HStack {
                    Text(String(localized: "How it's calculated", comment: "Calculation section header"))
                        .font(IRFont.footnote.weight(.semibold))
                        .foregroundStyle(Color.irTextPrimary)
                    Spacer()
                }

                cardiacLoadCalculationContent
            }
            .padding(Spacing.cardPadding)
            .detailCard()
        }
    }

    private func formulaSlices(for scoreType: ScoreType) -> [DetailFormulaSlice] {
        switch scoreType {
        case .effort:
            return [
                DetailFormulaSlice(label: String(localized: "Steps", comment: "Effort steps label"), weight: 30, color: Color.irSuccess),
                DetailFormulaSlice(label: String(localized: "Active Calories", comment: "Effort calories label"), weight: 35, color: Color.irWarning),
                DetailFormulaSlice(label: String(localized: "Exercise Minutes", comment: "Effort exercise label"), weight: 35, color: Color.irError)
            ]
        case .sleep:
            return [
                DetailFormulaSlice(label: String(localized: "Duration", comment: "Sleep duration label"), weight: 30, color: Color.irPrimaryAccent),
                DetailFormulaSlice(label: String(localized: "Efficiency", comment: "Sleep efficiency label"), weight: 30, color: Color.irSuccess),
                DetailFormulaSlice(label: String(localized: "Stages", comment: "Sleep stages label"), weight: 40, color: Color.irPrimaryAccent)
            ]
        case .readiness:
            return [
                DetailFormulaSlice(label: String(localized: "Sleep", comment: "Sleep weight label"), weight: 40, color: Color.irPrimaryAccent),
                DetailFormulaSlice(label: String(localized: "HRV", comment: "HRV weight label"), weight: 25, color: Color.irPrimaryAccent),
                DetailFormulaSlice(label: String(localized: "Resting HR", comment: "RHR weight label"), weight: 15, color: Color.irError),
                DetailFormulaSlice(label: String(localized: "SpO2", comment: "SpO2 weight label"), weight: 10, color: Color.irPrimaryAccent),
                DetailFormulaSlice(label: String(localized: "Respiratory Rate", comment: "Resp weight label"), weight: 10, color: Color.irPrimaryAccent)
            ]
        case .cardiacLoad:
            return []
        }
    }

    private func scoreCalculationExplanation(_ scoreType: ScoreType) -> String {
        switch scoreType {
        case .effort:
            return String(localized: "Daily score measuring your progress towards your personal activity goals. Calorie and exercise targets come from your Apple Activity Rings when available; defaults to 400 kcal and 30 min (WHO, 2020). Step target is 10,000/day (Tudor-Locke, 2004). Each component is capped at 100%.", comment: "Effort calculation explanation")
        case .sleep:
            return String(localized: "Score combining sleep duration (~30%), efficiency (~30%) and balance of sleep stages (~40%). Optimal range: 7\u{2013}9h with at least 85% efficiency and 15\u{2013}20% deep sleep + 20\u{2013}25% REM (Hirshkowitz et al., 2015).", comment: "Sleep calculation explanation")
        case .readiness:
            return String(localized: "Composite score weighting recovery signals from your autonomic nervous system, sleep quality and recent training load. Uses personal baseline deviation (z-score) when enough data is available; a normal day at your baseline scores around 50%.", comment: "Readiness calculation explanation")
        case .cardiacLoad:
            return ""
        }
    }

    private var effortCalculationContent: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(String(localized: "Formula", comment: "Calculation formula label"))
                    .font(IRFont.body).fontWeight(.semibold).foregroundStyle(Color.irTextPrimary)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(String(localized: "Steps × 30% + Calories × 35% + Exercise × 35%", comment: "Effort score formula"))
                        .font(IRFont.body).foregroundStyle(Color.irPrimaryAccent)
                    Text(String(localized: "Each component = actual / personal goal, capped at 100%", comment: "Effort score formula detail"))
                        .font(IRFont.caption).foregroundStyle(Color.irTextSecondary)
                }
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.irPrimaryAccent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
            }

            Divider()

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(String(localized: "Components & Targets", comment: "Effort components label"))
                    .font(IRFont.body).fontWeight(.semibold).foregroundStyle(Color.irTextPrimary)
                calculationRow(color: Color.irSuccess, label: String(localized: "Steps", comment: "Effort steps label"), value: String(localized: "10,000 steps/day", comment: "Effort steps target"))
                calculationRow(color: Color.irWarning, label: String(localized: "Active Calories", comment: "Effort calories label"), value: String(localized: "Apple Ring goal", comment: "Effort calories target"))
                calculationRow(color: Color.irError, label: String(localized: "Exercise Minutes", comment: "Effort exercise label"), value: String(localized: "Apple Ring goal", comment: "Effort exercise target"))
                calculationRow(color: Color.irPrimaryAccent, label: String(localized: "Cap", comment: "Effort score cap label"), value: String(localized: "Maximum 100%", comment: "Effort score cap value"))
            }

            Divider()

            Text(String(localized: "Calories and exercise targets use your personal Apple Activity Ring goals. If unavailable, defaults to 400 kcal and 30 min (WHO, 2020). Steps target is 10,000/day (Tudor-Locke, 2004).", comment: "Effort calculation detail"))
                .font(IRFont.caption).foregroundStyle(Color.irTextSecondary).lineSpacing(3)
        }
    }

    private var sleepCalculationContent: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(String(localized: "Base Score", comment: "Sleep base score label"))
                    .font(IRFont.body).fontWeight(.semibold).foregroundStyle(Color.irTextPrimary)
                calculationRow(color: Color.irTextTertiary, label: String(localized: "Starting points", comment: "Sleep base points label"), value: String(localized: "50 pts", comment: "Sleep base points value"))
            }

            Divider()

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(String(localized: "Duration Bonus", comment: "Sleep duration bonus label"))
                    .font(IRFont.body).fontWeight(.semibold).foregroundStyle(Color.irTextPrimary)
                sleepDurationRow(range: String(localized: "7-9 hours", comment: "Sleep range"), points: "+25", color: Color.irSuccess, isActive: sleepDurationHours.map { $0 >= 7 && $0 <= 9 })
                sleepDurationRow(range: String(localized: "6-7 hours", comment: "Sleep range"), points: "+15", color: Color.irWarning, isActive: sleepDurationHours.map { $0 >= 6 && $0 < 7 })
                sleepDurationRow(range: String(localized: "5-6 hours", comment: "Sleep range"), points: "+5", color: Color.irWarning, isActive: sleepDurationHours.map { $0 >= 5 && $0 < 6 })
                sleepDurationRow(range: String(localized: "< 5 hours", comment: "Sleep range"), points: "-20", color: Color.irError, isActive: sleepDurationHours.map { $0 < 5 })
            }

            Divider()

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(String(localized: "Efficiency Bonus", comment: "Sleep efficiency bonus label"))
                    .font(IRFont.body).fontWeight(.semibold).foregroundStyle(Color.irTextPrimary)
                sleepDurationRow(range: String(localized: "\u{2265} 85%", comment: "Sleep efficiency"), points: "+25", color: Color.irSuccess, isActive: sleepEfficiency.map { $0 >= 85 })
                sleepDurationRow(range: String(localized: "\u{2265} 75%", comment: "Sleep efficiency"), points: "+15", color: Color.irWarning, isActive: sleepEfficiency.map { $0 >= 75 && $0 < 85 })
                sleepDurationRow(range: String(localized: "\u{2265} 65%", comment: "Sleep efficiency"), points: "+5", color: Color.irWarning, isActive: sleepEfficiency.map { $0 >= 65 && $0 < 75 })
            }

            Divider()

            Text(String(localized: "Final score is clamped between 0 and 100.", comment: "Sleep score clamping note"))
                .font(IRFont.caption).foregroundStyle(Color.irTextSecondary)
        }
    }

    private var readinessCalculationContent: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(String(localized: "Metric Weights", comment: "Readiness metric weights label"))
                    .font(IRFont.body).fontWeight(.semibold).foregroundStyle(Color.irTextPrimary)
                calculationRow(color: Color.irPrimaryAccent, label: String(localized: "Sleep Quality", comment: "Readiness sleep weight"), value: "40%")
                calculationRow(color: Color.irPrimaryAccent, label: String(localized: "HRV", comment: "Readiness HRV weight"), value: "25%")
                calculationRow(color: Color.irError, label: String(localized: "Resting Heart Rate", comment: "Readiness RHR weight"), value: "15%")
                calculationRow(color: Color.irPrimaryAccent, label: String(localized: "Oxygen Saturation (SpO2)", comment: "Readiness SpO2 weight"), value: "10%")
                calculationRow(color: Color.irPrimaryAccent, label: String(localized: "Respiratory Rate", comment: "Readiness resp rate weight"), value: "10%")
            }

            Divider()

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(String(localized: "How each metric is scored", comment: "Readiness metric scoring header"))
                    .font(IRFont.body).fontWeight(.semibold).foregroundStyle(Color.irTextPrimary)
                metricScoringRow(icon: "waveform.path.ecg", color: Color.irPrimaryAccent, label: String(localized: "HRV", comment: "HRV scoring"), detail: String(localized: "Higher HRV = better parasympathetic recovery", comment: "HRV detail"))
                metricScoringRow(icon: "heart.fill", color: Color.irError, label: String(localized: "Resting HR", comment: "RHR scoring"), detail: String(localized: "Lower RHR = less cardiovascular stress", comment: "RHR detail"))
                metricScoringRow(icon: "drop.fill", color: Color.irPrimaryAccent, label: String(localized: "SpO2", comment: "SpO2 scoring"), detail: String(localized: "Higher = better oxygenation", comment: "SpO2 detail"))
                metricScoringRow(icon: "lungs.fill", color: Color.irPrimaryAccent, label: String(localized: "Respiratory Rate", comment: "Resp scoring"), detail: String(localized: "Lower = less stress", comment: "Resp detail"))
                metricScoringRow(icon: "moon.fill", color: Color.irPrimaryAccent, label: String(localized: "Sleep", comment: "Sleep scoring"), detail: String(localized: "Duration + efficiency + stages", comment: "Sleep detail"))
            }

            Divider()

            Text(String(localized: "Scoring uses personal baseline deviation (z-score) when enough data is available. A normal day at your baseline scores approximately 50%.", comment: "Readiness baseline explanation"))
                .font(IRFont.caption).foregroundStyle(Color.irTextSecondary).lineSpacing(3)
        }
    }

    private var cardiacLoadCalculationContent: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(String(localized: "Formula", comment: "Calculation formula label"))
                    .font(IRFont.body).fontWeight(.semibold).foregroundStyle(Color.irTextPrimary)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(String(localized: "TRIMP = Duration × \u{0394}HR × Weight(\u{0394}HR)", comment: "Cardiac load TRIMP formula"))
                        .font(IRFont.body).foregroundStyle(Color.irPrimaryAccent)
                    Text(String(localized: "Falls back to pace × intensity when HR unavailable", comment: "Cardiac load TRIMP fallback note"))
                        .font(IRFont.caption).foregroundStyle(Color.irTextSecondary)
                }
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.irPrimaryAccent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
            }

            Divider()

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(String(localized: "HR-based TRIMP (primary)", comment: "Cardiac load HR TRIMP label"))
                    .font(IRFont.body).fontWeight(.semibold).foregroundStyle(Color.irTextPrimary)
                calculationRow(color: Color.irError, label: "\u{0394}HR", value: "(HR_avg - HR_rest) / (HR_max - HR_rest)")
                calculationRow(color: Color.irPrimaryAccent, label: String(localized: "Male", comment: "TRIMP male label"), value: "0.64 × e^(1.92 × \u{0394}HR)")
                calculationRow(color: Color.irError, label: String(localized: "Female", comment: "TRIMP female label"), value: "0.86 × e^(1.67 × \u{0394}HR)")
            }

            Divider()

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(String(localized: "Pace-based (fallback)", comment: "Cardiac load pace fallback label"))
                    .font(IRFont.body).fontWeight(.semibold).foregroundStyle(Color.irTextPrimary)
                calculationRow(color: Color.irError, label: String(localized: "< 4:00 /km"), value: "1.8×")
                calculationRow(color: Color.irWarning, label: String(localized: "4:00–5:00 /km"), value: "1.4–1.6×")
                calculationRow(color: Color.irWarning, label: String(localized: "5:00–6:00 /km"), value: "1.0–1.2×")
                calculationRow(color: Color.irSuccess, label: String(localized: "6:00–7:00 /km"), value: "0.8×")
                calculationRow(color: Color.irPrimaryAccent, label: String(localized: "> 7:00 /km"), value: "0.6×")
            }

            Divider()

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(String(localized: "ATL / CTL / ACWR", comment: "Cardiac load EWMA section label"))
                    .font(IRFont.body).fontWeight(.semibold).foregroundStyle(Color.irTextPrimary)
                Text(String(localized: "ATL (7 days) & CTL (42 days) via EWMA. ACWR = ATL/CTL. Score 0-20 personalized: ATL/CTL × 10 (maintaining = 10/20).", comment: "Cardiac load EWMA explanation"))
                    .font(IRFont.caption).foregroundStyle(Color.irTextSecondary).lineSpacing(3)
            }

            Divider()

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(String(localized: "Status Thresholds (ACWR)", comment: "Cardiac load ACWR status thresholds label"))
                    .font(IRFont.body).fontWeight(.semibold).foregroundStyle(Color.irTextPrimary)
                calculationRow(color: Color.irWarning, label: String(localized: "Increasing", comment: "Cardiac load status"), value: "ACWR > 1.3")
                calculationRow(color: Color.irPrimaryAccent, label: String(localized: "Maintaining", comment: "Cardiac load status"), value: String(localized: "ACWR 0.8–1.3", comment: "ACWR maintaining range"))
                calculationRow(color: Color.irPrimaryAccent, label: String(localized: "Decreasing", comment: "Cardiac load status"), value: String(localized: "ACWR 0.5–0.8", comment: "ACWR decreasing range"))
                calculationRow(color: Color.irError, label: String(localized: "Detraining", comment: "Cardiac load status"), value: "ACWR < 0.5")
            }
        }
    }

    // MARK: - References

    private func scoreReferencesSection(_ scoreType: ScoreType) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            DetailReferencesCard(sources: scoreReferenceSources(scoreType))
            allSourcesButton
        }
    }

    @ViewBuilder
    private var metricReferenceCard: some View {
        if case .metric(let metricType) = mode {
            VStack(alignment: .leading, spacing: Spacing.md) {
                DetailReferencesCard(sources: metricReferenceSources(metricType))
                allSourcesButton
            }
        }
    }

    private var allSourcesButton: some View {
        Button {
            showMedicalSources = true
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "book.pages")
                    .font(IRFont.caption)
                Text(String(localized: "View all sources", comment: "Button to open full medical sources view"))
                    .font(IRFont.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(Color.irPrimaryAccent)
            .padding(.horizontal, Spacing.dash)
            .padding(.vertical, Spacing.sm)
            .background(Color.irPrimaryAccent.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showMedicalSources) {
            MedicalSourcesView()
        }
    }

    // MARK: - Score Helpers

    private var scoreAccentColor: Color {
        switch score {
        case 80...100: return Color.irSuccess
        case 60..<80: return Color.irWarning
        case 40..<60: return Color.irWarning
        default: return Color.irError
        }
    }

    private var scoreLabel: String {
        switch score {
        case 80...100: return String(localized: "Excellent", comment: "Score label")
        case 60..<80: return String(localized: "Good", comment: "Score label")
        case 40..<60: return String(localized: "Fair", comment: "Score label")
        default: return String(localized: "Low", comment: "Score label")
        }
    }

    private var scoreStatusIcon: String {
        switch score {
        case 80...100: return "checkmark.circle.fill"
        case 60..<80: return "hand.thumbsup.fill"
        case 40..<60: return "exclamationmark.triangle.fill"
        default: return "arrow.down.circle.fill"
        }
    }

    private func scoreDescription(_ scoreType: ScoreType) -> String {
        switch scoreType {
        case .effort:
            return String(localized: "A daily score measuring how close you are to your personal activity goals. Combines steps (30%), active calories (35%), and exercise minutes (35%). Calories and exercise targets are read from your Apple Activity Rings for a personalized score.", comment: "Effort description")
        case .sleep:
            return String(localized: "A composite score based on your sleep duration and sleep efficiency. It evaluates both how long you slept and how effectively you used your time in bed.", comment: "Sleep description")
        case .readiness:
            return String(localized: "An AI-enhanced score combining recovery metrics and your personal baseline. It indicates how ready your body is for physical activity by analyzing multiple physiological signals.", comment: "Readiness description")
        case .cardiacLoad:
            return String(localized: "Cardiac Load measures cumulative cardiovascular stress using HR-based TRIMP (with pace fallback). Calculates Acute (7-day ATL) and Chronic (42-day CTL) training loads. Status based on the ACWR ratio (Gabbett 2016).", comment: "Cardiac load description")
        }
    }

    private func scoreReferenceText(_ scoreType: ScoreType) -> String {
        scoreReferenceSources(scoreType).joined(separator: " ")
    }

    private func scoreReferenceSources(_ scoreType: ScoreType) -> [String] {
        switch scoreType {
        case .effort:
            return [
                String(localized: "Tudor-Locke C, Bassett DR \u{00B7} Sports Medicine 2004", comment: "Effort source 1"),
                String(localized: "Ainsworth BE et al. \u{00B7} Compendium of Physical Activities, MSSE 2011", comment: "Effort source 2"),
                String(localized: "WHO \u{00B7} Guidelines on Physical Activity 2020", comment: "Effort source 3"),
                String(localized: "Personal targets from Apple Activity Rings when available", comment: "Effort source 4")
            ]
        case .sleep:
            return [
                String(localized: "Hirshkowitz M et al. \u{00B7} Sleep Health 2015", comment: "Sleep source 1"),
                String(localized: "Ohayon M et al. \u{00B7} Sleep Health 2017", comment: "Sleep source 2")
            ]
        case .readiness:
            return [
                String(localized: "Plews DJ et al. \u{00B7} IJSPP 2013", comment: "Readiness source 1"),
                String(localized: "Buchheit M \u{00B7} IJSPP 2014", comment: "Readiness source 2"),
                String(localized: "Flatt AA, Esco MR \u{00B7} JSCR 2016", comment: "Readiness source 3"),
                String(localized: "Bouzat P et al. \u{00B7} BJSM 2018", comment: "Readiness source 4")
            ]
        case .cardiacLoad:
            return [
                String(localized: "Banister EW \u{00B7} Impulse-response model 1975, 1991", comment: "Cardiac source 1"),
                String(localized: "Lucia A et al. \u{00B7} MSSE 2003", comment: "Cardiac source 2"),
                String(localized: "Williams S et al. \u{00B7} BJSM 2017", comment: "Cardiac source 3"),
                String(localized: "Hulin BT et al. \u{00B7} BJSM 2016", comment: "Cardiac source 4"),
                String(localized: "Gabbett TJ \u{00B7} BJSM 2016", comment: "Cardiac source 5"),
                String(localized: "Impellizzeri FM et al. \u{00B7} IJSPP 2019", comment: "Cardiac source 6"),
                String(localized: "Windt J, Gabbett TJ \u{00B7} BJSM 2017", comment: "Cardiac source 7"),
                String(localized: "Coggan AR, Allen H \u{00B7} ATL/CTL framework", comment: "Cardiac source 8")
            ]
        }
    }

    // MARK: - Metric Helpers

    private func metricIcon(_ type: MetricType) -> String {
        switch type {
        case .recoveryScore: return "bolt.heart.fill"
        case .hrv: return "waveform.path.ecg"
        case .restingHeartRate: return "heart.fill"
        case .respiratoryRate: return "lungs.fill"
        case .oxygenSaturation: return "drop.fill"
        case .sleepDuration: return "bed.double.fill"
        case .sleepEfficiency: return "chart.bar.fill"
        case .totalCalories: return "flame.fill"
        }
    }

    private func metricColor(_ type: MetricType) -> Color {
        switch type {
        case .recoveryScore: return Color.irPrimaryAccent
        case .hrv: return Color.irPrimaryAccent
        case .restingHeartRate: return Color.irError
        case .respiratoryRate: return Color.irPrimaryAccent
        case .oxygenSaturation: return Color.irPrimaryAccent
        case .sleepDuration: return Color.irPrimaryAccent
        case .sleepEfficiency: return Color.irSuccess
        case .totalCalories: return Color.irWarning
        }
    }

    private func metricExplanationText(_ type: MetricType) -> String {
        switch type {
        case .recoveryScore:
            return String(localized: "Your recovery score reflects how well your body has recovered from recent stress and training. A higher score indicates better readiness for intense physical activity.", comment: "Recovery explanation")
        case .hrv:
            return String(localized: "Heart Rate Variability (HRV) measures the variation in time between heartbeats. Higher HRV generally indicates better cardiovascular fitness and recovery. It's influenced by stress, sleep quality, and overall health.", comment: "HRV explanation")
        case .restingHeartRate:
            return String(localized: "Resting heart rate is the number of heartbeats per minute when you're completely at rest. A lower resting heart rate typically indicates better cardiovascular fitness. An elevated rate can signal stress or insufficient recovery.", comment: "RHR explanation")
        case .respiratoryRate:
            return String(localized: "Respiratory rate is the number of breaths you take per minute. Normal range is 12-20 breaths per minute for adults at rest. Changes can indicate stress, illness, or changes in fitness level.", comment: "Respiratory explanation")
        case .oxygenSaturation:
            return String(localized: "Oxygen saturation (SpO2) measures the percentage of oxygen-carrying hemoglobin in your blood. Normal levels are typically 95-100%. Lower levels may indicate respiratory issues or altitude effects.", comment: "SpO2 explanation")
        case .sleepDuration:
            return String(localized: "Adults typically need 7-9 hours of sleep per night for optimal recovery and health. Both too little and too much sleep can negatively impact performance.", comment: "Sleep duration explanation")
        case .sleepEfficiency:
            return String(localized: "Sleep efficiency is the percentage of time in bed actually spent sleeping. Good sleep efficiency is above 85%.", comment: "Sleep efficiency explanation")
        case .totalCalories:
            return String(localized: "Total calories burned per day, combining basal metabolism (energy spent at rest) with active calories from movement and exercise. A useful proxy for daily energy expenditure.", comment: "Total calories explanation")
        }
    }

    private func metricRecommendation(_ type: MetricType, status: DeviationStatus) -> String {
        switch (type, status) {
        case (.hrv, .belowNormal), (.hrv, .poor):
            return String(localized: "Your HRV is below your normal range. Consider prioritizing rest, reducing training intensity, and ensuring quality sleep tonight.", comment: "Low HRV recommendation")
        case (.hrv, .excellent):
            return String(localized: "Your HRV is above your baseline, indicating excellent recovery. This is a good day for high-intensity training if desired.", comment: "High HRV recommendation")
        case (.restingHeartRate, .aboveNormal):
            return String(localized: "Your resting heart rate is elevated. This may indicate stress, dehydration, or incomplete recovery. Consider lighter activity today.", comment: "High RHR recommendation")
        case (.restingHeartRate, .excellent):
            return String(localized: "Your resting heart rate is lower than usual, indicating good cardiovascular recovery.", comment: "Low RHR recommendation")
        case (.oxygenSaturation, .belowNormal), (.oxygenSaturation, .poor):
            return String(localized: "Your oxygen saturation is lower than optimal. Ensure good ventilation and consider deep breathing exercises.", comment: "Low SpO2 recommendation")
        case (.respiratoryRate, .aboveNormal):
            return String(localized: "Your respiratory rate is elevated. This could indicate stress or incomplete recovery. Practice relaxation techniques.", comment: "High resp recommendation")
        default:
            return String(localized: "Your metrics are within normal range. Continue with your current training and recovery routine.", comment: "Normal recommendation")
        }
    }

    private func metricReferenceText(_ type: MetricType) -> String {
        metricReferenceSources(type).joined(separator: " ")
    }

    private func metricReferenceSources(_ type: MetricType) -> [String] {
        switch type {
        case .hrv:
            return [
                String(localized: "Frontiers in Physiology \u{00B7} 2019", comment: "HRV source 1"),
                String(localized: "European Journal of Applied Physiology", comment: "HRV source 2"),
                String(localized: "Individual baseline is more important than population averages.", comment: "HRV source 3")
            ]
        case .restingHeartRate:
            return [
                String(localized: "American Heart Association \u{00B7} Resting HR guidelines", comment: "RHR source 1"),
                String(localized: "Athletes typically have lower RHR (40\u{2013}60 bpm) due to cardiovascular adaptations.", comment: "RHR source 2")
            ]
        case .respiratoryRate:
            return [
                String(localized: "Johns Hopkins Medicine \u{00B7} Respiratory rate ranges", comment: "Resp source 1"),
                String(localized: "American Lung Association \u{00B7} 12\u{2013}20 breaths/min normal range for adults at rest", comment: "Resp source 2")
            ]
        case .oxygenSaturation:
            return [
                String(localized: "WHO \u{00B7} Pulse oximetry guidelines", comment: "SpO2 source 1"),
                String(localized: "Normal range 95\u{2013}100%; values below 94% may warrant medical attention.", comment: "SpO2 source 2")
            ]
        default:
            return [
                String(localized: "Hirshkowitz M et al. \u{00B7} Sleep Health 2015", comment: "Sleep source default 1"),
                String(localized: "National Sleep Foundation \u{00B7} 7\u{2013}9 hours recommended for adults 18\u{2013}64", comment: "Sleep source default 2")
            ]
        }
    }

    private func getBaselineAverage(_ type: MetricType) -> Double? {
        guard let baseline else { return nil }
        switch type {
        case .hrv: return baseline.hrvAverage
        case .restingHeartRate: return baseline.restingHeartRateAverage
        case .respiratoryRate: return baseline.respiratoryRateAverage
        case .oxygenSaturation: return baseline.oxygenSaturationAverage
        default: return nil
        }
    }

    // MARK: - Reusable Row Views

    private func calculationRow(color: Color, label: String, value: String) -> some View {
        HStack {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(label).font(IRFont.body).foregroundStyle(Color.irTextPrimary)
            Spacer()
            Text(value).font(IRFont.body).fontWeight(.bold).foregroundStyle(Color.irTextPrimary)
        }
    }

    private func sleepDurationRow(range: String, points: String, color: Color, isActive: Bool?) -> some View {
        HStack {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(range).font(IRFont.body).foregroundStyle(Color.irTextPrimary)
            Spacer()
            Text(points).font(IRFont.body).fontWeight(.bold)
                .foregroundStyle(isActive == true ? color : Color.irTextPrimary)
            if let isActive, isActive {
                Image(systemName: "checkmark.circle.fill").font(IRFont.caption).foregroundStyle(color)
            }
        }
    }

    private func metricScoringRow(icon: String, color: Color, label: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: icon).font(IRFont.caption).foregroundStyle(color).frame(width: 16)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(label).font(IRFont.body).fontWeight(.medium).foregroundStyle(Color.irTextPrimary)
                Text(detail).font(IRFont.caption).foregroundStyle(Color.irTextSecondary)
            }
            Spacer()
        }
    }
}

// MARK: - Previews

#Preview("Effort") {
    ScoreExplanationSheet(scoreType: .effort, score: 61)
        .environmentObject(RevenueCatManager.shared)
}

#Preview("Sleep") {
    ScoreExplanationSheet(scoreType: .sleep, score: 80, sleepDurationHours: 7.5, sleepEfficiency: 88)
        .environmentObject(RevenueCatManager.shared)
}

#Preview("HRV") {
    ScoreExplanationSheet(metricType: .hrv, currentValue: 76.2, unit: "ms", deviationStatus: .normal, baseline: nil)
        .environmentObject(RevenueCatManager.shared)
}
