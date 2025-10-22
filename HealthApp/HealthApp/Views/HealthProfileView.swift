//
//  HealthProfileView.swift
//  HealthApp
//
//  View for displaying health profile and body metrics
//

import SwiftUI

struct HealthProfileView: View {
    @StateObject private var viewModel = HealthProfileViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                if viewModel.isLoading {
                    loadingView
                } else if let errorMessage = viewModel.errorMessage {
                    errorView(errorMessage)
                } else if let profile = viewModel.healthProfile {
                    profileContent(profile)
                } else {
                    emptyView
                }
            }
            .navigationTitle("Profil de Santé")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await viewModel.refresh()
            }
            .task {
                await viewModel.loadHealthProfile()
            }
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Chargement...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.orange.gradient)

            VStack(spacing: 12) {
                Text("Erreur")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button("Réessayer") {
                Task {
                    await viewModel.refresh()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .padding(.top, 100)
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue.gradient)

            VStack(spacing: 12) {
                Text("Aucune Donnée")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Les données de santé ne sont pas disponibles.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Text("Tip: Activez les permissions dans Réglages → Confidentialité → Santé → healthapp")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
            }
        }
        .padding()
        .padding(.top, 100)
    }

    // MARK: - Profile Content

    @ViewBuilder
    private func profileContent(_ profile: HealthProfile) -> some View {
        VStack(spacing: 20) {
            // User Info
            userInfoSection(profile)
                .padding(.horizontal)
                .padding(.top)

            // Body Metrics
            bodyMetricsSection(profile)
                .padding(.horizontal)

            // Vital Signs
            vitalSignsSection(profile)
                .padding(.horizontal)

            // Daily Activity
            dailyActivitySection(profile)
                .padding(.horizontal)

            // Cross-training
            crossTrainingSection(profile)
                .padding(.horizontal)
        }
        .padding(.bottom, 20)
    }

    // MARK: - User Info Section

    private func userInfoSection(_ profile: HealthProfile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Informations", systemImage: "person.fill")
                .font(.headline)

            VStack(spacing: 12) {
                InfoRow(label: "Âge", value: profile.formattedAge)
                InfoRow(label: "Sexe", value: profile.biologicalSexString)
            }
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
    }

    // MARK: - Body Metrics Section

    @ViewBuilder
    private func bodyMetricsSection(_ profile: HealthProfile) -> some View {
        let hasBodyMass = profile.bodyMass != nil
        let hasBodyFat = profile.bodyFatPercentage != nil
        let hasLeanMass = profile.leanBodyMass != nil

        // Only show section if at least one metric is available
        if hasBodyMass || hasBodyFat || hasLeanMass {
            VStack(alignment: .leading, spacing: 16) {
                Label("Métriques Corporelles", systemImage: "figure.stand")
                    .font(.headline)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    if hasBodyMass {
                        MetricCard(
                            icon: "scalemass.fill",
                            iconColor: .blue,
                            title: "Poids",
                            value: profile.formattedBodyMass,
                            dateString: profile.formattedDate(profile.bodyMassDate)
                        )
                    }

                    if hasBodyFat {
                        MetricCard(
                            icon: "percent",
                            iconColor: .orange,
                            title: "Masse grasse",
                            value: profile.formattedBodyFat,
                            dateString: profile.formattedDate(profile.bodyFatDate)
                        )
                    }

                    if hasLeanMass {
                        MetricCard(
                            icon: "figure.arms.open",
                            iconColor: .green,
                            title: "Masse maigre",
                            value: profile.formattedLeanMass,
                            dateString: profile.formattedDate(profile.leanBodyMassDate)
                        )
                    }
                }
            }
            .padding(20)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
        }
    }

    // MARK: - Vital Signs Section

    @ViewBuilder
    private func vitalSignsSection(_ profile: HealthProfile) -> some View {
        let hasSpO2 = profile.oxygenSaturation != nil
        let hasTemp = profile.bodyTemperature != nil
        let hasRespRate = profile.respiratoryRate != nil

        // Only show section if at least one metric is available
        if hasSpO2 || hasTemp || hasRespRate {
            VStack(alignment: .leading, spacing: 16) {
                Label("Signes Vitaux", systemImage: "heart.text.square.fill")
                    .font(.headline)

                VStack(spacing: 12) {
                    if hasSpO2 {
                        HealthMetricRowWithDate(
                            icon: "drop.fill",
                            iconColor: .red,
                            title: "Saturation O2",
                            value: profile.formattedSpO2,
                            dateString: profile.formattedDate(profile.oxygenSaturationDate)
                        )
                    }

                    if hasTemp {
                        HealthMetricRowWithDate(
                            icon: "thermometer",
                            iconColor: .orange,
                            title: "Température",
                            value: profile.formattedTemperature,
                            dateString: profile.formattedDate(profile.bodyTemperatureDate)
                        )
                    }

                    if hasRespRate {
                        HealthMetricRowWithDate(
                            icon: "wind",
                            iconColor: .cyan,
                            title: "Fréquence respiratoire",
                            value: profile.formattedRespiratoryRate,
                            dateString: profile.formattedDate(profile.respiratoryRateDate)
                        )
                    }
                }
            }
            .padding(20)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
        }
    }

    // MARK: - Daily Activity Section

    private func dailyActivitySection(_ profile: HealthProfile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Activité Quotidienne", systemImage: "figure.run")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                MetricCard(
                    icon: "flame.fill",
                    iconColor: .red,
                    title: "Exercice",
                    value: profile.formattedExerciseTime
                )

                MetricCard(
                    icon: "figure.stand",
                    iconColor: .blue,
                    title: "Debout",
                    value: profile.formattedStandTime
                )

                if let flights = profile.flightsClimbed {
                    MetricCard(
                        icon: "figure.stairs",
                        iconColor: .purple,
                        title: "Étages",
                        value: "\(flights)"
                    )
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
    }

    // MARK: - Cross-training Section

    private func crossTrainingSection(_ profile: HealthProfile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Entraînement Croisé (7 jours)", systemImage: "figure.mixed.cardio")
                .font(.headline)

            VStack(spacing: 12) {
                HealthMetricRow(
                    icon: "bicycle",
                    iconColor: .orange,
                    title: "Vélo",
                    value: profile.formattedCyclingDistance
                )

                HealthMetricRow(
                    icon: "figure.pool.swim",
                    iconColor: .blue,
                    title: "Natation",
                    value: profile.formattedSwimmingDistance
                )
            }
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
    }
}

// MARK: - Info Row Component

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer()

            Text(value)
                .font(.body)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Health Metric Row With Date Component

struct HealthMetricRowWithDate: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    let dateString: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(iconColor.gradient)
                .frame(width: 32)

            Text(title)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                if let dateString = dateString {
                    Text(dateString)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

// MARK: - Metric Card Component

struct MetricCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    let dateString: String?

    init(icon: String, iconColor: Color, title: String, value: String, dateString: String? = nil) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.value = value
        self.dateString = dateString
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(iconColor.gradient)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                if let dateString = dateString {
                    Text(dateString)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    HealthProfileView()
}
