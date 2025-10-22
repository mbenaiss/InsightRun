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

struct WorkoutDetailView: View {
    let workout: WorkoutModel
    @StateObject private var viewModel: WorkoutDetailViewModel
    @State private var showingAIAssistant = false

    init(workout: WorkoutModel) {
        self.workout = workout
        _viewModel = StateObject(wrappedValue: WorkoutDetailViewModel(workout: workout))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header section
                headerSection

                if viewModel.isLoading {
                    loadingSection
                } else if let error = viewModel.errorMessage {
                    errorSection(error)
                } else if let metrics = viewModel.metrics {
                    // All metrics sections
                    basicMetricsSection(metrics: metrics)

                    if metrics.averageHeartRate != nil {
                        heartRateSection(metrics: metrics)
                    }

                    performanceSection(metrics: metrics)

                    if let splits = metrics.splits, !splits.isEmpty {
                        splitsSection(splits: splits)
                    }

                    if metrics.totalElevationAscent != nil || metrics.totalElevationDescent != nil {
                        elevationSection(metrics: metrics)
                    }

                    advancedMetricsSection(metrics: metrics)

                    if let routePoints = metrics.routePoints, !routePoints.isEmpty {
                        routeSection(routePoints: routePoints)
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
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(.blue.gradient.opacity(0.2))
                    .frame(width: 80, height: 80)

                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.blue.gradient)
            }

            VStack(spacing: 4) {
                Text(workout.startDate, style: .date)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(workout.startDate, style: .time)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical)
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

    // MARK: - Basic Metrics

    private func basicMetricsSection(metrics: WorkoutMetrics) -> some View {
        MetricsCard(title: "Vue d'ensemble") {
            VStack(spacing: 16) {
                MetricRow(
                    icon: "ruler",
                    label: "Distance",
                    value: workout.distanceFormatted,
                    color: .blue
                )

                MetricRow(
                    icon: "clock",
                    label: "Durée",
                    value: workout.durationFormatted,
                    color: .indigo
                )

                if let calories = workout.totalEnergyBurned {
                    MetricRow(
                        icon: "flame.fill",
                        label: "Calories",
                        value: String(format: "%.0f kcal", calories),
                        color: .orange
                    )
                }

                if let pace = metrics.averagePace {
                    MetricRow(
                        icon: "speedometer",
                        label: "Allure moyenne",
                        value: viewModel.formatPace(pace),
                        color: .green
                    )
                }

                if let speed = metrics.averageSpeed {
                    MetricRow(
                        icon: "gauge.with.dots.needle.67percent",
                        label: "Vitesse moyenne",
                        value: viewModel.formatSpeed(speed),
                        color: .cyan
                    )
                }
            }
        }
    }

    // MARK: - Heart Rate Section

    private func heartRateSection(metrics: WorkoutMetrics) -> some View {
        MetricsCard(title: "Fréquence Cardiaque", icon: "heart.fill", iconColor: .red) {
            HStack(spacing: 0) {
                if let avg = metrics.averageHeartRate {
                    HeartRateItem(value: Int(avg), label: "Moyenne", color: .red)
                }

                if metrics.minHeartRate != nil || metrics.maxHeartRate != nil {
                    Divider()
                        .frame(height: 60)
                        .padding(.horizontal)
                }

                if let min = metrics.minHeartRate {
                    HeartRateItem(value: Int(min), label: "Min", color: .blue)
                }

                if let max = metrics.maxHeartRate {
                    HeartRateItem(value: Int(max), label: "Max", color: .orange)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Performance Section

    private func performanceSection(metrics: WorkoutMetrics) -> some View {
        MetricsCard(title: "Performance") {
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
    }

    // MARK: - Splits Section

    private func splitsSection(splits: [Split]) -> some View {
        MetricsCard(title: "Splits par Kilomètre", icon: "list.number", iconColor: .blue) {
            VStack(spacing: 12) {
                // Best/Worst splits summary
                if let best = splits.min(by: { $0.pace < $1.pace }),
                   let worst = splits.max(by: { $0.pace < $1.pace }) {
                    HStack(spacing: 20) {
                        VStack(spacing: 4) {
                            Text("🏆 Meilleur")
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
                            Text("🐌 Plus lent")
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
    }

    // MARK: - Elevation Section

    private func elevationSection(metrics: WorkoutMetrics) -> some View {
        MetricsCard(title: "Élévation", icon: "mountain.2.fill", iconColor: .green) {
            HStack(spacing: 0) {
                if let ascent = metrics.totalElevationAscent {
                    ElevationItem(
                        value: ascent,
                        label: "Montée",
                        icon: "arrow.up.right",
                        color: .green
                    )
                }

                if metrics.totalElevationAscent != nil && metrics.totalElevationDescent != nil {
                    Divider()
                        .frame(height: 60)
                        .padding(.horizontal)
                }

                if let descent = metrics.totalElevationDescent {
                    ElevationItem(
                        value: descent,
                        label: "Descente",
                        icon: "arrow.down.right",
                        color: .blue
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Advanced Metrics Section

    private func advancedMetricsSection(metrics: WorkoutMetrics) -> some View {
        Group {
            if metrics.groundContactTime != nil
                || metrics.verticalOscillation != nil
                || metrics.groundContactTimeBalance != nil {
                MetricsCard(title: "Métriques Avancées", icon: "waveform.path.ecg", iconColor: .indigo) {
                    VStack(spacing: 16) {
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
                                label: "Équilibre temps de contact",
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
                    }
                }
            }
        }
    }

    // MARK: - Route Section

    private func routeSection(routePoints: [RoutePoint]) -> some View {
        MetricsCard(title: "Parcours", icon: "map.fill", iconColor: .green) {
            VStack(spacing: 12) {
                Text("\(routePoints.count) points GPS enregistrés")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                RouteMapView(routePoints: routePoints)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
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

struct HeartRateItem: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Text("\(value)")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(color.gradient)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("bpm")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
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

struct ElevationItem: View {
    let value: Double
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            Text(String(format: "%.0f m", value))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(color.gradient)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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
