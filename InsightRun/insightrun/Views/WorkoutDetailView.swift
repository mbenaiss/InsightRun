//
//  WorkoutDetailView.swift
//  InsightRun
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
    @State private var lastTrackedAnalysis: String?
    let workout: WorkoutModel
    let allWorkouts: [WorkoutModel]
    @StateObject private var viewModel: WorkoutDetailViewModel
    @Environment(\.modelContext) private var modelContext
    @StateObject private var analysisViewModel: WorkoutAnalysisViewModel
    @EnvironmentObject private var revenueCatManager: RevenueCatManager
    @ObservedObject private var remoteConfig = RemoteConfigService.shared
    @ObservedObject private var contextProvider = UnifiedAIContextProvider.shared
    @State private var showComparisonSheet = false
    @State private var similarWorkouts: [WorkoutModel] = []

    init(workout: WorkoutModel, allWorkouts: [WorkoutModel] = []) {
        self.workout = workout
        self.allWorkouts = allWorkouts
        _viewModel = StateObject(wrappedValue: WorkoutDetailViewModel(workout: workout))

        guard let container = InsightRunApp.shared else {
            fatalError("ModelContainer not initialized before WorkoutDetailView")
        }
        _analysisViewModel = StateObject(wrappedValue: WorkoutAnalysisViewModel(
            workout: workout,
            metrics: nil,
            modelContext: container.mainContext
        ))
    }

    // Extract Strava activity ID from workout metadata or source name
    private var stravaActivityId: Int64? {
        // Check if workout comes from Strava (metadata contains strava_id)
        if let stravaIdString = workout.metadata?["strava_id"] as? String,
           let stravaId = Int64(stravaIdString) {
            return stravaId
        }

        // Check if source name contains "Strava"
        if workout.sourceName.lowercased().contains("strava") {
            // For Strava workouts without explicit ID in metadata, we can't link
            // This would only happen for very old imports
            return nil
        }

        return nil
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if viewModel.isLoading {
                            loadingSection
                        } else if let error = viewModel.errorMessage {
                            errorSection(error)
                        } else if let metrics = viewModel.metrics {
                            // Editorial hero
                            headerSection(metrics: metrics)

                            if remoteConfig.isFeatureEnabled(.strava), let stravaId = stravaActivityId {
                                ViewOnStravaLink(activityId: stravaId, style: .boldOrange)
                            }

                            // 2x2 KPI hero
                            mainMetricsGrid(metrics: metrics)

                            // Coach narratif
                            VStack(alignment: .leading, spacing: 10) {
                                DashboardEyebrow(title: String(localized: "Coach verdict", comment: "Workout detail coach section eyebrow"))
                                aiAnalysisSection
                            }

                            // Compare similar
                            if similarWorkouts.count >= 2 {
                                compareWithSimilarSection
                            }

                            // Parcours
                            if let routePoints = metrics.routePoints, !routePoints.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    DashboardEyebrow(title: String(localized: "Route", comment: "Workout detail route section eyebrow"))
                                    routeMapSection(routePoints: routePoints)
                                }
                            }

                            // Évolution (charts)
                            if let splits = metrics.splits, !splits.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    DashboardEyebrow(title: String(localized: "Evolution", comment: "Workout detail evolution section eyebrow"))
                                    SwipeableChartsView(metrics: metrics)
                                }
                            }

                            // Performance
                            if hasPerformanceMetrics(metrics) {
                                VStack(alignment: .leading, spacing: 10) {
                                    DashboardEyebrow(title: String(localized: "Performance", comment: "Performance metrics section title"))
                                    MetricsCard {
                                        performanceContent(metrics: metrics)
                                    }
                                }
                            }

                            // Advanced
                            if hasAdvancedMetrics(metrics) {
                                VStack(alignment: .leading, spacing: 10) {
                                    DashboardEyebrow(title: String(localized: "Advanced Metrics", comment: "Advanced metrics section title"))
                                    MetricsCard {
                                        advancedMetricsContent(metrics: metrics)
                                    }
                                }
                            }

                            // Splits
                            if let splits = metrics.splits, !splits.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    DashboardEyebrow(title: String(localized: "Splits", comment: "Splits section title"))
                                    TabbedSplitsSection(
                                        splits: splits,
                                        intervals: metrics.intervals
                                    )
                                }
                            }

                            sourceSection
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
                .background(Color.irBackgroundApp)
                .accessibilityIdentifier("workout-detail")
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
            }
            .sheet(isPresented: $showComparisonSheet) {
                WorkoutComparisonView(
                    referenceWorkout: workout,
                    similarWorkouts: similarWorkouts
                )
            }
        .navigationTitle(String(localized: "Details", comment: "Workout detail screen title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Compute similar workouts once instead of on every render
            similarWorkouts = SimilarWorkoutFinder.findSimilar(to: workout, from: allWorkouts)

            await viewModel.loadMetrics()
            // Update metrics in analysisViewModel after loading
            analysisViewModel.updateMetrics(viewModel.metrics)
            // Load cached analysis only if user has AI access (subscribed or TestFlight)
            if revenueCatManager.hasAIAccess {
                await analysisViewModel.loadAnalysis()
            }
        }
        .onAppear {
            // Track workout detail viewed
            AnalyticsService.shared.trackWorkoutDetailViewed()

            // Update context provider with selected workout for unified AI assistant
            contextProvider.currentPage = .workoutDetail
            // Set selected workout immediately (metrics will be nil initially)
            contextProvider.setSelectedWorkout(workout, metrics: viewModel.metrics)
        }
        .onChange(of: viewModel.isLoading) { _, isLoading in
            // Update selected workout when loading completes
            if !isLoading {
                contextProvider.setSelectedWorkout(workout, metrics: viewModel.metrics)
            }
        }
        .onDisappear {
            // Clear selected workout when leaving detail view
            contextProvider.clearSelectedWorkout()
            contextProvider.currentPage = .workouts
        }
    }

    // MARK: - Header Section (editorial hero)

    private func sessionType(metrics: WorkoutMetrics) -> WorkoutSessionType {
        WorkoutSessionType.classify(workout)
    }

    private func headerSection(metrics: WorkoutMetrics) -> some View {
        let type = sessionType(metrics: metrics)
        let dateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale.current
            f.dateFormat = "EEE d MMMM"
            return f
        }()
        let timeFormatter: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale.current
            f.dateFormat = "HH:mm"
            return f
        }()
        let titleDateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale.current
            f.dateFormat = "EEEE d MMMM"
            return f
        }()

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(type.color)
                    .frame(width: 6, height: 6)
                Text("\(type.localizedLabel.uppercased()) · \(workout.distanceFormatted)")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(type.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(type.localizedLabel)
                    .font(.system(size: 30, weight: .heavy))
                    .kerning(-0.6)
                    .foregroundStyle(Color.irTextPrimary)
                    .lineLimit(1)
                Text(titleDateFormatter.string(from: workout.startDate).capitalized)
                    .font(.system(size: 30, weight: .heavy))
                    .kerning(-0.6)
                    .foregroundStyle(Color.irTextSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            HStack(spacing: 12) {
                if let routePoints = metrics.routePoints,
                   let firstPoint = routePoints.first {
                    LocationText(coordinate: firstPoint.coordinate)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.irTextSecondary)
                    Rectangle().fill(Color.irBorder).frame(width: 1, height: 12)
                }

                Text("\(dateFormatter.string(from: workout.startDate).capitalized) · \(timeFormatter.string(from: workout.startDate))")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.irTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Route Map Section (Pulse-Ring card)

    private func routeMapSection(routePoints: [RoutePoint]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                RouteMapView(routePoints: routePoints)
                    .frame(height: 200)
                    .clipShape(
                        RoundedRectangle(cornerRadius: Radius.xl)
                            .inset(by: 0.5)
                    )

                Text(String(format: String(localized: "%lld GPS points", comment: "GPS points count"), routePoints.count))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.black.opacity(0.5))
                    )
                    .padding(12)
            }
        }
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Main Metrics Grid (KPI hero card)

    private func mainMetricsGrid(metrics: WorkoutMetrics) -> some View {
        let type = sessionType(metrics: metrics)
        let peers = sameTypePeers(type: type)

        let distanceCell = KPICell(
            label: String(localized: "Distance", comment: "Distance metric"),
            value: shortDistance(workout.distance),
            unit: "km",
            mono: false,
            sub: distanceVsAvgLabel(peers: peers),
            subColor: distanceVsAvgColor(peers: peers)
        )
        let durationCell = KPICell(
            label: String(localized: "Duration", comment: "Duration metric"),
            value: shortDuration(workout.duration),
            unit: nil,
            mono: true,
            sub: netDurationLabel()
        )
        let paceCell: KPICell? = {
            guard let pace = metrics.averagePace else { return nil }
            return KPICell(
                label: String(localized: "Avg Pace", comment: "Average pace metric"),
                value: shortPace(pace),
                unit: "/km",
                mono: true,
                sub: paceVsAvgLabel(currentPace: pace, peers: peers),
                subColor: paceVsAvgColor(currentPace: pace, peers: peers)
            )
        }()
        let hrCell: KPICell? = {
            guard let avgHR = metrics.averageHeartRate else { return nil }
            return KPICell(
                label: String(localized: "Avg HR", comment: "Average heart rate metric"),
                value: String(format: "%.0f", avgHR),
                unit: "bpm",
                mono: false,
                sub: hrZoneLabel(avgHR: avgHR),
                subColor: hrZoneColor(avgHR: avgHR)
            )
        }()

        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                kpiView(cell: distanceCell, showsLeftBorder: false)
                Rectangle().fill(Color.irBorder).frame(width: 0.5)
                kpiView(cell: durationCell, showsLeftBorder: false)
            }
            .frame(maxWidth: .infinity)
            Rectangle().fill(Color.irBorder).frame(height: 0.5)
            HStack(spacing: 0) {
                if let paceCell {
                    kpiView(cell: paceCell, showsLeftBorder: false)
                } else {
                    Rectangle().fill(Color.clear).frame(maxWidth: .infinity).frame(height: 64)
                }
                Rectangle().fill(Color.irBorder).frame(width: 0.5)
                if let hrCell {
                    kpiView(cell: hrCell, showsLeftBorder: false)
                } else {
                    Rectangle().fill(Color.clear).frame(maxWidth: .infinity).frame(height: 64)
                }
            }
        }
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }

    private func kpiView(cell: KPICell, showsLeftBorder: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(cell.label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Color.irTextSecondary.opacity(0.7))

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(cell.value)
                    .font(.system(size: 26, weight: .heavy, design: cell.mono ? .monospaced : .rounded))
                    .kerning(-0.6)
                    .foregroundStyle(Color.irTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let unit = cell.unit {
                    Text(unit)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.irTextSecondary.opacity(0.7))
                }
            }

            if let sub = cell.sub {
                Text(sub)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(cell.subColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .padding(16)
    }

    private func shortDistance(_ meters: Double?) -> String {
        guard let meters else { return "—" }
        let km = meters / 1000.0
        return String(format: km < 10 ? "%.2f" : "%.1f", km)
    }

    private func shortDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    private func shortPace(_ pace: Double) -> String {
        let m = Int(pace)
        let s = Int((pace - Double(m)) * 60)
        return String(format: "%d'%02d\"", m, s)
    }

    // MARK: - KPI Context (peers, vs-avg, HR zone)

    private func sameTypePeers(type: WorkoutSessionType) -> [WorkoutModel] {
        allWorkouts.filter { peer in
            peer.id != workout.id &&
            WorkoutSessionType.classify(peer) == type
        }
    }

    private func distanceVsAvgLabel(peers: [WorkoutModel]) -> String? {
        guard let current = workout.distance, current > 0 else { return nil }
        let distances = peers.compactMap { $0.distance }.filter { $0 > 0 }
        guard distances.count >= 2 else { return nil }
        let avg = distances.reduce(0, +) / Double(distances.count)
        let deltaKm = (current - avg) / 1000.0
        let sign = deltaKm >= 0 ? "+" : "−"
        let abs = Swift.abs(deltaKm)
        let formatted = String(format: abs < 10 ? "%.1f" : "%.0f", abs)
        return "\(sign)\(formatted) " + String(localized: "vs avg", comment: "Versus average suffix in KPI subtitle")
    }

    private func distanceVsAvgColor(peers: [WorkoutModel]) -> Color {
        guard let current = workout.distance, current > 0 else { return .irTextSecondary }
        let distances = peers.compactMap { $0.distance }.filter { $0 > 0 }
        guard distances.count >= 2 else { return .irTextSecondary }
        let avg = distances.reduce(0, +) / Double(distances.count)
        return current >= avg ? .irSuccess : .irTextSecondary
    }

    private func paceVsAvgLabel(currentPace: Double, peers: [WorkoutModel]) -> String? {
        let paces = peers.compactMap { $0.averagePace }.filter { $0 > 0 }
        guard paces.count >= 2 else { return nil }
        let avg = paces.reduce(0, +) / Double(paces.count)
        let deltaSec = (currentPace - avg) * 60.0
        guard Swift.abs(deltaSec) >= 1 else { return nil }
        let sign = deltaSec < 0 ? "−" : "+"
        let abs = Int(Swift.abs(deltaSec).rounded())
        return "\(sign)\(abs)\" " + String(localized: "vs avg", comment: "Versus average suffix in KPI subtitle")
    }

    private func paceVsAvgColor(currentPace: Double, peers: [WorkoutModel]) -> Color {
        let paces = peers.compactMap { $0.averagePace }.filter { $0 > 0 }
        guard paces.count >= 2 else { return .irTextSecondary }
        let avg = paces.reduce(0, +) / Double(paces.count)
        if currentPace + 0.01 < avg { return .irSuccess }
        if currentPace > avg + 0.05 { return .irWarning }
        return .irTextSecondary
    }

    private func netDurationLabel() -> String? {
        guard workout.duration > 0 else { return nil }
        let total = Int(workout.duration)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        let pretty = h > 0
            ? String(format: "%dh%02d", h, m)
            : String(format: "%d'%02d", m, s)
        return "\(pretty) " + String(localized: "net", comment: "KPI subtitle: net duration suffix")
    }

    private var personalMaxHR: Double {
        let maxes = allWorkouts.compactMap { $0.maxHeartRate }.filter { $0 > 0 }
        return maxes.max() ?? 190
    }

    private func hrZone(avgHR: Double) -> Int {
        let pct = avgHR / personalMaxHR
        switch pct {
        case ..<0.60: return 1
        case ..<0.70: return 2
        case ..<0.80: return 3
        case ..<0.90: return 4
        default:      return 5
        }
    }

    private func hrZoneLabel(avgHR: Double) -> String? {
        guard avgHR > 0 else { return nil }
        let zone = hrZone(avgHR: avgHR)
        let pct = Int(((avgHR / personalMaxHR) * 100).rounded())
        return "Z\(zone) · \(pct)% FCmax"
    }

    private func hrZoneColor(avgHR: Double) -> Color {
        switch hrZone(avgHR: avgHR) {
        case 1: return .irSuccess
        case 2: return .irSuccess
        case 3: return .irWarning
        case 4: return .irWarning
        default: return .irError
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
            Text(String(localized: "Loading data...", comment: "Loading indicator"))
                .font(.subheadline)
                .foregroundStyle(Color.irTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    // MARK: - Error

    private func errorSection(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(Color.irWarning)

            Text(error)
                .font(.subheadline)
                .foregroundStyle(Color.irTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Content Functions

    private func metricRowList(_ rows: [MetricRowData]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                if idx > 0 {
                    Divider().background(Color.irBorder)
                }
                MetricRow(
                    icon: row.icon,
                    label: row.label,
                    value: row.value,
                    color: row.color,
                    metricInfoKey: row.metricInfoKey,
                    currentValue: row.currentValue
                )
            }
        }
        .padding(.bottom, 4)
    }

    private func performanceContent(metrics: WorkoutMetrics) -> some View {
        var rows: [MetricRowData] = []

        if let minPace = metrics.minPace {
            rows.append(MetricRowData(
                icon: "hare.fill",
                label: String(localized: "Best Pace", comment: "Best pace performance metric"),
                value: viewModel.formatPace(minPace),
                color: .green,
                metricInfoKey: "metric.best_pace",
                currentValue: minPace
            ))
        }
        if let maxSpeed = metrics.maxSpeed {
            rows.append(MetricRowData(
                icon: "bolt.fill",
                label: String(localized: "Max Speed", comment: "Maximum speed performance metric"),
                value: viewModel.formatSpeed(maxSpeed),
                color: .yellow,
                metricInfoKey: "metric.max_speed",
                currentValue: maxSpeed
            ))
        }
        if let cadence = metrics.averageCadence {
            rows.append(MetricRowData(
                icon: "metronome.fill",
                label: String(localized: "Avg Cadence", comment: "Average cadence performance metric"),
                value: viewModel.formatCadence(cadence),
                color: .indigo,
                metricInfoKey: "metric.avg_cadence",
                currentValue: cadence
            ))
        }
        if let strideLength = metrics.strideLength {
            rows.append(MetricRowData(
                icon: "figure.walk",
                label: String(localized: "Stride Length", comment: "Stride length performance metric"),
                value: viewModel.formatStrideLength(strideLength),
                color: .cyan,
                metricInfoKey: "metric.stride_length",
                currentValue: strideLength
            ))
        }
        if let power = metrics.runningPower {
            rows.append(MetricRowData(
                icon: "bolt.circle.fill",
                label: String(localized: "Power", comment: "Running power performance metric"),
                value: viewModel.formatPower(power),
                color: .orange,
                metricInfoKey: "metric.running_power",
                currentValue: power
            ))
        }
        if let vo2Max = metrics.vo2Max {
            rows.append(MetricRowData(
                icon: "lungs.fill",
                label: String(localized: "VO2 Max", comment: "VO2 Maximum performance metric"),
                value: String(format: "%.1f %@", vo2Max, String(localized: "ml/kg/min", comment: "VO2 Max unit")),
                color: .red,
                metricInfoKey: "metric.vo2_max",
                currentValue: vo2Max
            ))
        }
        return metricRowList(rows)
    }

    private func advancedMetricsContent(metrics: WorkoutMetrics) -> some View {
        var rows: [MetricRowData] = []

        if let gct = metrics.groundContactTime {
            rows.append(MetricRowData(
                icon: "timer",
                label: String(localized: "Ground Contact Time", comment: "Ground contact time advanced metric"),
                value: String(format: "%.0f %@", gct, String(localized: "ms", comment: "Milliseconds unit")),
                color: .indigo,
                metricInfoKey: "metric.ground_contact_time",
                currentValue: gct
            ))
        }
        if let vo = metrics.verticalOscillation {
            rows.append(MetricRowData(
                icon: "arrow.up.and.down",
                label: String(localized: "Vertical Oscillation", comment: "Vertical oscillation advanced metric"),
                value: String(format: "%.1f %@", vo, String(localized: "cm", comment: "Centimeters unit")),
                color: .cyan,
                metricInfoKey: "metric.vertical_oscillation",
                currentValue: vo
            ))
        }
        if let balance = metrics.groundContactTimeBalance {
            rows.append(MetricRowData(
                icon: "scale.3d",
                label: String(localized: "Contact Balance", comment: "Ground contact time balance advanced metric"),
                value: viewModel.formatPercentage(balance),
                color: .orange,
                metricInfoKey: "metric.contact_balance",
                currentValue: balance
            ))
        }
        if let efficiency = metrics.runningEfficiency {
            rows.append(MetricRowData(
                icon: "chart.line.uptrend.xyaxis",
                label: String(localized: "Running Efficiency", comment: "Running efficiency advanced metric"),
                value: viewModel.formatPercentage(efficiency),
                color: .green,
                metricInfoKey: "metric.running_efficiency",
                currentValue: efficiency
            ))
        }
        if let steadiness = metrics.walkingSteadiness {
            rows.append(MetricRowData(
                icon: "figure.walk",
                label: String(localized: "Walking Steadiness", comment: "Walking steadiness advanced metric"),
                value: viewModel.formatPercentage(steadiness),
                color: .green,
                metricInfoKey: "metric.walking_steadiness",
                currentValue: steadiness
            ))
        }
        if let asymmetry = metrics.walkingAsymmetry {
            rows.append(MetricRowData(
                icon: "figure.walk.arrival",
                label: String(localized: "Walking Asymmetry", comment: "Walking asymmetry advanced metric"),
                value: viewModel.formatPercentage(asymmetry),
                color: .orange,
                metricInfoKey: "metric.walking_asymmetry",
                currentValue: asymmetry
            ))
        }
        if let doubleSupport = metrics.doubleSupportPercentage {
            rows.append(MetricRowData(
                icon: "figure.2.arms.open",
                label: String(localized: "Double Support", comment: "Double support percentage advanced metric"),
                value: viewModel.formatPercentage(doubleSupport),
                color: .blue,
                metricInfoKey: "metric.double_support",
                currentValue: doubleSupport
            ))
        }
        if let speed = metrics.walkingSpeed {
            rows.append(MetricRowData(
                icon: "figure.walk.circle",
                label: String(localized: "Walking Speed", comment: "Walking speed advanced metric"),
                value: viewModel.formatSpeed(speed),
                color: .cyan,
                metricInfoKey: "metric.walking_speed",
                currentValue: speed
            ))
        }
        if let ascentSpeed = metrics.stairAscentSpeed {
            rows.append(MetricRowData(
                icon: "figure.stairs",
                label: String(localized: "Stair Ascent Speed", comment: "Stair ascent speed advanced metric"),
                value: viewModel.formatSpeed(ascentSpeed),
                color: .purple,
                metricInfoKey: "metric.stair_ascent_speed",
                currentValue: ascentSpeed
            ))
        }
        if let descentSpeed = metrics.stairDescentSpeed {
            rows.append(MetricRowData(
                icon: "figure.stairs",
                label: String(localized: "Stair Descent Speed", comment: "Stair descent speed advanced metric"),
                value: viewModel.formatSpeed(descentSpeed),
                color: .indigo,
                metricInfoKey: "metric.stair_descent_speed",
                currentValue: descentSpeed
            ))
        }
        return metricRowList(rows)
    }

    // MARK: - AI Analysis Section

    @State private var showSubscriptionPaywall = false
    @State private var showConsentSheet = false
    @State private var hasTrackedTeaser = false

    private var aiAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(
                            LinearGradient(
                                colors: [Color.irAIAccent, Color.irAIAccentSecondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.black)
                }
                .frame(width: 22, height: 22)

                Text(String(localized: "Coach", comment: "AI analysis section title"))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(Color.irTextPrimary)

                Spacer()

                if let analyzedAt = analysisViewModel.analyzedAt, analysisViewModel.analysisText != nil {
                    Text(analyzedAt, style: .relative)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.irTextSecondary.opacity(0.7))
                }
            }

            // Check AI access first (subscription or TestFlight)
            if !revenueCatManager.hasAIAccess {
                // No AI access — show blurred teaser to demonstrate value
                VStack(spacing: 16) {
                    // Blurred fake analysis preview — text visible but unreadable
                    ZStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(
                                localized: "Good pace consistency across splits. Your cadence of 172 spm is slightly below optimal — aim for 180 spm to improve efficiency.",
                                comment: "Blurred teaser text for locked AI analysis about pace consistency"
                            ))
                                .font(.subheadline)
                                .foregroundStyle(Color.irTextPrimary)
                            Text(String(
                                localized: "Recovery heart rate dropped well, indicating solid aerobic fitness. Consider adding tempo intervals to push your threshold.",
                                comment: "Blurred teaser text for locked AI analysis about recovery heart rate"
                            ))
                                .font(.subheadline)
                                .foregroundStyle(Color.irTextSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .blur(radius: 6)

                        // Lock overlay
                        VStack(spacing: 8) {
                            Image(systemName: "lock.fill")
                                .font(.title3)
                                .foregroundStyle(Color.irTextSecondary)
                            Text(String(localized: "Unlock your full AI analysis", comment: "AI teaser unlock message"))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.irTextSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .background(Color.irCardBackground)
                    .cornerRadius(12)

                    // CTA button
                    Button {
                        AnalyticsService.shared.track(.aiTeaserSubscribeTapped)
                        showSubscriptionPaywall = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 13, weight: .bold))
                            Text(String(localized: "Unlock Full Analysis", comment: "AI teaser subscribe CTA button"))
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.irAIAccent)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .onAppear {
                    guard !hasTrackedTeaser else { return }
                    hasTrackedTeaser = true
                    AnalyticsService.shared.track(.aiTeaserShown)
                }

            } else if analysisViewModel.isLoading {
                // Loading state
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text(String(localized: "Analyzing...", comment: "AI analysis loading indicator"))
                        .font(.subheadline)
                        .foregroundStyle(Color.irTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)

            } else if analysisViewModel.needsConsent {
                // Consent required - show consent button directly
                VStack(spacing: 12) {
                    Image(systemName: "hand.raised.fill")
                        .font(.title2)
                        .foregroundStyle(Color.irPrimaryAccent)

                    Text(String(localized: "AI consent is required to analyze your workouts.", comment: "Error when AI consent is missing"))
                        .font(.subheadline)
                        .foregroundStyle(Color.irTextSecondary)
                        .multilineTextAlignment(.center)

                    Button {
                        showConsentSheet = true
                    } label: {
                        Label(String(localized: "Review & Accept", comment: "Consent review button"), systemImage: "checkmark.shield")
                            .font(.subheadline)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .sheet(isPresented: $showConsentSheet) {
                    AIConsentSheet(
                        onConsent: {
                            showConsentSheet = false
                            analysisViewModel.needsConsent = false
                            Task {
                                if await HistoricalSummaryStorage.shared.requiresIndexation() {
                                    analysisViewModel.needsIndexation = true
                                } else {
                                    await analysisViewModel.generateAnalysis()
                                }
                            }
                        },
                        onDecline: {
                            showConsentSheet = false
                        }
                    )
                }
                .indexationGate(isPresented: $analysisViewModel.needsIndexation) {
                    await analysisViewModel.generateAnalysis()
                }

            } else if let error = analysisViewModel.error {
                // Error state
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(Color.irWarning)

                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(Color.irTextSecondary)
                        .multilineTextAlignment(.center)

                    Button {
                        Task {
                            await analysisViewModel.generateAnalysis()
                        }
                    } label: {
                        Label(String(localized: "Retry", comment: "Retry button"), systemImage: "arrow.clockwise")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

            } else if let analysis = analysisViewModel.analysisText {
                VStack(alignment: .leading, spacing: 10) {
                    MarkdownView(analysis)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onAppear {
                            if lastTrackedAnalysis != analysis {
                                ReviewManager.shared.recordAIEngagement()
                                lastTrackedAnalysis = analysis
                            }
                        }

                    HStack {
                        Spacer()
                        Button {
                            Task {
                                await analysisViewModel.regenerateAnalysis()
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.irTextSecondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }

            } else {
                // No analysis yet - show button to generate
                VStack(spacing: 12) {
                    Text(String(localized: "Get detailed analysis of your performance", comment: "AI analysis prompt"))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.irTextSecondary)
                        .multilineTextAlignment(.center)

                    Button {
                        Task {
                            await analysisViewModel.loadAnalysis()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 13, weight: .bold))
                            Text(String(localized: "Analyze with AI", comment: "Analyze button"))
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.irAIAccent)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
        .accessibilityIdentifier("workout-ai-analysis")
        .sheet(isPresented: $showSubscriptionPaywall) {
            SubscriptionPaywallView(isInitialFlow: false)
                .environmentObject(revenueCatManager)
        }
    }

    // MARK: - Compare With Similar Section

    private var compareWithSimilarSection: some View {
        Button {
            showComparisonSheet = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.irAIAccent.opacity(0.16))
                        .frame(width: 32, height: 32)
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.irAIAccent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Compare with similar", comment: "Button to compare with similar workouts"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.irTextPrimary)

                    Text(String(format: String(localized: "%lld similar workouts found", comment: "Number of similar workouts found"), similarWorkouts.count))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.irTextSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.irTextSecondary.opacity(0.55))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color.irCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(Color.irBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Source Section

    private var sourceSection: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 10))
                .foregroundStyle(Color.irTextSecondary.opacity(0.55))

            Text(String(localized: "workout.detail.source") + " \(workout.sourceName)")
                .font(.system(size: 10))
                .foregroundStyle(Color.irTextSecondary.opacity(0.7))

            if let version = workout.sourceVersion {
                Text(verbatim: "v\(version)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.irTextSecondary.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

// MARK: - KPI Cell value object (private to detail view)

struct KPICell {
    let label: String
    let value: String
    let unit: String?
    let mono: Bool
    var sub: String? = nil
    var subColor: Color = .irTextSecondary
}

// MARK: - Supporting Components

// MARK: - Metric Row Data

struct MetricRowData: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let value: String
    let color: Color
    let metricInfoKey: String?
    let currentValue: Double?
}

// MARK: - Metric Info Model

struct MetricInfo: Identifiable {
    let id = UUID()
    let key: String
    let currentValue: Double?

    init(key: String, currentValue: Double? = nil) {
        self.key = key
        self.currentValue = currentValue
    }

    var title: String {
        NSLocalizedString("\(key).title", comment: "Metric title")
    }

    var description: String {
        NSLocalizedString("\(key).description", comment: "Metric description")
    }

    var usage: String {
        NSLocalizedString("\(key).usage", comment: "Metric usage")
    }

    var recommendedValues: String {
        NSLocalizedString("\(key).recommended", comment: "Metric recommended values")
    }
}

// MARK: - Metric Info Sheet (Pulse-Ring style)

struct MetricInfoSheet: View {
    let metricInfo: MetricInfo
    @Environment(\.dismiss) private var dismiss
    @State private var showingMedicalSources = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Editorial header
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Metric", comment: "Metric info eyebrow").uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(Color.irTextSecondary.opacity(0.7))

                        Text(metricInfo.title)
                            .font(.system(size: 28, weight: .heavy))
                            .kerning(-0.6)
                            .foregroundStyle(Color.irTextPrimary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                    .padding(.bottom, 4)

                    // What is this?
                    metricSection(
                        eyebrow: String(localized: "What is this?", comment: "Metric info section eyebrow"),
                        body: metricInfo.description
                    )

                    // How is it used?
                    metricSection(
                        eyebrow: String(localized: "How is it used?", comment: "Metric info section eyebrow"),
                        body: metricInfo.usage
                    )

                    // Recommended values
                    DashboardEyebrow(title: String(localized: "Recommended values", comment: "Metric info recommended values eyebrow"))
                    if let rangeModel = MetricRanges.getRangeModel(for: metricInfo.key) {
                        VStack(spacing: 0) {
                            MetricRangeVisualization(
                                rangeModel: rangeModel,
                                currentValue: metricInfo.currentValue
                            )
                            .padding(.horizontal, 18)
                            .padding(.vertical, 16)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.irCardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.xl)
                                .strokeBorder(Color.irBorder, lineWidth: 0.5)
                        )
                    } else {
                        Text(metricInfo.recommendedValues)
                            .font(.system(size: 14))
                            .lineSpacing(3)
                            .foregroundStyle(Color.irTextPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(18)
                            .background(Color.irCardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.xl)
                                    .strokeBorder(Color.irBorder, lineWidth: 0.5)
                            )
                    }

                    // Sources
                    DashboardEyebrow(title: String(localized: "Sources", comment: "Metric info sources eyebrow"))
                    Button {
                        showingMedicalSources = true
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.irAIAccent.opacity(0.16))
                                    .frame(width: 32, height: 32)
                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.irAIAccent)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(localized: "View Medical Sources", comment: "Button to view medical sources from metric sheet"))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.irTextPrimary)
                                Text(String(localized: "These recommendations are based on published scientific research.", comment: "Metric info medical disclaimer"))
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.irTextSecondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.irTextSecondary.opacity(0.55))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(Color.irCardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.lg)
                                .strokeBorder(Color.irBorder, lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color.irBackgroundApp)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.irTextSecondary)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showingMedicalSources) {
            MedicalSourcesView()
        }
    }

    @ViewBuilder
    private func metricSection(eyebrow: String, body: String) -> some View {
        DashboardEyebrow(title: eyebrow)
        Text(body)
            .font(.system(size: 14))
            .lineSpacing(3)
            .foregroundStyle(Color.irTextPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Color.irCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xl)
                    .strokeBorder(Color.irBorder, lineWidth: 0.5)
            )
    }
}

// MARK: - Info Card Component

struct InfoCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with icon and title
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 36, height: 36)

                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(iconColor)
                }

                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.irTextPrimary)

                Spacer()
            }

            // Content
            Text(content)
                .font(.subheadline)
                .foregroundStyle(Color.irTextSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.irCardBackground)
                .shadow(color: Color.irBorder.opacity(0.3), radius: 8, y: 2)
        )
    }
}

struct MetricsCard<Content: View>: View {
    var title: String? = nil
    var icon: String? = nil
    var iconColor: Color = .irPrimaryAccent
    let content: Content

    init(
        title: String? = nil,
        icon: String? = nil,
        iconColor: Color = .irPrimaryAccent,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title = title {
                HStack(spacing: 8) {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(iconColor)
                    }
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.irTextPrimary)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 4)
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }
}

struct MetricRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    var metricInfoKey: String? = nil
    var currentValue: Double? = nil

    @State private var showingInfo = false

    var body: some View {
        Group {
            if let metricInfoKey {
                Button {
                    showingInfo = true
                } label: { rowContent }
                .buttonStyle(.plain)
                .sheet(isPresented: $showingInfo) {
                    MetricInfoSheet(metricInfo: MetricInfo(key: metricInfoKey, currentValue: currentValue))
                }
            } else {
                rowContent
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Color.irTextSecondary)

            Spacer()

            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Color.irTextPrimary)

            if metricInfoKey != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.irTextSecondary.opacity(0.45))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct SplitRow: View {
    let split: Split
    var averagePace: Double = 0
    var maxAbsDelta: Double = 1
    var isBest: Bool = false
    var isSlowest: Bool = false

    private var delta: Double { split.pace - averagePace }

    private var paceColor: Color {
        if isBest { return .irSuccess }
        if isSlowest { return .irWarning }
        return .irTextPrimary
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("km \(split.kilometer)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.irTextSecondary.opacity(0.7))
                .frame(width: 36, alignment: .leading)

            Text(split.paceFormatted)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(paceColor)
                .frame(width: 56, alignment: .leading)

            deltaBar
                .frame(height: 16)
                .frame(maxWidth: .infinity)

            if let hr = split.averageHeartRate {
                HStack(spacing: 3) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.red)
                    Text(String(format: "%.0f", hr))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.irError)
                }
                .frame(width: 44, alignment: .trailing)
            } else {
                Color.clear.frame(width: 44, height: 1)
            }
        }
    }

    private var deltaBar: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height: CGFloat = 12
            let centerY = geo.size.height / 2
            let safeMax = max(maxAbsDelta, 0.001)
            let barWidth = max(2, width * 0.5 * CGFloat(min(abs(delta) / safeMax, 1)))

            ZStack(alignment: .leading) {
                // background track
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.04))
                    .frame(height: height)
                    .position(x: width / 2, y: centerY)

                // center axis
                Rectangle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 1, height: height + 2)
                    .position(x: width / 2, y: centerY)

                // delta bar
                RoundedRectangle(cornerRadius: 2)
                    .fill((delta < 0 ? Color.irSuccess : Color.irWarning).opacity(0.8))
                    .frame(width: barWidth, height: height - 2)
                    .position(
                        x: delta < 0 ? width / 2 - barWidth / 2 : width / 2 + barWidth / 2,
                        y: centerY
                    )
            }
        }
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
                        .foregroundStyle(Color.irTextPrimary)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.subheadline)
                        .foregroundStyle(Color.irTextSecondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding()
                .background(Color.irCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 16 : 20))
            }
            .buttonStyle(.plain)

            // Content - collapsible
            if isExpanded {
                content
                    .padding()
                    .background(Color.irCardBackground)
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
                    .foregroundStyle(Color.irTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(label)
                    .font(.caption)
                    .foregroundStyle(Color.irTextSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.irBorder.opacity(0.3), radius: 8, y: 4)
    }
}

// MARK: - Swipeable Charts View

struct SwipeableChartsView: View {
    let metrics: WorkoutMetrics
    @State private var selectedPage = 0

    private var hasElevationData: Bool {
        guard let splits = metrics.splits else { return false }
        return splits.contains { $0.elevationGain != nil || $0.elevationLoss != nil }
    }

    private var chartCount: Int {
        var count = 2 // HR + Pace always
        if metrics.runningPower != nil { count += 1 }
        if hasElevationData { count += 1 }
        return count
    }

    var body: some View {
        VStack(spacing: 8) {
            TabView(selection: $selectedPage) {
                // Heart Rate Chart
                InteractiveHeartRateChart(metrics: metrics)
                    .tag(0)

                // Pace Chart
                InteractivePaceChart(metrics: metrics)
                    .tag(1)

                // Elevation Chart (if available)
                if hasElevationData {
                    InteractiveElevationChart(metrics: metrics)
                        .tag(2)
                }

                // Power Chart (if available)
                if metrics.runningPower != nil {
                    InteractivePowerChart(metrics: metrics)
                        .tag(hasElevationData ? 3 : 2)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 340)
            .clipped()

            // Custom page indicator dots
            HStack(spacing: 8) {
                ForEach(0..<chartCount, id: \.self) { index in
                    Circle()
                        .fill(selectedPage == index ? Color.irTextPrimary : Color.irTextSecondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut, value: selectedPage)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Interactive Heart Rate Chart

struct InteractiveHeartRateChart: View {
    let metrics: WorkoutMetrics
    @State private var selectedKm: Double?

    var heartRateData: [(km: Double, value: Double)] {
        guard let splits = metrics.splits else { return [] }

        // Calculate cumulative distance for each split
        var cumulativeDistance = 0.0
        let splitData = splits.compactMap { split -> (km: Double, value: Double)? in
            guard let hr = split.averageHeartRate else { return nil }
            cumulativeDistance += split.distance / 1000.0
            return (km: cumulativeDistance, value: hr)
        }

        guard !splitData.isEmpty else { return [] }

        // First point: use real first HR sample from workout start
        let firstPointHR = metrics.firstHeartRate ?? splitData.first?.value ?? 0
        let firstPoint = (km: 0.0, value: firstPointHR)

        return [firstPoint] + splitData
    }

    var selectedData: (km: Double, value: Double)? {
        guard let km = selectedKm else { return nil }
        // Find the closest point to the selected km
        return heartRateData.min(by: { abs($0.km - km) < abs($1.km - km) })
    }

    var minHeartRate: Double? {
        heartRateData.min(by: { $0.value < $1.value })?.value
    }

    var maxHeartRate: Double? {
        heartRateData.max(by: { $0.value < $1.value })?.value
    }

    var displayData: (value: Double, label: String)? {
        if let selected = selectedData {
            return (value: selected.value, label: String(format: "%@ %.1f", String(localized: "km", comment: "Kilometer abbreviation"), selected.km))
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
                    Text(String(localized: "Heart Rate", comment: "Heart rate chart title"))
                        .font(.headline)
                        .foregroundStyle(Color.irTextPrimary)

                    if let data = displayData {
                        Text("\(Int(data.value)) \(String(localized: "bpm", comment: "Beats per minute unit"))")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.red)
                        Text(data.label)
                            .font(.caption)
                            .foregroundStyle(Color.irTextSecondary)
                    } else if showMinMax, let min = minHeartRate, let max = maxHeartRate {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(Int(min)) \(String(localized: "bpm", comment: "Beats per minute unit"))")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.red)
                                Text(String(localized: "min", comment: "Minimum label"))
                                    .font(.caption2)
                                    .foregroundStyle(Color.irTextSecondary)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(Int(max)) \(String(localized: "bpm", comment: "Beats per minute unit"))")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.red)
                                Text(String(localized: "max", comment: "Maximum label"))
                                    .font(.caption2)
                                    .foregroundStyle(Color.irTextSecondary)
                            }
                        }
                    } else {
                        Text(String(localized: "No data available", comment: "Empty state message"))
                            .font(.caption)
                            .foregroundStyle(Color.irTextSecondary)
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
                        .foregroundStyle(Color.irTextSecondary)
                    Text(String(localized: "No heart rate data available", comment: "Empty HR chart message"))
                        .font(.subheadline)
                        .foregroundStyle(Color.irTextSecondary)
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

                        if let selectedData = selectedData, selectedData.km == data.km {
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
                .chartXScale(domain: 0...((metrics.workout.distance ?? 0) / 1000.0))
                .chartYScale(domain: .automatic)
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let km = value.as(Double.self) {
                                Text(String(format: "%.0f", km))
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
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Interactive Pace Chart

struct InteractivePaceChart: View {
    let metrics: WorkoutMetrics
    @State private var selectedKm: Double?

    var paceData: [(km: Double, value: Double)] {
        guard let splits = metrics.splits else { return [] }

        // Calculate cumulative distance for each split
        var cumulativeDistance = 0.0
        let splitData = splits.map { split in
            cumulativeDistance += split.distance / 1000.0
            return (km: cumulativeDistance, value: split.pace)
        }

        guard !splitData.isEmpty else { return [] }

        // Calculate real first point from route data
        let firstPointPace: Double
        if let routePoints = metrics.routePoints, routePoints.count > 10 {
            // Use average speed of first 10 GPS points for stability
            let firstPoints = Array(routePoints.prefix(10))
            let speeds = firstPoints.compactMap { $0.speed }
            if !speeds.isEmpty {
                let avgSpeed = speeds.reduce(0, +) / Double(speeds.count)
                // Convert m/s to min/km
                firstPointPace = avgSpeed > 0 ? (1000.0 / avgSpeed) / 60.0 : splitData.first?.value ?? 0
            } else {
                firstPointPace = splitData.first?.value ?? 0
            }
        } else {
            firstPointPace = splitData.first?.value ?? 0
        }
        let firstPoint = (km: 0.0, value: firstPointPace)

        return [firstPoint] + splitData
    }

    var selectedData: (km: Double, value: Double)? {
        guard let km = selectedKm else { return nil }
        // Find the closest point to the selected km
        return paceData.min(by: { abs($0.km - km) < abs($1.km - km) })
    }

    var minPace: Double? {
        paceData.min(by: { $0.value < $1.value })?.value
    }

    var maxPace: Double? {
        paceData.max(by: { $0.value < $1.value })?.value
    }

    var displayData: (value: Double, label: String)? {
        if let selected = selectedData {
            return (value: selected.value, label: String(format: "%@ %.1f", String(localized: "km", comment: "Kilometer abbreviation"), selected.km))
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
                    Text(String(localized: "workout.detail.pace"))
                        .font(.headline)
                        .foregroundStyle(Color.irTextPrimary)

                    if let data = displayData {
                        Text(formatPace(data.value))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.green)
                        Text(data.label)
                            .font(.caption)
                            .foregroundStyle(Color.irTextSecondary)
                    } else if showMinMax, let min = minPace, let max = maxPace {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(formatPace(min))
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.green)
                                Text(String(localized: "min", comment: "Minimum label"))
                                    .font(.caption2)
                                    .foregroundStyle(Color.irTextSecondary)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(formatPace(max))
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.green)
                                Text(String(localized: "max", comment: "Maximum label"))
                                    .font(.caption2)
                                    .foregroundStyle(Color.irTextSecondary)
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

                    if let selectedData = selectedData, selectedData.km == data.km {
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
            .chartXScale(domain: 0...((metrics.workout.distance ?? 0) / 1000.0))
            .chartYScale(domain: .automatic)
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let km = value.as(Double.self) {
                            Text(String(format: "%.0f", km))
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
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Interactive Power Chart

struct InteractivePowerChart: View {
    let metrics: WorkoutMetrics
    @State private var selectedKm: Double?

    var powerData: [(km: Double, value: Double)] {
        guard let splits = metrics.splits, let avgPower = metrics.runningPower else { return [] }

        // Calculate cumulative distance for each split
        var cumulativeDistance = 0.0
        let splitData = splits.map { split -> (km: Double, value: Double) in
            cumulativeDistance += split.distance / 1000.0
            if let power = split.averagePower {
                return (km: cumulativeDistance, value: power)
            }
            // Fallback to average if no split data
            return (km: cumulativeDistance, value: avgPower)
        }

        guard !splitData.isEmpty else { return [] }

        // First point: use real first power sample from workout start
        let firstPointPower = metrics.firstPower ?? splitData.first?.value ?? avgPower
        let firstPoint = (km: 0.0, value: firstPointPower)

        return [firstPoint] + splitData
    }

    var hasRealPowerData: Bool {
        metrics.splits?.contains { $0.averagePower != nil } ?? false
    }

    var selectedData: (km: Double, value: Double)? {
        guard let km = selectedKm else { return nil }
        // Find the closest point to the selected km
        return powerData.min(by: { abs($0.km - km) < abs($1.km - km) })
    }

    var minPower: Double? {
        powerData.min(by: { $0.value < $1.value })?.value
    }

    var maxPower: Double? {
        powerData.max(by: { $0.value < $1.value })?.value
    }

    var displayData: (value: Double, label: String)? {
        if let selected = selectedData {
            return (value: selected.value, label: String(format: "%@ %.1f", String(localized: "km", comment: "Kilometer abbreviation"), selected.km))
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
                    Text(String(localized: "workout.detail.power"))
                        .font(.headline)
                        .foregroundStyle(Color.irTextPrimary)

                    if let data = displayData {
                        Text("\(Int(data.value)) \(String(localized: "W", comment: "Watts unit"))")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.orange)
                        Text(data.label)
                            .font(.caption)
                            .foregroundStyle(Color.irTextSecondary)
                    } else if showMinMax, let min = minPower, let max = maxPower {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(Int(min)) \(String(localized: "W", comment: "Watts unit"))")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.orange)
                                Text(String(localized: "min", comment: "Minimum label"))
                                    .font(.caption2)
                                    .foregroundStyle(Color.irTextSecondary)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(Int(max)) \(String(localized: "W", comment: "Watts unit"))")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.orange)
                                Text(String(localized: "max", comment: "Maximum label"))
                                    .font(.caption2)
                                    .foregroundStyle(Color.irTextSecondary)
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
                        .foregroundStyle(Color.irTextSecondary)
                    Text(String(localized: "workout.detail.no_power_data"))
                        .font(.subheadline)
                        .foregroundStyle(Color.irTextSecondary)
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

                        if let selectedData = selectedData, selectedData.km == data.km {
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
                .chartXScale(domain: 0...((metrics.workout.distance ?? 0) / 1000.0))
                .chartYScale(domain: .automatic)
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let km = value.as(Double.self) {
                                Text(String(format: "%.0f", km))
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
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Interactive Elevation Chart

struct InteractiveElevationChart: View {
    let metrics: WorkoutMetrics
    @State private var selectedKm: Double?

    var elevationData: [(km: Double, value: Double)] {
        guard let splits = metrics.splits else { return [] }

        // Calculate cumulative elevation profile
        var cumulativeElevation = 0.0
        var cumulativeDistance = 0.0
        var data: [(km: Double, value: Double)] = [(km: 0.0, value: 0.0)]

        for split in splits {
            cumulativeDistance += split.distance / 1000.0

            // Add elevation gain, subtract elevation loss
            if let gain = split.elevationGain {
                cumulativeElevation += gain
            }
            if let loss = split.elevationLoss {
                cumulativeElevation -= loss
            }

            data.append((km: cumulativeDistance, value: cumulativeElevation))
        }

        return data
    }

    var selectedData: (km: Double, value: Double)? {
        guard let km = selectedKm else { return nil }
        return elevationData.min(by: { abs($0.km - km) < abs($1.km - km) })
    }

    var totalGain: Double {
        metrics.splits?.compactMap { $0.elevationGain }.reduce(0, +) ?? 0
    }

    var totalLoss: Double {
        metrics.splits?.compactMap { $0.elevationLoss }.reduce(0, +) ?? 0
    }

    var displayData: (value: Double, label: String)? {
        if let selected = selectedData {
            return (value: selected.value, label: String(format: "%@ %.1f", String(localized: "km", comment: "Kilometer abbreviation"), selected.km))
        }
        return nil
    }

    var showTotals: Bool {
        selectedData == nil && (totalGain > 0 || totalLoss > 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Elevation", comment: "Elevation chart title"))
                        .font(.headline)
                        .foregroundStyle(Color.irTextPrimary)

                    if let data = displayData {
                        Text(String(format: "%+.0f %@", data.value, String(localized: "m", comment: "Meters unit abbreviation")))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.green)
                        Text(data.label)
                            .font(.caption)
                            .foregroundStyle(Color.irTextSecondary)
                    } else if showTotals {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(format: "+%.0f %@", totalGain, String(localized: "m", comment: "Meters unit abbreviation")))
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.green)
                                Text(String(localized: "gain", comment: "Elevation gain label"))
                                    .font(.caption2)
                                    .foregroundStyle(Color.irTextSecondary)
                            }
                            if totalLoss > 0 {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(String(format: "-%.0f %@", totalLoss, String(localized: "m", comment: "Meters unit abbreviation")))
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.blue)
                                    Text(String(localized: "loss", comment: "Elevation loss label"))
                                        .font(.caption2)
                                        .foregroundStyle(Color.irTextSecondary)
                                }
                            }
                        }
                    }
                }

                Spacer()

                Image(systemName: "mountain.2.fill")
                    .font(.title2)
                    .foregroundStyle(.green.gradient)
            }

            if elevationData.count < 2 {
                VStack(spacing: 12) {
                    Image(systemName: "mountain.2")
                        .font(.largeTitle)
                        .foregroundStyle(Color.irTextSecondary)
                    Text(String(localized: "No elevation data available", comment: "Empty elevation chart message"))
                        .font(.subheadline)
                        .foregroundStyle(Color.irTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(height: 240)
                .frame(maxWidth: .infinity)
            } else {
                Chart {
                    ForEach(elevationData, id: \.km) { data in
                        AreaMark(
                            x: .value("Km", data.km),
                            y: .value("Elevation", data.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.green.opacity(0.4), .green.opacity(0.1)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("Km", data.km),
                            y: .value("Elevation", data.value)
                        )
                        .foregroundStyle(.green.gradient)
                        .lineStyle(StrokeStyle(lineWidth: 3))
                        .interpolationMethod(.catmullRom)

                        if let selectedData = selectedData, selectedData.km == data.km {
                            PointMark(
                                x: .value("Km", data.km),
                                y: .value("Elevation", data.value)
                            )
                            .foregroundStyle(.green)
                            .symbolSize(200)
                        }
                    }
                }
                .chartXSelection(value: $selectedKm)
                .chartXScale(domain: 0...((metrics.workout.distance ?? 0) / 1000.0))
                .chartYScale(domain: .automatic)
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let km = value.as(Double.self) {
                                Text(String(format: "%.0f", km))
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
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Location Cache Actor

actor LocationCache {
    static let shared = LocationCache()

    private var cache: [String: CacheEntry] = [:]
    private let maxCacheSize = 100 // Limit cache to 100 entries to prevent memory leaks

    private struct CacheEntry {
        let name: String
        let timestamp: Date
    }

    private init() {}

    func getCachedLocation(for coordinate: CLLocationCoordinate2D) -> String? {
        let key = cacheKey(for: coordinate)
        return cache[key]?.name
    }

    func setCachedLocation(_ name: String, for coordinate: CLLocationCoordinate2D) {
        let key = cacheKey(for: coordinate)
        cache[key] = CacheEntry(name: name, timestamp: Date())

        // Evict oldest entries if cache exceeds max size (LRU)
        if cache.count > maxCacheSize {
            let sortedEntries = cache.sorted { $0.value.timestamp < $1.value.timestamp }
            let toRemove = sortedEntries.prefix(cache.count - maxCacheSize)
            for (key, _) in toRemove {
                cache.removeValue(forKey: key)
            }
        }
    }

    func clearCache() {
        cache.removeAll()
    }

    private func cacheKey(for coordinate: CLLocationCoordinate2D) -> String {
        // Round to 3 decimal places (~110m precision) to improve cache hit rate
        let lat = String(format: "%.3f", coordinate.latitude)
        let lon = String(format: "%.3f", coordinate.longitude)
        return "\(lat),\(lon)"
    }
}

// MARK: - Location Text Component

struct LocationText: View {
    let coordinate: CLLocationCoordinate2D
    @State private var locationName: String = String(localized: "location.loading", comment: "Location loading")

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
        // Check cache first
        if let cached = await LocationCache.shared.getCachedLocation(for: coordinate) {
            locationName = cached
            return
        }

        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let unknownLocation = String(localized: "location.unknown", comment: "Unknown location")

        // Check if task was cancelled before making network request
        guard !Task.isCancelled else { return }

        if #available(iOS 26, *) {
            // Use MKReverseGeocodingRequest for iOS 26+
            guard let request = MKReverseGeocodingRequest(location: location) else {
                locationName = unknownLocation
                await LocationCache.shared.setCachedLocation(unknownLocation, for: coordinate)
                return
            }

            do {
                let mapItems = try await request.mapItems

                // Check cancellation after network request
                guard !Task.isCancelled else { return }

                if let mapItem = mapItems.first {
                    // Use addressRepresentations for iOS 26+ (preferred)
                    if let addressRepresentations = mapItem.addressRepresentations {
                        if let cityName = addressRepresentations.cityName {
                            locationName = cityName
                            await LocationCache.shared.setCachedLocation(cityName, for: coordinate)
                            return
                        }
                    }

                    // Fallback to address fullAddress if addressRepresentations not available
                    if let address = mapItem.address {
                        // MKAddress only has fullAddress and shortAddress, parse shortAddress for city
                        if let shortAddress = address.shortAddress {
                            locationName = shortAddress
                            await LocationCache.shared.setCachedLocation(shortAddress, for: coordinate)
                            return
                        }
                        // Last resort: use full address
                        let fullAddress = address.fullAddress
                        if !fullAddress.isEmpty {
                            // Try to extract city from full address (first line usually)
                            let components = fullAddress.components(separatedBy: "\n")
                            let cityName = components.first ?? unknownLocation
                            locationName = cityName
                            await LocationCache.shared.setCachedLocation(cityName, for: coordinate)
                            return
                        }
                    }

                    locationName = unknownLocation
                    await LocationCache.shared.setCachedLocation(unknownLocation, for: coordinate)
                } else {
                    locationName = unknownLocation
                    await LocationCache.shared.setCachedLocation(unknownLocation, for: coordinate)
                }
            } catch is CancellationError {
                // Task was cancelled, don't update state or cache
                return
            } catch {
                // Only update on non-cancellation errors
                guard !Task.isCancelled else { return }
                locationName = unknownLocation
                await LocationCache.shared.setCachedLocation(unknownLocation, for: coordinate)
            }
        } else {
            // Fallback to CLGeocoder for iOS 18.6 - 25.x
            let geocoder = CLGeocoder()

            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(location)

                // Check cancellation after network request
                guard !Task.isCancelled else { return }

                if let placemark = placemarks.first {
                    // Try to get city name from placemark
                    if let city = placemark.locality {
                        locationName = city
                        await LocationCache.shared.setCachedLocation(city, for: coordinate)
                        return
                    }

                    // Fallback to sublocality or administrative area
                    if let sublocality = placemark.subLocality {
                        locationName = sublocality
                        await LocationCache.shared.setCachedLocation(sublocality, for: coordinate)
                        return
                    }

                    if let administrativeArea = placemark.administrativeArea {
                        locationName = administrativeArea
                        await LocationCache.shared.setCachedLocation(administrativeArea, for: coordinate)
                        return
                    }
                }

                locationName = unknownLocation
                await LocationCache.shared.setCachedLocation(unknownLocation, for: coordinate)
            } catch is CancellationError {
                // Task was cancelled, don't update state or cache
                return
            } catch {
                // Only update on non-cancellation errors
                guard !Task.isCancelled else { return }
                locationName = unknownLocation
                await LocationCache.shared.setCachedLocation(unknownLocation, for: coordinate)
            }
        }
    }
}

// MARK: - Tabbed Splits Section (km vs intervals)

enum SplitsTabSelection: String, CaseIterable {
    case byKm = "km"
    case byInterval = "intervals"

    var localizedTitle: String {
        switch self {
        case .byKm:
            return String(localized: "By km", comment: "Splits tab: by kilometer")
        case .byInterval:
            return String(localized: "Intervals", comment: "Splits tab: by interval")
        }
    }
}

struct TabbedSplitsSection: View {
    let splits: [Split]
    let intervals: [WorkoutInterval]?
    @State private var selectedTab: SplitsTabSelection = .byKm

    private var hasIntervals: Bool {
        guard let intervals = intervals else { return false }
        return intervals.count > 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if hasIntervals {
                pulseTabBar
            }

            switch selectedTab {
            case .byKm:
                SplitsByKmContent(splits: splits)
            case .byInterval:
                if let intervals = intervals {
                    IntervalsSplitsContent(intervals: intervals)
                }
            }
        }
    }

    private var pulseTabBar: some View {
        HStack(spacing: 4) {
            ForEach(SplitsTabSelection.allCases, id: \.self) { tab in
                let active = tab == selectedTab
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selectedTab = tab }
                } label: {
                    Text(tab.localizedTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(active ? Color.irTextPrimary : Color.irTextSecondary)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(active ? Color.white.opacity(0.08) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }
}

// MARK: - Splits by Km Content

struct SplitsByKmContent: View {
    let splits: [Split]

    private var best: Split? { splits.min(by: { $0.pace < $1.pace }) }
    private var worst: Split? { splits.max(by: { $0.pace < $1.pace }) }

    private var averagePace: Double {
        let paces = splits.map { $0.pace }
        guard !paces.isEmpty else { return 0 }
        return paces.reduce(0, +) / Double(paces.count)
    }

    private var maxAbsDelta: Double {
        max(0.001, splits.map { abs($0.pace - averagePace) }.max() ?? 0)
    }

    private var variabilityFormatted: String {
        guard let bestPace = splits.map({ $0.pace }).min(),
              let worstPace = splits.map({ $0.pace }).max() else {
            return "—"
        }
        let halfRange = (worstPace - bestPace) / 2
        let m = Int(halfRange)
        let s = Int((halfRange - Double(m)) * 60)
        return String(format: "±%d'%02d\"", m, s)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let best, let worst {
                HStack(spacing: 16) {
                    summaryCol(
                        label: String(localized: "Best", comment: "Best split label"),
                        value: best.paceFormatted,
                        color: Color.irSuccess,
                        sub: "km \(best.kilometer)"
                    )
                    Rectangle().fill(Color.irBorder).frame(width: 0.5, height: 36)
                    summaryCol(
                        label: String(localized: "Slowest", comment: "Slowest split label"),
                        value: worst.paceFormatted,
                        color: Color.irWarning,
                        sub: "km \(worst.kilometer)"
                    )
                    Rectangle().fill(Color.irBorder).frame(width: 0.5, height: 36)
                    summaryCol(
                        label: String(localized: "Variability", comment: "Splits variability label"),
                        value: variabilityFormatted,
                        color: Color.irTextPrimary,
                        sub: nil
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider().background(Color.irBorder)
            }

            ForEach(Array(splits.enumerated()), id: \.element.id) { idx, split in
                if idx > 0 { Divider().background(Color.irBorder) }
                SplitRow(
                    split: split,
                    averagePace: averagePace,
                    maxAbsDelta: maxAbsDelta,
                    isBest: split.id == best?.id,
                    isSlowest: split.id == worst?.id
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }

    private func summaryCol(label: String, value: String, color: Color, sub: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Color.irTextSecondary.opacity(0.7))
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            if let sub {
                Text(sub)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.irTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Intervals Splits Content

struct IntervalsSplitsContent: View {
    let intervals: [WorkoutInterval]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(intervals.enumerated()), id: \.element.id) { idx, interval in
                if idx > 0 { Divider().background(Color.irBorder) }
                IntervalRow(interval: interval)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }
}

// MARK: - Interval Row Component

struct IntervalRow: View {
    let interval: WorkoutInterval

    private var intervalColor: Color {
        switch interval.type {
        case .warmup:
            return .yellow
        case .work:
            return .orange
        case .recovery:
            return .green
        case .cooldown:
            return .blue
        case .unknown:
            return .gray
        }
    }

    /// Compares actual pace with target pace and returns appropriate color
    /// Green = faster than target (good), Red = slower than target (missed)
    private var paceComparisonColor: Color {
        guard let actualPace = interval.pace,
              let targetMin = interval.targetPaceMin else {
            return Color.irTextPrimary
        }
        // Lower pace = faster, so actualPace < targetMin means faster than target
        if actualPace <= targetMin {
            return .green
        } else if let targetMax = interval.targetPaceMax, actualPace <= targetMax {
            return .orange // Within range
        } else {
            return .red // Slower than target
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: type icon + name + duration
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(intervalColor.opacity(0.18))
                        .frame(width: 28, height: 28)
                    Image(systemName: interval.type.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(intervalColor)
                }

                Text("\(interval.index). \(interval.type.localizedName)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.irTextPrimary)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.irTextSecondary.opacity(0.7))
                    Text(interval.durationCompactFormatted)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.irTextPrimary)
                }
            }

            // Metrics grid 2x2
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 12) {
                paceCell
                hrCell
                distanceCell
                powerCell
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var paceCell: some View {
        if let targetPace = interval.targetPaceRangeFormatted {
            VStack(alignment: .leading, spacing: 3) {
                cellLabel(String(localized: "Pace", comment: "Pace label"))
                HStack(spacing: 4) {
                    Image(systemName: "target")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.irTextSecondary.opacity(0.7))
                    Text(targetPace)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.irTextSecondary)
                }
                if let actualPace = interval.paceFormatted {
                    Text(actualPace)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(paceComparisonColor)
                }
            }
        } else if let pace = interval.paceFormatted {
            VStack(alignment: .leading, spacing: 3) {
                cellLabel(String(localized: "Pace", comment: "Pace label"))
                Text(pace)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.irTextPrimary)
            }
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var hrCell: some View {
        if let hr = interval.averageHeartRate {
            VStack(alignment: .leading, spacing: 3) {
                cellLabel(String(localized: "Heart Rate", comment: "HR label"))
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(String(format: "%.0f", hr))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.irTextPrimary)
                        Text(String(localized: "bpm", comment: "Heart rate unit"))
                            .font(.system(size: 9))
                            .foregroundStyle(Color.irTextSecondary.opacity(0.7))
                    }
                }
            }
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var distanceCell: some View {
        if let distance = interval.distanceFormatted {
            VStack(alignment: .leading, spacing: 3) {
                cellLabel(String(localized: "Distance", comment: "Distance label"))
                HStack(spacing: 4) {
                    Image(systemName: "ruler.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.blue)
                    Text(distance)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.irTextPrimary)
                }
            }
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var powerCell: some View {
        if let power = interval.averagePower {
            VStack(alignment: .leading, spacing: 3) {
                cellLabel(String(localized: "Power", comment: "Power label"))
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(String(format: "%.0f", power))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.irTextPrimary)
                        Text(String(localized: "W", comment: "Power unit (Watts)"))
                            .font(.system(size: 9))
                            .foregroundStyle(Color.irTextSecondary.opacity(0.7))
                    }
                }
            }
        } else {
            Color.clear
        }
    }

    private func cellLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(Color.irTextSecondary.opacity(0.7))
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
                sourceVersion: "10.0",
                metadata: nil,
                averageHeartRate: 145,
                maxHeartRate: 165,
                elevationGain: 50,
                hasRoute: false
            )
        )
    }
}
