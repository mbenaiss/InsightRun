//
//  RecoveryDashboardView.swift
//  InsightRun
//
//  Dashboard for recovery and readiness metrics
//

import SwiftUI
import Combine
import Charts

struct RecoveryDashboardView: View {
    @StateObject private var viewModel = RecoveryViewModel()
    @ObservedObject private var contextProvider = UnifiedAIContextProvider.shared
    @State private var showingMedicalSources = false
    @State private var showingCalendar = false
    @State private var availableDates: [Date] = []

    var body: some View {
        NavigationStack {
            TabView(selection: $viewModel.selectedDate) {
                    ForEach(availableDates, id: \.self) { date in
                        RecoveryDayView(date: date, viewModel: viewModel)
                            .tag(date)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .accessibilityIdentifier("recovery-dashboard")
                .navigationTitle(String(localized: "Recovery", comment: "Navigation title"))
                .navigationBarTitleDisplayMode(.inline) // Use inline for date title
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        datePickerDropdown
                    }
                }
                .refreshable {
                    await viewModel.refresh()
                }
                .task {
                    // Initialize dates if empty
                    if availableDates.isEmpty {
                        setupInitialDates()
                    }
                    await viewModel.loadRecoveryMetrics()

                    // Update context provider with recovery metrics
                    if let recovery = viewModel.recoveryMetrics {
                        contextProvider.recoveryMetrics = recovery
                    }
                }
                .onChange(of: viewModel.selectedDate) { _, newDate in
                    ensureDateIsAvailable(newDate)
                    // Update context provider when date changes
                    Task {
                        await viewModel.loadRecoveryMetrics(for: newDate)
                        contextProvider.recoveryMetrics = viewModel.recoveryMetrics
                    }
                }
            }
        .sheet(isPresented: $showingMedicalSources) {
            MedicalSourcesView()
        }
        .sheet(isPresented: $showingCalendar) {
            RecoveryCalendarView(
                selectedDate: $viewModel.selectedDate,
                isPresented: $showingCalendar,
                onDateSelected: { date in
                    ensureDateIsAvailable(date)
                    Task { await viewModel.loadRecoveryMetrics(for: date) }
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private func setupInitialDates() {
        let today = Calendar.current.startOfDay(for: Date())
        // Generate last 30 days up to today (no future dates)
        var dates: [Date] = []
        for i in -30...0 {
            if let date = Calendar.current.date(byAdding: .day, value: i, to: today) {
                dates.append(Calendar.current.startOfDay(for: date))
            }
        }
        availableDates = dates.sorted()
    }

    private func ensureDateIsAvailable(_ date: Date) {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let today = Calendar.current.startOfDay(for: Date())

        // Don't add future dates
        guard startOfDay <= today else { return }

        if !availableDates.contains(startOfDay) {
            availableDates.append(startOfDay)
            availableDates.sort()
        }
    }

    // MARK: - Date Picker Dropdown

    private var datePickerDropdown: some View {
        Button {
            showingCalendar = true
        } label: {
            HStack(spacing: Spacing.xxs) {
                Text(viewModel.formattedSelectedDateLong)
                    .font(IRFont.headline)
                    .foregroundStyle(Color.irTextPrimary)

                Image(systemName: "chevron.down")
                    .font(IRFont.microLabel)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.irTextSecondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Recovery Day View
struct RecoveryDayView: View {
    let date: Date
    @ObservedObject var viewModel: RecoveryViewModel
    @State private var hrvTrend: [TrendDataPoint] = []
    @State private var rhrTrend: [TrendDataPoint] = []
    @State private var respTrend: [TrendDataPoint] = []
    @State private var spo2Trend: [TrendDataPoint] = []

    var body: some View {
        ScrollView {
            // Check cache directly
            if let recovery = viewModel.metrics(for: date) {
                recoveryContent(recovery)
            } else if viewModel.isLoading && Calendar.current.isDate(date, inSameDayAs: viewModel.selectedDate) {
                loadingView
            } else if let error = viewModel.errorMessage, Calendar.current.isDate(date, inSameDayAs: viewModel.selectedDate) {
                errorView(error)
            } else {
                // Not loaded yet, show loading and fetch
                loadingView
                    .task {
                        await viewModel.loadRecoveryMetrics(for: date)
                    }
            }
        }
        .task {
            await loadTrendData()
        }
    }

    private func loadTrendData() async {
        let service = MetricTrendDataService.shared
        async let hrv = service.metricTrend(for: .hrv)
        async let rhr = service.metricTrend(for: .restingHeartRate)
        async let resp = service.metricTrend(for: .respiratoryRate)
        async let spo2 = service.metricTrend(for: .oxygenSaturation)

        hrvTrend = await hrv
        rhrTrend = await rhr
        respTrend = await resp
        spo2Trend = await spo2
    }

    // MARK: - Subviews (Copied/Adapted from Parent)
    
    @ViewBuilder
    private func recoveryContent(_ recovery: RecoveryMetrics) -> some View {
        VStack(spacing: Spacing.lg) {
            // Circular Recovery Score
            circularRecoveryScore(recovery)

            // Coaching Section (AI-enhanced for today, static for past days)
            if Calendar.current.isDateInToday(date) {
                CoachingSection(fallbackRecommendation: recovery.recoveryStatus.recommendation)
                    .padding(.horizontal)
            } else {
                recommendationCard(recovery)
                    .padding(.horizontal)
            }

            // Trends Section
            trendsSection(recovery)
                .padding(.horizontal)

            // Sleep Details Section
            if let sleep = recovery.sleepData {
                sleepDetailsSection(sleep)
                    .padding(.horizontal)
            }

            // Medical Sources Link
            medicalSourcesSection
                .padding(.horizontal)
        }
        .padding(.top, Spacing.lg)
        .padding(.bottom, 100)
    }

    private var loadingView: some View {
        VStack(spacing: Spacing.lg) {
            ProgressView()
                .scaleEffect(1.5)
            Text(String(localized: "Loading...", comment: "Loading indicator text"))
                .font(IRFont.body)
                .foregroundStyle(Color.irTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: Spacing.xl) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(IRFont.numXL)
                .foregroundStyle(Color.irWarning.gradient)

            VStack(spacing: Spacing.md) {
                Text(String(localized: "Error", comment: "Error state title"))
                    .font(IRFont.title2)
                    .fontWeight(.semibold)

                Text(message)
                    .font(IRFont.body)
                    .foregroundStyle(Color.irTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xxl)
            }
            
            Button(String(localized: "Retry", comment: "Button to retry loading data")) {
                Task { await viewModel.loadRecoveryMetrics(for: date) }
            }
        }
        .padding(.top, 100)
    }
    
    // MARK: - Shared Components
    
    private func circularRecoveryScore(_ recovery: RecoveryMetrics) -> some View {
        VStack(spacing: Spacing.base) {
            CircularProgressView(score: recovery.recoveryScore, size: 200, lineWidth: 14)

            Text(recovery.recoveryStatus.description)
                .font(IRFont.title3)
                .fontWeight(.semibold)
                .foregroundStyle(Color.irTextPrimary)
        }
        .padding(.vertical, Spacing.lg)
    }

    private func recommendationCard(_ recovery: RecoveryMetrics) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Label(String(localized: "Coaching", comment: "Section header for recovery recommendation"), systemImage: "text.bubble.fill")
                .font(IRFont.headline)
                .foregroundStyle(Color.irWarning.gradient)

            Text(recovery.recoveryStatus.recommendation)
                .font(IRFont.body)
                .foregroundStyle(Color.irTextPrimary)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.base)
        .background(Color.irWarning.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private func trendsSection(_ recovery: RecoveryMetrics) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(String(localized: "Trends", comment: "Section header for trends"))
                .font(IRFont.headline)
                .foregroundStyle(Color.irTextPrimary)

            VStack(spacing: Spacing.sm) {
                // HRV Card
                if let hrv = recovery.hrvAverage {
                    MetricTrendCard(
                        icon: "waveform.path.ecg",
                        iconColor: Color.irPrimaryAccent,
                        title: String(localized: "HRV at rest", comment: "HRV metric title"),
                        value: hrv,
                        unit: "ms",
                        deviationStatus: getHRVDeviationStatus(hrv, baseline: recovery.baseline),
                        metricType: .hrv,
                        trendData: hrvTrend,
                        baseline: recovery.baseline
                    )
                }

                // Resting Heart Rate Card
                if let rhr = recovery.restingHeartRate {
                    MetricTrendCard(
                        icon: "heart.fill",
                        iconColor: Color.irError,
                        title: String(localized: "Resting HR", comment: "Resting heart rate metric title"),
                        value: rhr,
                        unit: "bpm",
                        deviationStatus: getRHRDeviationStatus(rhr, baseline: recovery.baseline),
                        metricType: .restingHeartRate,
                        trendData: rhrTrend,
                        baseline: recovery.baseline
                    )
                }

                // Respiratory Rate Card
                if let respRate = recovery.respiratoryRate {
                    MetricTrendCard(
                        icon: "lungs.fill",
                        iconColor: Color.irPrimaryAccent,
                        title: String(localized: "Respiratory rate", comment: "Respiratory rate metric title"),
                        value: respRate,
                        unit: "rpm",
                        deviationStatus: getRespiratoryDeviationStatus(respRate, baseline: recovery.baseline),
                        metricType: .respiratoryRate,
                        trendData: respTrend,
                        baseline: recovery.baseline
                    )
                }

                // SpO2 Card
                if let spo2 = recovery.oxygenSaturation {
                    MetricTrendCard(
                        icon: "drop.fill",
                        iconColor: Color.irPrimaryAccent,
                        title: String(localized: "Oxygen saturation", comment: "SpO2 metric title"),
                        value: spo2,
                        unit: "%",
                        deviationStatus: getSpO2DeviationStatus(spo2),
                        metricType: .oxygenSaturation,
                        trendData: spo2Trend,
                        baseline: recovery.baseline
                    )
                }
            }
        }
    }

    private func sleepDetailsSection(_ sleep: SleepData) -> some View {
        VStack(alignment: .leading, spacing: Spacing.base) {
            Text(String(localized: "Sleep", comment: "Section header for sleep metrics"))
                .font(IRFont.headline)

            VStack(spacing: Spacing.md) {
                HealthMetricRow(
                    icon: "moon.fill",
                    iconColor: Color.irPurple,
                    title: String(localized: "Sleep session", comment: "Label for time of sleep session"),
                    value: sleep.formattedSleepTime
                )

                HealthMetricRow(
                    icon: "bed.double.fill",
                    iconColor: Color.irPrimaryAccent,
                    title: String(localized: "Sleep duration", comment: "Label for total sleep duration"),
                    value: sleep.formattedTotalSleep
                )

                if let napDuration = sleep.formattedNapDuration {
                    HealthMetricRow(
                        icon: "powersleep",
                        iconColor: Color.irWarning,
                        title: String(localized: "Naps", comment: "Label for nap duration"),
                        value: napDuration
                    )
                }

                HealthMetricRow(
                    icon: "chart.bar.fill",
                    iconColor: Color.irPrimaryAccent,
                    title: String(localized: "Efficiency", comment: "Label for sleep efficiency percentage"),
                    value: String(format: "%.0f%%", sleep.sleepEfficiency)
                )
            }

            // Sleep stages if available
            if let deep = sleep.deepSleepDuration,
               let core = sleep.coreSleepDuration,
               let rem = sleep.remSleepDuration {
                Divider()
                    .padding(.vertical, Spacing.xxs)

                Text(String(localized: "Sleep stages", comment: "Section header for sleep stages breakdown"))
                    .font(IRFont.body)
                    .foregroundStyle(Color.irTextSecondary)

                VStack(spacing: Spacing.sm) {
                    SleepStageRow(stage: String(localized: "Deep", comment: "Deep sleep stage label"), duration: deep, color: Color.irPrimaryAccent)
                    SleepStageRow(stage: String(localized: "Light", comment: "Light sleep stage label"), duration: core, color: Color.irPrimaryAccent)
                    SleepStageRow(stage: String(localized: "REM", comment: "REM sleep stage label"), duration: rem, color: Color.irPurple)
                }
            }
        }
        .padding(Spacing.lg)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .shadow(color: Color.irShadow, radius: 10, y: 5)
    }

    private var medicalSourcesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "book.closed.fill")
                    .foregroundStyle(Color.irPrimaryAccent.gradient)
                    .font(IRFont.title3)

                Text(String(localized: "Medical Information", comment: "Medical sources section title"))
                    .font(IRFont.headline)
                    .foregroundStyle(Color.irTextPrimary)

                Spacer()
            }

            Text(String(localized: "Recovery recommendations are based on published scientific research. Tap below to view all medical sources.", comment: "Medical sources disclaimer text"))
                .font(IRFont.body)
                .foregroundStyle(Color.irTextSecondary)
                .lineSpacing(4)
            
        }
        .padding(Spacing.lg)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .shadow(color: Color.irShadow, radius: 10, y: 5)
    }


    private func getHRVDeviationStatus(_ hrv: Double, baseline: PersonalBaseline?) -> DeviationStatus {
        guard let baseline = baseline, let avg = baseline.hrvAverage else { return hrv >= 50 ? .normal : .belowNormal }
        let std = baseline.hrvStdDev ?? (avg * 0.15)
        let zScore = (hrv - avg) / max(std, 1)
        if zScore > 0.5 { return .excellent }
        if zScore >= -0.5 { return .normal }
        return .belowNormal
    }

    private func getRHRDeviationStatus(_ rhr: Double, baseline: PersonalBaseline?) -> DeviationStatus {
        guard let baseline = baseline, let avg = baseline.restingHeartRateAverage else { return rhr <= 65 ? .normal : .aboveNormal }
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

}

// MARK: - Health Metric Row Component

struct HealthMetricRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(IRFont.title3)
                .foregroundStyle(iconColor.gradient)
                .frame(width: 32)

            Text(title)
                .font(IRFont.body)
                .foregroundStyle(Color.irTextPrimary)

            Spacer()

            Text(value)
                .font(IRFont.body)
                .fontWeight(.semibold)
                .foregroundStyle(Color.irTextSecondary)
        }
    }
}

// MARK: - Sleep Stage Row Component

struct SleepStageRow: View {
    let stage: String
    let duration: TimeInterval
    let color: Color

    private var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        return String(format: "%d%@%02d", hours, String(localized: "h", comment: "Hour abbreviation"), minutes)
    }

    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)

            Text(stage)
                .font(IRFont.body)
                .foregroundStyle(Color.irTextPrimary)

            Spacer()

            Text(formattedDuration)
                .font(IRFont.body)
                .fontWeight(.medium)
                .foregroundStyle(Color.irTextSecondary)
        }
    }
}

// MARK: - Coaching Section (AI-enhanced for today)

struct CoachingSection: View {
    let fallbackRecommendation: String
    @StateObject private var readinessVM = DailyReadinessViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header with coaching icon and readiness score badge
            HStack {
                Label(
                    String(localized: "Coaching", comment: "Section header for recovery recommendation"),
                    systemImage: "text.bubble.fill"
                )
                .font(IRFont.headline)
                .foregroundStyle(Color.irWarning.gradient)

                Spacer()

                if readinessVM.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if let score = readinessVM.readinessScore {
                    HStack(spacing: Spacing.xxs) {
                        Text(readinessVM.status.emoji)
                            .font(IRFont.caption)
                        Text("\(score)/100")
                            .font(IRFont.body)
                            .fontWeight(.bold)
                            .foregroundStyle(readinessVM.status.color)
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xxs)
                    .background(readinessVM.status.color.opacity(0.15))
                    .clipShape(Capsule())
                }
            }

            // Recommendation text (AI or fallback)
            if readinessVM.readinessScore != nil, !readinessVM.recommendation.isEmpty {
                Text(readinessVM.recommendation)
                    .font(IRFont.body)
                    .foregroundStyle(Color.irTextPrimary)
                    .multilineTextAlignment(.leading)
            } else {
                Text(fallbackRecommendation)
                    .font(IRFont.body)
                    .foregroundStyle(Color.irTextPrimary)
                    .multilineTextAlignment(.leading)
            }

            // Suggested workout (only when readiness is available)
            if readinessVM.readinessScore != nil {
                Divider()

                HStack(spacing: Spacing.sm) {
                    Image(systemName: readinessVM.suggestedWorkoutType.icon)
                        .font(IRFont.title3)
                        .foregroundStyle(readinessVM.status.color)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Suggested Workout", comment: "Suggested workout section title"))
                            .font(IRFont.caption)
                            .foregroundStyle(Color.irTextSecondary)
                        Text(readinessVM.suggestedWorkoutType.title)
                            .font(IRFont.body)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.irTextPrimary)
                    }

                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.base)
        .background(Color.irWarning.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .task {
            await readinessVM.fetchDailyReadiness()
        }
        .sheet(isPresented: $readinessVM.needsConsent) {
            AIConsentSheet(
                onConsent: {
                    readinessVM.needsConsent = false
                    Task {
                        if await HistoricalSummaryStorage.shared.requiresIndexation() {
                            readinessVM.needsIndexation = true
                        } else {
                            await readinessVM.fetchDailyReadiness()
                        }
                    }
                },
                onDecline: {
                    readinessVM.needsConsent = false
                }
            )
        }
        .indexationGate(isPresented: $readinessVM.needsIndexation) {
            await readinessVM.fetchDailyReadiness()
        }
    }
}

#Preview {
    RecoveryDashboardView()
}
