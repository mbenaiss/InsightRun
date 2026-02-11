//
//  DashboardView.swift
//  InsightRun
//
//  Main dashboard combining recovery, readiness and health metrics
//  Inspired by Whoop and Bevel for a modern, high-performance feel
//

import SwiftUI

struct DashboardView: View {
    @StateObject private var recoveryVM = RecoveryViewModel()
    @StateObject private var healthVM = HealthProfileViewModel()
    @StateObject private var readinessVM = DailyReadinessViewModel()
    @StateObject private var workoutVM = UnifiedWorkoutViewModel()
    @StateObject private var notificationRouter = NotificationRouter.shared
    @Environment(ThemeManager.self) private var themeManager
    @EnvironmentObject private var revenueCatManager: RevenueCatManager
    
    @State private var showingSettings = false
    @State private var showingCalendar = false
    @State private var availableDates: [Date] = []

    var body: some View {
        NavigationStack {
            ZStack {
                Color.irBackgroundApp.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Spacing.xl) {
                        // 0. Weekly Summary Link
                        weeklySummaryLink
                            .padding(.horizontal)

                        // 1. Recovery Score (Main Focus)
                        recoveryHeader
                        
                        // 2. AI Coaching / Readiness
                        coachingSection
                        
                        // 3. Key Performance Metrics (Grid)
                        performanceGrid
                        
                        // 4. Daily Activity / Strain
                        activitySection
                        
                        // 5. Recent Workouts (Courses)
                        recentActivitiesSection
                        
                        // 6. Vital Signs & Health
                        vitalsSection
                        
                        Spacer(minLength: 100)
                    }
                    .padding(.vertical)
                }
                .refreshable {
                    await refreshAll()
                }
            }
            .navigationTitle(String(localized: "Dashboard", comment: "Navigation title for main dashboard"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    datePickerButton
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "person.circle")
                            .font(.title3)
                            .foregroundStyle(Color.irTextPrimary)
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environment(themeManager)
                    .environmentObject(revenueCatManager)
            }
            .sheet(isPresented: $showingCalendar) {
                RecoveryCalendarView(
                    selectedDate: $recoveryVM.selectedDate,
                    isPresented: $showingCalendar,
                    onDateSelected: { date in
                        Task { await recoveryVM.loadRecoveryMetrics(for: date) }
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .navigationDestination(isPresented: $notificationRouter.showWeeklySummary) {
                WeeklySummaryView()
            }
            .task {
                if availableDates.isEmpty {
                    setupInitialDates()
                }
                await refreshAll()
            }
        }
    }

    // MARK: - Subviews

    private var weeklySummaryLink: some View {
        NavigationLink {
            WeeklySummaryView()
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: "calendar")
                    .font(.title3)
                    .foregroundStyle(Color.irPrimaryAccent.gradient)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Weekly Summary"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(String(localized: "Review your performance & recovery"))
                        .font(.caption2)
                        .foregroundStyle(Color.irTextSecondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(Color.irTextSecondary)
            }
            .padding(Spacing.md)
            .background(Color.irCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .shadow(color: Color.irShadow, radius: 5, y: 2)
        }
        .buttonStyle(.plain)
    }

    private var recoveryHeader: some View {
        VStack(spacing: Spacing.md) {
            if let recovery = recoveryVM.recoveryMetrics {
                ZStack {
                    CircularProgressView(
                        score: recovery.recoveryScore,
                        size: 220,
                        lineWidth: 18
                    )
                    
                    VStack(spacing: 4) {
                        Text("\(Int(recovery.recoveryScore))%")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.irTextPrimary)
                        
                        Text(recovery.recoveryStatus.description)
                            .font(.headline)
                            .foregroundStyle(recovery.recoveryStatus.color)
                    }
                }
                .padding(.vertical, Spacing.lg)
            } else if recoveryVM.isLoading {
                ProgressView()
                    .frame(height: 220)
            }
        }
    }

    private var coachingSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Label(String(localized: "AI Coaching"), systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(Color.irPrimaryAccent.gradient)
                
                Spacer()
                
                if let score = readinessVM.readinessScore {
                    Text("\(score)/100")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(readinessVM.status.color.opacity(0.15))
                        .foregroundStyle(readinessVM.status.color)
                        .clipShape(Capsule())
                }
            }
            
            Text(readinessVM.recommendation.isEmpty ? (recoveryVM.recoveryMetrics?.recoveryStatus.recommendation ?? "") : readinessVM.recommendation)
                .font(.body)
                .lineSpacing(4)
                .foregroundStyle(Color.irTextPrimary)
            
            if let _ = readinessVM.readinessScore {
                Divider()
                
                HStack {
                    Image(systemName: readinessVM.suggestedWorkoutType.icon)
                        .font(.title3)
                        .foregroundStyle(readinessVM.status.color)
                    
                    VStack(alignment: .leading) {
                        Text(String(localized: "Suggested Workout"))
                            .font(.caption2)
                            .foregroundStyle(Color.irTextSecondary)
                        Text(readinessVM.suggestedWorkoutType.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
            }
        }
        .cardStyle()
        .padding(.horizontal)
    }

    private var performanceGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.md) {
            if let recovery = recoveryVM.recoveryMetrics {
                // HRV
                MetricSmallCard(
                    title: "HRV",
                    value: String(format: "%.0f", recovery.hrvAverage ?? 0),
                    unit: "ms",
                    icon: "waveform.path.ecg",
                    color: .blue
                )
                
                // RHR
                MetricSmallCard(
                    title: "RHR",
                    value: String(format: "%.0f", recovery.restingHeartRate ?? 0),
                    unit: "bpm",
                    icon: "heart.fill",
                    color: .red
                )
                
                // Sleep
                if let sleep = recovery.sleepData {
                    MetricSmallCard(
                        title: "Sleep",
                        value: sleep.formattedTotalSleep,
                        unit: "",
                        icon: "moon.fill",
                        color: .indigo
                    )
                    
                    MetricSmallCard(
                        title: "Efficiency",
                        value: String(format: "%.0f%%", sleep.sleepEfficiency),
                        unit: "",
                        icon: "bed.double.fill",
                        color: .cyan
                    )
                }
            }
        }
        .padding(.horizontal)
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Label(String(localized: "Today's Activity"), systemImage: "figure.run")
                .font(.headline)
            
            if let profile = healthVM.healthProfile {
                HStack(spacing: Spacing.lg) {
                    ActivityRingSmall(
                        value: profile.exerciseTime ?? 0,
                        goal: 30,
                        icon: "flame.fill",
                        color: .red,
                        label: String(localized: "Exercise")
                    )
                    
                    ActivityRingSmall(
                        value: Double(profile.standTime ?? 0),
                        goal: 12,
                        icon: "figure.stand",
                        color: .blue,
                        label: String(localized: "Stand")
                    )
                    
                    if let steps = profile.flightsClimbed {
                         ActivityRingSmall(
                            value: Double(steps),
                            goal: 10,
                            icon: "figure.stairs",
                            color: .purple,
                            label: String(localized: "Floors")
                        )
                    }
                }
                .padding(.vertical, Spacing.xs)
            } else {
                Text(String(localized: "Activity data unavailable"))
                    .font(.caption)
                    .foregroundStyle(Color.irTextSecondary)
            }
        }
        .cardStyle()
        .padding(.horizontal)
    }

    private var recentActivitiesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Label(String(localized: "Recent Courses", defaultValue: "Recent Activities"), systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                Spacer()
                NavigationLink(destination: WorkoutListView()) {
                    Text(String(localized: "See All"))
                        .font(.caption)
                        .foregroundStyle(Color.irPrimaryAccent)
                }
            }
            
            if workoutVM.isLoading && workoutVM.unifiedWorkouts.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if workoutVM.unifiedWorkouts.isEmpty {
                Text(String(localized: "No recent activities"))
                    .font(.caption)
                    .foregroundStyle(Color.irTextSecondary)
                    .padding()
            } else {
                VStack(spacing: Spacing.sm) {
                    ForEach(workoutVM.unifiedWorkouts.prefix(3)) { workout in
                        NavigationLink(destination: WorkoutDetailView(workout: workout.toWorkoutModel())) {
                            RecentWorkoutRow(workout: workout.toWorkoutModel())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .cardStyle()
        .padding(.horizontal)
    }

    private var vitalsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Label(String(localized: "Health Vitals"), systemImage: "heart.text.square")
                .font(.headline)
            
            if let profile = healthVM.healthProfile {
                VStack(spacing: Spacing.sm) {
                    VitalRow(
                        title: String(localized: "Oxygen Saturation"),
                        value: profile.formattedSpO2,
                        icon: "drop.fill",
                        color: .red
                    )
                    Divider()
                    VitalRow(
                        title: String(localized: "Respiratory Rate"),
                        value: profile.formattedRespiratoryRate,
                        icon: "wind",
                        color: .cyan
                    )
                    Divider()
                    VitalRow(
                        title: String(localized: "Body Temperature"),
                        value: profile.formattedTemperature,
                        icon: "thermometer",
                        color: .orange
                    )
                }
            }
        }
        .cardStyle()
        .padding(.horizontal)
    }

    private var datePickerButton: some View {
        Button {
            showingCalendar = true
        } label: {
            HStack(spacing: 4) {
                Text(recoveryVM.formattedSelectedDate)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(Color.irTextPrimary)
        }
    }

    // MARK: - Helpers

    private func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await recoveryVM.loadRecoveryMetrics() }
            group.addTask { await healthVM.loadHealthProfile() }
            group.addTask { await readinessVM.fetchDailyReadiness() }
            group.addTask { await workoutVM.loadUnifiedWorkouts() }
        }
    }

    private func setupInitialDates() {
        let today = Calendar.current.startOfDay(for: Date())
        var dates: [Date] = []
        for i in -30...0 {
            if let date = Calendar.current.date(byAdding: .day, value: i, to: today) {
                dates.append(Calendar.current.startOfDay(for: date))
            }
        }
        availableDates = dates.sorted()
    }
}

// MARK: - Supporting Components

struct MetricSmallCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color.gradient)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Color.irTextSecondary)
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(Color.irTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: Spacing.md)
    }
}

struct ActivityRingSmall: View {
    let value: Double
    let goal: Double
    let icon: String
    let color: Color
    let label: String
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.1), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: min(value / goal, 1.0))
                    .stroke(color.gradient, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(color)
            }
            .frame(width: 44, height: 44)
            
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 8))
                    .foregroundStyle(Color.irTextSecondary)
                Text("\(Int(value))")
                    .font(.caption2)
                    .fontWeight(.bold)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct VitalRow: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(color.gradient)
                .frame(width: 24)
            
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Color.irTextPrimary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.irTextSecondary)
        }
        .padding(.vertical, 4)
    }
}

struct RecentWorkoutRow: View {
    let workout: WorkoutModel
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.irPrimaryAccent.opacity(0.1))
                    .frame(width: 40, height: 40)
                
                Image(systemName: "figure.run")
                    .foregroundStyle(Color.irPrimaryAccent)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.startDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(Color.irTextSecondary)
                Text(workout.formattedDistance)
                    .font(.subheadline)
                    .fontWeight(.bold)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(workout.formattedDuration)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(workout.formattedPace)
                    .font(.caption2)
                    .foregroundStyle(Color.irTextSecondary)
            }
            
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(Color.irTextSecondary.opacity(0.5))
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    DashboardView()
        .environment(ThemeManager())
}
