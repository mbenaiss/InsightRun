//
//  WorkoutListView.swift
//  HealthApp
//
//  Main screen displaying list of running workouts
//  Featuring iOS 26 Liquid Glass design
//

import SwiftUI

struct WorkoutListView: View {
    @StateObject private var viewModel = WorkoutListViewModel()
    @State private var showingAIAssistant = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            NavigationStack {
                Group {
                    switch viewModel.authorizationStatus {
                    case .notDetermined:
                        authorizationView
                    case .denied:
                        deniedView
                    case .authorized:
                        if viewModel.isLoading && viewModel.workouts.isEmpty {
                            loadingView
                        } else if viewModel.workouts.isEmpty {
                            emptyView
                        } else {
                            workoutList
                        }
                    }
                }
                .navigationTitle("Courses")
                .navigationBarTitleDisplayMode(.large)
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        // Refresh authorization status when app becomes active
                        viewModel.refreshAuthorizationStatus()
                    }
                }
            }

            // Floating AI Button
            if viewModel.authorizationStatus == .authorized && !viewModel.workouts.isEmpty {
                Button(action: { showingAIAssistant = true }) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .cyan],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 60, height: 60)
                            .shadow(color: .blue.opacity(0.4), radius: 12, y: 6)

                        Image(systemName: "sparkles")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
        }
        .sheet(isPresented: $showingAIAssistant) {
            WorkoutAIAssistantView(
                mode: .recentWorkouts(Array(viewModel.workouts.prefix(10))),
                isPresented: $showingAIAssistant
            )
        }
    }

    // MARK: - Authorization View

    private var authorizationView: some View {
        VStack(spacing: 32) {
            Spacer()

            // Icon with Liquid Glass effect
            ZStack {
                Circle()
                    .fill(.thinMaterial)
                    .frame(width: 120, height: 120)
                    .shadow(color: .black.opacity(0.1), radius: 20, y: 10)

                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.red.gradient)
            }

            VStack(spacing: 12) {
                Text("Accès aux Données")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Cette app a besoin d'accéder à vos workouts de course depuis HealthKit pour afficher votre historique.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                Task {
                    await viewModel.requestAuthorization()
                }
            } label: {
                Text("Autoriser l'accès")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .blue.opacity(0.3), radius: 10, y: 5)
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)

            Spacer()
        }
        .padding()
    }

    // MARK: - Denied View

    private var deniedView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.orange.gradient)

            VStack(spacing: 12) {
                Text("Accès Refusé")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Veuillez activer l'accès dans Réglages → Confidentialité → Santé → HealthApp")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Ouvrir Réglages")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.orange.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .padding()
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
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue.gradient)

            VStack(spacing: 12) {
                Text("Aucune Course")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Aucun workout de course trouvé.\nCommencez à courir pour voir vos statistiques ici!")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Workout List

    private var workoutList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // Combined stats card
                if !viewModel.workouts.isEmpty {
                    combinedStatsCard
                        .padding(.horizontal)
                        .padding(.top, 8)
                }

                // Grouped workout list by month
                ForEach(viewModel.groupedWorkouts, id: \.0) { groupTitle, groupWorkouts in
                    VStack(alignment: .leading, spacing: 12) {
                        // Month header with stats
                        monthHeaderView(title: groupTitle, workouts: groupWorkouts)
                            .padding(.horizontal)
                            .padding(.top, 8)

                        // Workouts in this month
                        ForEach(groupWorkouts) { workout in
                            NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                                WorkoutRowView(workout: workout)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.bottom, 20)
        }
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            if viewModel.workouts.isEmpty {
                await viewModel.loadWorkouts()
            }
        }
    }

    // MARK: - Combined Stats Card

    private var combinedStatsCard: some View {
        VStack(spacing: 16) {
            // Main title
            Text("Statistiques Globales")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Global stats section
            VStack(spacing: 12) {
                StatsRow(icon: "number", label: "Courses", value: "\(viewModel.workoutCount)")
                StatsRow(icon: "ruler", label: "Distance totale", value: viewModel.formatTotalDistance())
                StatsRow(icon: "clock", label: "Temps total", value: viewModel.formatTotalDuration())
                StatsRow(icon: "gauge", label: "Allure moyenne", value: viewModel.formatAveragePace())
                StatsRow(icon: "figure.run", label: "Distance moyenne", value: viewModel.formatAverageDistance())
            }

            // Records section
            if viewModel.longestRun != nil || viewModel.fastestRun != nil {
                Divider()

                Text("Records")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 12) {
                    if let longest = viewModel.longestRun {
                        HStack {
                            Image(systemName: "trophy.fill")
                                .foregroundStyle(.yellow.gradient)
                                .frame(width: 24)
                            Text("Course la plus longue")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.1f km", (longest.distance ?? 0) / 1000.0))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                    }

                    if let fastest = viewModel.fastestRun,
                       let pace = fastest.averagePace,
                       let distance = fastest.distance,
                       distance >= 5000 {
                        HStack {
                            Image(systemName: "bolt.fill")
                                .foregroundStyle(.orange.gradient)
                                .frame(width: 24)
                            Text("Course la plus rapide")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(viewModel.formatPace(pace) + " /km - " + String(format: "%.1f km", distance / 1000.0))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
    }

    // MARK: - Month Header View

    private func monthHeaderView(title: String, workouts: [WorkoutModel]) -> some View {
        let stats = viewModel.stats(for: workouts)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Text("\(stats.count) courses")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if stats.count >= 3 {
                // Show stats only if there are 3 or more workouts
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.formatDistance(stats.totalDistance))
                            .font(.headline)
                            .foregroundStyle(.blue)
                        Text("Distance")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Divider()
                        .frame(height: 30)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.formatDuration(stats.totalDuration))
                            .font(.headline)
                            .foregroundStyle(.green)
                        Text("Temps")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Divider()
                        .frame(height: 30)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.formatPace(stats.averagePace))
                            .font(.headline)
                            .foregroundStyle(.orange)
                        Text("Allure moy.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

// MARK: - Stat Item Component

struct StatItem: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue.gradient)

            Text(value)
                .font(.title3)
                .fontWeight(.semibold)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Stats Row Component

struct StatsRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.blue.gradient)
                .frame(width: 24)

            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
    }
}

#Preview {
    WorkoutListView()
}
