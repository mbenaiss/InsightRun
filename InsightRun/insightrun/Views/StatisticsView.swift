//
//  StatisticsView.swift
//  InsightRun
//
//  Pulse-Ring statistics screen — editorial header, custom segmented tabs,
//  full-bleed period chips, horizontal personal-records carousel,
//  KPI hero grid with sparklines/deltas, area chart, distributions.
//

import SwiftUI
import Charts
import SwiftData

enum StatisticsTab: String, CaseIterable {
    case overview
    case progression

    var localizedTitle: String {
        switch self {
        case .overview:
            return String(localized: "statistics.tab.overview", defaultValue: "Overview", comment: "Overview tab")
        case .progression:
            return String(localized: "statistics.tab.progression", defaultValue: "Progression", comment: "Progression tab")
        }
    }
}

struct StatisticsView: View {
    @StateObject private var viewModel: StatisticsViewModel
    @StateObject private var coachInsightVM: MonthlyCoachInsightViewModel
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject private var revenueCatManager: RevenueCatManager
    @State private var selectedTab: StatisticsTab = .overview
    @State private var selectedPeriodDate: Date?
    @State private var showSubscriptionPaywall = false
    @State private var showConsentSheet = false
    @State private var hasTrackedCoachTeaser = false

    init(injectedViewModel: StatisticsViewModel? = nil) {
        if let injected = injectedViewModel {
            _viewModel = StateObject(wrappedValue: injected)
        } else {
            _viewModel = StateObject(wrappedValue: StatisticsViewModel())
        }

        guard let container = InsightRunApp.shared else {
            fatalError("ModelContainer not initialized before StatisticsView")
        }
        _coachInsightVM = StateObject(wrappedValue: MonthlyCoachInsightViewModel(modelContext: container.mainContext))
    }

    private var pulseRingPeriods: [StatisticsViewModel.TimePeriod] {
        [.thisWeek, .thisMonth, .sixMonths, .oneYear, .allTime, .specificYear]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    editorialHeader
                    pulseRingTabs
                    periodChipsScroll

                    if viewModel.selectedPeriod == .specificYear {
                        yearMenu
                    }

                    if viewModel.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 50)
                    } else if viewModel.workouts.isEmpty {
                        emptyState
                    } else {
                        switch selectedTab {
                        case .overview:
                            overviewContent
                        case .progression:
                            MetricsProgressionView(viewModel: viewModel)
                        }
                    }
                }
                .padding(.horizontal, Spacing.cardPadding)
                .padding(.top, Spacing.sm)
                .padding(.bottom, 40)
            }
            .accessibilityIdentifier("statistics-content")
            .background(Color.irBackgroundApp.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                await viewModel.refresh()
            }
        }
        .sheet(isPresented: $showSubscriptionPaywall) {
            SubscriptionPaywallView(isInitialFlow: false)
                .environmentObject(revenueCatManager)
        }
        .sheet(isPresented: $showConsentSheet) {
            AIConsentSheet(
                onConsent: {
                    showConsentSheet = false
                    coachInsightVM.needsConsent = false
                    Task { await loadCoachInsight() }
                },
                onDecline: { showConsentSheet = false }
            )
        }
        .task {
            await viewModel.loadWorkouts()
            AnalyticsService.shared.trackStatisticsViewed()

            // Try to populate the coach insight from cache as soon as workouts land.
            await loadCoachInsight()
        }
        .onChange(of: viewModel.workouts.count) { _, _ in
            Task { await loadCoachInsight() }
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .progression {
                viewModel.loadProgressionMetrics()
            }
        }
        .onChange(of: viewModel.selectedPeriod) { _, _ in
            if selectedTab == .progression {
                viewModel.loadProgressionMetrics()
            }
        }
        .onChange(of: viewModel.selectedYear) { _, _ in
            if selectedTab == .progression {
                viewModel.loadProgressionMetrics()
            }
        }
    }

    // MARK: - Editorial Header

    private var editorialHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .top) {
                Text(String(localized: "statistics.eyebrow", defaultValue: "Trends", comment: "Statistics screen eyebrow").uppercased())
                    .font(IRFont.eyebrow.weight(.bold))
                    .tracking(IRTracking.eyebrow)
                    .foregroundStyle(Color.irTextTertiary)

                Spacer()
            }

            Text(String(localized: "statistics.title", comment: "Statistics screen title"))
                .font(IRFont.title1.weight(.heavy))
                .kerning(-1)
                .foregroundStyle(Color.irTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(viewModel.headerSubtitle)
                .font(IRFont.footnote)
                .foregroundStyle(Color.irTextSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Pulse-Ring Tabs (custom segmented)

    private var pulseRingTabs: some View {
        HStack(spacing: 0) {
            ForEach(StatisticsTab.allCases, id: \.self) { tab in
                let isActive = selectedTab == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.localizedTitle)
                        .font(IRFont.caption.weight(.bold))
                        .foregroundStyle(isActive ? Color.irBackgroundApp : Color.irTextSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .padding(.horizontal, Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.xs)
                                .fill(isActive ? Color.irTextPrimary : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm)
                .fill(Color.irCardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .strokeBorder(Color.irBorder, lineWidth: 0.5)
                )
        )
    }

    // MARK: - Period Chips (full-bleed scroll)

    private var periodChipsScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(pulseRingPeriods, id: \.self) { period in
                    PulseRingPeriodChip(
                        title: period.localizedTitle,
                        isSelected: viewModel.selectedPeriod == period
                    ) {
                        AnalyticsService.shared.trackStatisticsPeriodChanged(period: String(describing: period))
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.selectedPeriod = period
                            if period == .specificYear {
                                viewModel.selectedYear = viewModel.availableYears.first ?? Calendar.current.component(.year, from: Date())
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.cardPadding)
        }
        .padding(.horizontal, -18)
    }

    private var yearMenu: some View {
        Menu {
            ForEach(viewModel.availableYears, id: \.self) { year in
                Button {
                    withAnimation { viewModel.selectedYear = year }
                    AnalyticsService.shared.trackStatisticsYearChanged(year: year)
                } label: {
                    HStack {
                        Text("\(year)")
                        if viewModel.selectedYear == year {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.irPrimaryAccent)
                        }
                    }
                }
            }
        } label: {
            HStack {
                Text(String(localized: "statistics.year"))
                    .font(IRFont.body)
                    .foregroundStyle(Color.irTextSecondary)
                Spacer()
                Text("\(viewModel.selectedYear)")
                    .font(IRFont.bodyEmphasized)
                    .foregroundStyle(Color.irTextPrimary)
                Image(systemName: "chevron.down")
                    .font(IRFont.caption)
                    .foregroundStyle(Color.irTextSecondary)
            }
            .padding(Spacing.dash)
            .frame(maxWidth: .infinity)
            .background(Color.irCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .strokeBorder(Color.irBorder, lineWidth: 0.5)
            )
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Overview

    @ViewBuilder
    private var overviewContent: some View {
        // Section 01 — Personal records (horizontal scroll)
        VStack(alignment: .leading, spacing: Spacing.md) {
            pulseRingEyebrow(num: "01", title: String(localized: "statistics.records.title"))
            personalRecordsCarousel
        }

        // Section 02 — KPI hero (2x2 with sparkline + delta vs previous month + prev value)
        VStack(alignment: .leading, spacing: Spacing.md) {
            pulseRingEyebrow(num: "02", title: String(localized: "statistics.section.thisMonth", defaultValue: "This month", comment: "Stats section: this month"))
            kpiHeroGrid
        }

        // Coach insight (no eyebrow number — sits as a narrative bridge between 02 and 03)
        if shouldShowCoachInsightCard {
            MonthlyCoachInsightCard(
                vm: coachInsightVM,
                hasAIAccess: revenueCatManager.hasAIAccess,
                onUnlockTap: {
                    AnalyticsService.shared.track(.aiTeaserSubscribeTapped)
                    showSubscriptionPaywall = true
                },
                onConsentTap: { showConsentSheet = true },
                onTeaserShown: {
                    guard !hasTrackedCoachTeaser else { return }
                    hasTrackedCoachTeaser = true
                    AnalyticsService.shared.track(.aiTeaserShown)
                },
                onGenerateTap: {
                    Task { await loadCoachInsight() }
                },
                onRegenerateTap: {
                    Task { await regenerateCoachInsight() }
                }
            )
            .indexationGate(isPresented: $coachInsightVM.needsIndexation) {
                await loadCoachInsight()
            }
        }

        // Section 03 — Distance over period
        VStack(alignment: .leading, spacing: Spacing.md) {
            pulseRingEyebrow(num: "03", title: String(localized: "statistics.section.distanceOverPeriod", defaultValue: "Distance over period", comment: "Stats section: distance over period"))
            distanceChartCard
        }

        // Section 04 — Pace distribution
        VStack(alignment: .leading, spacing: Spacing.md) {
            pulseRingEyebrow(num: "04", title: String(localized: "statistics.section.paceDistribution", defaultValue: "Pace distribution", comment: "Stats section: pace distribution"))
            paceDistributionCard
        }

        // Section 05 — Distance distribution
        VStack(alignment: .leading, spacing: Spacing.md) {
            pulseRingEyebrow(num: "05", title: String(localized: "statistics.section.distanceDistribution", defaultValue: "Distance distribution", comment: "Stats section: distance distribution"))
            distanceDistributionCard
        }
    }

    // MARK: - Numbered eyebrow

    private func pulseRingEyebrow(num: String, title: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Text(num)
                .font(IRFont.monoSM.weight(.bold))
                .foregroundStyle(Color.irTextSecondary)
            Rectangle()
                .fill(Color.irBorder)
                .frame(width: 18, height: 0.5)
            Text(title.uppercased())
                .font(IRFont.eyebrow.weight(.bold))
                .tracking(IRTracking.eyebrow)
                .foregroundStyle(Color.irTextTertiary)
            Spacer()
        }
        .padding(.horizontal, Spacing.xxs)
    }

    // MARK: - Personal records carousel (Section 01)

    private var personalRecordsCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(personalRecords, id: \.id) { record in
                    PRCard(record: record)
                }
            }
            .padding(.horizontal, Spacing.cardPadding)
        }
        .padding(.horizontal, -18)
        .accessibilityIdentifier("personal-records-carousel")
    }

    private var personalRecords: [PersonalRecord] {
        var list: [PersonalRecord] = []

        if let r = viewModel.longestRun, let d = r.distance {
            list.append(PersonalRecord(
                label: String(localized: "statistics.records.longestDistance"),
                value: Formatters.decimal(Formatters.distanceValue(km: d / 1000.0), fractionDigits: 1),
                unit: Formatters.distanceUnitLabel(),
                date: r.startDate,
                color: Color.irPrimaryAccent,
                icon: "trophy",
                mono: false,
                recent: isRecent(r.startDate)
            ))
        }
        if let r = viewModel.fastestRun, let pace = r.averagePace {
            list.append(PersonalRecord(
                label: String(localized: "statistics.records.fastestPace"),
                value: viewModel.formatPace(pace),
                unit: nil,
                date: r.startDate,
                color: .irWarning,
                icon: "bolt",
                mono: true,
                recent: isRecent(r.startDate)
            ))
        }
        if let r = viewModel.longestDuration {
            list.append(PersonalRecord(
                label: String(localized: "statistics.records.longestDuration"),
                value: viewModel.formatDuration(r.duration),
                unit: nil,
                date: r.startDate,
                color: .irSuccess,
                icon: "clock",
                mono: true,
                recent: isRecent(r.startDate)
            ))
        }
        if let r = viewModel.best5K {
            list.append(PersonalRecord(
                label: String(localized: "statistics.records.best5k"),
                value: viewModel.formatDuration(r.duration),
                unit: nil,
                date: r.startDate,
                color: Color.irPrimaryAccent,
                icon: "5K",
                mono: true,
                recent: isRecent(r.startDate)
            ))
        }
        if let r = viewModel.best10K {
            list.append(PersonalRecord(
                label: String(localized: "statistics.records.best10k"),
                value: viewModel.formatDuration(r.duration),
                unit: nil,
                date: r.startDate,
                color: .irPrimaryAccent,
                icon: "10K",
                mono: true,
                recent: isRecent(r.startDate)
            ))
        }
        if let r = viewModel.bestHalfMarathon {
            list.append(PersonalRecord(
                label: String(localized: "statistics.records.bestHalf"),
                value: viewModel.formatDuration(r.duration),
                unit: nil,
                date: r.startDate,
                color: .irWarning,
                icon: "21K",
                mono: true,
                recent: isRecent(r.startDate)
            ))
        }
        if let r = viewModel.bestMarathon {
            list.append(PersonalRecord(
                label: String(localized: "statistics.records.bestMarathon"),
                value: viewModel.formatDuration(r.duration),
                unit: nil,
                date: r.startDate,
                color: Color.irPrimaryAccent,
                icon: "42K",
                mono: true,
                recent: isRecent(r.startDate)
            ))
        }

        return list
    }

    private func isRecent(_ date: Date) -> Bool {
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? Int.max
        return days <= 30
    }

    // MARK: - KPI hero grid (Section 02)

    private var kpiHeroGrid: some View {
        let mc = viewModel.monthlyChange

        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                kpiHeroCell(
                    label: String(localized: "statistics.kpi.workouts", defaultValue: "Sessions", comment: "KPI hero label: workouts count"),
                    value: "\(mc.thisMonthWorkouts)",
                    unit: nil,
                    valueColor: .irTextPrimary,
                    mono: false,
                    delta: percentChange(now: Double(mc.thisMonthWorkouts), prev: Double(mc.lastMonthWorkouts)),
                    invertDelta: false,
                    prevLabel: "\(mc.lastMonthWorkouts)",
                    sparkline: viewModel.sparklineWorkouts,
                    sparklineColor: .irTextPrimary,
                    showsRightBorder: true,
                    showsBottomBorder: true
                )
                kpiHeroCell(
                    label: String(localized: "statistics.kpi.distance", defaultValue: "Distance", comment: "KPI hero label: distance"),
                    value: Formatters.decimal(Formatters.distanceValue(km: mc.thisMonthDistance / 1000.0), fractionDigits: 1),
                    unit: Formatters.distanceUnitLabel(),
                    valueColor: .irPrimaryAccent,
                    mono: false,
                    delta: percentChange(now: mc.thisMonthDistance, prev: mc.lastMonthDistance),
                    invertDelta: false,
                    prevLabel: viewModel.formatDistance(mc.lastMonthDistance),
                    sparkline: viewModel.sparklineDistance,
                    sparklineColor: .irPrimaryAccent,
                    showsRightBorder: false,
                    showsBottomBorder: true
                )
            }
            HStack(spacing: 0) {
                kpiHeroCell(
                    label: String(localized: "statistics.kpi.duration", defaultValue: "Time", comment: "KPI hero label: duration"),
                    value: viewModel.formatDuration(mc.thisMonthDuration),
                    unit: nil,
                    valueColor: .irSuccess,
                    mono: true,
                    delta: percentChange(now: mc.thisMonthDuration, prev: mc.lastMonthDuration),
                    invertDelta: false,
                    prevLabel: viewModel.formatDuration(mc.lastMonthDuration),
                    sparkline: viewModel.sparklineDuration,
                    sparklineColor: .irSuccess,
                    showsRightBorder: true,
                    showsBottomBorder: false
                )
                kpiHeroCell(
                    label: String(localized: "statistics.kpi.avgPace", defaultValue: "Avg pace", comment: "KPI hero label: avg pace"),
                    value: mc.thisMonthAvgPace.map { viewModel.formatPace($0) } ?? "—",
                    unit: nil,
                    valueColor: .irWarning,
                    mono: true,
                    delta: paceDeltaPercent,
                    invertDelta: true,
                    prevLabel: mc.lastMonthAvgPace.map { viewModel.formatPace($0) } ?? "—",
                    sparkline: viewModel.sparklinePace,
                    sparklineColor: .irWarning,
                    showsRightBorder: false,
                    showsBottomBorder: false
                )
            }
        }
        .detailCard()
    }

    /// Returns nil when there is no baseline (prev = 0) so the delta badge can hide,
    /// otherwise returns a signed percentage clipped to ±999% to avoid pathological values.
    private func percentChange(now: Double, prev: Double) -> Double? {
        guard prev > 0 else { return nil }
        let pct = (now - prev) / prev * 100
        return min(999, max(-999, pct))
    }

    private var paceDeltaPercent: Double? {
        guard let now = viewModel.monthlyChange.thisMonthAvgPace,
              let prev = viewModel.monthlyChange.lastMonthAvgPace,
              prev > 0 else { return nil }
        return (now - prev) / prev * 100
    }

    private func kpiHeroCell(
        label: String,
        value: String,
        unit: String?,
        valueColor: Color,
        mono: Bool,
        delta: Double?,
        invertDelta: Bool,
        prevLabel: String,
        sparkline: [Double],
        sparklineColor: Color,
        showsRightBorder: Bool,
        showsBottomBorder: Bool
    ) -> some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Text(label.uppercased())
                        .font(IRFont.microLabel.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(Color.irTextSecondary.opacity(0.7))
                        .lineLimit(1)
                    Spacer()
                    if let delta {
                        DeltaBadge(percent: delta, invertSign: invertDelta)
                    }
                }

                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(value)
                        .font(mono ? IRFont.monoXL.weight(.heavy) : IRFont.title3.weight(.heavy))
                        .kerning(-0.4)
                        .foregroundStyle(valueColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let unit {
                        Text(unit)
                            .font(IRFont.eyebrow.weight(.semibold))
                            .foregroundStyle(Color.irTextSecondary.opacity(0.7))
                    }
                }

                HStack(alignment: .center, spacing: Spacing.xxs) {
                    Text("\(String(localized: "statistics.kpi.vsPrev", defaultValue: "vs", comment: "KPI hero subtitle: 'vs <prev value>'")) \(prevLabel)")
                        .font(IRFont.eyebrow)
                        .foregroundStyle(Color.irTextSecondary.opacity(0.55))
                        .lineLimit(1)
                    Spacer()
                    MicroSparkline(values: sparkline, color: sparklineColor)
                        .frame(width: 60, height: 18)
                        .accessibilityHidden(true)
                }
            }
            .padding(Spacing.dash)
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .overlay(alignment: .trailing) {
            if showsRightBorder {
                Rectangle().fill(Color.irBorder).frame(width: 0.5)
            }
        }
        .overlay(alignment: .bottom) {
            if showsBottomBorder {
                Rectangle().fill(Color.irBorder).frame(height: 0.5)
            }
        }
    }

    // MARK: - Distance chart card (Section 03)

    private var distanceChartCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
                        Text(Formatters.decimal(Formatters.distanceValue(km: viewModel.totalDistance / 1000.0), fractionDigits: 1))
                            .font(IRFont.numMD.weight(.heavy))
                            .kerning(IRTracking.num(28))
                            .foregroundStyle(Color.irPrimaryAccent)
                        Text(String(format: String(localized: "statistics.charts.totalDistanceUnit", defaultValue: "%@ total", comment: "Distance chart caption: '<unit> total' (e.g. 'km total')"), Formatters.distanceUnitLabel()))
                            .font(IRFont.footnote)
                            .foregroundStyle(Color.irTextSecondary.opacity(0.55))
                    }
                    if let peak = peakBucketLabel {
                        Text(peak)
                            .font(IRFont.eyebrow)
                            .foregroundStyle(Color.irTextSecondary)
                    }
                }
                Spacer()
                granularityToggle
            }
            .onChange(of: viewModel.selectedPeriod) { _, newValue in
                if newValue == .thisMonth || newValue == .thisWeek {
                    viewModel.chartGranularity = .week
                } else if viewModel.chartGranularity != .month {
                    viewModel.chartGranularity = .month
                }
            }

            if !viewModel.periodDistanceData.isEmpty {
                distanceChartContent
            } else {
                Text(String(localized: "statistics.charts.noData"))
                    .foregroundStyle(Color.irTextSecondary)
                    .frame(height: 130)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(Spacing.cardPadding)
        .detailCard()
    }

    private var peakBucketLabel: String? {
        let sorted = viewModel.periodDistanceData.sorted { $0.distance > $1.distance }
        guard let top = sorted.first, top.distance > 0 else { return nil }
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate(viewModel.chartGranularity == .week ? "dMMM" : "LLLyyyy")
        let dateLabel = f.string(from: top.date)
        let kmLabel = viewModel.formatDistance(top.distance)
        return "\(String(localized: "statistics.charts.peak", defaultValue: "Peak", comment: "Distance chart caption prefix: peak")) \(dateLabel) · \(kmLabel)"
    }

    private var granularityToggle: some View {
        HStack(spacing: 0) {
            ForEach(StatisticsViewModel.ChartGranularity.allCases, id: \.self) { gran in
                let isActive = viewModel.chartGranularity == gran
                Button {
                    viewModel.chartGranularity = gran
                } label: {
                    Text(gran.localizedTitle)
                        .font(IRFont.microLabel.weight(.bold))
                        .foregroundStyle(isActive ? Color.irTextPrimary : Color.irTextSecondary)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.xxs)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.xs)
                                .fill(isActive ? Color.irBorder : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: Radius.xs)
                .fill(Color.irCardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.xs)
                        .strokeBorder(Color.irBorder, lineWidth: 0.5)
                )
        )
    }

    private var distanceChartContent: some View {
        let sortedData = viewModel.periodDistanceData.sorted { $0.date < $1.date }
        let selectedData = selectedPeriodDate.flatMap { selectedDate in
            sortedData.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
        }

        return VStack(alignment: .leading, spacing: Spacing.xs) {
            if let selected = selectedData {
                HStack(alignment: .firstTextBaseline) {
                    Text(viewModel.formatDistance(selected.distance))
                        .font(IRFont.bodyEmphasized.weight(.bold))
                        .foregroundStyle(Color.irPrimaryAccent)
                    Spacer()
                    Text(formatChartDate(selected.date))
                        .font(IRFont.caption)
                        .foregroundStyle(Color.irTextSecondary)
                }
            }

            Chart {
                ForEach(sortedData) { data in
                    AreaMark(
                        x: .value("Date", data.date),
                        y: .value("Distance", data.distance / 1000.0)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.irPrimaryAccent.opacity(0.5), Color.irPrimaryAccent.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }

                ForEach(sortedData) { data in
                    LineMark(
                        x: .value("Date", data.date),
                        y: .value("Distance", data.distance / 1000.0)
                    )
                    .foregroundStyle(Color.irPrimaryAccent)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }

                if let peak = sortedData.max(by: { $0.distance < $1.distance }), peak.distance > 0 {
                    PointMark(
                        x: .value("Date", peak.date),
                        y: .value("Distance", peak.distance / 1000.0)
                    )
                    .foregroundStyle(Color.irPrimaryAccent)
                    .symbolSize(40)
                }

                if let selected = selectedData {
                    PointMark(
                        x: .value("Date", selected.date),
                        y: .value("Distance", selected.distance / 1000.0)
                    )
                    .foregroundStyle(Color.irPrimaryAccent)
                    .symbolSize(50)
                    RuleMark(x: .value("Date", selected.date))
                        .foregroundStyle(Color.irTextSecondary.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .frame(height: 140)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(formatChartAxisDate(date))
                                .font(IRFont.monoSM)
                                .foregroundStyle(Color.irTextSecondary.opacity(0.7))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                        .foregroundStyle(Color.irTextSecondary.opacity(0.15))
                    AxisValueLabel {
                        if let distance = value.as(Double.self) {
                            Text("\(Int(distance))")
                                .font(IRFont.monoSM)
                                .foregroundStyle(Color.irTextSecondary.opacity(0.7))
                        }
                    }
                }
            }
            .chartXSelection(value: $selectedPeriodDate)
            .accessibilityLabel(String(localized: "statistics.charts.distance.accessibility", defaultValue: "Distance over period chart", comment: "VoiceOver label for the distance-over-period chart"))
        }
    }

    private func formatChartDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale.current
        return formatter.string(from: date)
    }

    private func formatChartAxisDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate(viewModel.chartGranularity == .week ? "dMMM" : "LLL")
        return formatter.string(from: date)
    }

    // MARK: - Pace distribution (Section 04)

    private var paceDistributionCard: some View {
        VStack(spacing: Spacing.dash) {
            ForEach(viewModel.paceDistributionData) { dist in
                PaceZoneRow(distribution: dist)
            }
        }
        .padding(Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .detailCard()
    }

    // MARK: - Distance distribution (Section 05)

    private var distanceDistributionCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.distanceDistributionData.enumerated()), id: \.element.id) { index, dist in
                if index > 0 {
                    Divider().background(Color.irBorder)
                }
                DistanceBucketRow(distribution: dist)
            }
        }
        .frame(maxWidth: .infinity)
        .detailCard()
    }

    // MARK: - Coach insight helpers

    /// Only show the card on the overview tab when the user is actually looking at
    /// "this month" comparisons — for other periods the LLM context wouldn't fit
    /// the "Lecture du mois" framing.
    private var shouldShowCoachInsightCard: Bool {
        guard !viewModel.workouts.isEmpty else { return false }
        let mc = viewModel.monthlyChange
        return mc.thisMonthWorkouts > 0 || mc.lastMonthWorkouts > 0
    }

    private func currentAndPreviousMonthWorkouts() -> ([WorkoutModel], [WorkoutModel]) {
        let calendar = Calendar.current
        guard let startOfThisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())),
              let startOfLastMonth = calendar.date(byAdding: .month, value: -1, to: startOfThisMonth) else {
            return ([], [])
        }
        let thisMonth = viewModel.workouts.filter { $0.startDate >= startOfThisMonth }
        let lastMonth = viewModel.workouts.filter { $0.startDate >= startOfLastMonth && $0.startDate < startOfThisMonth }
        return (thisMonth, lastMonth)
    }

    private func loadCoachInsight() async {
        guard revenueCatManager.hasAIAccess else { return }
        let (thisMonth, lastMonth) = currentAndPreviousMonthWorkouts()
        guard !thisMonth.isEmpty || !lastMonth.isEmpty else { return }
        await coachInsightVM.loadInsight(thisMonth: thisMonth, lastMonth: lastMonth)
    }

    private func regenerateCoachInsight() async {
        guard revenueCatManager.hasAIAccess else { return }
        let (thisMonth, lastMonth) = currentAndPreviousMonthWorkouts()
        // Refresh the snapshot first so the prompt sees the latest data, then regen.
        await coachInsightVM.loadInsight(thisMonth: thisMonth, lastMonth: lastMonth)
        await coachInsightVM.regenerate()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.base) {
            Image(systemName: "chart.bar.xaxis")
                .font(IRFont.display)
                .foregroundStyle(Color.irTextSecondary.opacity(0.5))
                .accessibilityHidden(true)

            Text(String(localized: "statistics.empty.title"))
                .font(IRFont.numSM.weight(.semibold))
                .foregroundStyle(Color.irTextPrimary)

            Text(String(localized: "statistics.empty.message"))
                .font(IRFont.footnote)
                .foregroundStyle(Color.irTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Personal Record value object

struct PersonalRecord: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let unit: String?
    let date: Date
    let color: Color
    let icon: String
    let mono: Bool
    let recent: Bool
}

// MARK: - PR card

struct PRCard: View {
    let record: PersonalRecord

    private var dateLabel: String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("dMMMyyyy")
        return f.string(from: record.date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.xs)
                        .fill(record.color.opacity(0.22))
                    iconGlyph
                        .foregroundStyle(record.color)
                }
                .frame(width: 28, height: 28)

                Spacer()

                if record.recent {
                    Text(String(localized: "statistics.records.new", defaultValue: "★ NEW", comment: "Badge for recent personal record").uppercased())
                        .font(IRFont.eyebrow.weight(.heavy))
                        .tracking(IRTracking.eyebrow)
                        .foregroundStyle(Color.irTextOnAccent)
                        .padding(.horizontal, Spacing.xxs + 1)
                        .padding(.vertical, 2)
                        .background(record.color)
                        .clipShape(Capsule())
                }
            }

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(record.label.uppercased())
                    .font(IRFont.microLabel.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color.irTextSecondary)
                    .lineLimit(1)

                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(record.value)
                        .font(record.mono ? IRFont.monoXL.weight(.heavy) : IRFont.title3.weight(.heavy))
                        .kerning(-0.4)
                        .foregroundStyle(Color.irTextPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let unit = record.unit {
                        Text(unit)
                            .font(IRFont.microLabel.weight(.semibold))
                            .foregroundStyle(Color.irTextSecondary.opacity(0.7))
                    }
                }

                Text(dateLabel)
                    .font(IRFont.monoSM)
                    .foregroundStyle(Color.irTextSecondary.opacity(0.55))
            }
        }
        .padding(Spacing.dash)
        .frame(width: 180, alignment: .leading)
        .background(
            LinearGradient(
                colors: [record.color.opacity(0.14), Color.irCardBackground],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(record.color.opacity(0.25), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var iconGlyph: some View {
        switch record.icon {
        case "trophy":
            Image(systemName: "trophy.fill").font(IRFont.body.weight(.semibold))
        case "bolt":
            Image(systemName: "bolt.fill").font(IRFont.body.weight(.semibold))
        case "clock":
            Image(systemName: "clock.fill").font(IRFont.body.weight(.semibold))
        default:
            Text(record.icon)
                .font(IRFont.monoSM.weight(.heavy))
        }
    }
}

// MARK: - Delta badge

struct DeltaBadge: View {
    let percent: Double
    let invertSign: Bool

    private var direction: Int {
        if abs(percent) < 0.5 { return 0 }
        return percent > 0 ? 1 : -1
    }

    private var color: Color {
        guard direction != 0 else { return Color.irTextSecondary.opacity(0.7) }
        let positive = invertSign ? direction < 0 : direction > 0
        return positive ? .irSuccess : .irError
    }

    private var arrow: String {
        switch direction {
        case 1: return "↗"
        case -1: return "↘"
        default: return "→"
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            Text(arrow)
                .font(IRFont.eyebrow.weight(.heavy))
            Text("\(Int(abs(percent).rounded()))%")
                .font(IRFont.eyebrow.weight(.heavy))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(color.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Pulse-Ring period chip

struct PulseRingPeriodChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(IRFont.eyebrow.weight(.bold))
                .foregroundStyle(isSelected ? Color.irTextOnAccent : Color.irTextSecondary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.irPrimaryAccent : Color.irCardBackground)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? Color.irPrimaryAccent : Color.irBorder, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pace zone row

struct PaceZoneRow: View {
    let distribution: StatisticsViewModel.PaceDistribution

    private var isEmpty: Bool { distribution.count == 0 }

    var body: some View {
        VStack(spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
                    Text(distribution.range)
                        .font(IRFont.monoSM.weight(.heavy))
                        .foregroundStyle(isEmpty ? Color.irTextSecondary.opacity(0.5) : Color.irTextPrimary)
                    Text(String(localized: "/km", comment: "Pace unit suffix"))
                        .font(IRFont.eyebrow.weight(.semibold))
                        .foregroundStyle(Color.irTextSecondary.opacity(0.55))
                    if !distribution.zoneLabel.isEmpty {
                        Text("· \(distribution.zoneLabel)")
                            .font(IRFont.microLabel)
                            .foregroundStyle(Color.irTextSecondary.opacity(0.55))
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(Int(distribution.percentage.rounded()))%")
                        .font(IRFont.monoSM.weight(.heavy))
                        .foregroundStyle(isEmpty ? Color.irTextSecondary.opacity(0.5) : distribution.color)
                    Text(String(format: String(localized: "statistics.distribution.workoutsCount", defaultValue: "%lld workouts", comment: "Number of workouts"), distribution.count))
                        .font(IRFont.microLabel)
                        .foregroundStyle(Color.irTextSecondary.opacity(0.55))
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.irBorder)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(distribution.color)
                        .frame(width: max(0, geo.size.width * (distribution.percentage / 100.0)), height: 6)
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Distance bucket row

struct DistanceBucketRow: View {
    let distribution: StatisticsViewModel.DistanceDistribution

    private var isEmpty: Bool { distribution.count == 0 }
    private var fillColor: Color { .irPrimaryAccent }

    var body: some View {
        HStack(spacing: Spacing.md) {
            Text(distribution.category)
                .font(IRFont.monoSM.weight(.semibold))
                .foregroundStyle(isEmpty ? Color.irTextSecondary.opacity(0.5) : Color.irTextPrimary)
                .frame(width: 76, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.irBorder)
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(fillColor)
                        .frame(width: max(0, geo.size.width * (distribution.percentage / 100.0)), height: 8)
                }
            }
            .frame(height: 8)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(distribution.count > 0 ? Formatters.decimal(Formatters.distanceValue(km: distribution.totalKm), fractionDigits: 1) : "—")
                    .font(IRFont.monoSM.weight(.heavy))
                    .foregroundStyle(isEmpty ? Color.irTextSecondary.opacity(0.5) : Color.irTextPrimary)
                Text(Formatters.distanceUnitLabel())
                    .font(IRFont.eyebrow.weight(.semibold))
                    .foregroundStyle(Color.irTextSecondary.opacity(0.55))
            }
            .frame(width: 56, alignment: .trailing)
        }
        .padding(.horizontal, Spacing.dash)
        .padding(.vertical, Spacing.md)
    }
}

// MARK: - Monthly coach insight card (LLM-backed, paywalled)

struct MonthlyCoachInsightCard: View {
    @ObservedObject var vm: MonthlyCoachInsightViewModel
    let hasAIAccess: Bool
    let onUnlockTap: () -> Void
    let onConsentTap: () -> Void
    let onTeaserShown: () -> Void
    let onGenerateTap: () -> Void
    let onRegenerateTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            header
            content
        }
        .padding(Spacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.irPrimaryAccent.opacity(0.08), Color.irCardBackground],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Color.irPrimaryAccent.opacity(0.30), lineWidth: 0.5)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.xs)
                    .fill(LinearGradient.irAIAccent)
                Text("✦")
                    .font(IRFont.footnote.weight(.heavy))
                    .foregroundStyle(Color.irTextOnAccent)
            }
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)

            Text(String(localized: "statistics.coach.eyebrow", defaultValue: "Read of the month", comment: "Coach insight eyebrow").uppercased())
                .font(IRFont.eyebrow.weight(.bold))
                .tracking(IRTracking.eyebrow)
                .foregroundStyle(Color.irPrimaryAccent)

            Spacer()

            if let analyzedAt = vm.analyzedAt, vm.body != nil {
                Text(analyzedAt, style: .relative)
                    .font(IRFont.microLabel.weight(.semibold))
                    .foregroundStyle(Color.irTextSecondary.opacity(0.7))
            }
        }
    }

    // MARK: - State-driven content

    @ViewBuilder
    private var content: some View {
        if !hasAIAccess {
            teaser
        } else if vm.needsConsent {
            consentPrompt
        } else if vm.isLoading {
            loadingRow
        } else if let error = vm.error {
            errorRow(message: error)
        } else if let body = vm.body, !body.isEmpty {
            bodyRow(body: body)
        } else {
            generatePrompt
        }
    }

    // MARK: - States

    private var teaser: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            ZStack {
                Text(String(
                    localized: "statistics.coach.teaser.placeholder",
                    defaultValue: "Volume down −21% vs last month, but quality preserved: average pace improved by 5\"/km. You ran less, but better.",
                    comment: "Blurred teaser placeholder text for the locked monthly coach insight"
                ))
                .font(IRFont.footnote.weight(.semibold))
                .foregroundStyle(Color.irTextPrimary)
                .blur(radius: 6)

                VStack(spacing: Spacing.xs) {
                    Image(systemName: "lock.fill")
                        .font(IRFont.body.weight(.semibold))
                        .foregroundStyle(Color.irTextSecondary)
                    Text(String(localized: "statistics.coach.teaser.unlock", defaultValue: "Unlock the read of the month", comment: "Locked monthly coach insight CTA caption"))
                        .font(IRFont.eyebrow.weight(.semibold))
                        .foregroundStyle(Color.irTextSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)

            Button(action: onUnlockTap) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "sparkles")
                        .font(IRFont.caption.weight(.bold))
                    Text(String(localized: "statistics.coach.teaser.cta", defaultValue: "Unlock with AI", comment: "Subscribe CTA on locked monthly coach insight"))
                        .font(IRFont.footnote.weight(.bold))
                }
                .foregroundStyle(Color.irTextOnAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(Color.irPrimaryAccent)
                .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
            }
            .buttonStyle(.plain)
        }
        .onAppear { onTeaserShown() }
    }

    private var consentPrompt: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(String(localized: "statistics.coach.needsConsent", defaultValue: "AI consent is required to generate your monthly read.", comment: "Coach insight: consent required message"))
                .font(IRFont.footnote)
                .foregroundStyle(Color.irTextSecondary)

            Button(action: onConsentTap) {
                Label(String(localized: "Review & Accept", comment: "Consent review button"), systemImage: "checkmark.shield")
                    .font(IRFont.footnote.weight(.semibold))
                    .foregroundStyle(Color.irPrimaryAccent)
            }
            .buttonStyle(.plain)
        }
    }

    private var loadingRow: some View {
        HStack(spacing: Spacing.sm) {
            ProgressView().controlSize(.small)
            Text(String(localized: "statistics.coach.loading", defaultValue: "Reading your month…", comment: "Coach insight loading text"))
                .font(IRFont.footnote)
                .foregroundStyle(Color.irTextSecondary)
            Spacer()
        }
    }

    private func errorRow(message: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(message)
                .font(IRFont.caption)
                .foregroundStyle(Color.irWarning)
            Button(action: onGenerateTap) {
                Label(String(localized: "Retry", comment: "Retry button"), systemImage: "arrow.clockwise")
                    .font(IRFont.caption.weight(.semibold))
                    .foregroundStyle(Color.irPrimaryAccent)
            }
            .buttonStyle(.plain)
        }
    }

    private func bodyRow(body: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(body)
                .font(IRFont.footnote.weight(.semibold))
                .foregroundStyle(Color.irTextPrimary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button(action: onRegenerateTap) {
                    Image(systemName: "arrow.clockwise")
                        .font(IRFont.eyebrow.weight(.semibold))
                        .foregroundStyle(Color.irTextSecondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var generatePrompt: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(String(localized: "statistics.coach.generate.caption", defaultValue: "Get a one-line read of how this month compared to last month.", comment: "Coach insight: pre-generation caption"))
                .font(IRFont.footnote)
                .foregroundStyle(Color.irTextSecondary)

            Button(action: onGenerateTap) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "sparkles")
                        .font(IRFont.caption.weight(.bold))
                    Text(String(localized: "statistics.coach.generate.cta", defaultValue: "Generate with AI", comment: "Coach insight generate CTA"))
                        .font(IRFont.footnote.weight(.bold))
                }
                .foregroundStyle(Color.irTextOnAccent)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(Color.irPrimaryAccent)
                .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    StatisticsView(injectedViewModel: StatisticsViewModel.createWithTestData())
        .environmentObject(RevenueCatManager.shared)
}
