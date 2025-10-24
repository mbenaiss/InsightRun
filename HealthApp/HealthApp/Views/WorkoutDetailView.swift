//
//  WorkoutDetailView.swift
//  HealthApp
//
//  Detail screen showing all workout metrics
//  Featuring iOS 26 Liquid Glass design with comprehensive data display
//

import SwiftUI
import MapKit
import HealthKit
import SwiftData
import Charts

struct WorkoutDetailView: View {
    let workout: WorkoutModel
    @StateObject private var viewModel: WorkoutDetailViewModel
    @State private var showingAIAssistant = false
    @Environment(\.modelContext) private var modelContext
    @StateObject private var analysisViewModel: WorkoutAnalysisViewModel

    init(workout: WorkoutModel) {
        self.workout = workout
        _viewModel = StateObject(wrappedValue: WorkoutDetailViewModel(workout: workout))

        // Initialize analysisViewModel with a temporary modelContext
        // Will be replaced in onAppear with actual modelContext
        let container = try! ModelContainer(for: WorkoutAnalysis.self)
        _analysisViewModel = StateObject(wrappedValue: WorkoutAnalysisViewModel(
            workout: workout,
            metrics: nil,
            modelContext: container.mainContext
        ))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if viewModel.isLoading {
                    loadingSection
                } else if let error = viewModel.errorMessage {
                    errorSection(error)
                } else if let metrics = viewModel.metrics {
                    // Header with date and location
                    headerSection(metrics: metrics)

                    // Main metrics grid (2x2)
                    mainMetricsGrid(metrics: metrics)

                    // AI Analysis Section
                    aiAnalysisSection

                    // Route map after AI analysis
                    if let routePoints = metrics.routePoints, !routePoints.isEmpty {
                        routeMapSection(routePoints: routePoints)
                    }

                    // Interactive Charts (HR, Pace, Power)
                    if let splits = metrics.splits, !splits.isEmpty {
                        SwipeableChartsView(splits: splits, averagePower: metrics.runningPower)
                    }

                    // Performance section (no accordion)
                    if hasPerformanceMetrics(metrics) {
                        MetricsCard(
                            title: "Performance",
                            icon: "bolt.fill",
                            iconColor: .yellow
                        ) {
                            performanceContent(metrics: metrics)
                        }
                    }

                    // Advanced metrics section (no accordion)
                    if hasAdvancedMetrics(metrics) {
                        MetricsCard(
                            title: "Métriques Avancées",
                            icon: "waveform.path.ecg",
                            iconColor: .indigo
                        ) {
                            advancedMetricsContent(metrics: metrics)
                        }
                    }

                    // Splits section (with accordion)
                    if let splits = metrics.splits, !splits.isEmpty {
                        AccordionSection(
                            title: "Splits",
                            icon: "list.number",
                            iconColor: .blue,
                            isExpanded: false
                        ) {
                            splitsContent(splits: splits)
                        }
                    }

                    sourceSection
                }
            }
            .padding()
        }
        .navigationTitle("Détails")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadMetrics()
            // Update metrics in analysisViewModel after loading
            analysisViewModel.updateMetrics(viewModel.metrics)
            // Also load cached analysis automatically
            await analysisViewModel.loadAnalysis()
        }
    }

    // MARK: - Header Section

    private func headerSection(metrics: WorkoutMetrics) -> some View {
        HStack(alignment: .center) {
            // Date à gauche
            Text(workout.startDate, style: .date)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

            Spacer()

            // Location à droite
            if let routePoints = metrics.routePoints,
               let firstPoint = routePoints.first {
                LocationText(coordinate: firstPoint.coordinate)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: - Route Map Section

    private func routeMapSection(routePoints: [RoutePoint]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "map.fill")
                    .foregroundStyle(.green.gradient)
                    .font(.headline)

                Text("Parcours")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(routePoints.count) points GPS")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            RouteMapView(routePoints: routePoints)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }

    // MARK: - Main Metrics Grid

    private func mainMetricsGrid(metrics: WorkoutMetrics) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            CompactMetricCard(
                icon: "ruler",
                label: "Distance",
                value: workout.distanceFormatted,
                color: .blue
            )

            CompactMetricCard(
                icon: "clock",
                label: "Durée",
                value: workout.durationFormatted,
                color: .indigo
            )

            if let pace = metrics.averagePace {
                CompactMetricCard(
                    icon: "speedometer",
                    label: "Allure moy.",
                    value: viewModel.formatPace(pace),
                    color: .green
                )
            }

            if let calories = workout.totalEnergyBurned {
                CompactMetricCard(
                    icon: "flame.fill",
                    label: "Calories",
                    value: String(format: "%.0f", calories),
                    color: .orange
                )
            }
        }
    }

    // MARK: - Helper Functions

    private func hasPerformanceMetrics(_ metrics: WorkoutMetrics) -> Bool {
        metrics.minPace != nil || metrics.maxSpeed != nil ||
        metrics.averageCadence != nil || metrics.strideLength != nil ||
        metrics.runningPower != nil || metrics.vo2Max != nil
    }

    private func hasAdvancedMetrics(_ metrics: WorkoutMetrics) -> Bool {
        metrics.groundContactTime != nil || metrics.verticalOscillation != nil ||
        metrics.groundContactTimeBalance != nil || metrics.runningEfficiency != nil ||
        metrics.walkingSteadiness != nil || metrics.walkingAsymmetry != nil ||
        metrics.doubleSupportPercentage != nil || metrics.walkingSpeed != nil ||
        metrics.stairAscentSpeed != nil || metrics.stairDescentSpeed != nil
    }

    // MARK: - Loading

    private var loadingSection: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Chargement des données...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    // MARK: - Error

    private func errorSection(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)

            Text(error)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Content Functions for Accordion Sections

    private func performanceContent(metrics: WorkoutMetrics) -> some View {
        VStack(spacing: 16) {
            if let minPace = metrics.minPace {
                MetricRow(
                    icon: "hare.fill",
                    label: "Meilleure allure",
                    value: viewModel.formatPace(minPace),
                    color: .green
                )
            }

            if let maxSpeed = metrics.maxSpeed {
                MetricRow(
                    icon: "bolt.fill",
                    label: "Vitesse max",
                    value: viewModel.formatSpeed(maxSpeed),
                    color: .yellow
                )
            }

            if let cadence = metrics.averageCadence {
                MetricRow(
                    icon: "metronome.fill",
                    label: "Cadence moyenne",
                    value: viewModel.formatCadence(cadence),
                    color: .indigo
                )
            }

            if let strideLength = metrics.strideLength {
                MetricRow(
                    icon: "figure.walk",
                    label: "Longueur de foulée",
                    value: viewModel.formatStrideLength(strideLength),
                    color: .cyan
                )
            }

            if let power = metrics.runningPower {
                MetricRow(
                    icon: "bolt.circle.fill",
                    label: "Puissance",
                    value: viewModel.formatPower(power),
                    color: .orange
                )
            }

            if let vo2Max = metrics.vo2Max {
                MetricRow(
                    icon: "lungs.fill",
                    label: "VO2 Max",
                    value: String(format: "%.1f ml/kg/min", vo2Max),
                    color: .red
                )
            }
        }
    }

    private func splitsContent(splits: [Split]) -> some View {
        VStack(spacing: 12) {
            // Best/Worst splits summary
            if let best = splits.min(by: { $0.pace < $1.pace }),
               let worst = splits.max(by: { $0.pace < $1.pace }) {
                HStack(spacing: 20) {
                    VStack(spacing: 4) {
                        Text("Meilleur")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(best.paceFormatted)
                            .font(.headline)
                            .foregroundStyle(.green)
                        Text("km \(best.kilometer)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)

                    Divider()
                        .frame(height: 50)

                    VStack(spacing: 4) {
                        Text("Plus lent")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(worst.paceFormatted)
                            .font(.headline)
                            .foregroundStyle(.orange)
                        Text("km \(worst.kilometer)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.bottom, 8)

                Divider()
            }

            // All splits
            ForEach(splits) { split in
                SplitRow(split: split)
            }
        }
    }

    private func advancedMetricsContent(metrics: WorkoutMetrics) -> some View {
        VStack(spacing: 16) {
            // Running biomechanics
            if let gct = metrics.groundContactTime {
                MetricRow(
                    icon: "timer",
                    label: "Temps de contact au sol",
                    value: String(format: "%.0f ms", gct),
                    color: .indigo
                )
            }

            if let vo = metrics.verticalOscillation {
                MetricRow(
                    icon: "arrow.up.and.down",
                    label: "Oscillation verticale",
                    value: String(format: "%.1f cm", vo),
                    color: .cyan
                )
            }

            if let balance = metrics.groundContactTimeBalance {
                MetricRow(
                    icon: "scale.3d",
                    label: "Équilibre de contact",
                    value: viewModel.formatPercentage(balance),
                    color: .orange
                )
            }

            if let efficiency = metrics.runningEfficiency {
                MetricRow(
                    icon: "chart.line.uptrend.xyaxis",
                    label: "Efficacité de course",
                    value: viewModel.formatPercentage(efficiency),
                    color: .green
                )
            }

            // Walking and mobility metrics
            if let steadiness = metrics.walkingSteadiness {
                MetricRow(
                    icon: "figure.walk",
                    label: "Stabilité de marche",
                    value: viewModel.formatPercentage(steadiness),
                    color: .green
                )
            }

            if let asymmetry = metrics.walkingAsymmetry {
                MetricRow(
                    icon: "figure.walk.arrival",
                    label: "Asymétrie de marche",
                    value: viewModel.formatPercentage(asymmetry),
                    color: .orange
                )
            }

            if let doubleSupport = metrics.doubleSupportPercentage {
                MetricRow(
                    icon: "figure.2.arms.open",
                    label: "Double appui",
                    value: viewModel.formatPercentage(doubleSupport),
                    color: .blue
                )
            }

            if let speed = metrics.walkingSpeed {
                MetricRow(
                    icon: "figure.walk.circle",
                    label: "Vitesse de marche",
                    value: viewModel.formatSpeed(speed),
                    color: .cyan
                )
            }

            if let ascentSpeed = metrics.stairAscentSpeed {
                MetricRow(
                    icon: "figure.stairs",
                    label: "Vitesse montée d'escaliers",
                    value: viewModel.formatSpeed(ascentSpeed),
                    color: .purple
                )
            }

            if let descentSpeed = metrics.stairDescentSpeed {
                MetricRow(
                    icon: "figure.stairs",
                    label: "Vitesse descente d'escaliers",
                    value: viewModel.formatSpeed(descentSpeed),
                    color: .indigo
                )
            }
        }
    }

    // MARK: - AI Analysis Section

    private var aiAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple.gradient)
                    .font(.title3)

                Text("Analyse IA")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            if analysisViewModel.isLoading {
                // Loading state
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Analyse en cours...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)

            } else if let error = analysisViewModel.error {
                // Error state
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(.orange)

                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button {
                        Task {
                            await analysisViewModel.generateAnalysis()
                        }
                    } label: {
                        Label("Réessayer", systemImage: "arrow.clockwise")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

            } else if let analysis = analysisViewModel.analysisText {
                // Analysis available
                VStack(alignment: .leading, spacing: 12) {
                    MarkdownText(analysis)
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    HStack {
                        if let analyzedAt = analysisViewModel.analyzedAt {
                            Text(analyzedAt, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        Button {
                            Task {
                                await analysisViewModel.regenerateAnalysis()
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .tint(.purple)
                    }
                }

            } else {
                // No analysis yet - show button to generate
                VStack(spacing: 12) {
                    Text("Obtenez une analyse détaillée de votre performance")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button {
                        Task {
                            await analysisViewModel.loadAnalysis()
                        }
                    } label: {
                        Label("Analyser avec IA", systemImage: "sparkles")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }

    // MARK: - Source Section

    private var sourceSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)

                Text("Source: \(workout.sourceName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let version = workout.sourceVersion {
                    Text("v\(version)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

// MARK: - Supporting Components

struct MetricsCard<Content: View>: View {
    let title: String
    var icon: String? = nil
    var iconColor: Color = .blue
    let content: Content

    init(
        title: String,
        icon: String? = nil,
        iconColor: Color = .blue,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                if let icon = icon {
                    Image(systemName: icon)
                        .foregroundStyle(iconColor.gradient)
                }

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
    }
}

struct MetricRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color.gradient)
                .frame(width: 28)

            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.headline)
                .foregroundStyle(.primary)
        }
    }
}

struct SplitRow: View {
    let split: Split

    var body: some View {
        HStack(spacing: 12) {
            // Kilometer number
            Text("km \(split.kilometer)")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)

            // Pace
            Text(split.paceFormatted)
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer()

            // Time
            Text(split.timeFormatted)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Elevation indicators
            HStack(spacing: 4) {
                if let gain = split.elevationGain, gain > 0 {
                    Label(String(format: "↗ %.0fm", gain), systemImage: "")
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .labelStyle(.titleOnly)
                }

                if let loss = split.elevationLoss, loss > 0 {
                    Label(String(format: "↘ %.0fm", loss), systemImage: "")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                        .labelStyle(.titleOnly)
                }
            }
            .frame(width: 60, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Accordion Section Component

struct AccordionSection<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    @State var isExpanded: Bool
    let content: Content

    init(
        title: String,
        icon: String,
        iconColor: Color,
        isExpanded: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self._isExpanded = State(initialValue: isExpanded)
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header - always visible
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: icon)
                        .foregroundStyle(iconColor.gradient)
                        .font(.title3)

                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 16 : 20))
            }
            .buttonStyle(.plain)

            // Content - collapsible
            if isExpanded {
                content
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.top, 4)
            }
        }
    }
}

// MARK: - Compact Metric Card (for grid layout)

struct CompactMetricCard: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color.gradient)

            VStack(spacing: 4) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }
}

// MARK: - Swipeable Charts View

struct SwipeableChartsView: View {
    let splits: [Split]
    let averagePower: Double?
    @State private var selectedPage = 0

    var body: some View {
        VStack(spacing: 8) {
            TabView(selection: $selectedPage) {
                // Heart Rate Chart
                InteractiveHeartRateChart(splits: splits)
                    .tag(0)

                // Pace Chart
                InteractivePaceChart(splits: splits)
                    .tag(1)

                // Power Chart (if available)
                if averagePower != nil {
                    InteractivePowerChart(splits: splits, averagePower: averagePower!)
                        .tag(2)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 340)

            // Custom page indicator dots
            HStack(spacing: 8) {
                ForEach(0..<(averagePower != nil ? 3 : 2), id: \.self) { index in
                    Circle()
                        .fill(selectedPage == index ? Color.primary : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut, value: selectedPage)
                }
            }
        }
    }
}

// MARK: - Interactive Heart Rate Chart

struct InteractiveHeartRateChart: View {
    let splits: [Split]
    @State private var selectedKm: Int?

    var heartRateData: [(km: Int, value: Double)] {
        splits.compactMap { split in
            guard let hr = split.averageHeartRate else { return nil }
            return (km: split.kilometer, value: hr)
        }
    }

    var selectedData: (km: Int, value: Double)? {
        guard let km = selectedKm else { return nil }
        return heartRateData.first { $0.km == km }
    }

    var minHeartRate: Double? {
        heartRateData.min(by: { $0.value < $1.value })?.value
    }

    var maxHeartRate: Double? {
        heartRateData.max(by: { $0.value < $1.value })?.value
    }

    var displayData: (value: Double, label: String)? {
        if let selected = selectedData {
            return (value: selected.value, label: "km \(selected.km)")
        }
        return nil
    }

    var showMinMax: Bool {
        selectedData == nil && minHeartRate != nil && maxHeartRate != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fréquence Cardiaque")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if let data = displayData {
                        Text("\(Int(data.value)) bpm")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.red)
                        Text(data.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if showMinMax, let min = minHeartRate, let max = maxHeartRate {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(Int(min)) bpm")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.red)
                                Text("min")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(Int(max)) bpm")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.red)
                                Text("max")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("Aucune donnée disponible")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "heart.fill")
                    .font(.title2)
                    .foregroundStyle(.red.gradient)
            }

            if heartRateData.isEmpty {
                // No data available
                VStack(spacing: 12) {
                    Image(systemName: "heart.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Aucune donnée de fréquence cardiaque disponible")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(height: 240)
                .frame(maxWidth: .infinity)
            } else {
                Chart {
                    ForEach(heartRateData, id: \.km) { data in
                        LineMark(
                            x: .value("Km", data.km),
                            y: .value("BPM", data.value)
                        )
                        .foregroundStyle(.red.gradient)
                        .lineStyle(StrokeStyle(lineWidth: 3))
                        .interpolationMethod(.catmullRom)

                        AreaMark(
                            x: .value("Km", data.km),
                            y: .value("BPM", data.value)
                        )
                        .foregroundStyle(.red.gradient.opacity(0.2))
                        .interpolationMethod(.catmullRom)

                        if selectedKm == data.km {
                            PointMark(
                                x: .value("Km", data.km),
                                y: .value("BPM", data.value)
                            )
                            .foregroundStyle(.red)
                            .symbolSize(200)
                        }
                    }
                }
                .chartXSelection(value: $selectedKm)
                .chartYScale(domain: .automatic)
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let km = value.as(Int.self) {
                                Text("\(km)")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .frame(height: 240)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Interactive Pace Chart

struct InteractivePaceChart: View {
    let splits: [Split]
    @State private var selectedKm: Int?

    var paceData: [(km: Int, value: Double)] {
        splits.map { split in
            (km: split.kilometer, value: split.pace)
        }
    }

    var selectedData: (km: Int, value: Double)? {
        guard let km = selectedKm else { return nil }
        return paceData.first { $0.km == km }
    }

    var minPace: Double? {
        paceData.min(by: { $0.value < $1.value })?.value
    }

    var maxPace: Double? {
        paceData.max(by: { $0.value < $1.value })?.value
    }

    var displayData: (value: Double, label: String)? {
        if let selected = selectedData {
            return (value: selected.value, label: "km \(selected.km)")
        }
        return nil
    }

    var showMinMax: Bool {
        selectedData == nil && minPace != nil && maxPace != nil
    }

    func formatPace(_ pace: Double) -> String {
        let minutes = Int(pace)
        let seconds = Int((pace - Double(minutes)) * 60)
        return String(format: "%d'%02d\"", minutes, seconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Allure")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if let data = displayData {
                        Text(formatPace(data.value))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.green)
                        Text(data.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if showMinMax, let min = minPace, let max = maxPace {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(formatPace(min))
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.green)
                                Text("min")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(formatPace(max))
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.green)
                                Text("max")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Spacer()

                Image(systemName: "speedometer")
                    .font(.title2)
                    .foregroundStyle(.green.gradient)
            }

            Chart {
                ForEach(paceData, id: \.km) { data in
                    LineMark(
                        x: .value("Km", data.km),
                        y: .value("Pace", data.value)
                    )
                    .foregroundStyle(.green.gradient)
                    .lineStyle(StrokeStyle(lineWidth: 3))
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Km", data.km),
                        y: .value("Pace", data.value)
                    )
                    .foregroundStyle(.green.gradient.opacity(0.2))
                    .interpolationMethod(.catmullRom)

                    if selectedKm == data.km {
                        PointMark(
                            x: .value("Km", data.km),
                            y: .value("Pace", data.value)
                        )
                        .foregroundStyle(.green)
                        .symbolSize(200)
                    }
                }
            }
            .chartXSelection(value: $selectedKm)
            .chartYScale(domain: .automatic)
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let km = value.as(Int.self) {
                            Text("\(km)")
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .frame(height: 240)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Interactive Power Chart

struct InteractivePowerChart: View {
    let splits: [Split]
    let averagePower: Double
    @State private var selectedKm: Int?

    var powerData: [(km: Int, value: Double)] {
        // Use real power data from splits if available
        splits.compactMap { split in
            if let power = split.averagePower {
                return (km: split.kilometer, value: power)
            }
            // Fallback to average if no split data
            return (km: split.kilometer, value: averagePower)
        }
    }

    var hasRealPowerData: Bool {
        splits.contains { $0.averagePower != nil }
    }

    var selectedData: (km: Int, value: Double)? {
        guard let km = selectedKm else { return nil }
        return powerData.first { $0.km == km }
    }

    var minPower: Double? {
        powerData.min(by: { $0.value < $1.value })?.value
    }

    var maxPower: Double? {
        powerData.max(by: { $0.value < $1.value })?.value
    }

    var displayData: (value: Double, label: String)? {
        if let selected = selectedData {
            return (value: selected.value, label: "km \(selected.km)")
        }
        return nil
    }

    var showMinMax: Bool {
        selectedData == nil && minPower != nil && maxPower != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Puissance")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if let data = displayData {
                        Text("\(Int(data.value)) W")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.orange)
                        Text(data.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if showMinMax, let min = minPower, let max = maxPower {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(Int(min)) W")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.orange)
                                Text("min")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(Int(max)) W")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.orange)
                                Text("max")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Spacer()

                Image(systemName: "bolt.fill")
                    .font(.title2)
                    .foregroundStyle(.orange.gradient)
            }

            if powerData.isEmpty {
                // No data available
                VStack(spacing: 12) {
                    Image(systemName: "bolt.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Aucune donnée de puissance disponible")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(height: 240)
                .frame(maxWidth: .infinity)
            } else {
                Chart {
                    ForEach(powerData, id: \.km) { data in
                        LineMark(
                            x: .value("Km", data.km),
                            y: .value("Power", data.value)
                        )
                        .foregroundStyle(.orange.gradient)
                        .lineStyle(StrokeStyle(lineWidth: 3))
                        .interpolationMethod(hasRealPowerData ? .catmullRom : .linear)

                        AreaMark(
                            x: .value("Km", data.km),
                            y: .value("Power", data.value)
                        )
                        .foregroundStyle(.orange.gradient.opacity(0.2))
                        .interpolationMethod(hasRealPowerData ? .catmullRom : .linear)

                        if selectedKm == data.km {
                            PointMark(
                                x: .value("Km", data.km),
                                y: .value("Power", data.value)
                            )
                            .foregroundStyle(.orange)
                            .symbolSize(200)
                        }
                    }
                }
                .chartXSelection(value: $selectedKm)
                .chartYScale(domain: .automatic)
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let km = value.as(Int.self) {
                                Text("\(km)")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .frame(height: 240)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Location Text Component

struct LocationText: View {
    let coordinate: CLLocationCoordinate2D
    @State private var locationName: String = "Chargement..."

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "location.fill")
                .font(.caption)
            Text(locationName)
        }
        .task {
            await fetchLocationName()
        }
    }

    private func fetchLocationName() async {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        guard let request = MKReverseGeocodingRequest(location: location) else {
            locationName = "Lieu inconnu"
            return
        }

        do {
            let mapItems = try await request.mapItems

            if let mapItem = mapItems.first {
                // Use addressRepresentations for iOS 26+ (preferred)
                if let addressRepresentations = mapItem.addressRepresentations {
                    if let cityName = addressRepresentations.cityName {
                        locationName = cityName
                        return
                    }
                }

                // Fallback to address fullAddress if addressRepresentations not available
                if let address = mapItem.address {
                    // MKAddress only has fullAddress and shortAddress, parse shortAddress for city
                    if let shortAddress = address.shortAddress {
                        locationName = shortAddress
                        return
                    }
                    // Last resort: use full address
                    let fullAddress = address.fullAddress
                    if !fullAddress.isEmpty {
                        // Try to extract city from full address (first line usually)
                        let components = fullAddress.components(separatedBy: "\n")
                        locationName = components.first ?? "Lieu inconnu"
                        return
                    }
                }

                locationName = "Lieu inconnu"
            } else {
                locationName = "Lieu inconnu"
            }
        } catch {
            locationName = "Lieu inconnu"
        }
    }
}

#Preview {
    NavigationStack {
        WorkoutDetailView(
            workout: WorkoutModel(
                id: UUID(),
                workoutType: .running,
                startDate: Date(),
                endDate: Date().addingTimeInterval(1800),
                duration: 1800,
                distance: 5000,
                totalEnergyBurned: 350,
                sourceName: "Apple Watch",
                sourceVersion: "10.0"
            )
        )
    }
}
