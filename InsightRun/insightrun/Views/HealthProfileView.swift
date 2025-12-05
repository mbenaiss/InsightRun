//
//  HealthProfileView.swift
//  InsightRun
//
//  View for displaying health profile and body metrics
//

import SwiftUI

struct HealthProfileView: View {
    @StateObject private var viewModel = HealthProfileViewModel()
    @State private var showSettings = false
    @Environment(ThemeManager.self) private var themeManager
    @EnvironmentObject private var revenueCatManager: RevenueCatManager

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
            .navigationTitle(String(localized: "Health Profile", comment: "Navigation title for health profile view"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environment(themeManager)
                    .environmentObject(revenueCatManager)
            }
            .refreshable {
                await viewModel.refresh()
            }
            .task {
                await viewModel.loadHealthProfile()
                AnalyticsService.shared.trackHealthProfileViewed()
            }
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text(String(localized: "Loading...", comment: "Loading indicator text"))
                .font(.subheadline)
                .foregroundStyle(Color.irTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 80))
                .foregroundStyle(Color.irWarning.gradient)

            VStack(spacing: 12) {
                Text(String(localized: "Error", comment: "Error state title"))
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.irTextPrimary)

                Text(message)
                    .font(.body)
                    .foregroundStyle(Color.irTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button(String(localized: "Retry", comment: "Button to retry loading data")) {
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
                .foregroundStyle(Color.irPrimaryAccent.gradient)

            VStack(spacing: 12) {
                Text(String(localized: "No Data", comment: "Empty state title when no health data available"))
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.irTextPrimary)

                Text(String(localized: "Health data is not available.", comment: "Empty state message for health data"))
                    .font(.body)
                    .foregroundStyle(Color.irTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Text(String(localized: "Tip: Enable permissions in Settings → Privacy → Health → Insight Run", comment: "Tip about enabling HealthKit permissions"))
                    .font(.caption)
                    .foregroundStyle(Color.irTextSecondary)
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
            Label(String(localized: "Information", comment: "Section header for user information"), systemImage: "person.fill")
                .font(.headline)
                .foregroundStyle(Color.irTextPrimary)

            VStack(spacing: 12) {
                InfoRow(label: String(localized: "Age", comment: "Label for age"), value: profile.formattedAge)
                InfoRow(label: String(localized: "Sex", comment: "Label for biological sex"), value: profile.biologicalSexString)
            }
        }
        .padding(20)
        .background(Color.irCardBackground)
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
                Label(String(localized: "Body Metrics", comment: "Section header for body composition metrics"), systemImage: "figure.stand")
                    .font(.headline)
                    .foregroundStyle(Color.irTextPrimary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    if hasBodyMass {
                        MetricCard(
                            icon: "scalemass.fill",
                            iconColor: .blue,
                            title: String(localized: "Weight", comment: "Label for body weight"),
                            value: profile.formattedBodyMass,
                            dateString: profile.formattedDate(profile.bodyMassDate)
                        )
                    }

                    if hasBodyFat {
                        MetricCard(
                            icon: "percent",
                            iconColor: .orange,
                            title: String(localized: "Body fat", comment: "Label for body fat percentage"),
                            value: profile.formattedBodyFat,
                            dateString: profile.formattedDate(profile.bodyFatDate)
                        )
                    }

                    if hasLeanMass {
                        MetricCard(
                            icon: "figure.arms.open",
                            iconColor: .green,
                            title: String(localized: "Lean mass", comment: "Label for lean body mass"),
                            value: profile.formattedLeanMass,
                            dateString: profile.formattedDate(profile.leanBodyMassDate)
                        )
                    }
                }
            }
            .padding(20)
            .background(Color.irCardBackground)
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
                Label(String(localized: "Vital Signs", comment: "Section header for vital signs"), systemImage: "heart.text.square.fill")
                    .font(.headline)
                    .foregroundStyle(Color.irTextPrimary)

                VStack(spacing: 12) {
                    if hasSpO2 {
                        HealthMetricRowWithDate(
                            icon: "drop.fill",
                            iconColor: .red,
                            title: String(localized: "Oxygen saturation", comment: "Label for blood oxygen saturation"),
                            value: profile.formattedSpO2,
                            dateString: profile.formattedDate(profile.oxygenSaturationDate)
                        )
                    }

                    if hasTemp {
                        HealthMetricRowWithDate(
                            icon: "thermometer",
                            iconColor: .orange,
                            title: String(localized: "Temperature", comment: "Label for body temperature"),
                            value: profile.formattedTemperature,
                            dateString: profile.formattedDate(profile.bodyTemperatureDate)
                        )
                    }

                    if hasRespRate {
                        HealthMetricRowWithDate(
                            icon: "wind",
                            iconColor: .cyan,
                            title: String(localized: "Respiratory rate", comment: "Label for respiratory rate"),
                            value: profile.formattedRespiratoryRate,
                            dateString: profile.formattedDate(profile.respiratoryRateDate)
                        )
                    }
                }
            }
            .padding(20)
            .background(Color.irCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
        }
    }

    // MARK: - Daily Activity Section

    private func dailyActivitySection(_ profile: HealthProfile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(String(localized: "Daily Activity", comment: "Section header for daily activity metrics"), systemImage: "figure.run")
                .font(.headline)
                .foregroundStyle(Color.irTextPrimary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                MetricCard(
                    icon: "flame.fill",
                    iconColor: .red,
                    title: String(localized: "Exercise", comment: "Label for exercise time"),
                    value: profile.formattedExerciseTime
                )

                MetricCard(
                    icon: "figure.stand",
                    iconColor: .blue,
                    title: String(localized: "Stand", comment: "Label for stand time"),
                    value: profile.formattedStandTime
                )

                if let flights = profile.flightsClimbed {
                    MetricCard(
                        icon: "figure.stairs",
                        iconColor: .purple,
                        title: String(localized: "Floors", comment: "Label for flights of stairs climbed"),
                        value: "\(flights)"
                    )
                }
            }
        }
        .padding(20)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
    }

    // MARK: - Cross-training Section

    private func crossTrainingSection(_ profile: HealthProfile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(String(localized: "Cross-training (7 days)", comment: "Section header for cross-training activities over 7 days"), systemImage: "figure.mixed.cardio")
                .font(.headline)
                .foregroundStyle(Color.irTextPrimary)

            VStack(spacing: 12) {
                HealthMetricRow(
                    icon: "bicycle",
                    iconColor: .orange,
                    title: String(localized: "Cycling", comment: "Label for cycling distance"),
                    value: profile.formattedCyclingDistance
                )

                HealthMetricRow(
                    icon: "figure.pool.swim",
                    iconColor: .blue,
                    title: String(localized: "Swimming", comment: "Label for swimming distance"),
                    value: profile.formattedSwimmingDistance
                )
            }
        }
        .padding(20)
        .background(Color.irCardBackground)
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
                .foregroundStyle(Color.irTextPrimary)

            Spacer()

            Text(value)
                .font(.body)
                .fontWeight(.semibold)
                .foregroundStyle(Color.irTextSecondary)
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
                .foregroundStyle(Color.irTextPrimary)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.irTextSecondary)

                if let dateString = dateString {
                    Text(dateString)
                        .font(.caption2)
                        .foregroundStyle(Color.irTextSecondary)
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
                .foregroundStyle(Color.irTextSecondary)

            VStack(spacing: 4) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.irTextPrimary)

                if let dateString = dateString {
                    Text(dateString)
                        .font(.caption2)
                        .foregroundStyle(Color.irTextSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    HealthProfileView()
}
