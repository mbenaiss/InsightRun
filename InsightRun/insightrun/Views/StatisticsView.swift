//
//  StatisticsView.swift
//  InsightRun
//
//  Statistics and performance metrics view
//

import SwiftUI
import Charts

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
    @StateObject private var viewModel = StatisticsViewModel()
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedTab: StatisticsTab = .overview
    @State private var selectedPeriodDate: Date?
    @State private var isRecordsExpanded: Bool = false

    // Optional injected viewModel for testing - replaces the default one
    init(injectedViewModel: StatisticsViewModel? = nil) {
        if let injected = injectedViewModel {
            _viewModel = StateObject(wrappedValue: injected)
        } else {
            _viewModel = StateObject(wrappedValue: StatisticsViewModel())
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Section 1: Personal records (always at top)
                    personalRecordsSection

                    // Tab picker
                    Picker("", selection: $selectedTab) {
                        ForEach(StatisticsTab.allCases, id: \.self) { tab in
                            Text(tab.localizedTitle).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)

                    // Period selector
                    periodSelector

                    if viewModel.isLoading {
                        ProgressView()
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
                .padding()
            }
            .accessibilityIdentifier("statistics-content")
            .navigationTitle(String(localized: "statistics.title"))
            .refreshable {
                await viewModel.refresh()
            }
        }
        .task {
            await viewModel.loadWorkouts()
            AnalyticsService.shared.trackStatisticsViewed()
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

    // MARK: - Overview Content

    private var overviewContent: some View {
        Group {
            // Section 2: Overview metrics
            overviewMetricsSection

            // Section 3: Performance averages
            performanceAveragesSection

            // Section 4: Monthly comparison
            monthlyComparisonSection

            // Section 5: Distance over time chart
            distanceChartSection

            // Section 6: Pace distribution
            paceDistributionSection

            // Section 7: Distance distribution
            distanceDistributionSection
        }
    }

    // MARK: - Period Selector

    private var periodSelector: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(StatisticsViewModel.TimePeriod.allCases, id: \.self) { period in
                        PeriodButton(
                            title: period.localizedTitle,
                            isSelected: viewModel.selectedPeriod == period
                        ) {
                            AnalyticsService.shared.trackStatisticsPeriodChanged(period: String(describing: period))

                            withAnimation {
                                viewModel.selectedPeriod = period
                                // Set default year if switching to year filter
                                if period == .specificYear {
                                    viewModel.selectedYear = viewModel.availableYears.first ?? Calendar.current.component(.year, from: Date())
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
            }

            // Year selector dropdown
            if viewModel.selectedPeriod == .specificYear {
                Menu {
                    ForEach(viewModel.availableYears, id: \.self) { year in
                        Button(action: {
                            withAnimation {
                                viewModel.selectedYear = year
                            }
                            AnalyticsService.shared.trackStatisticsYearChanged(year: year)
                        }) {
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
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.irTextPrimary)

                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundStyle(Color.irTextSecondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.irCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Overview Metrics Section

    private var overviewMetricsSection: some View {
        VStack(spacing: 16) {
            Text(String(localized: "statistics.overview.title"))
                .font(.headline)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                StatMetricCard(
                    icon: "figure.run",
                    iconColor: .blue,
                    title: String(localized: "statistics.overview.totalWorkouts"),
                    value: "\(viewModel.totalWorkouts)",
                    subtitle: nil,
                    trend: nil
                )

                StatMetricCard(
                    icon: "ruler",
                    iconColor: .green,
                    title: String(localized: "statistics.overview.totalDistance"),
                    value: viewModel.formatDistance(viewModel.totalDistance),
                    subtitle: nil,
                    trend: nil
                )

                StatMetricCard(
                    icon: "clock",
                    iconColor: .orange,
                    title: String(localized: "statistics.overview.totalDuration"),
                    value: viewModel.formatDuration(viewModel.totalDuration),
                    subtitle: nil,
                    trend: nil
                )

                if let avgPace = viewModel.averagePace {
                    StatMetricCard(
                        icon: "speedometer",
                        iconColor: .cyan,
                        title: String(localized: "statistics.overview.averagePace"),
                        value: viewModel.formatPace(avgPace),
                        subtitle: nil,
                        trend: nil
                    )
                }
            }
        }
    }

    // MARK: - Performance Averages Section

    private var performanceAveragesSection: some View {
        VStack(spacing: 16) {
            Text(String(localized: "statistics.performance.title"))
                .font(.headline)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 12) {
                PerformanceRow(
                    icon: "ruler.fill",
                    title: String(localized: "statistics.performance.averageDistance"),
                    value: viewModel.formatDistance(viewModel.averageDistance)
                )

                Divider()

                PerformanceRow(
                    icon: "clock.fill",
                    title: String(localized: "statistics.performance.averageDuration"),
                    value: viewModel.formatDuration(viewModel.averageDuration)
                )

                Divider()

                PerformanceRow(
                    icon: "calendar",
                    title: String(localized: "statistics.performance.weeklyFrequency"),
                    value: String(format: String(localized: "statistics.performance.workoutsPerWeekValue", defaultValue: "%@ workouts/week", comment: "Number of workouts per week"), viewModel.formatFrequency(viewModel.weeklyFrequency))
                )
            }
            .padding()
            .background(Color.irCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: Color.irShadow, radius: 8, y: 4)
        }
    }

    // MARK: - Personal Records Section

    private var personalRecordsSection: some View {
        VStack(spacing: 16) {
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isRecordsExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "trophy.fill")
                        .foregroundStyle(.yellow)
                    Text(String(localized: "statistics.records.title"))
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.irTextPrimary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.irTextSecondary)
                        .rotationEffect(.degrees(isRecordsExpanded ? 90 : 0))
                }
            }

            if isRecordsExpanded {
                VStack(spacing: 12) {
                    if let longestRun = viewModel.longestRun {
                        RecordRow(
                            icon: "figure.run",
                            title: String(localized: "statistics.records.longestDistance"),
                            value: viewModel.formatDistance(longestRun.distance ?? 0),
                            date: longestRun.startDate
                        )
                        Divider()
                    }

                    if let fastestRun = viewModel.fastestRun {
                        RecordRow(
                            icon: "bolt.fill",
                            title: String(localized: "statistics.records.fastestPace"),
                            value: viewModel.formatPace(fastestRun.averagePace ?? 0),
                            date: fastestRun.startDate
                        )
                        Divider()
                    }

                    if let longestDuration = viewModel.longestDuration {
                        RecordRow(
                            icon: "clock.fill",
                            title: String(localized: "statistics.records.longestDuration"),
                            value: viewModel.formatDuration(longestDuration.duration),
                            date: longestDuration.startDate
                        )
                    }

                    // Distance records
                    Group {
                        if let best5K = viewModel.best5K {
                            Divider()
                            RecordRow(
                                icon: "5.circle.fill",
                                title: String(localized: "statistics.records.best5k"),
                                value: viewModel.formatDuration(best5K.duration),
                                date: best5K.startDate
                            )
                        }

                        if let best10K = viewModel.best10K {
                            Divider()
                            RecordRow(
                                icon: "10.circle.fill",
                                title: String(localized: "statistics.records.best10k"),
                                value: viewModel.formatDuration(best10K.duration),
                                date: best10K.startDate
                            )
                        }

                        if let bestHalf = viewModel.bestHalfMarathon {
                            Divider()
                            RecordRow(
                                icon: "figure.run.circle.fill",
                                title: String(localized: "statistics.records.bestHalf"),
                                value: viewModel.formatDuration(bestHalf.duration),
                                date: bestHalf.startDate
                            )
                        }

                        if let bestMarathon = viewModel.bestMarathon {
                            Divider()
                            RecordRow(
                                icon: "medal.fill",
                                title: String(localized: "statistics.records.bestMarathon"),
                                value: viewModel.formatDuration(bestMarathon.duration),
                                date: bestMarathon.startDate
                            )
                        }
                    }
                }
                .padding()
                .background(Color.irCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: Color.irShadow, radius: 8, y: 4)
            }
        }
        .clipped()
    }

    // MARK: - Monthly Comparison Section

    private var monthlyComparisonSection: some View {
        VStack(spacing: 16) {
            Text(String(localized: "statistics.comparison.title"))
                .font(.headline)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                ComparisonCard(
                    icon: "figure.run",
                    title: String(localized: "statistics.comparison.workouts"),
                    change: viewModel.formatPercentageChange(Double(viewModel.monthlyChange.workoutsChange)),
                    trend: viewModel.monthlyChange.workoutsChange > 0 ? .up : (viewModel.monthlyChange.workoutsChange < 0 ? .down : .neutral),
                    thisMonthValue: "\(viewModel.monthlyChange.thisMonthWorkouts)",
                    lastMonthValue: "\(viewModel.monthlyChange.lastMonthWorkouts)"
                )

                ComparisonCard(
                    icon: "ruler.fill",
                    title: String(localized: "statistics.comparison.distance"),
                    change: viewModel.formatPercentageChange(viewModel.monthlyChange.distancePercentage),
                    trend: viewModel.monthlyChange.distanceChange > 0 ? .up : (viewModel.monthlyChange.distanceChange < 0 ? .down : .neutral),
                    thisMonthValue: viewModel.formatDistance(viewModel.monthlyChange.thisMonthDistance),
                    lastMonthValue: viewModel.formatDistance(viewModel.monthlyChange.lastMonthDistance)
                )

                ComparisonCard(
                    icon: "clock.fill",
                    title: String(localized: "statistics.comparison.duration"),
                    change: viewModel.formatDuration(abs(viewModel.monthlyChange.durationChange)),
                    trend: viewModel.monthlyChange.durationChange > 0 ? .up : (viewModel.monthlyChange.durationChange < 0 ? .down : .neutral),
                    thisMonthValue: viewModel.formatDuration(viewModel.monthlyChange.thisMonthDuration),
                    lastMonthValue: viewModel.formatDuration(viewModel.monthlyChange.lastMonthDuration)
                )

                if let paceChange = viewModel.monthlyChange.paceChange {
                    let thisMonthPaceValue = viewModel.monthlyChange.thisMonthAvgPace.map { viewModel.formatPace($0) } ?? "—"
                    let lastMonthPaceValue = viewModel.monthlyChange.lastMonthAvgPace.map { viewModel.formatPace($0) } ?? "—"

                    ComparisonCard(
                        icon: "speedometer",
                        title: String(localized: "statistics.comparison.pace"),
                        change: formatPaceChange(paceChange),
                        trend: paceChange < 0 ? .up : (paceChange > 0 ? .down : .neutral),
                        thisMonthValue: thisMonthPaceValue,
                        lastMonthValue: lastMonthPaceValue
                    )
                }
            }
        }
    }

    // MARK: - Distance Chart Section

    private var distanceChartSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text(String(localized: "statistics.charts.distance.title"))
                    .font(.headline)
                    .fontWeight(.bold)

                Spacer()

                Text(viewModel.selectedPeriod == .thisMonth
                    ? StatisticsViewModel.ChartGranularity.week.localizedTitle
                    : StatisticsViewModel.ChartGranularity.month.localizedTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.2))
                    .clipShape(Capsule())
            }
            .onChange(of: viewModel.selectedPeriod) { oldValue, newValue in
                // Force appropriate granularity based on filter
                if newValue == .thisMonth {
                    // For "This month", use week granularity
                    viewModel.chartGranularity = .week
                } else if newValue != .thisMonth && viewModel.chartGranularity != .month {
                    // For other filters, use month granularity
                    viewModel.chartGranularity = .month
                }
            }

            if !viewModel.periodDistanceData.isEmpty {
                distanceChartContent
            } else {
                Text(String(localized: "statistics.charts.noData"))
                    .foregroundStyle(Color.irTextSecondary)
                    .frame(height: 100)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.irCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: Color.irShadow, radius: 8, y: 4)
            }
        }
    }

    private var distanceChartContent: some View {
        let sortedData = viewModel.periodDistanceData.sorted { $0.date < $1.date }
        let selectedData = selectedPeriodDate.flatMap { selectedDate in
            sortedData.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
        }

        return VStack(alignment: .leading, spacing: 8) {
            // Value display
            if let selected = selectedData {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(viewModel.formatDistance(selected.distance))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.irPrimaryAccent)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formatChartDate(selected.date))
                            .font(.caption)
                            .foregroundStyle(Color.irTextSecondary)
                        if selected.workoutCount > 0 {
                            Text("\(selected.workoutCount) " + (selected.workoutCount == 1 ? String(localized: "statistics.charts.workout", defaultValue: "workout", comment: "Singular workout") : String(localized: "statistics.charts.workouts", defaultValue: "workouts", comment: "Plural workouts")))
                                .font(.caption2)
                                .foregroundStyle(Color.irTextSecondary)
                        }
                    }
                }
            } else {
                let totalDistance = sortedData.map(\.distance).reduce(0, +)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(viewModel.formatDistance(totalDistance))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.irPrimaryAccent)

                    Text(String(localized: "statistics.charts.total", defaultValue: "total", comment: "Total label"))
                        .font(.subheadline)
                        .foregroundStyle(Color.irTextSecondary)
                }
            }

            // Line chart
            Chart {
                ForEach(sortedData) { data in
                    AreaMark(
                        x: .value("Date", data.date),
                        y: .value("Distance", data.distance / 1000.0)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.irPrimaryAccent.opacity(0.3), Color.irPrimaryAccent.opacity(0.05)],
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
            .frame(height: 200)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(formatChartAxisDate(date))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                        .foregroundStyle(Color.irTextSecondary.opacity(0.2))
                    AxisValueLabel {
                        if let distance = value.as(Double.self) {
                            Text("\(Int(distance)) \(String(localized: "km", comment: "Kilometer abbreviation"))")
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartXSelection(value: $selectedPeriodDate)
        }
        .padding()
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.irShadow, radius: 8, y: 4)
    }

    private func formatChartDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale.current
        return formatter.string(from: date)
    }

    private func formatChartAxisDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        formatter.locale = Locale.current
        return formatter.string(from: date)
    }

    // MARK: - Pace Distribution Section

    private var paceDistributionSection: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "speedometer")
                    .foregroundStyle(Color.irPrimaryAccent)
                Text(String(localized: "statistics.distribution.pace.title"))
                    .font(.headline)
                    .fontWeight(.bold)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !viewModel.paceDistributionData.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.paceDistributionData.enumerated()), id: \.element.id) { index, dist in
                        DistributionRow(
                            label: "\(dist.range) \(String(localized: "/km", comment: "Pace unit suffix"))",
                            count: dist.count,
                            percentage: dist.percentage,
                            maxPercentage: viewModel.paceDistributionData.map(\.percentage).max() ?? 100,
                            color: paceZoneColor(for: index, total: viewModel.paceDistributionData.count)
                        )

                        if index < viewModel.paceDistributionData.count - 1 {
                            Divider()
                                .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical, 12)
                .background(Color.irCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: Color.irShadow, radius: 8, y: 4)
            }
        }
    }

    private func paceZoneColor(for index: Int, total: Int) -> Color {
        let colors: [Color] = [.irSuccess, Color.irPrimaryAccent, .irWarning, .irError]
        return colors[min(index, colors.count - 1)]
    }

    // MARK: - Distance Distribution Section

    private var distanceDistributionSection: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "ruler")
                    .foregroundStyle(Color.irPrimaryAccent)
                Text(String(localized: "statistics.distribution.distance.title"))
                    .font(.headline)
                    .fontWeight(.bold)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !viewModel.distanceDistributionData.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.distanceDistributionData.enumerated()), id: \.element.id) { index, dist in
                        DistributionRow(
                            label: dist.category,
                            count: dist.count,
                            percentage: dist.percentage,
                            maxPercentage: viewModel.distanceDistributionData.map(\.percentage).max() ?? 100,
                            color: distanceZoneColor(for: index, total: viewModel.distanceDistributionData.count)
                        )

                        if index < viewModel.distanceDistributionData.count - 1 {
                            Divider()
                                .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical, 12)
                .background(Color.irCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: Color.irShadow, radius: 8, y: 4)
            }
        }
    }

    private func distanceZoneColor(for index: Int, total: Int) -> Color {
        let colors: [Color] = [Color.irPrimaryAccent, .irSuccess, .irWarning, .irError]
        return colors[min(index, colors.count - 1)]
    }


    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 60))
                .foregroundStyle(Color.irTextSecondary)

            Text(String(localized: "statistics.empty.title"))
                .font(.title2)
                .fontWeight(.semibold)

            Text(String(localized: "statistics.empty.message"))
                .font(.body)
                .foregroundStyle(Color.irTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.top, 50)
    }

    // MARK: - Helper Methods

    private func formatPaceChange(_ change: Double) -> String {
        let absMinutes = Int(abs(change))
        let absSeconds = Int((abs(change) - Double(absMinutes)) * 60)
        let sign = change < 0 ? "-" : "+"
        return "\(sign)\(absMinutes):\(String(format: "%02d", absSeconds)) \(String(localized: "/km", comment: "Pace unit suffix"))"
    }
}

// MARK: - Supporting Views

struct PeriodButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(isSelected ? Color.irPrimaryAccent : Color.irSurface)
                )
                .foregroundStyle(isSelected ? Color.irTextPrimary : Color.irTextPrimary)
        }
    }
}

struct StatMetricCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    let subtitle: String?
    let trend: Trend?

    enum Trend {
        case up, down
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top row: Icon + Title with trend arrow on the right
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(iconColor.gradient)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(Color.irTextSecondary)
                    .lineLimit(1)

                Spacer()

                if let trend = trend {
                    Image(systemName: trend == .up ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption)
                        .foregroundStyle(trend == .up ? .green : .red)
                }
            }

            Spacer()

            // Center: Value centered horizontally and vertically
            VStack(spacing: 4) {
                Text(value)
                    .font(.title)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity, alignment: .center)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.irTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 100)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.irShadow, radius: 8, y: 4)
    }
}

struct PerformanceRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(Color.irPrimaryAccent)
                .frame(width: 24)

            Text(title)
                .font(.subheadline)

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.irTextSecondary)
        }
    }
}

struct RecordRow: View {
    let icon: String
    let title: String
    let value: String
    let date: Date

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(.yellow.gradient)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(formatDate(date))
                    .font(.caption)
                    .foregroundStyle(Color.irTextSecondary)
            }

            Spacer()

            Text(value)
                .font(.headline)
                .fontWeight(.bold)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale.current
        return formatter.string(from: date)
    }
}

struct ComparisonCard: View {
    let icon: String
    let title: String
    let change: String
    let trend: Trend
    let thisMonthValue: String
    let lastMonthValue: String

    enum Trend {
        case up, down, neutral
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top row: Icon + Title with trend arrow on the right
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(Color.irPrimaryAccent.gradient)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(Color.irTextSecondary)
                    .lineLimit(1)

                Spacer()

                trendIcon
            }

            // Current month and last month values
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(String(localized: "statistics.comparison.thisMonth", defaultValue: "This month", comment: "This month label"))
                        .font(.caption)
                        .foregroundStyle(Color.irTextSecondary)
                    Spacer()
                    Text(thisMonthValue)
                        .font(.caption)
                        .fontWeight(.semibold)
                }

                HStack {
                    Text(String(localized: "statistics.comparison.lastMonth", defaultValue: "Last month", comment: "Last month label"))
                        .font(.caption)
                        .foregroundStyle(Color.irTextSecondary)
                    Spacer()
                    Text(lastMonthValue)
                        .font(.caption)
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)

            Spacer()

            // Change value
            HStack(spacing: 8) {
                Text(change)
                    .font(.title3)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 140)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.irShadow, radius: 8, y: 4)
    }

    @ViewBuilder
    private var trendIcon: some View {
        switch trend {
        case .up:
            Image(systemName: "arrow.up.right")
                .font(.caption)
                .foregroundStyle(.green)
        case .down:
            Image(systemName: "arrow.down.right")
                .font(.caption)
                .foregroundStyle(.red)
        case .neutral:
            Image(systemName: "minus")
                .font(.caption)
                .foregroundStyle(.gray)
        }
    }
}

struct DistributionRow: View {
    let label: String
    let count: Int
    let percentage: Double
    let maxPercentage: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.irTextPrimary)

                Spacer()

                Text("\(Int(percentage))%")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(color)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.15))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.gradient)
                        .frame(width: max(4, geometry.size.width * (percentage / max(maxPercentage, 1))), height: 8)
                }
            }
            .frame(height: 8)

            Text(String(format: String(localized: "statistics.distribution.workoutsCount", defaultValue: "%d workouts", comment: "Number of workouts in a distribution category"), count))
                .font(.caption)
                .foregroundStyle(Color.irTextSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

#Preview {
    StatisticsView(injectedViewModel: StatisticsViewModel.createWithTestData())
}
