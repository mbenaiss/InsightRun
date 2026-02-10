//
//  DashboardView.swift
//  InsightRun
//
//  Unified dashboard merging recovery, health vitals, sleep & coaching
//  Inspired by Whoop & Bevel design language
//

import SwiftUI
import Charts

struct DashboardView: View {
    @StateObject private var recoveryVM = RecoveryViewModel()
    @StateObject private var healthVM = HealthProfileViewModel()
    @StateObject private var readinessVM = DailyReadinessViewModel()
    @ObservedObject private var contextProvider = UnifiedAIContextProvider.shared
    @StateObject private var notificationRouter = NotificationRouter.shared
    @Environment(ThemeManager.self) private var themeManager
    @EnvironmentObject private var revenueCatManager: RevenueCatManager

    @State private var showSettings = false
    @State private var showingMedicalSources = false
    @State private var showingCalendar = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Recovery Ring - hero section
                    recoveryHeroSection
                        .padding(.horizontal)

                    // Quick Vitals Row
                    quickVitalsRow
                        .padding(.horizontal)

                    // Coaching Card
                    coachingCard
                        .padding(.horizontal)

                    // Sleep Summary
                    if let sleep = recoveryVM.recoveryMetrics?.sleepData {
                        sleepCard(sleep)
                            .padding(.horizontal)
                    }

                    // Health Trends
                    if let recovery = recoveryVM.recoveryMetrics {
                        healthTrendsSection(recovery)
                            .padding(.horizontal)
                    }

                    // Weekly Summary Link
                    weeklySummaryLink
                        .padding(.horizontal)
                }
                .padding(.top, Spacing.md)
                .padding(.bottom, 100)
            }
            .background(Color.irBackgroundApp)
            .navigationTitle(String(localized: "Dashboard", comment: "Dashboard navigation title"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                            .foregroundStyle(Color.irTextSecondary)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environment(themeManager)
                    .environmentObject(revenueCatManager)
            }
            .sheet(isPresented: $showingMedicalSources) {
                MedicalSourcesView()
            }
            .navigationDestination(isPresented: $notificationRouter.showWeeklySummary) {
                WeeklySummaryView()
            }
            .refreshable {
                await loadAllData()
            }
            .task {
                await loadAllData()
            }
        }
    }

    // MARK: - Data Loading

    private func loadAllData() async {
        async let recoveryLoad: () = recoveryVM.loadRecoveryMetrics()
        async let healthLoad: () = healthVM.loadHealthProfile()
        async let readinessLoad: () = readinessVM.fetchDailyReadiness()

        _ = await (recoveryLoad, healthLoad, readinessLoad)

        if let recovery = recoveryVM.recoveryMetrics {
            contextProvider.recoveryMetrics = recovery
        }
    }

    // MARK: - Recovery Hero Section

    private var recoveryHeroSection: some View {
        VStack(spacing: Spacing.base) {
            // Date
            Text(recoveryVM.formattedSelectedDateLong)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Color.irTextSecondary)

            if recoveryVM.isLoading {
                ProgressView()
                    .scaleEffect(1.2)
                    .frame(height: 200)
            } else if let recovery = recoveryVM.recoveryMetrics {
                // Recovery ring
                CircularProgressView(score: recovery.recoveryScore, size: 180, lineWidth: 12)

                // Status label
                Text(recovery.recoveryStatus.description)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.irTextPrimary)
            } else {
                // No data placeholder
                VStack(spacing: Spacing.md) {
                    Image(systemName: "heart.circle")
                        .font(.system(size: 60))
                        .foregroundStyle(Color.irTextSecondary.opacity(0.5))
                    Text(String(localized: "No recovery data", comment: "Dashboard no recovery data"))
                        .font(.subheadline)
                        .foregroundStyle(Color.irTextSecondary)
                }
                .frame(height: 200)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
        .padding(.horizontal, Spacing.lg)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xxl))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xxl)
                .stroke(Color.irBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Quick Vitals Row

    private var quickVitalsRow: some View {
        let recovery = recoveryVM.recoveryMetrics

        return HStack(spacing: Spacing.md) {
            // HRV
            VitalPill(
                icon: "waveform.path.ecg",
                label: "HRV",
                value: recovery?.hrvAverage.map { String(format: "%.0f", $0) } ?? "--",
                unit: "ms",
                color: .blue
            )

            // Resting HR
            VitalPill(
                icon: "heart.fill",
                label: String(localized: "RHR", comment: "Resting heart rate abbreviation"),
                value: recovery?.restingHeartRate.map { String(format: "%.0f", $0) } ?? "--",
                unit: "bpm",
                color: .red
            )

            // Sleep
            if let sleep = recovery?.sleepData {
                VitalPill(
                    icon: "moon.fill",
                    label: String(localized: "Sleep", comment: "Sleep vital label"),
                    value: sleep.formattedTotalSleep,
                    unit: "",
                    color: .indigo
                )
            } else {
                VitalPill(
                    icon: "moon.fill",
                    label: String(localized: "Sleep", comment: "Sleep vital label"),
                    value: "--",
                    unit: "",
                    color: .indigo
                )
            }
        }
    }

    // MARK: - Coaching Card

    private var coachingCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header
            HStack {
                Image(systemName: "text.bubble.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.irPrimaryAccent)

                Text(String(localized: "Coaching", comment: "Dashboard coaching section"))
                    .font(.headline)
                    .foregroundStyle(Color.irTextPrimary)

                Spacer()

                if readinessVM.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if let score = readinessVM.readinessScore {
                    HStack(spacing: 4) {
                        Text(readinessVM.status.emoji)
                            .font(.caption)
                        Text("\(score)/100")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(readinessVM.status.color)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(readinessVM.status.color.opacity(0.12))
                    .clipShape(Capsule())
                }
            }

            // Recommendation
            if readinessVM.readinessScore != nil, !readinessVM.recommendation.isEmpty {
                Text(readinessVM.recommendation)
                    .font(.subheadline)
                    .foregroundStyle(Color.irTextPrimary)
                    .lineSpacing(4)
            } else if let recovery = recoveryVM.recoveryMetrics {
                Text(recovery.recoveryStatus.recommendation)
                    .font(.subheadline)
                    .foregroundStyle(Color.irTextPrimary)
                    .lineSpacing(4)
            }

            // Suggested workout
            if readinessVM.readinessScore != nil {
                Divider()
                    .background(Color.irBorder)

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

                    Spacer()
                }
            }
        }
        .padding(Spacing.lg)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl)
                .stroke(Color.irBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Sleep Card

    private func sleepCard(_ sleep: SleepData) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Image(systemName: "bed.double.fill")
                    .font(.subheadline)
                    .foregroundStyle(.indigo)

                Text(String(localized: "Sleep", comment: "Sleep section header"))
                    .font(.headline)
                    .foregroundStyle(Color.irTextPrimary)

                Spacer()

                Text(String(format: "%.0f%%", sleep.sleepEfficiency))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(sleep.sleepEfficiency >= 85 ? Color.irSuccess : Color.irWarning)
            }

            // Sleep metrics row
            HStack(spacing: 0) {
                sleepMetric(
                    title: String(localized: "Duration", comment: "Sleep duration label"),
                    value: sleep.formattedTotalSleep
                )

                Divider()
                    .frame(height: 32)

                sleepMetric(
                    title: String(localized: "Session", comment: "Sleep session label"),
                    value: sleep.formattedSleepTime
                )

                if sleep.formattedNapDuration != nil {
                    Divider()
                        .frame(height: 32)

                    sleepMetric(
                        title: String(localized: "Naps", comment: "Naps label"),
                        value: sleep.formattedNapDuration ?? "--"
                    )
                }
            }

            // Sleep stages bar
            if let deep = sleep.deepSleepDuration,
               let core = sleep.coreSleepDuration,
               let rem = sleep.remSleepDuration {
                let total = deep + core + rem
                if total > 0 {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        // Stage bar
                        GeometryReader { geo in
                            HStack(spacing: 2) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.blue)
                                    .frame(width: max(4, geo.size.width * deep / total))
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.cyan)
                                    .frame(width: max(4, geo.size.width * core / total))
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.indigo)
                                    .frame(width: max(4, geo.size.width * rem / total))
                            }
                        }
                        .frame(height: 8)

                        // Legend
                        HStack(spacing: Spacing.base) {
                            stageLegend(color: .blue, label: String(localized: "Deep", comment: "Deep sleep"), duration: deep)
                            stageLegend(color: .cyan, label: String(localized: "Light", comment: "Light sleep"), duration: core)
                            stageLegend(color: .indigo, label: "REM", duration: rem)
                        }
                    }
                }
            }
        }
        .padding(Spacing.lg)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl)
                .stroke(Color.irBorder, lineWidth: 0.5)
        )
    }

    private func sleepMetric(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.headline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.irTextPrimary)
            Text(title)
                .font(.caption2)
                .foregroundStyle(Color.irTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func stageLegend(color: Color, label: String, duration: TimeInterval) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.irTextSecondary)
            Text(formatSleepDuration(duration))
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(Color.irTextPrimary)
        }
    }

    private func formatSleepDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        return String(format: "%d%@%02d", hours, String(localized: "h", comment: "Hour abbreviation"), minutes)
    }

    // MARK: - Health Trends Section

    private func healthTrendsSection(_ recovery: RecoveryMetrics) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(String(localized: "Trends", comment: "Health trends section header"))
                .font(.headline)
                .foregroundStyle(Color.irTextPrimary)

            VStack(spacing: Spacing.sm) {
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
                        baseline: recovery.baseline
                    )
                }

                if let rhr = recovery.restingHeartRate {
                    MetricTrendCard(
                        icon: "heart.fill",
                        iconColor: .red,
                        title: String(localized: "Resting HR", comment: "Resting heart rate"),
                        value: rhr,
                        unit: "bpm",
                        deviationStatus: getRHRDeviationStatus(rhr, baseline: recovery.baseline),
                        metricType: .restingHeartRate,
                        trendData: generateTrendData(baseValue: rhr),
                        baseline: recovery.baseline
                    )
                }

                if let respRate = recovery.respiratoryRate {
                    MetricTrendCard(
                        icon: "lungs.fill",
                        iconColor: .teal,
                        title: String(localized: "Respiratory rate", comment: "Respiratory rate"),
                        value: respRate,
                        unit: "rpm",
                        deviationStatus: getRespiratoryDeviationStatus(respRate, baseline: recovery.baseline),
                        metricType: .respiratoryRate,
                        trendData: generateTrendData(baseValue: respRate),
                        baseline: recovery.baseline
                    )
                }

                if let spo2 = recovery.oxygenSaturation {
                    MetricTrendCard(
                        icon: "drop.fill",
                        iconColor: .cyan,
                        title: String(localized: "Oxygen saturation", comment: "SpO2"),
                        value: spo2,
                        unit: "%",
                        deviationStatus: getSpO2DeviationStatus(spo2),
                        metricType: .oxygenSaturation,
                        trendData: generateTrendData(baseValue: spo2, variance: 2),
                        baseline: recovery.baseline
                    )
                }
            }
        }
    }

    // MARK: - Weekly Summary Link

    private var weeklySummaryLink: some View {
        NavigationLink {
            WeeklySummaryView()
        } label: {
            HStack(spacing: Spacing.base) {
                Image(systemName: "calendar")
                    .font(.title3)
                    .foregroundStyle(Color.irPrimaryAccent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Weekly Summary", comment: "Weekly summary link"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.irTextPrimary)
                    Text(String(localized: "Running, sleep & recovery overview", comment: "Weekly summary description"))
                        .font(.caption)
                        .foregroundStyle(Color.irTextSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.irTextSecondary)
            }
            .padding(Spacing.lg)
            .background(Color.irCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xl)
                    .stroke(Color.irBorder, lineWidth: 0.5)
            )
        }
    }

    // MARK: - Deviation Helpers

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

// MARK: - Vital Pill Component

struct VitalPill: View {
    let icon: String
    let label: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(color.opacity(0.8))

            Text(value)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.bold)
                .foregroundStyle(Color.irTextPrimary)

            if !unit.isEmpty {
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(Color.irTextSecondary)
            } else {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(Color.irTextSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(Color.irBorder, lineWidth: 0.5)
        )
    }
}

#Preview {
    DashboardView()
        .environment(ThemeManager())
        .environmentObject(RevenueCatManager.shared)
}
