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

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Period selector
                    periodSelector

                    if viewModel.isLoading {
                        ProgressView()
                            .padding(.top, 50)
                    } else if viewModel.workouts.isEmpty {
                        emptyState
                    } else {
                        // Section 1: Overview metrics
                        overviewMetricsSection

                        // Section 2: Performance averages
                        performanceAveragesSection

                        // Section 3: Personal records
                        personalRecordsSection

                        // Section 4: Monthly comparison
                        monthlyComparisonSection

                        // Section 5: Distance over time chart
                        distanceChartSection

                        // Section 6: Activity heat map
                        activityHeatMapSection

                        // Section 7: Pace distribution
                        paceDistributionSection

                        // Section 8: Distance distribution
                        distanceDistributionSection

                        // Section 9: Yearly comparison
                        if viewModel.yearlyComparisonData.lastYearWorkouts > 0 {
                            yearlyComparisonSection
                        }
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(StatisticsViewModel.TimePeriod.allCases, id: \.self) { period in
                    PeriodButton(
                        title: period.rawValue,
                        isSelected: viewModel.selectedPeriod == period
                    ) {
                        withAnimation {
                            viewModel.selectedPeriod = period
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Overview Metrics Section

    private var overviewMetricsSection: some View {
        VStack(spacing: 16) {
            Text(String(localized: "statistics.overview.title"))
                .font(.title2)
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
                    subtitle: viewModel.monthlyChange.workoutsChange != 0 ?
                        "\(viewModel.formatPercentageChange(Double(viewModel.monthlyChange.workoutsChange))) ce mois" : nil,
                    trend: viewModel.monthlyChange.workoutsChange > 0 ? .up : (viewModel.monthlyChange.workoutsChange < 0 ? .down : nil)
                )

                StatMetricCard(
                    icon: "ruler",
                    iconColor: .green,
                    title: String(localized: "statistics.overview.totalDistance"),
                    value: viewModel.formatDistance(viewModel.totalDistance),
                    subtitle: viewModel.monthlyChange.distancePercentage != 0 ?
                        "\(viewModel.formatPercentageChange(viewModel.monthlyChange.distancePercentage)) ce mois" : nil,
                    trend: viewModel.monthlyChange.distanceChange > 0 ? .up : (viewModel.monthlyChange.distanceChange < 0 ? .down : nil)
                )

                StatMetricCard(
                    icon: "clock",
                    iconColor: .orange,
                    title: String(localized: "statistics.overview.totalDuration"),
                    value: viewModel.formatDuration(viewModel.totalDuration),
                    subtitle: nil,
                    trend: nil
                )

                StatMetricCard(
                    icon: "flame.fill",
                    iconColor: .red,
                    title: String(localized: "statistics.overview.currentStreak"),
                    value: "\(viewModel.currentStreak) jours",
                    subtitle: String(localized: "statistics.overview.recordStreak", defaultValue: "Record: \(viewModel.longestStreak) jours"),
                    trend: nil
                )

                StatMetricCard(
                    icon: "chart.bar.fill",
                    iconColor: .purple,
                    title: String(localized: "statistics.overview.consistency"),
                    value: viewModel.formatConsistencyRate(viewModel.consistencyRate),
                    subtitle: nil,
                    trend: nil
                )

                if let avgPace = viewModel.averagePace {
                    StatMetricCard(
                        icon: "speedometer",
                        iconColor: .cyan,
                        title: String(localized: "statistics.overview.averagePace"),
                        value: viewModel.formatPace(avgPace),
                        subtitle: viewModel.monthlyChange.paceChange != nil ?
                            formatPaceChange(viewModel.monthlyChange.paceChange!) : nil,
                        trend: (viewModel.monthlyChange.paceChange ?? 0) < 0 ? .up : ((viewModel.monthlyChange.paceChange ?? 0) > 0 ? .down : nil)
                    )
                }
            }
        }
    }

    // MARK: - Performance Averages Section

    private var performanceAveragesSection: some View {
        VStack(spacing: 16) {
            Text(String(localized: "statistics.performance.title"))
                .font(.title2)
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
                    value: String(localized: "statistics.performance.workoutsPerWeek",
                                defaultValue: "\(viewModel.formatFrequency(viewModel.weeklyFrequency)) entraînements/semaine")
                )
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
    }

    // MARK: - Personal Records Section

    private var personalRecordsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(.yellow)
                Text(String(localized: "statistics.records.title"))
                    .font(.title2)
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
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
    }

    // MARK: - Monthly Comparison Section

    private var monthlyComparisonSection: some View {
        VStack(spacing: 16) {
            Text(String(localized: "statistics.comparison.title"))
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                ComparisonCard(
                    icon: "ruler.fill",
                    title: String(localized: "statistics.comparison.distance"),
                    change: viewModel.formatPercentageChange(viewModel.monthlyChange.distancePercentage),
                    trend: viewModel.monthlyChange.distanceChange > 0 ? .up : (viewModel.monthlyChange.distanceChange < 0 ? .down : .neutral)
                )

                ComparisonCard(
                    icon: "figure.run",
                    title: String(localized: "statistics.comparison.workouts"),
                    change: viewModel.formatPercentageChange(Double(viewModel.monthlyChange.workoutsChange)),
                    trend: viewModel.monthlyChange.workoutsChange > 0 ? .up : (viewModel.monthlyChange.workoutsChange < 0 ? .down : .neutral)
                )

                if let paceChange = viewModel.monthlyChange.paceChange {
                    ComparisonCard(
                        icon: "speedometer",
                        title: String(localized: "statistics.comparison.pace"),
                        change: formatPaceChange(paceChange),
                        trend: paceChange < 0 ? .up : (paceChange > 0 ? .down : .neutral)
                    )
                }

                ComparisonCard(
                    icon: "clock.fill",
                    title: String(localized: "statistics.comparison.duration"),
                    change: viewModel.formatDuration(abs(viewModel.monthlyChange.durationChange)),
                    trend: viewModel.monthlyChange.durationChange > 0 ? .up : (viewModel.monthlyChange.durationChange < 0 ? .down : .neutral)
                )
            }
        }
    }

    // MARK: - Distance Chart Section

    private var distanceChartSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text(String(localized: "statistics.charts.distance.title"))
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                // Granularity picker
                Picker("", selection: $viewModel.chartGranularity) {
                    ForEach(StatisticsViewModel.ChartGranularity.allCases, id: \.self) { granularity in
                        Text(granularity.rawValue).tag(granularity)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }

            if !viewModel.periodDistanceData.isEmpty {
                Chart {
                    ForEach(viewModel.periodDistanceData) { data in
                        BarMark(
                            x: .value("Période", data.date, unit: viewModel.chartGranularity == .week ? .weekOfYear : .month),
                            y: .value("Distance", data.distance / 1000.0)
                        )
                        .foregroundStyle(Color.blue.gradient)
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
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
            } else {
                Text(String(localized: "statistics.charts.noData"))
                    .foregroundStyle(.secondary)
                    .frame(height: 100)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
            }
        }
    }

    // MARK: - Activity Heat Map Section

    private var activityHeatMapSection: some View {
        VStack(spacing: 16) {
            Text(String(localized: "statistics.heatmap.title"))
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                // Week day labels
                HStack(spacing: 4) {
                    ForEach(["L", "M", "M", "J", "V", "S", "D"], id: \.self) { day in
                        Text(day)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }

                // Heat map grid
                let calendar = Calendar.current
                let weeks = getHeatMapWeeks()

                ForEach(0..<weeks.count, id: \.self) { weekIndex in
                    HStack(spacing: 4) {
                        ForEach(0..<7) { dayIndex in
                            let index = weekIndex * 7 + dayIndex
                            if index < viewModel.activityHeatMapData.count {
                                let day = viewModel.activityHeatMapData[index]
                                Rectangle()
                                    .fill(day.intensity.color)
                                    .frame(height: 20)
                                    .cornerRadius(4)
                            } else {
                                Color.clear
                                    .frame(height: 20)
                            }
                        }
                    }
                }

                // Legend
                HStack(spacing: 12) {
                    Text("Moins")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 3) {
                        ForEach([StatisticsViewModel.ActivityIntensity.none, .light, .moderate, .high, .veryHigh], id: \.rawValue) { intensity in
                            Rectangle()
                                .fill(intensity.color)
                                .frame(width: 12, height: 12)
                                .cornerRadius(2)
                        }
                    }

                    Text("Plus")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
    }

    // MARK: - Pace Distribution Section

    private var paceDistributionSection: some View {
        VStack(spacing: 16) {
            Text(String(localized: "statistics.distribution.pace.title"))
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !viewModel.paceDistributionData.isEmpty {
                Chart {
                    ForEach(viewModel.paceDistributionData) { dist in
                        BarMark(
                            x: .value("Zone", dist.range),
                            y: .value("Pourcentage", dist.percentage)
                        )
                        .foregroundStyle(dist.color.gradient)
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
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )

                // Details list
                VStack(spacing: 8) {
                    ForEach(viewModel.paceDistributionData) { dist in
                        HStack {
                            Circle()
                                .fill(dist.color)
                                .frame(width: 12, height: 12)

                            Text("\(dist.range) /km")
                                .font(.body)

                            Spacer()

                            Text("\(dist.count) entraînements")
                                .font(.body)
                                .foregroundStyle(.secondary)

                            Text("(\(Int(dist.percentage))%)")
                                .font(.body)
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
            }
        }
    }

    // MARK: - Distance Distribution Section

    private var distanceDistributionSection: some View {
        VStack(spacing: 16) {
            Text(String(localized: "statistics.distribution.distance.title"))
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !viewModel.distanceDistributionData.isEmpty {
                Chart {
                    ForEach(viewModel.distanceDistributionData) { dist in
                        SectorMark(
                            angle: .value("Pourcentage", dist.percentage),
                            innerRadius: .ratio(0.5),
                            angularInset: 2
                        )
                        .foregroundStyle(by: .value("Catégorie", dist.category))
                        .annotation(position: .overlay) {
                            Text("\(Int(dist.percentage))%")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                    }
                }
                .frame(height: 250)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )

                // Details list
                VStack(spacing: 8) {
                    ForEach(viewModel.distanceDistributionData) { dist in
                        HStack {
                            Text(dist.category)
                                .font(.body)

                            Spacer()

                            Text("\(dist.count) entraînements")
                                .font(.body)
                                .foregroundStyle(.secondary)

                            Text("(\(Int(dist.percentage))%)")
                                .font(.body)
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
            }
        }
    }

    // MARK: - Yearly Comparison Section

    private var yearlyComparisonSection: some View {
        VStack(spacing: 16) {
            Text(String(localized: "statistics.yearly.title"))
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)

            let yearData = viewModel.yearlyComparisonData

            VStack(spacing: 12) {
                YearlyComparisonRow(
                    title: String(localized: "statistics.yearly.distance"),
                    thisYear: viewModel.formatDistance(yearData.thisYearDistance),
                    lastYear: viewModel.formatDistance(yearData.lastYearDistance),
                    change: yearData.distanceChange
                )

                Divider()

                YearlyComparisonRow(
                    title: String(localized: "statistics.yearly.workouts"),
                    thisYear: "\(yearData.thisYearWorkouts)",
                    lastYear: "\(yearData.lastYearWorkouts)",
                    change: yearData.workoutsChange
                )

                if let thisPace = yearData.thisYearAvgPace, let lastPace = yearData.lastYearAvgPace {
                    Divider()

                    HStack {
                        Text(String(localized: "statistics.yearly.pace"))
                            .font(.body)

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text("2025: \(viewModel.formatPace(thisPace))")
                                .font(.body)
                                .fontWeight(.semibold)

                            Text("2024: \(viewModel.formatPace(lastPace))")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }

                        if let paceChange = yearData.paceChange {
                            Image(systemName: paceChange < 0 ? "arrow.up.right" : "arrow.down.right")
                                .foregroundStyle(paceChange < 0 ? .green : .red)
                                .padding(.leading, 8)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
    }

    // MARK: - Helper Methods

    private func getHeatMapWeeks() -> [[StatisticsViewModel.ActivityDay]] {
        let data = viewModel.activityHeatMapData
        var weeks: [[StatisticsViewModel.ActivityDay]] = []

        for i in stride(from: 0, to: data.count, by: 7) {
            let endIndex = min(i + 7, data.count)
            weeks.append(Array(data[i..<endIndex]))
        }

        return weeks
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
                        .fill(isSelected ? Color.blue : Color(uiColor: .secondarySystemGroupedBackground))
                )
                .foregroundStyle(isSelected ? .white : .primary)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(iconColor.gradient)
                Spacer()
                if let trend = trend {
                    Image(systemName: trend == .up ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption)
                        .foregroundStyle(trend == .up ? .green : .red)
                }
            }

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title3)
                .fontWeight(.bold)

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

struct PerformanceRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 24)

            Text(title)
                .font(.body)

            Spacer()

            Text(value)
                .font(.body)
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
                .font(.title2)
                .foregroundStyle(.yellow.gradient)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)

                Text(formatDate(date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(value)
                .font(.title3)
                .fontWeight(.bold)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale(identifier: "fr_FR")
        return formatter.string(from: date)
    }
}

struct ComparisonCard: View {
    let icon: String
    let title: String
    let change: String
    let trend: Trend

    enum Trend {
        case up, down, neutral
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.blue)
                Spacer()
                trendIcon
            }

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(change)
                .font(.headline)
                .fontWeight(.bold)

            Text("vs mois dernier")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    @ViewBuilder
    private var trendIcon: some View {
        switch trend {
        case .up:
            Image(systemName: "arrow.up.right")
                .foregroundStyle(.green)
        case .down:
            Image(systemName: "arrow.down.right")
                .foregroundStyle(.red)
        case .neutral:
            Image(systemName: "minus")
                .foregroundStyle(.gray)
        }
    }
}

struct YearlyComparisonRow: View {
    let title: String
    let thisYear: String
    let lastYear: String
    let change: Double

    var body: some View {
        HStack {
            Text(title)
                .font(.body)

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("2025: \(thisYear)")
                    .font(.body)
                    .fontWeight(.semibold)

                Text("2024: \(lastYear)")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Image(systemName: change > 0 ? "arrow.up.right" : (change < 0 ? "arrow.down.right" : "minus"))
                .foregroundStyle(change > 0 ? .green : (change < 0 ? .red : .gray))
                .padding(.leading, 8)

            Text(String(format: "%+.0f%%", change))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(change > 0 ? .green : (change < 0 ? .red : .gray))
        }
        .padding(.horizontal)
    }
}

#Preview {
    StatisticsView()
}
