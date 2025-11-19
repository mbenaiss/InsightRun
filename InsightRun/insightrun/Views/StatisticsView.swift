//
//  StatisticsView.swift
//  InsightRun
//
//  Statistics and performance metrics view
//

import SwiftUI
import Charts

struct StatisticsView: View {
    @StateObject private var viewModel = StatisticsViewModel()
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedPeriodDate: Date?
    @State private var selectedPaceDistributionId: UUID?
    @State private var selectedDistanceDistributionId: UUID?

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

                    // Period selector
                    periodSelector

                    if viewModel.isLoading {
                        ProgressView()
                            .padding(.top, 50)
                    } else if viewModel.workouts.isEmpty {
                        emptyState
                    } else {
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
                .padding()
            }
            .navigationTitle(String(localized: "statistics.title"))
            .refreshable {
                await viewModel.refresh()
            }
        }
        .task {
            await viewModel.loadWorkouts()
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
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("\(viewModel.selectedYear)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.irTextPrimary)

                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        }
    }

    // MARK: - Personal Records Section

    private var personalRecordsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(.yellow)
                Text(String(localized: "statistics.records.title"))
                    .font(.headline)
                    .fontWeight(.bold)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

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
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        }
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

                // Granularity picker - only show for "This month" filter with only Week option
                if viewModel.selectedPeriod == .thisMonth {
                    Picker("", selection: $viewModel.chartGranularity) {
                        Text(StatisticsViewModel.ChartGranularity.week.localizedTitle).tag(StatisticsViewModel.ChartGranularity.week)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }
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
                    .foregroundStyle(.secondary)
                    .frame(height: 100)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.irCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
            }
        }
    }

    private var distanceChartContent: some View {
        let selectedData = selectedPeriodDate.flatMap { selectedDate in
            viewModel.periodDistanceData.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
        }

        return ZStack(alignment: .top) {
            distanceChart(selectedData: selectedData)

            if let selected = selectedData {
                distanceChartTooltip(selected: selected)
                    .padding(.top, 16)
            }
        }
    }

    private func distanceChart(selectedData: StatisticsViewModel.PeriodData?) -> some View {
        Chart {
            ForEach(viewModel.periodDistanceData) { data in
                BarMark(
                    x: .value(String(localized: "statistics.charts.period", defaultValue: "Period", comment: "Chart period label"), data.date, unit: viewModel.chartGranularity == .week ? .weekOfYear : .month),
                    y: .value(String(localized: "statistics.charts.distance", defaultValue: "Distance", comment: "Chart distance label"), data.distance / 1000.0)
                )
                .foregroundStyle(selectedData?.id == data.id ? Color.irPrimaryAccent : Color.irPrimaryAccent.opacity(0.5))
                .opacity(selectedData == nil || selectedData?.id == data.id ? 1.0 : 0.5)
            }
        }
        .frame(height: 250)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let distance = value.as(Double.self) {
                        Text("\(Int(distance)) km")
                    }
                }
            }
        }
        .chartXSelection(value: $selectedPeriodDate)
        .padding()
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }

    private func distanceChartTooltip(selected: StatisticsViewModel.PeriodData) -> some View {
        return VStack(spacing: 6) {
            Text(String(localized: "statistics.charts.distance", defaultValue: "Distance", comment: "Chart distance label").uppercased())
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .tracking(0.5)

            Text(viewModel.formatDistance(selected.distance))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Color.irPrimaryAccent)

            if selected.workoutCount > 0 {
                Text("\(selected.workoutCount) " + (selected.workoutCount == 1 ? String(localized: "statistics.charts.workout", defaultValue: "workout", comment: "Singular workout") : String(localized: "statistics.charts.workouts", defaultValue: "workouts", comment: "Plural workouts")))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 180)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Pace Distribution Section

    private var paceDistributionSection: some View {
        VStack(spacing: 16) {
            Text(String(localized: "statistics.distribution.pace.title"))
                .font(.headline)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !viewModel.paceDistributionData.isEmpty {
                paceChartContent
            }
        }
    }

    private var paceChartContent: some View {
        let selectedData = selectedPaceDistributionId.flatMap { selectedId in
            viewModel.paceDistributionData.first { $0.id == selectedId }
        }

        return VStack(spacing: 12) {
            paceChart(selectedData: selectedData)

            if let selected = selectedData {
                paceChartDetails(selected: selected)
            }

            // Details list
            VStack(spacing: 8) {
                ForEach(viewModel.paceDistributionData) { dist in
                    Button(action: {
                        selectedPaceDistributionId = dist.id
                    }) {
                        HStack {
                            Circle()
                                .fill(dist.color)
                                .frame(width: 10, height: 10)

                            Text("\(dist.range) /km")
                                .font(.subheadline)

                            Spacer()

                            Text(String(format: String(localized: "statistics.distribution.workoutsCount", defaultValue: "%d workouts", comment: "Number of workouts in a distribution category"), dist.count))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Text("(\(Int(dist.percentage))%)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal)
                        .foregroundStyle(Color.irTextPrimary)
                        .contentShape(Rectangle())
                    }
                }
            }
            .padding(.vertical)
            .background(Color.irCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        }
    }

    private func paceChart(selectedData: StatisticsViewModel.PaceDistribution?) -> some View {
        Chart {
            ForEach(viewModel.paceDistributionData) { dist in
                BarMark(
                    x: .value(String(localized: "statistics.charts.zone", defaultValue: "Zone", comment: "Chart zone label"), dist.range),
                    y: .value(String(localized: "statistics.charts.percentage", defaultValue: "Percentage", comment: "Chart percentage label"), dist.percentage)
                )
                .foregroundStyle(selectedData?.id == dist.id ? dist.color : dist.color.opacity(0.5))
                .opacity(selectedData == nil || selectedData?.id == dist.id ? 1.0 : 0.5)
                .annotation(position: .top) {
                    Text("\(Int(dist.percentage))%")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
            }
        }
        .frame(height: 200)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let pct = value.as(Double.self) {
                        Text("\(Int(pct))%")
                    }
                }
            }
        }
        .chartBackground { chartProxy in
            VStack {
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            let frame = geometry.frame(in: .local)
                            let xPosition = location.x / frame.width

                            let sortedData = viewModel.paceDistributionData.sorted { $0.range < $1.range }
                            if !sortedData.isEmpty {
                                let index = Int(xPosition * Double(sortedData.count))
                                let clampedIndex = max(0, min(index, sortedData.count - 1))
                                selectedPaceDistributionId = sortedData[clampedIndex].id
                            }
                        }
                }
            }
        }
        .padding()
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }

    private func paceChartDetails(selected: StatisticsViewModel.PaceDistribution) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(selected.range)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Button(action: { selectedPaceDistributionId = nil }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(String(localized: "statistics.charts.percentage", defaultValue: "Percentage", comment: "Chart percentage label"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(selected.percentage))%")
                        .fontWeight(.semibold)
                }

                HStack {
                    Text(String(localized: "statistics.charts.workouts"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: String(localized: "statistics.distribution.workoutsCount", defaultValue: "%d workouts", comment: "Number of workouts in a distribution category"), selected.count))
                        .fontWeight(.semibold)
                }
            }
        }
        .padding()
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Distance Distribution Section

    private var distanceDistributionSection: some View {
        VStack(spacing: 16) {
            Text(String(localized: "statistics.distribution.distance.title"))
                .font(.headline)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !viewModel.distanceDistributionData.isEmpty {
                distanceDistributionContent
            }
        }
    }

    private var distanceDistributionContent: some View {
        let selectedData = selectedDistanceDistributionId.flatMap { selectedId in
            viewModel.distanceDistributionData.first { $0.id == selectedId }
        }

        return VStack(spacing: 12) {
            distanceDistributionChart(selectedData: selectedData)

            if let selected = selectedData {
                distanceDistributionDetails(selected: selected)
            }

            // Details list
            VStack(spacing: 8) {
                ForEach(viewModel.distanceDistributionData) { dist in
                    Button(action: {
                        selectedDistanceDistributionId = dist.id
                    }) {
                        HStack {
                            Text(dist.category)
                                .font(.subheadline)

                            Spacer()

                            Text(String(format: String(localized: "statistics.distribution.workoutsCount", defaultValue: "%d workouts", comment: "Number of workouts in a distribution category"), dist.count))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Text("(\(Int(dist.percentage))%)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal)
                        .foregroundStyle(Color.irTextPrimary)
                        .contentShape(Rectangle())
                    }
                }
            }
            .padding(.vertical)
            .background(Color.irCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        }
    }

    private func distanceDistributionChart(selectedData: StatisticsViewModel.DistanceDistribution?) -> some View {
        Chart {
            ForEach(viewModel.distanceDistributionData) { dist in
                SectorMark(
                    angle: .value(String(localized: "statistics.charts.percentage", defaultValue: "Percentage", comment: "Chart percentage label"), dist.percentage),
                    innerRadius: .ratio(0.5),
                    angularInset: 2
                )
                .foregroundStyle(by: .value(String(localized: "statistics.charts.category", defaultValue: "Category", comment: "Chart category label"), dist.category))
                .opacity(selectedData == nil || selectedData?.id == dist.id ? 1.0 : 0.3)
                .annotation(position: .overlay) {
                    Text("\(Int(dist.percentage))%")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.irTextPrimary)
                }
            }
        }
        .frame(height: 250)
        .contentShape(Circle())
        .onTapGesture { location in
            // For pie charts, tapping toggles selection
            if selectedData != nil {
                selectedDistanceDistributionId = nil
            } else if !viewModel.distanceDistributionData.isEmpty {
                selectedDistanceDistributionId = viewModel.distanceDistributionData[0].id
            }
        }
        .padding()
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }

    private func distanceDistributionDetails(selected: StatisticsViewModel.DistanceDistribution) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(selected.category)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Button(action: { selectedDistanceDistributionId = nil }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(String(localized: "statistics.charts.percentage", defaultValue: "Percentage", comment: "Chart percentage label"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(selected.percentage))%")
                        .fontWeight(.semibold)
                }

                HStack {
                    Text(String(localized: "statistics.charts.workouts"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: String(localized: "statistics.distribution.workoutsCount", defaultValue: "%d workouts", comment: "Number of workouts in a distribution category"), selected.count))
                        .fontWeight(.semibold)
                }
            }
        }
        .padding()
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }


    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text(String(localized: "statistics.empty.title"))
                .font(.title2)
                .fontWeight(.semibold)

            Text(String(localized: "statistics.empty.message"))
                .font(.body)
                .foregroundStyle(.secondary)
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
        return "\(sign)\(absMinutes):\(String(format: "%02d", absSeconds)) /km"
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
                    .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 100)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
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
                .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                trendIcon
            }

            // Current month and last month values
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(String(localized: "statistics.comparison.thisMonth", defaultValue: "This month", comment: "This month label"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(thisMonthValue)
                        .font(.caption)
                        .fontWeight(.semibold)
                }

                HStack {
                    Text(String(localized: "statistics.comparison.lastMonth", defaultValue: "Last month", comment: "Last month label"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
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

#Preview {
    StatisticsView(injectedViewModel: StatisticsViewModel.createWithTestData())
}
