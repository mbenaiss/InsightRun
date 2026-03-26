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
                    VStack(spacing: 16) {
                        if viewModel.isLoading {
                            loadingSection
                        } else if let error = viewModel.errorMessage {
                            errorSection(error)
                        } else if let metrics = viewModel.metrics {
                            // Header with date and location
                            headerSection(metrics: metrics)

                            // View on Strava link (if activity comes from Strava and Strava is enabled)
                            if remoteConfig.isFeatureEnabled(.strava), let stravaId = stravaActivityId {
                                ViewOnStravaLink(activityId: stravaId, style: .boldOrange)
                                    .padding(.horizontal)
                            }

                            // Main metrics grid (2x2)
                            mainMetricsGrid(metrics: metrics)

                            // Workout comparison section (before AI)
                            if similarWorkouts.count >= 2 {
                                compareWithSimilarSection
                            }

                            // AI Analysis Section
                            aiAnalysisSection

                            // Route map after AI analysis
                            if let routePoints = metrics.routePoints, !routePoints.isEmpty {
                                routeMapSection(routePoints: routePoints)
                            }

                            // Interactive Charts (HR, Pace, Power)
                            if let splits = metrics.splits, !splits.isEmpty {
                                SwipeableChartsView(metrics: metrics)
                            }

                            // Performance section (no accordion)
                            if hasPerformanceMetrics(metrics) {
                                MetricsCard(
                                    title: String(localized: "Performance", comment: "Performance metrics section title"),
                                    icon: "bolt.fill",
                                    iconColor: .yellow
                                ) {
                                    performanceContent(metrics: metrics)
                                }
                            }

                            // Advanced metrics section (no accordion)
                            if hasAdvancedMetrics(metrics) {
                                MetricsCard(
                                    title: String(localized: "Advanced Metrics", comment: "Advanced metrics section title"),
                                    icon: "waveform.path.ecg",
                                    iconColor: .indigo
                                ) {
                                    advancedMetricsContent(metrics: metrics)
                                }
                            }

                            // Splits section (with accordion and tabs for km/intervals)
                            if let splits = metrics.splits, !splits.isEmpty {
                                TabbedSplitsSection(
                                    splits: splits,
                                    intervals: metrics.intervals
                                )
                            }

                            sourceSection
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
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

    // MARK: - Header Section

    private func headerSection(metrics: WorkoutMetrics) -> some View {
        HStack(alignment: .center) {
            // Date à gauche
            Text(workout.startDate, style: .date)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(Color.irTextPrimary)

            Spacer()

            // Location à droite
            if let routePoints = metrics.routePoints,
               let firstPoint = routePoints.first {
                LocationText(coordinate: firstPoint.coordinate)
                    .font(.callout)
                    .foregroundStyle(Color.irTextSecondary)
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
                    .foregroundStyle(Color.irSuccess.gradient)
                    .font(.headline)

                Text(String(localized: "Route", comment: "Route map section title"))
                    .font(.headline)
                    .foregroundStyle(Color.irTextPrimary)

                Spacer()

                Text(String(format: String(localized: "%lld GPS points", comment: "GPS points count"), routePoints.count))
                    .font(.caption)
                    .foregroundStyle(Color.irTextSecondary)
            }

            RouteMapView(routePoints: routePoints)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding()
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.irBorder.opacity(0.3), radius: 8, y: 4)
    }

    // MARK: - Main Metrics Grid

    private func mainMetricsGrid(metrics: WorkoutMetrics) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            CompactMetricCard(
                icon: "ruler",
                label: String(localized: "Distance", comment: "Distance metric"),
                value: workout.distanceFormatted,
                color: .blue
            )

            CompactMetricCard(
                icon: "clock",
                label: String(localized: "Duration", comment: "Duration metric"),
                value: workout.durationFormatted,
                color: .indigo
            )

            if let pace = metrics.averagePace {
                CompactMetricCard(
                    icon: "speedometer",
                    label: String(localized: "Avg Pace", comment: "Average pace metric"),
                    value: viewModel.formatPace(pace),
                    color: .green
                )
            }

            if let avgHR = metrics.averageHeartRate {
                CompactMetricCard(
                    icon: "heart.fill",
                    label: String(localized: "Avg HR", comment: "Average heart rate metric"),
                    value: viewModel.formatHeartRate(avgHR),
                    color: .red
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

    // MARK: - Content Functions for Accordion Sections

    private func performanceContent(metrics: WorkoutMetrics) -> some View {
        VStack(spacing: 16) {
            if let minPace = metrics.minPace {
                MetricRow(
                    icon: "hare.fill",
                    label: String(localized: "Best Pace", comment: "Best pace performance metric"),
                    value: viewModel.formatPace(minPace),
                    color: .green,
                    metricInfoKey: "metric.best_pace",
                    currentValue: minPace
                )
            }

            if let maxSpeed = metrics.maxSpeed {
                MetricRow(
                    icon: "bolt.fill",
                    label: String(localized: "Max Speed", comment: "Maximum speed performance metric"),
                    value: viewModel.formatSpeed(maxSpeed),
                    color: .yellow,
                    metricInfoKey: "metric.max_speed",
                    currentValue: maxSpeed
                )
            }

            if let cadence = metrics.averageCadence {
                MetricRow(
                    icon: "metronome.fill",
                    label: String(localized: "Avg Cadence", comment: "Average cadence performance metric"),
                    value: viewModel.formatCadence(cadence),
                    color: .indigo,
                    metricInfoKey: "metric.avg_cadence",
                    currentValue: cadence
                )
            }

            if let strideLength = metrics.strideLength {
                MetricRow(
                    icon: "figure.walk",
                    label: String(localized: "Stride Length", comment: "Stride length performance metric"),
                    value: viewModel.formatStrideLength(strideLength),
                    color: .cyan,
                    metricInfoKey: "metric.stride_length",
                    currentValue: strideLength
                )
            }

            if let power = metrics.runningPower {
                MetricRow(
                    icon: "bolt.circle.fill",
                    label: String(localized: "Power", comment: "Running power performance metric"),
                    value: viewModel.formatPower(power),
                    color: .orange,
                    metricInfoKey: "metric.running_power",
                    currentValue: power
                )
            }

            if let vo2Max = metrics.vo2Max {
                MetricRow(
                    icon: "lungs.fill",
                    label: String(localized: "VO2 Max", comment: "VO2 Maximum performance metric"),
                    value: String(format: "%.1f %@", vo2Max, String(localized: "ml/kg/min", comment: "VO2 Max unit")),
                    color: .red,
                    metricInfoKey: "metric.vo2_max",
                    currentValue: vo2Max
                )
            }
        }
    }

    private func advancedMetricsContent(metrics: WorkoutMetrics) -> some View {
        VStack(spacing: 16) {
            // Running biomechanics
            if let gct = metrics.groundContactTime {
                MetricRow(
                    icon: "timer",
                    label: String(localized: "Ground Contact Time", comment: "Ground contact time advanced metric"),
                    value: String(format: "%.0f %@", gct, String(localized: "ms", comment: "Milliseconds unit")),
                    color: .indigo,
                    metricInfoKey: "metric.ground_contact_time",
                    currentValue: gct
                )
            }

            if let vo = metrics.verticalOscillation {
                MetricRow(
                    icon: "arrow.up.and.down",
                    label: String(localized: "Vertical Oscillation", comment: "Vertical oscillation advanced metric"),
                    value: String(format: "%.1f %@", vo, String(localized: "cm", comment: "Centimeters unit")),
                    color: .cyan,
                    metricInfoKey: "metric.vertical_oscillation",
                    currentValue: vo
                )
            }

            if let balance = metrics.groundContactTimeBalance {
                MetricRow(
                    icon: "scale.3d",
                    label: String(localized: "Contact Balance", comment: "Ground contact time balance advanced metric"),
                    value: viewModel.formatPercentage(balance),
                    color: .orange,
                    metricInfoKey: "metric.contact_balance",
                    currentValue: balance
                )
            }

            if let efficiency = metrics.runningEfficiency {
                MetricRow(
                    icon: "chart.line.uptrend.xyaxis",
                    label: String(localized: "Running Efficiency", comment: "Running efficiency advanced metric"),
                    value: viewModel.formatPercentage(efficiency),
                    color: .green,
                    metricInfoKey: "metric.running_efficiency",
                    currentValue: efficiency
                )
            }

            // Walking and mobility metrics
            if let steadiness = metrics.walkingSteadiness {
                MetricRow(
                    icon: "figure.walk",
                    label: String(localized: "Walking Steadiness", comment: "Walking steadiness advanced metric"),
                    value: viewModel.formatPercentage(steadiness),
                    color: .green,
                    metricInfoKey: "metric.walking_steadiness",
                    currentValue: steadiness
                )
            }

            if let asymmetry = metrics.walkingAsymmetry {
                MetricRow(
                    icon: "figure.walk.arrival",
                    label: String(localized: "Walking Asymmetry", comment: "Walking asymmetry advanced metric"),
                    value: viewModel.formatPercentage(asymmetry),
                    color: .orange,
                    metricInfoKey: "metric.walking_asymmetry",
                    currentValue: asymmetry
                )
            }

            if let doubleSupport = metrics.doubleSupportPercentage {
                MetricRow(
                    icon: "figure.2.arms.open",
                    label: String(localized: "Double Support", comment: "Double support percentage advanced metric"),
                    value: viewModel.formatPercentage(doubleSupport),
                    color: .blue,
                    metricInfoKey: "metric.double_support",
                    currentValue: doubleSupport
                )
            }

            if let speed = metrics.walkingSpeed {
                MetricRow(
                    icon: "figure.walk.circle",
                    label: String(localized: "Walking Speed", comment: "Walking speed advanced metric"),
                    value: viewModel.formatSpeed(speed),
                    color: .cyan,
                    metricInfoKey: "metric.walking_speed",
                    currentValue: speed
                )
            }

            if let ascentSpeed = metrics.stairAscentSpeed {
                MetricRow(
                    icon: "figure.stairs",
                    label: String(localized: "Stair Ascent Speed", comment: "Stair ascent speed advanced metric"),
                    value: viewModel.formatSpeed(ascentSpeed),
                    color: .purple,
                    metricInfoKey: "metric.stair_ascent_speed",
                    currentValue: ascentSpeed
                )
            }

            if let descentSpeed = metrics.stairDescentSpeed {
                MetricRow(
                    icon: "figure.stairs",
                    label: String(localized: "Stair Descent Speed", comment: "Stair descent speed advanced metric"),
                    value: viewModel.formatSpeed(descentSpeed),
                    color: .indigo,
                    metricInfoKey: "metric.stair_descent_speed",
                    currentValue: descentSpeed
                )
            }
        }
    }

    // MARK: - AI Analysis Section

    @State private var showSubscriptionPaywall = false
    @State private var showConsentSheet = false
    @State private var hasTrackedTeaser = false

    private var aiAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .font(.title3)

                Text(String(localized: "AI Analysis", comment: "AI analysis section title"))
                    .font(.headline)
                    .foregroundStyle(Color.irTextPrimary)
            }

            // Check AI access first (subscription or TestFlight)
            if !revenueCatManager.hasAIAccess {
                // No AI access — show blurred teaser to demonstrate value
                VStack(spacing: 16) {
                    // Blurred fake analysis preview — text visible but unreadable
                    ZStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Good pace consistency across splits. Your cadence of 172 spm is slightly below optimal — aim for 180 spm to improve efficiency.")
                                .font(.subheadline)
                                .foregroundStyle(Color.irTextPrimary)
                            Text("Recovery heart rate dropped well, indicating solid aerobic fitness. Consider adding tempo intervals to push your threshold.")
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
                        HStack {
                            Image(systemName: "sparkles")
                            Text(String(localized: "Unlock Full Analysis", comment: "AI teaser subscribe CTA button"))
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
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
                .sheet(isPresented: $analysisViewModel.needsIndexation) {
                    HistoricalIndexationSheet()
                }
                .onChange(of: analysisViewModel.needsIndexation) { _, needsIndexation in
                    if !needsIndexation {
                        Task { await analysisViewModel.generateAnalysis() }
                    }
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
                // Analysis available — trigger review prompt on positive experience
                VStack(alignment: .leading, spacing: 12) {
                    MarkdownView(analysis)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onAppear {
                            ReviewManager.shared.recordPositiveAIAnalysis()
                        }

                    HStack {
                        if let analyzedAt = analysisViewModel.analyzedAt {
                            Text(analyzedAt, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(Color.irTextSecondary)
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
                        .tint(Color.irPrimaryAccent)
                    }
                }

            } else {
                // No analysis yet - show button to generate
                VStack(spacing: 12) {
                    Text(String(localized: "Get detailed analysis of your performance", comment: "AI analysis prompt"))
                        .font(.subheadline)
                        .foregroundStyle(Color.irTextSecondary)
                        .multilineTextAlignment(.center)

                    Button {
                        Task {
                            await analysisViewModel.loadAnalysis()
                        }
                    } label: {
                        Label(String(localized: "Analyze with AI", comment: "Analyze button"), systemImage: "sparkles")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.irPrimaryAccent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        }
        .padding()
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.irBorder.opacity(0.3), radius: 8, y: 4)
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
            HStack {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.title3)
                    .foregroundStyle(Color.irPrimaryAccent.gradient)

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Compare with similar", comment: "Button to compare with similar workouts"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.irTextPrimary)

                    Text(String(localized: "\(similarWorkouts.count) similar workouts found", comment: "Number of similar workouts found"))
                        .font(.caption)
                        .foregroundStyle(Color.irTextSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.irTextSecondary)
            }
            .padding()
            .background(Color.irCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.irShadow, radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Source Section

    private var sourceSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(Color.irTextSecondary)

                Text(String(localized: "workout.detail.source") + " \(workout.sourceName)")
                    .font(.caption)
                    .foregroundStyle(Color.irTextSecondary)

                if let version = workout.sourceVersion {
                    Text(verbatim: "v\(version)")
                        .font(.caption2)
                        .foregroundStyle(Color.irTextSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

// MARK: - Supporting Components

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

// MARK: - Metric Info Sheet

struct MetricInfoSheet: View {
    let metricInfo: MetricInfo
    @Environment(\.dismiss) private var dismiss
    @State private var showingMedicalSources = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header with metric title badge
                    VStack(spacing: 12) {
                        Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .cyan],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .padding(.top, 8)

                        Text(metricInfo.title)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.irTextPrimary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 8)

                    // Description Card
                    InfoCard(
                        icon: "info.circle.fill",
                        iconColor: .blue,
                        title: String(localized: "metric.info.what", comment: "What is this metric?"),
                        content: metricInfo.description
                    )

                    // Usage Card
                    InfoCard(
                        icon: "lightbulb.fill",
                        iconColor: .orange,
                        title: String(localized: "metric.info.usage", comment: "How is it used?"),
                        content: metricInfo.usage
                    )

                    // Recommended Values - Visualization or Text
                    if let rangeModel = MetricRanges.getRangeModel(for: metricInfo.key) {
                        // Use visual range component when available
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color.green.opacity(0.15))
                                        .frame(width: 36, height: 36)

                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(.green)
                                }

                                Text(String(localized: "metric.info.recommended", comment: "Recommended values"))
                                    .font(.headline)
                                    .foregroundStyle(Color.irTextPrimary)

                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 16)

                            MetricRangeVisualization(
                                rangeModel: rangeModel,
                                currentValue: metricInfo.currentValue
                            )
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.irCardBackground)
                                .shadow(color: Color.irBorder.opacity(0.3), radius: 8, y: 2)
                        )
                    } else {
                        // Fallback to text card when no visual range available
                        InfoCard(
                            icon: "checkmark.seal.fill",
                            iconColor: .green,
                            title: String(localized: "metric.info.recommended", comment: "Recommended values"),
                            content: metricInfo.recommendedValues
                        )
                    }

                    // Medical Sources Disclaimer
                    VStack(alignment: .leading, spacing: 12) {
                        Text(String(localized: "These recommendations are based on published scientific research.", comment: "Metric info medical disclaimer"))
                            .font(.caption)
                            .foregroundStyle(Color.irTextSecondary)
                            .lineSpacing(4)

                        Button {
                            showingMedicalSources = true
                        } label: {
                            HStack {
                                Image(systemName: "doc.text.fill")
                                    .font(.caption)
                                Text(String(localized: "View Medical Sources", comment: "Button to view medical sources from metric sheet"))
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .foregroundStyle(Color.irPrimaryAccent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.irPrimaryAccent.opacity(0.1))
                            )
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.irCardBackground)
                            .shadow(color: Color.irBorder.opacity(0.3), radius: 8, y: 2)
                    )
                }
                .padding()
                .padding(.bottom, 20)
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
                    .foregroundStyle(Color.irTextPrimary)
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.irBorder.opacity(0.3), radius: 10, y: 5)
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
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color.gradient)
                .frame(width: 28)

            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.irTextSecondary)

            Spacer()

            Text(value)
                .font(.headline)
                .foregroundStyle(Color.irTextPrimary)

            if let metricInfoKey = metricInfoKey {
                Button {
                    showingInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(Color.irTextSecondary)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showingInfo) {
                    MetricInfoSheet(metricInfo: MetricInfo(key: metricInfoKey, currentValue: currentValue))
                }
            }
        }
    }
}

struct SplitRow: View {
    let split: Split

    var body: some View {
        HStack(spacing: 8) {
            // Kilometer number and distance
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "km", comment: "Kilometer abbreviation") + " \(split.kilometer)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.irTextSecondary)

                // Show actual distance if different from 1000m
                let distanceKm = split.distance / 1000.0
                if abs(distanceKm - 1.0) > 0.01 {
                    Text(String(format: "%.2f %@", distanceKm, String(localized: "km", comment: "Kilometer abbreviation")))
                        .font(.caption2)
                        .foregroundStyle(Color.irTextSecondary)
                }
            }
            .frame(width: 60, alignment: .leading)

            // Pace - 1/3
            Text(split.paceFormatted)
                .font(.headline)
                .foregroundStyle(Color.irTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Heart Rate - 1/3
            if let hr = split.averageHeartRate {
                HStack(spacing: 3) {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                    Text(String(format: "%.0f %@", hr, String(localized: "bpm", comment: "Beats per minute unit")))
                        .font(.subheadline)
                        .foregroundStyle(Color.irTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer()
                    .frame(maxWidth: .infinity)
            }

            // Elevation indicators - 1/3
            HStack(spacing: 4) {
                if let gain = split.elevationGain, gain > 0 {
                    Label(String(format: "↗%.0f%@", gain, String(localized: "m", comment: "Meters unit abbreviation")), systemImage: "")
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .labelStyle(.titleOnly)
                }

                if let loss = split.elevationLoss, loss > 0 {
                    Label(String(format: "↘%.0f%@", loss, String(localized: "m", comment: "Meters unit abbreviation")), systemImage: "")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                        .labelStyle(.titleOnly)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
    @State private var isExpanded = false
    @State private var selectedTab: SplitsTabSelection = .byKm

    private var hasIntervals: Bool {
        guard let intervals = intervals else { return false }
        return intervals.count > 1
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
                    Image(systemName: "list.number")
                        .foregroundStyle(Color.blue.gradient)
                        .font(.title3)

                    Text(String(localized: "Splits", comment: "Splits section title"))
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
                VStack(spacing: 12) {
                    // Show tabs only if intervals exist
                    if hasIntervals {
                        Picker("", selection: $selectedTab) {
                            ForEach(SplitsTabSelection.allCases, id: \.self) { tab in
                                Text(tab.localizedTitle).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // Content based on selected tab
                    switch selectedTab {
                    case .byKm:
                        SplitsByKmContent(splits: splits)
                    case .byInterval:
                        if let intervals = intervals {
                            IntervalsSplitsContent(intervals: intervals)
                        }
                    }
                }
                .padding()
                .background(Color.irCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - Splits by Km Content

struct SplitsByKmContent: View {
    let splits: [Split]

    var body: some View {
        VStack(spacing: 12) {
            // Best/Worst splits summary
            if let best = splits.min(by: { $0.pace < $1.pace }),
               let worst = splits.max(by: { $0.pace < $1.pace }) {
                HStack(spacing: 20) {
                    VStack(spacing: 4) {
                        Text(String(localized: "Best", comment: "Best split label"))
                            .font(.caption)
                            .foregroundStyle(Color.irTextSecondary)
                        Text(best.paceFormatted)
                            .font(.headline)
                            .foregroundStyle(Color.irSuccess)
                        Text(String(localized: "km", comment: "Kilometer abbreviation") + " \(best.kilometer)")
                            .font(.caption2)
                            .foregroundStyle(Color.irTextSecondary)
                    }
                    .frame(maxWidth: .infinity)

                    Divider()
                        .frame(height: 50)

                    VStack(spacing: 4) {
                        Text(String(localized: "Slowest", comment: "Slowest split label"))
                            .font(.caption)
                            .foregroundStyle(Color.irTextSecondary)
                        Text(worst.paceFormatted)
                            .font(.headline)
                            .foregroundStyle(Color.irWarning)
                        Text(String(localized: "km", comment: "Kilometer abbreviation") + " \(worst.kilometer)")
                            .font(.caption2)
                            .foregroundStyle(Color.irTextSecondary)
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
}

// MARK: - Intervals Splits Content

struct IntervalsSplitsContent: View {
    let intervals: [WorkoutInterval]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(intervals) { interval in
                IntervalRow(interval: interval)
            }
        }
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
        HStack(spacing: 0) {
            // Left color strip
            Rectangle()
                .fill(intervalColor)
                .frame(width: 5)
                .frame(maxHeight: .infinity)

            VStack(spacing: 10) {
                // 1. Header: Type, Index, Time
                HStack {
                    // Type Icon & Name
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(intervalColor.opacity(0.15))
                                .frame(width: 30, height: 30)
                            Image(systemName: interval.type.icon)
                                .font(.caption.bold())
                                .foregroundStyle(intervalColor)
                        }

                        Text("\(interval.index). \(interval.type.localizedName)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.irTextPrimary)
                    }

                    Spacer()

                    // Duration
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption)
                            .foregroundStyle(Color.irTextSecondary)
                        Text(interval.durationCompactFormatted)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.irTextPrimary)
                            .monospacedDigit()
                    }
                }

                Divider()

                // 2. Metrics Grid
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 16) {
                    // Cell 1: Pace
                    if let targetPace = interval.targetPaceRangeFormatted {
                        // Target vs Actual
                        VStack(alignment: .leading, spacing: 3) {
                            Text(String(localized: "Pace", comment: "Pace label"))
                                .font(.caption2)
                                .foregroundStyle(Color.irTextSecondary)
                                .textCase(.uppercase)
                            
                            HStack(spacing: 4) {
                                Image(systemName: "target")
                                    .font(.caption2)
                                    .foregroundStyle(Color.irTextSecondary)
                                Text(targetPace)
                                    .font(.caption)
                                    .foregroundStyle(Color.irTextSecondary)
                            }
                            
                            if let actualPace = interval.paceFormatted {
                                HStack(spacing: 4) {
                                    Image(systemName: "speedometer")
                                        .font(.caption2)
                                        .foregroundStyle(paceComparisonColor)
                                    Text(actualPace)
                                        .font(.callout)
                                        .fontWeight(.bold)
                                        .foregroundStyle(paceComparisonColor)
                                        .monospacedDigit()
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else if let pace = interval.paceFormatted {
                        // Just Pace
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "Pace", comment: "Pace label"))
                                .font(.caption2)
                                .foregroundStyle(Color.irTextSecondary)
                                .textCase(.uppercase)
                            
                            Text(pace)
                                .font(.callout)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.irTextPrimary)
                                .monospacedDigit()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                         Color.clear
                    }

                    // Cell 2: Heart Rate
                    if let hr = interval.averageHeartRate {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "Heart Rate", comment: "HR label"))
                                .font(.caption2)
                                .foregroundStyle(Color.irTextSecondary)
                                .textCase(.uppercase)
                            
                            HStack(spacing: 4) {
                                Image(systemName: "heart.fill")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                Text(String(format: "%.0f", hr))
                                    .font(.callout)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.irTextPrimary)
                                    .monospacedDigit()
                                Text(String(localized: "bpm", comment: "Heart rate unit"))
                                    .font(.caption2)
                                    .foregroundStyle(Color.irTextSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Color.clear
                    }

                    // Cell 3: Distance
                    if let distance = interval.distanceFormatted {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "Distance", comment: "Distance label"))
                                .font(.caption2)
                                .foregroundStyle(Color.irTextSecondary)
                                .textCase(.uppercase)
                            
                            HStack(spacing: 4) {
                                Image(systemName: "ruler.fill")
                                    .font(.caption)
                                    .foregroundStyle(Color.blue)
                                Text(distance)
                                    .font(.callout)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.irTextPrimary)
                                    .monospacedDigit()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                         Color.clear
                    }

                    // Cell 4: Power
                    if let power = interval.averagePower {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "Power", comment: "Power label"))
                                .font(.caption2)
                                .foregroundStyle(Color.irTextSecondary)
                                .textCase(.uppercase)
                            
                            HStack(spacing: 4) {
                                Image(systemName: "bolt.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                Text(String(format: "%.0f", power))
                                    .font(.callout)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.irTextPrimary)
                                    .monospacedDigit()
                                Text(String(localized: "W", comment: "Power unit (Watts)"))
                                    .font(.caption2)
                                    .foregroundStyle(Color.irTextSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                         Color.clear
                    }
                }
            }
            .padding(12)
        }
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.irBorder.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: Color.irShadow, radius: 3, x: 0, y: 1)
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
