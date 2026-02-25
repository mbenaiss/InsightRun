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
    @State private var showConsentSheet = false
    @State private var historyData: [TrendDataPoint] = []

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
    }

    // MARK: - Metric Init

    init(
        metricType: MetricType,
        currentValue: Double,
        unit: String,
        deviationStatus: DeviationStatus?,
        baseline: PersonalBaseline?,
        trendData: [TrendDataPoint]? = nil,
        recoveryMetrics: RecoveryMetrics? = nil
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
        self.activityData = nil
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
                    await analysisVM.analyzeMetric(metricType: metricType, value: metricValue, unit: metricUnit, recoveryMetrics: metrics)
                }
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
            }
        }
    }

    // MARK: - Score Body (Effort, Sleep, Readiness)

    private func scoreBody(_ scoreType: ScoreType) -> some View {
        VStack(spacing: 24) {
            scoreValueCard(scoreType)

            if scoreType == .effort, let activity = activityData {
                effortActivityCard(activity)
            }

            if scoreType == .sleep, let sleep = recoveryMetrics?.sleepData {
                sleepDataCard(sleep)
            }

            if scoreType == .readiness, let metrics = recoveryMetrics {
                readinessMetricsCard(metrics)
            }

            aiInsightCard

            if let data = trendData, !data.isEmpty {
                scoreTrendChart(data, scoreType: scoreType)
            }

            scoreExplanationCard(scoreType)
            calculationSection(scoreType)
            scoreReferencesSection(scoreType)
        }
        .padding()
    }

    // MARK: - Cardiac Load Body

    private var cardiacLoadBody: some View {
        VStack(spacing: 24) {
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
        VStack(spacing: 24) {
            metricValueCard
            aiInsightCard
            metricHistoryChart

            if let baseline = baseline {
                baselineComparisonCard(baseline)
            }

            metricExplanationCard
            metricReferenceCard
        }
        .padding()
    }

    // MARK: - Effort Activity Card

    private func effortActivityCard(_ activity: DailyActivityData) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Image(systemName: "figure.run")
                    .foregroundStyle(Color.orange.gradient)

                Text(String(localized: "Today's Activity", comment: "Effort activity card header"))
                    .font(.headline)
                    .foregroundStyle(Color.irTextPrimary)

                Spacer()
            }

            HealthMetricRow(
                icon: "figure.walk",
                iconColor: .green,
                title: String(localized: "Steps", comment: "Steps metric label"),
                value: String(format: "%.0f", activity.steps)
            )

            HealthMetricRow(
                icon: "flame.fill",
                iconColor: .orange,
                title: String(localized: "Active Calories", comment: "Active calories metric label"),
                value: String(format: "%.0f kcal", activity.activeCalories)
            )

            HealthMetricRow(
                icon: "timer",
                iconColor: .red,
                title: String(localized: "Exercise Minutes", comment: "Exercise minutes metric label"),
                value: String(format: "%.0f min", activity.exerciseMinutes)
            )
        }
        .padding(20)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Sleep Data Card

    private func sleepDataCard(_ sleep: SleepData) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Image(systemName: "moon.fill")
                    .foregroundStyle(Color.indigo.gradient)

                Text(String(localized: "Sleep Details", comment: "Sleep data card header"))
                    .font(.headline)
                    .foregroundStyle(Color.irTextPrimary)

                Spacer()
            }

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
        .padding(20)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Readiness Metrics Card

    private func readinessMetricsCard(_ metrics: RecoveryMetrics) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Image(systemName: "heart.text.clipboard")
                    .foregroundStyle(Color.purple.gradient)

                Text(String(localized: "Today's Metrics", comment: "Readiness metrics card header"))
                    .font(.headline)
                    .foregroundStyle(Color.irTextPrimary)

                Spacer()
            }

            if let hrv = metrics.hrvAverage {
                HealthMetricRow(
                    icon: "waveform.path.ecg",
                    iconColor: .blue,
                    title: String(localized: "HRV", comment: "HRV metric label"),
                    value: String(format: "%.0f ms", hrv)
                )
            }

            if let rhr = metrics.restingHeartRate {
                HealthMetricRow(
                    icon: "heart.fill",
                    iconColor: .red,
                    title: String(localized: "Resting HR", comment: "Resting heart rate label"),
                    value: String(format: "%.0f bpm", rhr)
                )
            }

            if let respRate = metrics.respiratoryRate {
                HealthMetricRow(
                    icon: "lungs.fill",
                    iconColor: .teal,
                    title: String(localized: "Respiratory Rate", comment: "Respiratory rate label"),
                    value: String(format: "%.1f rpm", respRate)
                )
            }

            if let spo2 = metrics.oxygenSaturation {
                HealthMetricRow(
                    icon: "drop.fill",
                    iconColor: .cyan,
                    title: String(localized: "SpO2", comment: "Oxygen saturation label"),
                    value: String(format: "%.0f%%", spo2)
                )
            }

            if let sleep = metrics.sleepData {
                Divider()

                HealthMetricRow(
                    icon: "bed.double.fill",
                    iconColor: .indigo,
                    title: String(localized: "Sleep", comment: "Sleep metric label"),
                    value: sleep.formattedTotalSleep
                )

                HealthMetricRow(
                    icon: "chart.bar.fill",
                    iconColor: .green,
                    title: String(localized: "Sleep Efficiency", comment: "Sleep efficiency label"),
                    value: String(format: "%.0f%%", sleep.sleepEfficiency)
                )
            }
        }
        .padding(20)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Shared AI Insight Card

    private var aiInsightCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .font(.title3)

                Text(String(localized: "AI Analysis", comment: "AI analysis section title"))
                    .font(.headline)
                    .foregroundStyle(Color.irTextPrimary)
            }

            if !revenueCatManager.hasAIAccess {
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

                    Text(String(localized: "Subscribe to unlock AI analysis", comment: "AI locked message"))
                        .font(.subheadline)
                        .foregroundStyle(Color.irTextSecondary)
                        .multilineTextAlignment(.center)

                    Button {
                        showSubscriptionPaywall = true
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                            Text(String(localized: "Subscribe Now", comment: "Subscribe CTA button"))
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
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
                    .padding(.horizontal, 16)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

            } else if analysisVM.isLoading {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text(String(localized: "Analyzing...", comment: "AI analysis loading"))
                        .font(.subheadline)
                        .foregroundStyle(Color.irTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)

            } else if let analysis = analysisVM.analysisText, !analysis.isEmpty {
                Text(analysis)
                    .font(.body)
                    .foregroundStyle(Color.irTextSecondary)
                    .lineSpacing(4)

            } else if let error = analysisVM.error {
                let isConsentError = error.lowercased().contains("consent")

                VStack(spacing: 12) {
                    Image(systemName: isConsentError ? "hand.raised.fill" : "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(isConsentError ? Color.irPrimaryAccent : Color.irWarning)

                    Text(isConsentError ? error : String(localized: "Unable to load analysis", comment: "AI analysis error"))
                        .font(.subheadline)
                        .foregroundStyle(Color.irTextSecondary)
                        .multilineTextAlignment(.center)

                    if isConsentError {
                        Button {
                            showConsentSheet = true
                        } label: {
                            Label(String(localized: "Review & Accept", comment: "Consent review button"), systemImage: "checkmark.shield")
                                .font(.subheadline)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .sheet(isPresented: $showConsentSheet) {
                    AIConsentSheet(
                        onConsent: {
                            showConsentSheet = false
                            Task {
                                guard let metrics = recoveryMetrics else { return }
                                switch mode {
                                case .score(let scoreType):
                                    await analysisVM.analyze(scoreType: scoreType, score: score, recoveryMetrics: metrics, trendData: trendData)
                                case .metric(let metricType):
                                    await analysisVM.analyzeMetric(metricType: metricType, value: metricValue, unit: metricUnit, recoveryMetrics: metrics)
                                }
                            }
                        },
                        onDecline: {
                            showConsentSheet = false
                        }
                    )
                }

            } else {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text(String(localized: "Loading analysis...", comment: "AI analysis loading"))
                        .font(.subheadline)
                        .foregroundStyle(Color.irTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
            }
        }
        .padding(20)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .sheet(isPresented: $showSubscriptionPaywall) {
            SubscriptionPaywallView(isInitialFlow: false)
                .environmentObject(revenueCatManager)
        }
    }

    // MARK: - Score Value Cards

    private func scoreValueCard(_ scoreType: ScoreType) -> some View {
        let accent = scoreAccentColor
        let icon: String = switch scoreType {
        case .effort: "flame.fill"
        case .sleep: "moon.fill"
        case .readiness, .cardiacLoad: "bolt.heart.fill"
        }

        return VStack(spacing: 16) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(accent.gradient)

                Text(String(localized: "Current Score", comment: "Current score header"))
                    .font(.headline)
                    .foregroundStyle(Color.irTextSecondary)

                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(score)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.irTextPrimary)

                Text("%")
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.irTextSecondary)

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Image(systemName: scoreStatusIcon)
                        .font(.title2)
                        .foregroundStyle(accent)

                    Text(scoreLabel)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(accent)
                }
            }
        }
        .padding(20)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var cardiacLoadValueCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "bolt.heart.fill")
                    .font(.title2)
                    .foregroundStyle((cardiacLoadStatus?.color ?? .purple).gradient)

                Text(String(localized: "Current Load", comment: "Current cardiac load header"))
                    .font(.headline)
                    .foregroundStyle(Color.irTextSecondary)

                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(score)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.irTextPrimary)

                Text("/20")
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.irTextSecondary)

                Spacer()

                if let status = cardiacLoadStatus {
                    VStack(alignment: .trailing, spacing: 4) {
                        Image(systemName: status.icon)
                            .font(.title2)
                            .foregroundStyle(status.color)

                        Text(status.title)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(status.color)
                    }
                }
            }
        }
        .padding(20)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Metric Value Card

    private var metricValueCard: some View {
        guard case .metric(let metricType) = mode else { return AnyView(EmptyView()) }

        return AnyView(VStack(spacing: 16) {
            HStack {
                Image(systemName: metricIcon(metricType))
                    .font(.title2)
                    .foregroundStyle(metricColor(metricType).gradient)

                Text(String(localized: "Current Value", comment: "Current metric value header"))
                    .font(.headline)
                    .foregroundStyle(Color.irTextSecondary)

                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(format: "%.1f", metricValue))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.irTextPrimary)

                Text(metricUnit)
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.irTextSecondary)

                Spacer()

                if let status = deviationStatus, case .metric(let mt) = mode {
                    VStack(alignment: .trailing, spacing: 4) {
                        Image(systemName: status.icon)
                            .font(.title2)
                            .foregroundStyle(status.color)

                        Text(status.localizedDescription(for: mt))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(status.color)
                    }
                }
            }
        }
        .padding(20)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20)))
    }

    // MARK: - Score Charts

    private func scoreTrendChart(_ data: [TrendDataPoint], scoreType: ScoreType) -> some View {
        let accent = scoreAccentColor
        let selected = selectedPoint(in: data)

        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(String(localized: "7-Day Trend", comment: "Score trend chart title"))
                    .font(.headline)
                    .foregroundStyle(Color.irTextPrimary)

                Spacer()

                if let selected {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.0f%%", selected.value))
                            .font(.system(.title3, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundStyle(accent)

                        Text(selected.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                            .font(.caption2)
                            .foregroundStyle(Color.irTextSecondary)
                    }
                    .animation(.easeInOut(duration: 0.15), value: selected.id)
                }
            }

            interactiveChart(data: data, accent: accent)

            chartLegend(color: accent, label: String(localized: "Daily score", comment: "Chart legend - daily score"))
        }
        .padding(20)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func cardiacLoadChartCard(_ data: [TrendDataPoint]) -> some View {
        let accent = cardiacLoadStatus?.color ?? .purple
        let selected = selectedPoint(in: data)

        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(String(localized: "14-Day Trend", comment: "Cardiac load trend chart title"))
                    .font(.headline)
                    .foregroundStyle(Color.irTextPrimary)

                Spacer()

                if let selected {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.0f", selected.value))
                            .font(.system(.title3, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundStyle(accent)

                        Text(selected.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                            .font(.caption2)
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
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        .foregroundStyle(Color.irTextSecondary)
                    AxisGridLine().foregroundStyle(Color.irBorder.opacity(0.5))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel().font(.caption2)
                    AxisGridLine().foregroundStyle(Color.irBorder.opacity(0.3))
                }
            }

            chartLegend(color: accent, label: String(localized: "Daily load", comment: "Chart legend - daily load"))
        }
        .padding(20)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
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

        return AnyView(VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(String(localized: "7-Day History", comment: "History chart header"))
                    .font(.headline)
                    .foregroundStyle(Color.irTextPrimary)

                Spacer()

                if let selected {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(String(format: "%.1f", selected.value))
                                .font(.system(.title3, design: .rounded))
                                .fontWeight(.bold)
                                .foregroundStyle(accent)

                            Text(metricUnit)
                                .font(.caption)
                                .foregroundStyle(Color.irTextSecondary)
                        }

                        Text(selected.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                            .font(.caption2)
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
                        .foregroundStyle(Color.gray.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text(String(localized: "Avg", comment: "Average baseline label"))
                                .font(.caption2)
                                .foregroundStyle(Color.irTextSecondary)
                        }
                }
            }
            .chartXSelection(value: $selectedDate)
            .frame(height: 200)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 1)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated)).font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel().font(.caption2)
                    AxisGridLine()
                }
            }

            HStack(spacing: 16) {
                chartLegend(color: accent, label: String(localized: "Daily value", comment: "Chart legend - daily value"))

                if getBaselineAverage(metricType) != nil {
                    HStack(spacing: 4) {
                        Rectangle().fill(Color.gray.opacity(0.5)).frame(width: 16, height: 2)
                        Text(String(localized: "Personal average", comment: "Chart legend - personal average"))
                            .font(.caption)
                            .foregroundStyle(Color.irTextSecondary)
                    }
                }

                Spacer()
            }
        }
        .padding(20)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20)))
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
                AxisValueLabel(format: .dateTime.weekday(.abbreviated)).font(.caption2)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisValueLabel().font(.caption2)
                AxisGridLine()
            }
        }
    }

    private func chartLegend(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.irTextSecondary)
        }
    }

    // MARK: - Score Explanation Card

    private func scoreExplanationCard(_ scoreType: ScoreType) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Color.blue.gradient)

                Text(String(localized: "What does this mean?", comment: "Explanation header"))
                    .font(.headline)
                    .foregroundStyle(Color.irTextPrimary)

                Spacer()
            }

            Text(scoreDescription(scoreType))
                .font(.body)
                .foregroundStyle(Color.irTextSecondary)
                .lineSpacing(4)
        }
        .padding(20)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Metric Explanation Card

    private var metricExplanationCard: some View {
        guard case .metric(let metricType) = mode else { return AnyView(EmptyView()) }

        return AnyView(VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Color.blue.gradient)

                Text(String(localized: "What does this mean?", comment: "Explanation header"))
                    .font(.headline)
                    .foregroundStyle(Color.irTextPrimary)

                Spacer()
            }

            Text(metricExplanationText(metricType))
                .font(.body)
                .foregroundStyle(Color.irTextSecondary)
                .lineSpacing(4)

            if let status = deviationStatus {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text(String(localized: "Recommendation", comment: "Recommendation header"))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    } icon: {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(.orange)
                    }

                    Text(metricRecommendation(metricType, status: status))
                        .font(.subheadline)
                        .foregroundStyle(Color.irTextSecondary)
                }
            }
        }
        .padding(20)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20)))
    }

    // MARK: - Baseline Comparison Card

    private func baselineComparisonCard(_ baseline: PersonalBaseline) -> some View {
        guard case .metric(let metricType) = mode else { return AnyView(EmptyView()) }

        return AnyView(VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "person.badge.clock.fill")
                    .foregroundStyle(Color.blue.gradient)

                Text(String(localized: "Personal Baseline", comment: "Personal baseline header"))
                    .font(.headline)
                    .foregroundStyle(Color.irTextPrimary)

                Spacer()
            }

            if let avg = getBaselineAverage(metricType) {
                VStack(spacing: 12) {
                    HStack {
                        Text(String(localized: "Your average", comment: "Average label"))
                            .foregroundStyle(Color.irTextSecondary)
                        Spacer()
                        Text(String(format: "%.1f %@", avg, metricUnit))
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.irTextPrimary)
                    }

                    HStack {
                        Text(String(localized: "Current deviation", comment: "Deviation label"))
                            .foregroundStyle(Color.irTextSecondary)
                        Spacer()

                        let deviation = metricValue - avg
                        let deviationPercent = (deviation / avg) * 100
                        let isPositive = deviation >= 0

                        let isGood: Bool = {
                            switch metricType {
                            case .hrv, .oxygenSaturation: return isPositive
                            case .restingHeartRate, .respiratoryRate: return !isPositive
                            default: return true
                            }
                        }()

                        HStack(spacing: 4) {
                            Image(systemName: isPositive ? "arrow.up" : "arrow.down")
                                .font(.caption)
                            Text(String(format: "%.1f%%", abs(deviationPercent)))
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(isGood ? Color.green : Color.orange)
                    }
                }
            }
        }
        .padding(20)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20)))
    }

    // MARK: - Score Calculation Section

    private func calculationSection(_ scoreType: ScoreType) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "function")
                    .foregroundStyle(Color.purple.gradient)

                Text(String(localized: "How it's calculated", comment: "Calculation section header"))
                    .font(.headline)
                    .foregroundStyle(Color.irTextPrimary)

                Spacer()
            }

            switch scoreType {
            case .effort: effortCalculationContent
            case .sleep: sleepCalculationContent
            case .readiness: readinessCalculationContent
            case .cardiacLoad: cardiacLoadCalculationContent
            }
        }
        .padding(20)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var effortCalculationContent: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(String(localized: "Formula", comment: "Calculation formula label"))
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(Color.irTextPrimary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Steps × 30% + Calories × 35% + Exercise × 35%", comment: "Effort score formula"))
                        .font(.subheadline).foregroundStyle(Color.irPrimaryAccent)
                    Text(String(localized: "Each component = actual / personal goal, capped at 100%", comment: "Effort score formula detail"))
                        .font(.caption).foregroundStyle(Color.irTextSecondary)
                }
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.irPrimaryAccent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            }

            Divider()

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(String(localized: "Components & Targets", comment: "Effort components label"))
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(Color.irTextPrimary)
                calculationRow(color: .green, label: String(localized: "Steps", comment: "Effort steps label"), value: String(localized: "10,000 steps/day", comment: "Effort steps target"))
                calculationRow(color: .orange, label: String(localized: "Active Calories", comment: "Effort calories label"), value: String(localized: "Apple Ring goal", comment: "Effort calories target"))
                calculationRow(color: .red, label: String(localized: "Exercise Minutes", comment: "Effort exercise label"), value: String(localized: "Apple Ring goal", comment: "Effort exercise target"))
                calculationRow(color: .blue, label: String(localized: "Cap", comment: "Effort score cap label"), value: String(localized: "Maximum 100%", comment: "Effort score cap value"))
            }

            Divider()

            Text(String(localized: "Calories and exercise targets use your personal Apple Activity Ring goals. If unavailable, defaults to 400 kcal and 30 min (WHO, 2020). Steps target is 10,000/day (Tudor-Locke, 2004).", comment: "Effort calculation detail"))
                .font(.caption).foregroundStyle(Color.irTextSecondary).lineSpacing(3)
        }
    }

    private var sleepCalculationContent: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(String(localized: "Base Score", comment: "Sleep base score label"))
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(Color.irTextPrimary)
                calculationRow(color: .gray, label: String(localized: "Starting points", comment: "Sleep base points label"), value: String(localized: "50 pts", comment: "Sleep base points value"))
            }

            Divider()

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(String(localized: "Duration Bonus", comment: "Sleep duration bonus label"))
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(Color.irTextPrimary)
                sleepDurationRow(range: String(localized: "7-9 hours", comment: "Sleep range"), points: "+25", color: .green, isActive: sleepDurationHours.map { $0 >= 7 && $0 <= 9 })
                sleepDurationRow(range: String(localized: "6-7 hours", comment: "Sleep range"), points: "+15", color: .yellow, isActive: sleepDurationHours.map { $0 >= 6 && $0 < 7 })
                sleepDurationRow(range: String(localized: "5-6 hours", comment: "Sleep range"), points: "+5", color: .orange, isActive: sleepDurationHours.map { $0 >= 5 && $0 < 6 })
                sleepDurationRow(range: String(localized: "< 5 hours", comment: "Sleep range"), points: "-20", color: .red, isActive: sleepDurationHours.map { $0 < 5 })
            }

            Divider()

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(String(localized: "Efficiency Bonus", comment: "Sleep efficiency bonus label"))
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(Color.irTextPrimary)
                sleepDurationRow(range: String(localized: "\u{2265} 85%", comment: "Sleep efficiency"), points: "+25", color: .green, isActive: sleepEfficiency.map { $0 >= 85 })
                sleepDurationRow(range: String(localized: "\u{2265} 75%", comment: "Sleep efficiency"), points: "+15", color: .yellow, isActive: sleepEfficiency.map { $0 >= 75 && $0 < 85 })
                sleepDurationRow(range: String(localized: "\u{2265} 65%", comment: "Sleep efficiency"), points: "+5", color: .orange, isActive: sleepEfficiency.map { $0 >= 65 && $0 < 75 })
            }

            Divider()

            Text(String(localized: "Final score is clamped between 0 and 100.", comment: "Sleep score clamping note"))
                .font(.caption).foregroundStyle(Color.irTextSecondary)
        }
    }

    private var readinessCalculationContent: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(String(localized: "Metric Weights", comment: "Readiness metric weights label"))
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(Color.irTextPrimary)
                calculationRow(color: .indigo, label: String(localized: "Sleep Quality", comment: "Readiness sleep weight"), value: "30%")
                calculationRow(color: .blue, label: String(localized: "HRV", comment: "Readiness HRV weight"), value: "25%")
                calculationRow(color: .red, label: String(localized: "Resting Heart Rate", comment: "Readiness RHR weight"), value: "20%")
                calculationRow(color: .cyan, label: String(localized: "Oxygen Saturation (SpO2)", comment: "Readiness SpO2 weight"), value: "15%")
                calculationRow(color: .teal, label: String(localized: "Respiratory Rate", comment: "Readiness resp rate weight"), value: "10%")
            }

            Divider()

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(String(localized: "How each metric is scored", comment: "Readiness metric scoring header"))
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(Color.irTextPrimary)
                metricScoringRow(icon: "waveform.path.ecg", color: .blue, label: String(localized: "HRV", comment: "HRV scoring"), detail: String(localized: "Higher HRV = better parasympathetic recovery", comment: "HRV detail"))
                metricScoringRow(icon: "heart.fill", color: .red, label: String(localized: "Resting HR", comment: "RHR scoring"), detail: String(localized: "Lower RHR = less cardiovascular stress", comment: "RHR detail"))
                metricScoringRow(icon: "drop.fill", color: .cyan, label: String(localized: "SpO2", comment: "SpO2 scoring"), detail: String(localized: "Higher = better oxygenation", comment: "SpO2 detail"))
                metricScoringRow(icon: "lungs.fill", color: .teal, label: String(localized: "Respiratory Rate", comment: "Resp scoring"), detail: String(localized: "Lower = less stress", comment: "Resp detail"))
                metricScoringRow(icon: "moon.fill", color: .indigo, label: String(localized: "Sleep", comment: "Sleep scoring"), detail: String(localized: "Duration + efficiency + stages", comment: "Sleep detail"))
            }

            Divider()

            Text(String(localized: "Scoring uses personal baseline deviation (z-score) when enough data is available. A normal day at your baseline scores approximately 70%.", comment: "Readiness baseline explanation"))
                .font(.caption).foregroundStyle(Color.irTextSecondary).lineSpacing(3)
        }
    }

    private var cardiacLoadCalculationContent: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(String(localized: "Formula", comment: "Calculation formula label"))
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(Color.irTextPrimary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "TRIMP = Duration × \u{0394}HR × Weight(\u{0394}HR)", comment: "Cardiac load TRIMP formula"))
                        .font(.subheadline).foregroundStyle(.purple)
                    Text(String(localized: "Falls back to pace × intensity when HR unavailable", comment: "Cardiac load TRIMP fallback note"))
                        .font(.caption).foregroundStyle(Color.irTextSecondary)
                }
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.purple.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            }

            Divider()

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(String(localized: "HR-based TRIMP (primary)", comment: "Cardiac load HR TRIMP label"))
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(Color.irTextPrimary)
                calculationRow(color: .red, label: "\u{0394}HR", value: "(HR_avg - HR_rest) / (HR_max - HR_rest)")
                calculationRow(color: .blue, label: String(localized: "Male", comment: "TRIMP male label"), value: "0.64 × e^(1.92 × \u{0394}HR)")
                calculationRow(color: .pink, label: String(localized: "Female", comment: "TRIMP female label"), value: "0.86 × e^(1.67 × \u{0394}HR)")
            }

            Divider()

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(String(localized: "Pace-based (fallback)", comment: "Cardiac load pace fallback label"))
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(Color.irTextPrimary)
                calculationRow(color: .red, label: String(localized: "< 4:00 /km"), value: "1.8×")
                calculationRow(color: .orange, label: String(localized: "4:00–5:00 /km"), value: "1.4–1.6×")
                calculationRow(color: .yellow, label: String(localized: "5:00–6:00 /km"), value: "1.0–1.2×")
                calculationRow(color: .green, label: String(localized: "6:00–7:00 /km"), value: "0.8×")
                calculationRow(color: .blue, label: String(localized: "> 7:00 /km"), value: "0.6×")
            }

            Divider()

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(String(localized: "ATL / CTL / ACWR", comment: "Cardiac load EWMA section label"))
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(Color.irTextPrimary)
                Text(String(localized: "ATL (7 days) & CTL (42 days) via EWMA. ACWR = ATL/CTL. Score 0-20 personalized: ATL/CTL × 10 (maintaining = 10/20).", comment: "Cardiac load EWMA explanation"))
                    .font(.caption).foregroundStyle(Color.irTextSecondary).lineSpacing(3)
            }

            Divider()

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(String(localized: "Status Thresholds (ACWR)", comment: "Cardiac load ACWR status thresholds label"))
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(Color.irTextPrimary)
                calculationRow(color: .orange, label: String(localized: "Increasing", comment: "Cardiac load status"), value: "ACWR > 1.3")
                calculationRow(color: .purple, label: String(localized: "Maintaining", comment: "Cardiac load status"), value: String(localized: "ACWR 0.8–1.3", comment: "ACWR maintaining range"))
                calculationRow(color: .blue, label: String(localized: "Decreasing", comment: "Cardiac load status"), value: String(localized: "ACWR 0.5–0.8", comment: "ACWR decreasing range"))
                calculationRow(color: .red, label: String(localized: "Detraining", comment: "Cardiac load status"), value: "ACWR < 0.5")
            }
        }
    }

    // MARK: - References

    private func scoreReferencesSection(_ scoreType: ScoreType) -> some View {
        AccordionSection(
            title: String(localized: "Scientific References", comment: "Scientific references section header"),
            icon: "book.closed.fill",
            iconColor: .purple
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text(scoreReferenceText(scoreType))
                    .font(.caption)
                    .foregroundStyle(Color.irTextSecondary)
                    .lineSpacing(4)

                allSourcesButton
            }
        }
    }

    @ViewBuilder
    private var metricReferenceCard: some View {
        if case .metric(let metricType) = mode {
            AccordionSection(
                title: String(localized: "Scientific References", comment: "Scientific references section header"),
                icon: "book.closed.fill",
                iconColor: .purple
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(metricReferenceText(metricType))
                        .font(.caption)
                        .foregroundStyle(Color.irTextSecondary)
                        .lineSpacing(4)

                    allSourcesButton
                }
            }
        }
    }

    private var allSourcesButton: some View {
        Button {
            showMedicalSources = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "book.pages")
                    .font(.caption)
                Text(String(localized: "View all sources", comment: "Button to open full medical sources view"))
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(Color.irPrimaryAccent)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.irPrimaryAccent.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showMedicalSources) {
            MedicalSourcesView()
        }
    }

    // MARK: - Score Helpers

    private var scoreAccentColor: Color {
        switch score {
        case 80...100: return .green
        case 60..<80: return .yellow
        case 40..<60: return .orange
        default: return .red
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
        switch scoreType {
        case .effort:
            return String(localized: "Steps target based on Tudor-Locke C, Bassett DR, Sports Medicine (2004). Default calorie target from Ainsworth BE et al., Compendium of Physical Activities, MSSE (2011). Exercise minutes from WHO Guidelines on Physical Activity (2020), 150 min/week \u{2248} 30 min/day. Personal targets from Apple Activity Rings when available.", comment: "Effort reference")
        case .sleep:
            return String(localized: "Based on National Sleep Foundation's sleep duration recommendations (Hirshkowitz et al., Sleep Health, 2015) recommending 7\u{2013}9 hours for adults, and sleep quality indicators from Ohayon M et al., Sleep Health (2017) defining \u{2265}85% efficiency as good sleep quality.", comment: "Sleep reference")
        case .readiness:
            return String(localized: "Based on research from Plews et al. (IJSPP, 2013) on HRV-guided recovery monitoring, Buchheit (IJSPP, 2014) on HR measures for training status, Flatt & Esco (JSCR, 2016) on nocturnal HRV, and Bouzat et al. (BJSM, 2018) on pulse oximetry.", comment: "Readiness reference")
        case .cardiacLoad:
            return String(localized: "Based on Banister's impulse-response model (1975, 1991) for TRIMP, Lucia et al. (MSSE, 2003) on HR-based TRIMP validation, Williams et al. (BJSM, 2017) on EWMA-based ACWR, Hulin et al. (BJSM, 2016) on ACWR injury prediction, Gabbett (BJSM, 2016) on the training-injury prevention paradox, Impellizzeri et al. (IJSPP, 2019) on individualized load monitoring via CTL, Windt & Gabbett (BJSM, 2017) on CTL-based personal normalization, and Coggan & Allen's ATL/CTL framework.", comment: "Cardiac load reference")
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
        }
    }

    private func metricColor(_ type: MetricType) -> Color {
        switch type {
        case .recoveryScore: return .purple
        case .hrv: return .blue
        case .restingHeartRate: return .red
        case .respiratoryRate: return .teal
        case .oxygenSaturation: return .cyan
        case .sleepDuration: return .indigo
        case .sleepEfficiency: return .green
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
        switch type {
        case .hrv:
            return String(localized: "HRV reference values are based on studies published in Frontiers in Physiology (2019) and the European Journal of Applied Physiology. Individual baseline is more important than population averages.", comment: "HRV reference")
        case .restingHeartRate:
            return String(localized: "Resting heart rate guidelines are based on American Heart Association recommendations. Athletes typically have lower RHR (40-60 bpm) due to cardiovascular adaptations.", comment: "RHR reference")
        case .respiratoryRate:
            return String(localized: "Normal respiratory rate ranges are defined by Johns Hopkins Medicine and the American Lung Association. 12-20 breaths/min is considered normal for adults at rest.", comment: "Respiratory reference")
        case .oxygenSaturation:
            return String(localized: "SpO2 guidelines are based on WHO recommendations. Normal range is 95-100%. Values below 94% may warrant medical attention.", comment: "SpO2 reference")
        default:
            return String(localized: "Sleep recommendations are based on National Sleep Foundation guidelines (2015). 7-9 hours is recommended for adults aged 18-64.", comment: "Sleep reference")
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
            Text(label).font(.subheadline).foregroundStyle(Color.irTextPrimary)
            Spacer()
            Text(value).font(.subheadline).fontWeight(.bold).foregroundStyle(Color.irTextPrimary)
        }
    }

    private func sleepDurationRow(range: String, points: String, color: Color, isActive: Bool?) -> some View {
        HStack {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(range).font(.subheadline).foregroundStyle(Color.irTextPrimary)
            Spacer()
            Text(points).font(.subheadline).fontWeight(.bold)
                .foregroundStyle(isActive == true ? color : Color.irTextPrimary)
            if let isActive, isActive {
                Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(color)
            }
        }
    }

    private func metricScoringRow(icon: String, color: Color, label: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: icon).font(.caption).foregroundStyle(color).frame(width: 16)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(label).font(.subheadline).fontWeight(.medium).foregroundStyle(Color.irTextPrimary)
                Text(detail).font(.caption).foregroundStyle(Color.irTextSecondary)
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
