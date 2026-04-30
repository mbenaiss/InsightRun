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
                VStack(alignment: .leading, spacing: 22) {
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
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .accessibilityIdentifier("statistics-content")
            .background(Color.irBackgroundApp)
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(String(localized: "statistics.eyebrow", defaultValue: "Trends", comment: "Statistics screen eyebrow").uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(Color.irTextSecondary.opacity(0.55))

                Spacer()
            }

            Text(String(localized: "statistics.title", comment: "Statistics screen title"))
                .font(.system(size: 34, weight: .heavy))
                .kerning(-1)
                .foregroundStyle(Color.irTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(viewModel.headerSubtitle)
                .font(.system(size: 13))
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
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isActive ? Color.black : Color.irTextSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 9)
                                .fill(isActive ? Color.white : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.irCardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.irBorder, lineWidth: 0.5)
                )
        )
    }

    // MARK: - Period Chips (full-bleed scroll)

    private var periodChipsScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
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
            .padding(.horizontal, 18)
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
                    .font(.subheadline)
                    .foregroundStyle(Color.irTextSecondary)
                Spacer()
                Text("\(viewModel.selectedYear)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.irTextPrimary)
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(Color.irTextSecondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(Color.irCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.irBorder, lineWidth: 0.5)
            )
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Overview

    @ViewBuilder
    private var overviewContent: some View {
        // Section 01 — Personal records (horizontal scroll)
        VStack(alignment: .leading, spacing: 10) {
            pulseRingEyebrow(num: "01", title: String(localized: "statistics.records.title"))
            personalRecordsCarousel
        }

        // Section 02 — KPI hero (2x2 with sparkline + delta vs previous month + prev value)
        VStack(alignment: .leading, spacing: 10) {
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
        VStack(alignment: .leading, spacing: 10) {
            pulseRingEyebrow(num: "03", title: String(localized: "statistics.section.distanceOverPeriod", defaultValue: "Distance over period", comment: "Stats section: distance over period"))
            distanceChartCard
        }

        // Section 04 — Pace distribution
        VStack(alignment: .leading, spacing: 10) {
            pulseRingEyebrow(num: "04", title: String(localized: "statistics.section.paceDistribution", defaultValue: "Pace distribution", comment: "Stats section: pace distribution"))
            paceDistributionCard
        }

        // Section 05 — Distance distribution
        VStack(alignment: .leading, spacing: 10) {
            pulseRingEyebrow(num: "05", title: String(localized: "statistics.section.distanceDistribution", defaultValue: "Distance distribution", comment: "Stats section: distance distribution"))
            distanceDistributionCard
        }
    }

    // MARK: - Numbered eyebrow

    private func pulseRingEyebrow(num: String, title: String) -> some View {
        HStack(spacing: 8) {
            Text(num)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.irTextSecondary)
            Rectangle()
                .fill(Color.irBorder)
                .frame(width: 18, height: 0.5)
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Color.irTextSecondary.opacity(0.7))
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Personal records carousel (Section 01)

    private var personalRecordsCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(personalRecords, id: \.id) { record in
                    PRCard(record: record)
                }
            }
            .padding(.horizontal, 18)
        }
        .padding(.horizontal, -18)
    }

    private var personalRecords: [PersonalRecord] {
        var list: [PersonalRecord] = []

        if let r = viewModel.longestRun, let d = r.distance {
            list.append(PersonalRecord(
                label: String(localized: "statistics.records.longestDistance"),
                value: viewModel.formatDistance(d).replacingOccurrences(of: " km", with: ""),
                unit: "km",
                date: r.startDate,
                color: Color(hex: "BF5AF2"),
                icon: "trophy",
                mono: false,
                recent: isRecent(r.startDate)
            ))
        }
        if let r = viewModel.fastestRun, let pace = r.averagePace {
            list.append(PersonalRecord(
                label: String(localized: "statistics.records.fastestPace"),
                value: viewModel.formatPace(pace).replacingOccurrences(of: " /km", with: ""),
                unit: "/km",
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
                color: Color(hex: "5AC8FA"),
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
                color: Color(hex: "BF5AF2"),
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
                    value: viewModel.formatDistance(mc.thisMonthDistance).replacingOccurrences(of: " km", with: ""),
                    unit: "km",
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
                    value: mc.thisMonthAvgPace.map { viewModel.formatPace($0).replacingOccurrences(of: " /km", with: "") } ?? "—",
                    unit: "/km",
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
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
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
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(label.uppercased())
                        .font(.system(size: 10, weight: .bold))
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
                        .font(.system(size: 22, weight: .heavy, design: mono ? .monospaced : .rounded))
                        .kerning(-0.4)
                        .foregroundStyle(valueColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let unit {
                        Text(unit)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.irTextSecondary.opacity(0.7))
                    }
                }

                HStack(alignment: .center, spacing: 4) {
                    Text("\(String(localized: "statistics.kpi.vsPrev", defaultValue: "vs", comment: "KPI hero subtitle: 'vs <prev value>'")) \(prevLabel)")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.irTextSecondary.opacity(0.55))
                        .lineLimit(1)
                    Spacer()
                    Sparkline(values: sparkline, color: sparklineColor)
                        .frame(width: 60, height: 18)
                }
            }
            .padding(14)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(viewModel.formatDistance(viewModel.totalDistance).replacingOccurrences(of: " km", with: ""))
                            .font(.system(size: 32, weight: .heavy, design: .rounded))
                            .kerning(-0.6)
                            .foregroundStyle(Color.irPrimaryAccent)
                        Text(String(localized: "statistics.charts.totalKm", defaultValue: "km total", comment: "Distance chart caption: total km"))
                            .font(.system(size: 13))
                            .foregroundStyle(Color.irTextSecondary.opacity(0.55))
                    }
                    if let peak = peakBucketLabel {
                        Text(peak)
                            .font(.system(size: 11))
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
        .padding(18)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }

    private var peakBucketLabel: String? {
        let sorted = viewModel.periodDistanceData.sorted { $0.distance > $1.distance }
        guard let top = sorted.first, top.distance > 0 else { return nil }
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = viewModel.chartGranularity == .week ? "d MMM" : "LLL yyyy"
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
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isActive ? Color.irTextPrimary : Color.irTextSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isActive ? Color.white.opacity(0.08) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.irCardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.irBorder, lineWidth: 0.5)
                )
        )
    }

    private var distanceChartContent: some View {
        let sortedData = viewModel.periodDistanceData.sorted { $0.date < $1.date }
        let selectedData = selectedPeriodDate.flatMap { selectedDate in
            sortedData.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
        }

        return VStack(alignment: .leading, spacing: 6) {
            if let selected = selectedData {
                HStack(alignment: .firstTextBaseline) {
                    Text(viewModel.formatDistance(selected.distance))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.irPrimaryAccent)
                    Spacer()
                    Text(formatChartDate(selected.date))
                        .font(.caption)
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
                                .font(.system(size: 9, design: .monospaced))
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
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(Color.irTextSecondary.opacity(0.7))
                        }
                    }
                }
            }
            .chartXSelection(value: $selectedPeriodDate)
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
        formatter.dateFormat = viewModel.chartGranularity == .week ? "d MMM" : "LLL"
        formatter.locale = Locale.current
        return formatter.string(from: date)
    }

    // MARK: - Pace distribution (Section 04)

    private var paceDistributionCard: some View {
        VStack(spacing: 14) {
            ForEach(viewModel.paceDistributionData) { dist in
                PaceZoneRow(distribution: dist)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
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
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
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
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 56))
                .foregroundStyle(Color.irTextSecondary.opacity(0.5))

            Text(String(localized: "statistics.empty.title"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.irTextPrimary)

            Text(String(localized: "statistics.empty.message"))
                .font(.system(size: 13))
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
        f.dateFormat = "d MMM yyyy"
        return f.string(from: record.date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(record.color.opacity(0.22))
                    iconGlyph
                        .foregroundStyle(record.color)
                }
                .frame(width: 28, height: 28)

                Spacer()

                if record.recent {
                    Text(String(localized: "statistics.records.new", defaultValue: "★ NEW", comment: "Badge for recent personal record").uppercased())
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(record.color)
                        .clipShape(Capsule())
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(record.label.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color.irTextSecondary)
                    .lineLimit(1)

                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(record.value)
                        .font(.system(size: 22, weight: .heavy, design: record.mono ? .monospaced : .rounded))
                        .kerning(-0.4)
                        .foregroundStyle(Color.irTextPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let unit = record.unit {
                        Text(unit)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.irTextSecondary.opacity(0.7))
                    }
                }

                Text(dateLabel)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.irTextSecondary.opacity(0.55))
            }
        }
        .padding(14)
        .frame(width: 180, alignment: .leading)
        .background(
            LinearGradient(
                colors: [record.color.opacity(0.14), Color.irCardBackground],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(record.color.opacity(0.25), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var iconGlyph: some View {
        switch record.icon {
        case "trophy":
            Image(systemName: "trophy.fill").font(.system(size: 14, weight: .semibold))
        case "bolt":
            Image(systemName: "bolt.fill").font(.system(size: 14, weight: .semibold))
        case "clock":
            Image(systemName: "clock.fill").font(.system(size: 14, weight: .semibold))
        default:
            Text(record.icon)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
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
                .font(.system(size: 9, weight: .heavy))
            Text("\(Int(abs(percent).rounded()))%")
                .font(.system(size: 9, weight: .heavy))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(color.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Sparkline

struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if values.count >= 2 {
                    let normalized = normalize(values)
                    Path { path in
                        for (i, v) in normalized.enumerated() {
                            let x = CGFloat(i) * (geo.size.width / CGFloat(normalized.count - 1))
                            let y = geo.size.height * (1 - CGFloat(v))
                            if i == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(color, lineWidth: 1.4)

                    // Terminal dot
                    if let last = normalized.last {
                        let x = geo.size.width
                        let y = geo.size.height * (1 - CGFloat(last))
                        Circle()
                            .fill(color)
                            .frame(width: 4, height: 4)
                            .position(x: x, y: y)
                    }
                }
            }
        }
    }

    private func normalize(_ vs: [Double]) -> [Double] {
        guard let minV = vs.min(), let maxV = vs.max(), maxV > minV else {
            return vs.map { _ in 0.5 }
        }
        return vs.map { ($0 - minV) / (maxV - minV) }
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
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isSelected ? Color.black : Color.irTextSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
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
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(distribution.range)
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .foregroundStyle(isEmpty ? Color.irTextSecondary.opacity(0.5) : Color.irTextPrimary)
                    Text(String(localized: "/km", comment: "Pace unit suffix"))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.irTextSecondary.opacity(0.55))
                    if !distribution.zoneLabel.isEmpty {
                        Text("· \(distribution.zoneLabel)")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.irTextSecondary.opacity(0.55))
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(Int(distribution.percentage.rounded()))%")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(isEmpty ? Color.irTextSecondary.opacity(0.5) : distribution.color)
                    Text(String(format: String(localized: "statistics.distribution.workoutsCount", defaultValue: "%lld workouts", comment: "Number of workouts"), distribution.count))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.irTextSecondary.opacity(0.55))
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.05))
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
    private var fillColor: Color { distribution.isMarathon ? Color(hex: "BF5AF2") : .irPrimaryAccent }

    var body: some View {
        HStack(spacing: 10) {
            Text(distribution.category)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(isEmpty ? Color.irTextSecondary.opacity(0.5) : Color.irTextPrimary)
                .frame(width: 76, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.04))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(fillColor)
                        .frame(width: max(0, geo.size.width * (distribution.percentage / 100.0)), height: 8)
                }
            }
            .frame(height: 8)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(distribution.count > 0 ? String(format: "%.1f", distribution.totalKm) : "—")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundStyle(isEmpty ? Color.irTextSecondary.opacity(0.5) : Color.irTextPrimary)
                Text("km")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.irTextSecondary.opacity(0.55))
            }
            .frame(width: 56, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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
        VStack(alignment: .leading, spacing: 12) {
            header
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.irAIAccent.opacity(0.08), Color.irCardBackground],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.irAIAccent.opacity(0.30), lineWidth: 0.5)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [Color.irAIAccent, Color.irAIAccentSecondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text("✦")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Color.black)
            }
            .frame(width: 28, height: 28)

            Text(String(localized: "statistics.coach.eyebrow", defaultValue: "Read of the month", comment: "Coach insight eyebrow").uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Color.irAIAccent)

            Spacer()

            if let analyzedAt = vm.analyzedAt, vm.body != nil {
                Text(analyzedAt, style: .relative)
                    .font(.system(size: 10, weight: .semibold))
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
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                Text(String(
                    localized: "statistics.coach.teaser.placeholder",
                    defaultValue: "Volume down −21% vs last month, but quality preserved: average pace improved by 5\"/km. You ran less, but better.",
                    comment: "Blurred teaser placeholder text for the locked monthly coach insight"
                ))
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Color.irTextPrimary)
                .blur(radius: 6)

                VStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.irTextSecondary)
                    Text(String(localized: "statistics.coach.teaser.unlock", defaultValue: "Unlock the read of the month", comment: "Locked monthly coach insight CTA caption"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.irTextSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)

            Button(action: onUnlockTap) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .bold))
                    Text(String(localized: "statistics.coach.teaser.cta", defaultValue: "Unlock with AI", comment: "Subscribe CTA on locked monthly coach insight"))
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.irAIAccent)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .onAppear { onTeaserShown() }
    }

    private var consentPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "statistics.coach.needsConsent", defaultValue: "AI consent is required to generate your monthly read.", comment: "Coach insight: consent required message"))
                .font(.system(size: 13))
                .foregroundStyle(Color.irTextSecondary)

            Button(action: onConsentTap) {
                Label(String(localized: "Review & Accept", comment: "Consent review button"), systemImage: "checkmark.shield")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.irAIAccent)
            }
            .buttonStyle(.plain)
        }
    }

    private var loadingRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(String(localized: "statistics.coach.loading", defaultValue: "Reading your month…", comment: "Coach insight loading text"))
                .font(.system(size: 13))
                .foregroundStyle(Color.irTextSecondary)
            Spacer()
        }
    }

    private func errorRow(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Color.irWarning)
            Button(action: onGenerateTap) {
                Label(String(localized: "Retry", comment: "Retry button"), systemImage: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.irAIAccent)
            }
            .buttonStyle(.plain)
        }
    }

    private func bodyRow(body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(body)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Color.irTextPrimary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button(action: onRegenerateTap) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.irTextSecondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var generatePrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "statistics.coach.generate.caption", defaultValue: "Get a one-line read of how this month compared to last month.", comment: "Coach insight: pre-generation caption"))
                .font(.system(size: 13))
                .foregroundStyle(Color.irTextSecondary)

            Button(action: onGenerateTap) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .bold))
                    Text(String(localized: "statistics.coach.generate.cta", defaultValue: "Generate with AI", comment: "Coach insight generate CTA"))
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(Color.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.irAIAccent)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    StatisticsView(injectedViewModel: StatisticsViewModel.createWithTestData())
        .environmentObject(RevenueCatManager.shared)
}
