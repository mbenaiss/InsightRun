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
        ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.cardPadding) {
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
                            VStack(alignment: .leading, spacing: Spacing.md) {
                                DashboardEyebrow(title: String(localized: "Coach verdict", comment: "Workout detail coach section eyebrow"))
                                aiAnalysisSection
                            }

                            // Compare similar
                            if similarWorkouts.count >= 2 {
                                compareWithSimilarSection
                            }

                            // Parcours
                            if let routePoints = metrics.routePoints, !routePoints.isEmpty {
                                VStack(alignment: .leading, spacing: Spacing.md) {
                                    DashboardEyebrow(title: String(localized: "Route", comment: "Workout detail route section eyebrow"))
                                    routeMapSection(routePoints: routePoints)
                                }
                            }

                            // Évolution (charts)
                            if let splits = metrics.splits, !splits.isEmpty {
                                VStack(alignment: .leading, spacing: Spacing.md) {
                                    DashboardEyebrow(title: String(localized: "Evolution", comment: "Workout detail evolution section eyebrow"))
                                    SwipeableChartsView(metrics: metrics)
                                }
                            }

                            // Performance
                            if hasPerformanceMetrics(metrics) {
                                VStack(alignment: .leading, spacing: Spacing.md) {
                                    DashboardEyebrow(title: String(localized: "Performance", comment: "Performance metrics section title"))
                                    MetricsCard {
                                        performanceContent(metrics: metrics)
                                    }
                                }
                            }

                            // Advanced
                            if hasAdvancedMetrics(metrics) {
                                VStack(alignment: .leading, spacing: Spacing.md) {
                                    DashboardEyebrow(title: String(localized: "Advanced Metrics", comment: "Advanced metrics section title"))
                                    MetricsCard {
                                        advancedMetricsContent(metrics: metrics)
                                    }
                                }
                            }

                            // Splits
                            if let splits = metrics.splits, !splits.isEmpty {
                                VStack(alignment: .leading, spacing: Spacing.md) {
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
                    .padding(.horizontal, Spacing.cardPadding)
                    .padding(.top, Spacing.sm)
                    .padding(.bottom, Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color.irBackgroundApp.ignoresSafeArea())
                .accessibilityIdentifier("workout-detail")
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
        let heroText = workoutHeroText(type: type)
        let eyebrowDate = workout.startDate.formatted(
            .dateTime.day().month(.abbreviated)
        ).uppercased()
        let fullDate = workout.startDate.formatted(
            .dateTime.weekday(.abbreviated).day().month(.wide)
        ).capitalized
        let time = workout.startDate.formatted(date: .omitted, time: .shortened)

        return VStack(alignment: .leading, spacing: Spacing.base) {
            Text("\(String(localized: "workout.detail.hero_eyebrow", defaultValue: "Séance", comment: "Workout detail hero eyebrow").uppercased()) · \(eyebrowDate)")
                .font(IRFont.eyebrow.weight(.heavy))
                .tracking(IRTracking.eyebrow)
                .foregroundStyle(Color.irTextTertiary)
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.xs) {
                    Circle()
                        .fill(type.color)
                        .frame(width: Spacing.xs, height: Spacing.xs)
                    Text("\(type.localizedLabel.uppercased()) · \(Formatters.distance(km: (workout.distance ?? 0) / 1000.0))")
                        .font(IRFont.footnote.weight(.heavy))
                        .tracking(IRTracking.eyebrow)
                        .foregroundStyle(type.color)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text(heroText.title)
                        .font(IRFont.title1.weight(.heavy))
                        .kerning(IRTracking.title1)
                        .foregroundStyle(Color.irTextPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)

                    if let subtitle = heroText.subtitle {
                        Text(subtitle)
                            .font(IRFont.title1.weight(.heavy))
                            .kerning(IRTracking.title1)
                            .foregroundStyle(Color.irTextSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }

                HStack(spacing: Spacing.dash) {
                    if let routePoints = metrics.routePoints,
                       let firstPoint = routePoints.first {
                        LocationText(coordinate: firstPoint.coordinate)
                            .font(IRFont.body)
                            .foregroundStyle(Color.irTextSecondary)
                        Rectangle().fill(Color.irBorder).frame(width: 0.5, height: Spacing.xl)
                    }

                    Text("\(fullDate) · \(time)")
                        .font(IRFont.body)
                        .foregroundStyle(Color.irTextSecondary)

                    if let temperature = metrics.temperature {
                        Rectangle().fill(Color.irBorder).frame(width: 0.5, height: Spacing.xl)
                        HStack(spacing: Spacing.xxs) {
                            Text(verbatim: "\(Formatters.integer(Int(temperature.rounded())))°C")
                            Image(systemName: "cloud.fill")
                                .font(IRFont.body)
                        }
                        .font(IRFont.body)
                        .foregroundStyle(Color.irTextSecondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func workoutHeroText(type: WorkoutSessionType) -> (title: String, subtitle: String?) {
        let title = metadataString(for: [
            "display_name",
            "strava_name",
            "title",
            "workout_name",
            "activity_name",
            "name"
        ]) ?? workoutListTitle

        if let subtitle = metadataString(for: ["subtitle", "notes", "description"]) {
            return (title, subtitle)
        }

        return splitWorkoutHeroTitle(title)
    }

    private var workoutListTitle: String {
        if workout.isIndoor {
            return String(localized: "Treadmill", comment: "Workout title: indoor / treadmill run")
        }
        return String(localized: "Outdoor run", comment: "Workout title: outdoor run")
    }

    private func splitWorkoutHeroTitle(_ title: String) -> (title: String, subtitle: String?) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let splitMarkers = [
            " au bord de ",
            " près de ",
            " autour de ",
            " le long de "
        ]

        for marker in splitMarkers {
            if let range = trimmedTitle.range(of: marker, options: [.caseInsensitive]) {
                let primary = String(trimmedTitle[..<range.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let secondary = String(trimmedTitle[range.lowerBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if !primary.isEmpty && !secondary.isEmpty {
                    return (primary, secondary)
                }
            }
        }

        return (trimmedTitle, nil)
    }

    private func metadataString(for keys: [String]) -> String? {
        for key in keys {
            guard let rawValue = workout.metadata?[key] else { continue }
            let value = String(describing: rawValue).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }
        return nil
    }

    // MARK: - Route Map Section (Pulse-Ring card)

    private func routeMapSection(routePoints: [RoutePoint]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                RouteMapView(routePoints: routePoints)
                    .frame(height: 200)
                    .clipShape(
                        RoundedRectangle(cornerRadius: Radius.md)
                            .inset(by: 0.5)
                    )

                Text(String(format: String(localized: "%lld GPS points", comment: "GPS points count"), routePoints.count))
                    .font(IRFont.microLabel.weight(.semibold))
                    .tracking(IRTracking.microLabel)
                    .foregroundStyle(Color.irTextOnAccent)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xxs)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.xs)
                            .fill(Color.irPrimaryAccent)
                    )
                    .padding(Spacing.md)
            }
        }
        .detailCard()
    }

    // MARK: - Main Metrics Grid (KPI hero card)

    private func mainMetricsGrid(metrics: WorkoutMetrics) -> some View {
        let type = sessionType(metrics: metrics)
        let peers = sameTypePeers(type: type)

        let distanceCell = KPICell(
            label: String(localized: "Distance", comment: "Distance metric"),
            value: shortDistance(workout.distance),
            unit: Formatters.distanceUnitLabel(),
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
            let secondsPerKm = pace * 60.0
            let secondsPerUnit = UnitPreference.current.usesImperial
                ? secondsPerKm / Formatters.kmToMiles
                : secondsPerKm
            return KPICell(
                label: String(localized: "Avg Pace", comment: "Average pace metric"),
                value: Formatters.paceClock(secondsPerUnit),
                unit: Formatters.paceUnitSuffix(),
                mono: true,
                sub: paceVsAvgLabel(currentPace: pace, peers: peers),
                subColor: paceVsAvgColor(currentPace: pace, peers: peers)
            )
        }()
        let hrCell: KPICell? = {
            guard let avgHR = metrics.averageHeartRate else { return nil }
            return KPICell(
                label: String(localized: "Avg HR", comment: "Average heart rate metric"),
                value: Formatters.integer(Int(avgHR.rounded())),
                unit: String(localized: "bpm", comment: "Beats per minute unit"),
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
        .detailCard()
    }

    private func kpiView(cell: KPICell, showsLeftBorder: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(cell.label.uppercased())
                .font(IRFont.microLabel.weight(.bold))
                .tracking(IRTracking.microLabel)
                .foregroundStyle(Color.irTextTertiary)

            HStack(alignment: .lastTextBaseline, spacing: Spacing.xxs) {
                Text(cell.value)
                    .font(IRFont.numMD.weight(.heavy))
                    .kerning(IRTracking.title2)
                    .foregroundStyle(Color.irTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let unit = cell.unit {
                    Text(unit)
                        .font(IRFont.footnote.weight(.bold))
                        .foregroundStyle(Color.irTextTertiary)
                }
            }

            if let sub = cell.sub {
                Text(sub)
                    .font(IRFont.microLabel.weight(.semibold))
                    .foregroundStyle(cell.subColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .padding(.horizontal, Spacing.base)
        .padding(.vertical, Spacing.base)
    }

    private func shortDistance(_ meters: Double?) -> String {
        guard let meters else { return "—" }
        let value = Formatters.distanceValue(km: meters / 1000.0)
        return Formatters.decimal(value, fractionDigits: value < 10 ? 2 : 1)
    }

    private func shortDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
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
        let deltaValue = Formatters.distanceValue(km: (current - avg) / 1000.0)
        let sign = deltaValue >= 0 ? "+" : "−"
        let abs = Swift.abs(deltaValue)
        let formatted = Formatters.decimal(abs, fractionDigits: abs < 10 ? 1 : 0)
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
        let pctLabel = Formatters.percent(Double(pct))
        return "Z\(zone) · \(pctLabel) \(String(localized: "workout.detail.hr_max_suffix", defaultValue: "FCmax", comment: "Heart-rate percentage-of-max suffix"))"
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
        VStack(spacing: Spacing.base) {
            ProgressView()
            Text(String(localized: "Loading data...", comment: "Loading indicator"))
                .font(IRFont.body)
                .foregroundStyle(Color.irTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.xxl)
    }

    // MARK: - Error

    private func errorSection(_ error: String) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(IRFont.title1)
                .foregroundStyle(Color.irWarning)

            Text(error)
                .font(IRFont.body)
                .foregroundStyle(Color.irTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.base)
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
        .padding(.bottom, Spacing.xxs)
    }

    private func performanceContent(metrics: WorkoutMetrics) -> some View {
        var rows: [MetricRowData] = []

        if let minPace = metrics.minPace {
            rows.append(MetricRowData(
                icon: "hare.fill",
                label: String(localized: "Best Pace", comment: "Best pace performance metric"),
                value: viewModel.formatPace(minPace),
                color: Color.irSuccess,
                metricInfoKey: "metric.best_pace",
                currentValue: minPace
            ))
        }
        if let maxSpeed = metrics.maxSpeed {
            rows.append(MetricRowData(
                icon: "bolt.fill",
                label: String(localized: "Max Speed", comment: "Maximum speed performance metric"),
                value: viewModel.formatSpeed(maxSpeed),
                color: Color.irWarning,
                metricInfoKey: "metric.max_speed",
                currentValue: maxSpeed
            ))
        }
        if let cadence = metrics.averageCadence {
            rows.append(MetricRowData(
                icon: "metronome.fill",
                label: String(localized: "Avg Cadence", comment: "Average cadence performance metric"),
                value: viewModel.formatCadence(cadence),
                color: Color.irPrimaryAccent,
                metricInfoKey: "metric.avg_cadence",
                currentValue: cadence
            ))
        }
        if let strideLength = metrics.strideLength {
            rows.append(MetricRowData(
                icon: "figure.walk",
                label: String(localized: "Stride Length", comment: "Stride length performance metric"),
                value: viewModel.formatStrideLength(strideLength),
                color: Color.irPrimaryAccent,
                metricInfoKey: "metric.stride_length",
                currentValue: strideLength
            ))
        }
        if let power = metrics.runningPower {
            rows.append(MetricRowData(
                icon: "bolt.circle.fill",
                label: String(localized: "Power", comment: "Running power performance metric"),
                value: viewModel.formatPower(power),
                color: Color.irWarning,
                metricInfoKey: "metric.running_power",
                currentValue: power
            ))
        }
        if let vo2Max = metrics.vo2Max {
            rows.append(MetricRowData(
                icon: "lungs.fill",
                label: String(localized: "VO2 Max", comment: "VO2 Maximum performance metric"),
                value: "\(Formatters.decimal(vo2Max, fractionDigits: 1)) \(String(localized: "ml/kg/min", comment: "VO2 Max unit"))",
                color: Color.irError,
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
                value: "\(Formatters.integer(Int(gct.rounded()))) \(String(localized: "ms", comment: "Milliseconds unit"))",
                color: Color.irPrimaryAccent,
                metricInfoKey: "metric.ground_contact_time",
                currentValue: gct
            ))
        }
        if let vo = metrics.verticalOscillation {
            rows.append(MetricRowData(
                icon: "arrow.up.and.down",
                label: String(localized: "Vertical Oscillation", comment: "Vertical oscillation advanced metric"),
                value: "\(Formatters.decimal(vo, fractionDigits: 1)) \(String(localized: "cm", comment: "Centimeters unit"))",
                color: Color.irPrimaryAccent,
                metricInfoKey: "metric.vertical_oscillation",
                currentValue: vo
            ))
        }
        if let balance = metrics.groundContactTimeBalance {
            rows.append(MetricRowData(
                icon: "scale.3d",
                label: String(localized: "Contact Balance", comment: "Ground contact time balance advanced metric"),
                value: viewModel.formatPercentage(balance),
                color: Color.irWarning,
                metricInfoKey: "metric.contact_balance",
                currentValue: balance
            ))
        }
        if let efficiency = metrics.runningEfficiency {
            rows.append(MetricRowData(
                icon: "chart.line.uptrend.xyaxis",
                label: String(localized: "Running Efficiency", comment: "Running efficiency advanced metric"),
                value: viewModel.formatPercentage(efficiency),
                color: Color.irSuccess,
                metricInfoKey: "metric.running_efficiency",
                currentValue: efficiency
            ))
        }
        if let steadiness = metrics.walkingSteadiness {
            rows.append(MetricRowData(
                icon: "figure.walk",
                label: String(localized: "Walking Steadiness", comment: "Walking steadiness advanced metric"),
                value: viewModel.formatPercentage(steadiness),
                color: Color.irSuccess,
                metricInfoKey: "metric.walking_steadiness",
                currentValue: steadiness
            ))
        }
        if let asymmetry = metrics.walkingAsymmetry {
            rows.append(MetricRowData(
                icon: "figure.walk.arrival",
                label: String(localized: "Walking Asymmetry", comment: "Walking asymmetry advanced metric"),
                value: viewModel.formatPercentage(asymmetry),
                color: Color.irWarning,
                metricInfoKey: "metric.walking_asymmetry",
                currentValue: asymmetry
            ))
        }
        if let doubleSupport = metrics.doubleSupportPercentage {
            rows.append(MetricRowData(
                icon: "figure.2.arms.open",
                label: String(localized: "Double Support", comment: "Double support percentage advanced metric"),
                value: viewModel.formatPercentage(doubleSupport),
                color: Color.irPrimaryAccent,
                metricInfoKey: "metric.double_support",
                currentValue: doubleSupport
            ))
        }
        if let speed = metrics.walkingSpeed {
            rows.append(MetricRowData(
                icon: "figure.walk.circle",
                label: String(localized: "Walking Speed", comment: "Walking speed advanced metric"),
                value: viewModel.formatSpeed(speed),
                color: Color.irPrimaryAccent,
                metricInfoKey: "metric.walking_speed",
                currentValue: speed
            ))
        }
        if let ascentSpeed = metrics.stairAscentSpeed {
            rows.append(MetricRowData(
                icon: "figure.stairs",
                label: String(localized: "Stair Ascent Speed", comment: "Stair ascent speed advanced metric"),
                value: viewModel.formatSpeed(ascentSpeed),
                color: Color.irPrimaryAccent,
                metricInfoKey: "metric.stair_ascent_speed",
                currentValue: ascentSpeed
            ))
        }
        if let descentSpeed = metrics.stairDescentSpeed {
            rows.append(MetricRowData(
                icon: "figure.stairs",
                label: String(localized: "Stair Descent Speed", comment: "Stair descent speed advanced metric"),
                value: viewModel.formatSpeed(descentSpeed),
                color: Color.irPrimaryAccent,
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
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.xs)
                        .fill(LinearGradient.irAIAccent)
                    Image(systemName: "sparkles")
                        .font(IRFont.eyebrow.weight(.bold))
                        .foregroundStyle(Color.irTextOnAccent)
                }
                .frame(width: 22, height: 22)

                Text(String(localized: "Coach", comment: "AI analysis section title"))
                    .font(IRFont.eyebrow.weight(.semibold))
                    .tracking(IRTracking.eyebrow)
                    .foregroundStyle(Color.irTextPrimary)

                Spacer()

                if let analyzedAt = analysisViewModel.analyzedAt, analysisViewModel.analysisText != nil {
                    Text(analyzedAt, style: .relative)
                        .font(IRFont.microLabel.weight(.semibold))
                        .foregroundStyle(Color.irTextTertiary)
                }
            }

            // Check AI access first (subscription or TestFlight)
            if !revenueCatManager.hasAIAccess {
                // No AI access — show blurred teaser to demonstrate value
                VStack(spacing: Spacing.base) {
                    // Blurred fake analysis preview — text visible but unreadable
                    ZStack {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(String(
                                localized: "Good pace consistency across splits. Your cadence of 172 spm is slightly below optimal — aim for 180 spm to improve efficiency.",
                                comment: "Blurred teaser text for locked AI analysis about pace consistency"
                            ))
                                .font(IRFont.body)
                                .foregroundStyle(Color.irTextPrimary)
                            Text(String(
                                localized: "Recovery heart rate dropped well, indicating solid aerobic fitness. Consider adding tempo intervals to push your threshold.",
                                comment: "Blurred teaser text for locked AI analysis about recovery heart rate"
                            ))
                                .font(IRFont.body)
                                .foregroundStyle(Color.irTextSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Spacing.md)
                        .blur(radius: 6)

                        // Lock overlay
                        VStack(spacing: Spacing.sm) {
                            Image(systemName: "lock.fill")
                                .font(IRFont.title3)
                                .foregroundStyle(Color.irTextSecondary)
                            Text(String(localized: "Unlock your full AI analysis", comment: "AI teaser unlock message"))
                                .font(IRFont.caption.weight(.medium))
                                .foregroundStyle(Color.irTextSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .background(Color.irCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))

                    // CTA button
                    Button {
                        AnalyticsService.shared.track(.aiTeaserSubscribeTapped)
                        showSubscriptionPaywall = true
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "sparkles")
                                .font(IRFont.footnote.weight(.bold))
                            Text(String(localized: "Unlock Full Analysis", comment: "AI teaser subscribe CTA button"))
                                .font(IRFont.body.weight(.bold))
                        }
                        .foregroundStyle(Color.irTextOnAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .background(Color.irPrimaryAccent)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
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
                        .font(IRFont.body)
                        .foregroundStyle(Color.irTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, Spacing.lg)

            } else if analysisViewModel.needsConsent {
                // Consent required - show consent button directly
                VStack(spacing: Spacing.md) {
                    Image(systemName: "hand.raised.fill")
                        .font(IRFont.title2)
                        .foregroundStyle(Color.irPrimaryAccent)

                    Text(String(localized: "AI consent is required to analyze your workouts.", comment: "Error when AI consent is missing"))
                        .font(IRFont.body)
                        .foregroundStyle(Color.irTextSecondary)
                        .multilineTextAlignment(.center)

                    Button {
                        showConsentSheet = true
                    } label: {
                        Label(String(localized: "Review & Accept", comment: "Consent review button"), systemImage: "checkmark.shield")
                            .font(IRFont.body.weight(.bold))
                            .foregroundStyle(Color.irTextOnAccent)
                            .padding(.horizontal, Spacing.base)
                            .padding(.vertical, Spacing.md)
                            .background(Color.irPrimaryAccent)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
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
                VStack(spacing: Spacing.md) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(IRFont.title2)
                        .foregroundStyle(Color.irWarning)

                    Text(error)
                        .font(IRFont.body)
                        .foregroundStyle(Color.irTextSecondary)
                        .multilineTextAlignment(.center)

                    Button {
                        Task {
                            await analysisViewModel.generateAnalysis()
                        }
                    } label: {
                        Label(String(localized: "Retry", comment: "Retry button"), systemImage: "arrow.clockwise")
                            .font(IRFont.body)
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)

            } else if let analysis = analysisViewModel.analysisText {
                VStack(alignment: .leading, spacing: Spacing.md) {
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
                                .font(IRFont.eyebrow.weight(.semibold))
                                .foregroundStyle(Color.irTextSecondary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(String(localized: "Regenerate analysis", comment: "Accessibility label for AI analysis regenerate button"))
                    }
                }

            } else {
                // No analysis yet - show button to generate
                VStack(spacing: Spacing.md) {
                    Text(String(localized: "Get detailed analysis of your performance", comment: "AI analysis prompt"))
                        .font(IRFont.footnote)
                        .foregroundStyle(Color.irTextSecondary)
                        .multilineTextAlignment(.center)

                    Button {
                        Task {
                            await analysisViewModel.loadAnalysis()
                        }
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "sparkles")
                                .font(IRFont.footnote.weight(.bold))
                            Text(String(localized: "Analyze with AI", comment: "Analyze button"))
                                .font(IRFont.footnote.weight(.bold))
                        }
                        .foregroundStyle(Color.irTextOnAccent)
                        .padding(.horizontal, Spacing.base)
                        .padding(.vertical, Spacing.md)
                        .background(Color.irPrimaryAccent)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xxs)
            }
        }
        .padding(Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .detailCard()
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
            HStack(spacing: Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.xs)
                        .fill(Color.irAccentSoft)
                        .frame(width: 32, height: 32)
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(IRFont.bodyEmphasized.weight(.semibold))
                        .foregroundStyle(Color.irPrimaryAccent)
                }

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(String(localized: "Compare with similar", comment: "Button to compare with similar workouts"))
                        .font(IRFont.footnote.weight(.semibold))
                        .foregroundStyle(Color.irTextPrimary)

                    Text(String(format: String(localized: "%lld similar workouts found", comment: "Number of similar workouts found"), similarWorkouts.count))
                        .font(IRFont.eyebrow)
                        .foregroundStyle(Color.irTextSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(IRFont.eyebrow.weight(.bold))
                    .foregroundStyle(Color.irTextTertiary)
            }
            .padding(.horizontal, Spacing.dash)
            .padding(.vertical, Spacing.md)
            .frame(maxWidth: .infinity)
            .detailCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Source Section

    private var sourceSection: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "info.circle")
                .font(IRFont.microLabel)
                .foregroundStyle(Color.irTextTertiary)

            Text(String(localized: "workout.detail.source") + " \(workout.sourceName)")
                .font(IRFont.microLabel)
                .foregroundStyle(Color.irTextTertiary)

            if let version = workout.sourceVersion {
                Text(verbatim: "v\(version)")
                    .font(IRFont.monoSM)
                    .foregroundStyle(Color.irTextTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.sm)
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
                VStack(alignment: .leading, spacing: Spacing.dash) {
                    // Editorial header
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(String(localized: "Metric", comment: "Metric info eyebrow").uppercased())
                            .font(IRFont.eyebrow.weight(.bold))
                            .tracking(IRTracking.eyebrow)
                            .foregroundStyle(Color.irTextTertiary)

                        Text(metricInfo.title)
                            .font(IRFont.numMD.weight(.heavy))
                            .kerning(IRTracking.title2)
                            .foregroundStyle(Color.irTextPrimary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, Spacing.xxs)
                    .padding(.bottom, Spacing.xxs)

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
                            .padding(.horizontal, Spacing.cardPadding)
                            .padding(.vertical, Spacing.base)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .detailCard()
                    } else {
                        Text(metricInfo.recommendedValues)
                            .font(IRFont.body)
                            .lineSpacing(3)
                            .foregroundStyle(Color.irTextPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Spacing.cardPadding)
                            .detailCard()
                    }

                    // Sources
                    DashboardEyebrow(title: String(localized: "Sources", comment: "Metric info sources eyebrow"))
                    Button {
                        showingMedicalSources = true
                    } label: {
                        HStack(spacing: Spacing.md) {
                            ZStack {
                                RoundedRectangle(cornerRadius: Radius.xs)
                                    .fill(Color.irAccentSoft)
                                    .frame(width: 32, height: 32)
                                Image(systemName: "doc.text.fill")
                                    .font(IRFont.footnote.weight(.semibold))
                                    .foregroundStyle(Color.irPrimaryAccent)
                            }
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(String(localized: "View Medical Sources", comment: "Button to view medical sources from metric sheet"))
                                    .font(IRFont.footnote.weight(.semibold))
                                    .foregroundStyle(Color.irTextPrimary)
                                Text(String(localized: "These recommendations are based on published scientific research.", comment: "Metric info medical disclaimer"))
                                    .font(IRFont.eyebrow)
                                    .foregroundStyle(Color.irTextSecondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(IRFont.eyebrow.weight(.bold))
                                .foregroundStyle(Color.irTextTertiary)
                        }
                        .padding(.horizontal, Spacing.dash)
                        .padding(.vertical, Spacing.md)
                        .frame(maxWidth: .infinity)
                        .detailCard()
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Spacing.cardPadding)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xl)
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
                            .font(IRFont.title3)
                            .foregroundStyle(Color.irTextSecondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(String(localized: "Close", comment: "Accessibility label for close button"))
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
            .font(IRFont.body)
            .lineSpacing(3)
            .foregroundStyle(Color.irTextPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.cardPadding)
            .detailCard()
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
                HStack(spacing: Spacing.sm) {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(IRFont.footnote.weight(.semibold))
                            .foregroundStyle(iconColor)
                    }
                    Text(title)
                        .font(IRFont.footnote.weight(.semibold))
                        .foregroundStyle(Color.irTextPrimary)
                }
                .padding(.horizontal, Spacing.cardPadding)
                .padding(.top, Spacing.dash)
                .padding(.bottom, Spacing.xxs)
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .detailCard()
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
        HStack(spacing: Spacing.md) {
            Text(label)
                .font(IRFont.footnote)
                .foregroundStyle(Color.irTextSecondary)

            Spacer()

            Text(value)
                .font(IRFont.body.weight(.bold))
                .foregroundStyle(Color.irTextPrimary)

            if metricInfoKey != nil {
                Image(systemName: "chevron.right")
                    .font(IRFont.microLabel.weight(.bold))
                    .foregroundStyle(Color.irTextTertiary)
            }
        }
        .padding(.horizontal, Spacing.cardPadding)
        .padding(.vertical, Spacing.dash)
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
        HStack(spacing: Spacing.md) {
            Text(String(format: String(localized: "split.km_label", defaultValue: "km %lld", comment: "Split kilometer index label"), split.kilometer))
                .font(IRFont.eyebrow.weight(.semibold))
                .foregroundStyle(Color.irTextTertiary)
                .frame(width: 36, alignment: .leading)

            Text(split.paceFormatted)
                .font(IRFont.monoSM.weight(.bold))
                .foregroundStyle(paceColor)
                .frame(width: 56, alignment: .leading)

            deltaBar
                .frame(height: 16)
                .frame(maxWidth: .infinity)

            if let hr = split.averageHeartRate {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "heart.fill")
                        .font(IRFont.eyebrow)
                        .foregroundStyle(Color.irError)
                    Text(Formatters.integer(Int(hr.rounded())))
                        .font(IRFont.eyebrow.weight(.semibold))
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
                    .fill(Color.irBorder)
                    .frame(height: height)
                    .position(x: width / 2, y: centerY)

                // center axis
                Rectangle()
                    .fill(Color.irTextPrimary.opacity(0.18))
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
        VStack(spacing: Spacing.sm) {
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
            HStack(spacing: Spacing.sm) {
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

// MARK: - Chart Axis Helpers

enum ChartAxis {
    static func kilometerLabel(_ km: Double) -> String {
        Formatters.distance(km: km, fractionDigits: 1)
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
            return (value: selected.value, label: ChartAxis.kilometerLabel(selected.km))
        }
        return nil
    }

    var showMinMax: Bool {
        selectedData == nil && minHeartRate != nil && maxHeartRate != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(String(localized: "Heart Rate", comment: "Heart rate chart title"))
                        .font(IRFont.headline)
                        .foregroundStyle(Color.irTextPrimary)

                    if let data = displayData {
                        Text(Formatters.heartRate(data.value))
                            .font(IRFont.title2.weight(.bold))
                            .foregroundStyle(Color.irError)
                        Text(data.label)
                            .font(IRFont.caption)
                            .foregroundStyle(Color.irTextSecondary)
                    } else if showMinMax, let min = minHeartRate, let max = maxHeartRate {
                        HStack(spacing: Spacing.md) {
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(Formatters.heartRate(min))
                                    .font(IRFont.title3.weight(.semibold))
                                    .foregroundStyle(Color.irError)
                                Text(String(localized: "min", comment: "Minimum label"))
                                    .font(IRFont.microLabel)
                                    .foregroundStyle(Color.irTextSecondary)
                            }
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(Formatters.heartRate(max))
                                    .font(IRFont.title3.weight(.semibold))
                                    .foregroundStyle(Color.irError)
                                Text(String(localized: "max", comment: "Maximum label"))
                                    .font(IRFont.microLabel)
                                    .foregroundStyle(Color.irTextSecondary)
                            }
                        }
                    } else {
                        Text(String(localized: "No data available", comment: "Empty state message"))
                            .font(IRFont.caption)
                            .foregroundStyle(Color.irTextSecondary)
                    }
                }

                Spacer()

                Image(systemName: "heart.fill")
                    .font(IRFont.title2)
                    .foregroundStyle(Color.irError.gradient)
            }

            if heartRateData.isEmpty {
                // No data available
                VStack(spacing: Spacing.md) {
                    Image(systemName: "heart.slash")
                        .font(IRFont.title1)
                        .foregroundStyle(Color.irTextSecondary)
                    Text(String(localized: "No heart rate data available", comment: "Empty HR chart message"))
                        .font(IRFont.body)
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
                        .foregroundStyle(Color.irError.gradient)
                        .lineStyle(StrokeStyle(lineWidth: 3))
                        .interpolationMethod(.catmullRom)

                        AreaMark(
                            x: .value("Km", data.km),
                            y: .value("BPM", data.value)
                        )
                        .foregroundStyle(Color.irError.gradient.opacity(0.2))
                        .interpolationMethod(.catmullRom)

                        if let selectedData = selectedData, selectedData.km == data.km {
                            PointMark(
                                x: .value("Km", data.km),
                                y: .value("BPM", data.value)
                            )
                            .foregroundStyle(Color.irError)
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
                                Text(Formatters.integer(Int(km)))
                                    .font(IRFont.microLabel)
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
        .padding(Spacing.base)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Heart rate evolution chart", comment: "Accessibility label for heart rate chart"))
        .accessibilityValue(heartRateAccessibilityValue)
    }

    private var heartRateAccessibilityValue: String {
        guard let min = minHeartRate, let max = maxHeartRate else {
            return String(localized: "No heart rate data available", comment: "Empty HR chart message")
        }
        return String(
            format: String(localized: "Minimum %1$@, maximum %2$@", comment: "Chart min/max accessibility value"),
            Formatters.heartRate(min),
            Formatters.heartRate(max)
        )
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
            return (value: selected.value, label: ChartAxis.kilometerLabel(selected.km))
        }
        return nil
    }

    var showMinMax: Bool {
        selectedData == nil && minPace != nil && maxPace != nil
    }

    func formatPace(_ pace: Double) -> String {
        Formatters.paceClock(pace * 60.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(String(localized: "workout.detail.pace"))
                        .font(IRFont.headline)
                        .foregroundStyle(Color.irTextPrimary)

                    if let data = displayData {
                        Text(formatPace(data.value))
                            .font(IRFont.title2.weight(.bold))
                            .foregroundStyle(Color.irSuccess)
                        Text(data.label)
                            .font(IRFont.caption)
                            .foregroundStyle(Color.irTextSecondary)
                    } else if showMinMax, let min = minPace, let max = maxPace {
                        HStack(spacing: Spacing.md) {
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(formatPace(min))
                                    .font(IRFont.title3.weight(.semibold))
                                    .foregroundStyle(Color.irSuccess)
                                Text(String(localized: "min", comment: "Minimum label"))
                                    .font(IRFont.microLabel)
                                    .foregroundStyle(Color.irTextSecondary)
                            }
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(formatPace(max))
                                    .font(IRFont.title3.weight(.semibold))
                                    .foregroundStyle(Color.irSuccess)
                                Text(String(localized: "max", comment: "Maximum label"))
                                    .font(IRFont.microLabel)
                                    .foregroundStyle(Color.irTextSecondary)
                            }
                        }
                    }
                }

                Spacer()

                Image(systemName: "speedometer")
                    .font(IRFont.title2)
                    .foregroundStyle(Color.irSuccess.gradient)
            }

            Chart {
                ForEach(paceData, id: \.km) { data in
                    LineMark(
                        x: .value("Km", data.km),
                        y: .value("Pace", data.value)
                    )
                    .foregroundStyle(Color.irSuccess.gradient)
                    .lineStyle(StrokeStyle(lineWidth: 3))
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Km", data.km),
                        y: .value("Pace", data.value)
                    )
                    .foregroundStyle(Color.irSuccess.gradient.opacity(0.2))
                    .interpolationMethod(.catmullRom)

                    if let selectedData = selectedData, selectedData.km == data.km {
                        PointMark(
                            x: .value("Km", data.km),
                            y: .value("Pace", data.value)
                        )
                        .foregroundStyle(Color.irSuccess)
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
                            Text(Formatters.integer(Int(km)))
                                .font(IRFont.microLabel)
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
        .padding(Spacing.base)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Pace evolution chart", comment: "Accessibility label for pace chart"))
        .accessibilityValue(paceAccessibilityValue)
    }

    private var paceAccessibilityValue: String {
        guard let min = minPace, let max = maxPace else {
            return String(localized: "No data available", comment: "Empty state message")
        }
        return String(
            format: String(localized: "Best %1$@, slowest %2$@", comment: "Pace chart min/max accessibility value"),
            Formatters.paceFromMinutesPerKm(min),
            Formatters.paceFromMinutesPerKm(max)
        )
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
            return (value: selected.value, label: ChartAxis.kilometerLabel(selected.km))
        }
        return nil
    }

    var showMinMax: Bool {
        selectedData == nil && minPower != nil && maxPower != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(String(localized: "workout.detail.power"))
                        .font(IRFont.headline)
                        .foregroundStyle(Color.irTextPrimary)

                    if let data = displayData {
                        Text("\(Formatters.integer(Int(data.value.rounded()))) \(String(localized: "W", comment: "Watts unit"))")
                            .font(IRFont.title2.weight(.bold))
                            .foregroundStyle(Color.irWarning)
                        Text(data.label)
                            .font(IRFont.caption)
                            .foregroundStyle(Color.irTextSecondary)
                    } else if showMinMax, let min = minPower, let max = maxPower {
                        HStack(spacing: Spacing.md) {
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text("\(Formatters.integer(Int(min.rounded()))) \(String(localized: "W", comment: "Watts unit"))")
                                    .font(IRFont.title3.weight(.semibold))
                                    .foregroundStyle(Color.irWarning)
                                Text(String(localized: "min", comment: "Minimum label"))
                                    .font(IRFont.microLabel)
                                    .foregroundStyle(Color.irTextSecondary)
                            }
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text("\(Formatters.integer(Int(max.rounded()))) \(String(localized: "W", comment: "Watts unit"))")
                                    .font(IRFont.title3.weight(.semibold))
                                    .foregroundStyle(Color.irWarning)
                                Text(String(localized: "max", comment: "Maximum label"))
                                    .font(IRFont.microLabel)
                                    .foregroundStyle(Color.irTextSecondary)
                            }
                        }
                    }
                }

                Spacer()

                Image(systemName: "bolt.fill")
                    .font(IRFont.title2)
                    .foregroundStyle(Color.irWarning.gradient)
            }

            if powerData.isEmpty {
                // No data available
                VStack(spacing: Spacing.md) {
                    Image(systemName: "bolt.slash")
                        .font(IRFont.title1)
                        .foregroundStyle(Color.irTextSecondary)
                    Text(String(localized: "workout.detail.no_power_data"))
                        .font(IRFont.body)
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
                        .foregroundStyle(Color.irWarning.gradient)
                        .lineStyle(StrokeStyle(lineWidth: 3))
                        .interpolationMethod(hasRealPowerData ? .catmullRom : .linear)

                        AreaMark(
                            x: .value("Km", data.km),
                            y: .value("Power", data.value)
                        )
                        .foregroundStyle(Color.irWarning.gradient.opacity(0.2))
                        .interpolationMethod(hasRealPowerData ? .catmullRom : .linear)

                        if let selectedData = selectedData, selectedData.km == data.km {
                            PointMark(
                                x: .value("Km", data.km),
                                y: .value("Power", data.value)
                            )
                            .foregroundStyle(Color.irWarning)
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
                                Text(Formatters.integer(Int(km)))
                                    .font(IRFont.microLabel)
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
        .padding(Spacing.base)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Power evolution chart", comment: "Accessibility label for power chart"))
        .accessibilityValue(powerAccessibilityValue)
    }

    private var powerAccessibilityValue: String {
        guard let min = minPower, let max = maxPower else {
            return String(localized: "workout.detail.no_power_data")
        }
        return String(
            format: String(localized: "Minimum %1$@, maximum %2$@", comment: "Chart min/max accessibility value"),
            "\(Formatters.integer(Int(min.rounded()))) \(String(localized: "W", comment: "Watts unit"))",
            "\(Formatters.integer(Int(max.rounded()))) \(String(localized: "W", comment: "Watts unit"))"
        )
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
            return (value: selected.value, label: ChartAxis.kilometerLabel(selected.km))
        }
        return nil
    }

    var showTotals: Bool {
        selectedData == nil && (totalGain > 0 || totalLoss > 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(String(localized: "Elevation", comment: "Elevation chart title"))
                        .font(IRFont.headline)
                        .foregroundStyle(Color.irTextPrimary)

                    if let data = displayData {
                        Text("\(data.value >= 0 ? "+" : "−")\(Formatters.elevation(meters: abs(data.value)))")
                            .font(IRFont.title2.weight(.bold))
                            .foregroundStyle(Color.irSuccess)
                        Text(data.label)
                            .font(IRFont.caption)
                            .foregroundStyle(Color.irTextSecondary)
                    } else if showTotals {
                        HStack(spacing: Spacing.md) {
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text("+\(Formatters.elevation(meters: totalGain))")
                                    .font(IRFont.title3.weight(.semibold))
                                    .foregroundStyle(Color.irSuccess)
                                Text(String(localized: "gain", comment: "Elevation gain label"))
                                    .font(IRFont.microLabel)
                                    .foregroundStyle(Color.irTextSecondary)
                            }
                            if totalLoss > 0 {
                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    Text("−\(Formatters.elevation(meters: totalLoss))")
                                        .font(IRFont.title3.weight(.semibold))
                                        .foregroundStyle(Color.irPrimaryAccent)
                                    Text(String(localized: "loss", comment: "Elevation loss label"))
                                        .font(IRFont.microLabel)
                                        .foregroundStyle(Color.irTextSecondary)
                                }
                            }
                        }
                    }
                }

                Spacer()

                Image(systemName: "mountain.2.fill")
                    .font(IRFont.title2)
                    .foregroundStyle(Color.irSuccess.gradient)
            }

            if elevationData.count < 2 {
                VStack(spacing: Spacing.md) {
                    Image(systemName: "mountain.2")
                        .font(IRFont.title1)
                        .foregroundStyle(Color.irTextSecondary)
                    Text(String(localized: "No elevation data available", comment: "Empty elevation chart message"))
                        .font(IRFont.body)
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
                                colors: [Color.irSuccess.opacity(0.4), Color.irSuccess.opacity(0.1)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("Km", data.km),
                            y: .value("Elevation", data.value)
                        )
                        .foregroundStyle(Color.irSuccess.gradient)
                        .lineStyle(StrokeStyle(lineWidth: 3))
                        .interpolationMethod(.catmullRom)

                        if let selectedData = selectedData, selectedData.km == data.km {
                            PointMark(
                                x: .value("Km", data.km),
                                y: .value("Elevation", data.value)
                            )
                            .foregroundStyle(Color.irSuccess)
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
                                Text(Formatters.integer(Int(km)))
                                    .font(IRFont.microLabel)
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
        .padding(Spacing.base)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Elevation profile chart", comment: "Accessibility label for elevation chart"))
        .accessibilityValue(elevationAccessibilityValue)
    }

    private var elevationAccessibilityValue: String {
        guard totalGain > 0 || totalLoss > 0 else {
            return String(localized: "No elevation data available", comment: "Empty elevation chart message")
        }
        return String(
            format: String(localized: "Gain %1$@, loss %2$@", comment: "Elevation chart gain/loss accessibility value"),
            Formatters.elevation(meters: totalGain),
            Formatters.elevation(meters: totalLoss)
        )
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
        HStack(spacing: Spacing.xxs) {
            Image(systemName: "mappin")
                .font(IRFont.body)
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
        VStack(alignment: .leading, spacing: Spacing.md) {
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
        HStack(spacing: Spacing.xxs) {
            ForEach(SplitsTabSelection.allCases, id: \.self) { tab in
                let active = tab == selectedTab
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selectedTab = tab }
                } label: {
                    Text(tab.localizedTitle)
                        .font(IRFont.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .foregroundStyle(active ? Color.irTextPrimary : Color.irTextSecondary)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.xs)
                                .fill(active ? Color.irBorder : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xs)
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
        return "±\(Formatters.paceClock(halfRange * 60.0))"
    }

    var body: some View {
        VStack(spacing: 0) {
            if let best, let worst {
                HStack(spacing: Spacing.base) {
                    summaryCol(
                        label: String(localized: "Best", comment: "Best split label"),
                        value: best.paceFormatted,
                        color: Color.irSuccess,
                        sub: String(format: String(localized: "split.km_label", defaultValue: "km %lld", comment: "Split kilometer index label"), best.kilometer)
                    )
                    Rectangle().fill(Color.irBorder).frame(width: 0.5, height: 36)
                    summaryCol(
                        label: String(localized: "Slowest", comment: "Slowest split label"),
                        value: worst.paceFormatted,
                        color: Color.irWarning,
                        sub: String(format: String(localized: "split.km_label", defaultValue: "km %lld", comment: "Split kilometer index label"), worst.kilometer)
                    )
                    Rectangle().fill(Color.irBorder).frame(width: 0.5, height: 36)
                    summaryCol(
                        label: String(localized: "Variability", comment: "Splits variability label"),
                        value: variabilityFormatted,
                        color: Color.irTextPrimary,
                        sub: nil
                    )
                }
                .padding(.horizontal, Spacing.base)
                .padding(.vertical, Spacing.dash)

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
                .padding(.horizontal, Spacing.base)
                .padding(.vertical, Spacing.md)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .detailCard()
    }

    private func summaryCol(label: String, value: String, color: Color, sub: String?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(label.uppercased())
                .font(IRFont.microLabel)
                .tracking(IRTracking.microLabel)
                .foregroundStyle(Color.irTextTertiary)
            Text(value)
                .font(IRFont.monoLG.weight(.bold))
                .foregroundStyle(color)
            if let sub {
                Text(sub)
                    .font(IRFont.microLabel)
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
        .detailCard()
    }
}

// MARK: - Interval Row Component

struct IntervalRow: View {
    let interval: WorkoutInterval

    private var intervalColor: Color {
        switch interval.type {
        case .warmup:
            return Color.irWarning
        case .work:
            return Color.irWarning
        case .recovery:
            return Color.irSuccess
        case .cooldown:
            return Color.irPrimaryAccent
        case .unknown:
            return Color.irTextTertiary
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
            return Color.irSuccess
        } else if let targetMax = interval.targetPaceMax, actualPace <= targetMax {
            return Color.irWarning // Within range
        } else {
            return Color.irError // Slower than target
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header: type icon + name + duration
            HStack(spacing: Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.xs)
                        .fill(intervalColor.opacity(0.18))
                        .frame(width: 28, height: 28)
                    Image(systemName: interval.type.icon)
                        .font(IRFont.caption.weight(.semibold))
                        .foregroundStyle(intervalColor)
                }

                Text("\(interval.index). \(interval.type.localizedName)")
                    .font(IRFont.bodyEmphasized)
                    .foregroundStyle(Color.irTextPrimary)

                Spacer()

                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "clock")
                        .font(IRFont.microLabel.weight(.semibold))
                        .foregroundStyle(Color.irTextTertiary)
                    Text(interval.durationCompactFormatted)
                        .font(IRFont.monoMD)
                        .foregroundStyle(Color.irTextPrimary)
                }
            }

            // Metrics grid 2x2
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: Spacing.md) {
                paceCell
                hrCell
                distanceCell
                powerCell
            }
        }
        .padding(.horizontal, Spacing.base)
        .padding(.vertical, Spacing.dash)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var paceCell: some View {
        if let targetPace = interval.targetPaceRangeFormatted {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                cellLabel(String(localized: "Pace", comment: "Pace label"))
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "target")
                        .font(IRFont.microLabel)
                        .foregroundStyle(Color.irTextTertiary)
                    Text(targetPace)
                        .font(IRFont.monoSM)
                        .foregroundStyle(Color.irTextSecondary)
                }
                if let actualPace = interval.paceFormatted {
                    Text(actualPace)
                        .font(IRFont.monoMD.weight(.bold))
                        .foregroundStyle(paceComparisonColor)
                }
            }
        } else if let pace = interval.paceFormatted {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                cellLabel(String(localized: "Pace", comment: "Pace label"))
                Text(pace)
                    .font(IRFont.monoMD.weight(.bold))
                    .foregroundStyle(Color.irTextPrimary)
            }
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var hrCell: some View {
        if let hr = interval.averageHeartRate {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                cellLabel(String(localized: "Heart Rate", comment: "HR label"))
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "heart.fill")
                        .font(IRFont.microLabel)
                        .foregroundStyle(Color.irError)
                    HStack(alignment: .lastTextBaseline, spacing: Spacing.xxs) {
                        Text(Formatters.integer(Int(hr.rounded())))
                            .font(IRFont.numXS.weight(.bold))
                            .foregroundStyle(Color.irTextPrimary)
                        Text(String(localized: "bpm", comment: "Heart rate unit"))
                            .font(IRFont.microLabel)
                            .foregroundStyle(Color.irTextTertiary)
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
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                cellLabel(String(localized: "Distance", comment: "Distance label"))
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "ruler.fill")
                        .font(IRFont.microLabel)
                        .foregroundStyle(Color.irPrimaryAccent)
                    Text(distance)
                        .font(IRFont.numXS.weight(.bold))
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
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                cellLabel(String(localized: "Power", comment: "Power label"))
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "bolt.fill")
                        .font(IRFont.microLabel)
                        .foregroundStyle(Color.irWarning)
                    HStack(alignment: .lastTextBaseline, spacing: Spacing.xxs) {
                        Text(Formatters.integer(Int(power.rounded())))
                            .font(IRFont.numXS.weight(.bold))
                            .foregroundStyle(Color.irTextPrimary)
                        Text(String(localized: "W", comment: "Power unit (Watts)"))
                            .font(IRFont.microLabel)
                            .foregroundStyle(Color.irTextTertiary)
                    }
                }
            }
        } else {
            Color.clear
        }
    }

    private func cellLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(IRFont.microLabel)
            .tracking(IRTracking.microLabel)
            .foregroundStyle(Color.irTextTertiary)
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
