//
//  WorkoutPlanView.swift
//  InsightRun
//
//  AI-powered workout generation with preview and export to Apple Fitness
//

import SwiftUI
import Combine

@MainActor
class WorkoutPlanViewModel: ObservableObject {
    private enum PendingAction {
        case generateWorkout
        case generateSmartSuggestion
    }

    @Published var promptText = ""
    @Published var isGenerating = false
    @Published var generatedWorkout: AIGeneratedWorkout?
    @Published var error: String?
    @Published var showSuccessAlert = false
    @Published var showPreview = false

    private let backendClient = BackendAPIClient.shared
    private let workoutKitManager = WorkoutKitManager.shared
    private let healthKitManager = HealthKitManager.shared

    // Smart suggestion state
    @Published var isGeneratingSmartSuggestion = false
    @Published var smartSuggestionError: String?

    // Consent state
    @Published var needsConsent = false
    @Published var needsIndexation = false

    // Subscription state
    @Published var showSubscriptionPaywall = false

    // Export retry state
    @Published var consecutiveExportFailures: Int = 0
    @Published var exportCooldown = false
    @Published var exportAuthDenied = false
    private static let maxExportRetries = 3
    private var pendingAction: PendingAction?

    // Demo mode: auto-show preview with mock data
    func loadDemoDataIfNeeded() {
        guard DemoMode.isEnabled else { return }
        generatedWorkout = .sampleIntervalWorkout
        showPreview = true
    }

    // Sample prompts
    let samplePrompts = [
        String(localized: "10x400m speed intervals", comment: "Sample workout prompt"),
        String(localized: "5km tempo run", comment: "Sample workout prompt"),
        String(localized: "Pyramid workout (400-800-1200-800-400)", comment: "Sample workout prompt"),
        String(localized: "Easy 60-minute endurance run", comment: "Sample workout prompt"),
        String(localized: "3x8min threshold intervals", comment: "Sample workout prompt")
    ]

    func generateWorkout() async {
        guard !promptText.isEmpty else { return }
        pendingAction = .generateWorkout

        guard ConsentService.shared.hasConsentedToAIDataSharing else {
            needsConsent = true
            return
        }

        if await HistoricalSummaryStorage.shared.requiresIndexation() {
            AnalyticsService.shared.trackIndexationGateTriggered(source: "workout_generation")
            needsIndexation = true
            return
        }

        pendingAction = nil
        isGenerating = true
        error = nil
        showSuccessAlert = false
        generatedWorkout = nil

        // Track generation requested
        AnalyticsService.shared.trackWorkoutGenerationRequested(
            prompt: promptText,
            userLevel: nil
        )

        let startTime = Date()

        do {
            // Get enriched user context from HealthKit
            let userContext = await buildEnrichedUserContext()

            // Get user language
            let language = Locale.current.language.languageCode?.identifier ?? "en"

            // Call backend (backend selects optimal model based on requestType)
            let response = try await backendClient.generateWorkout(
                userQuestion: promptText,
                language: language,
                userContext: userContext,
                model: nil // Backend selects optimal model
            )

            // Convert backend response to AIGeneratedWorkout
            let workout = convertToAIWorkout(response.workout)

            // Validate backend values vs calculated values
            validateWorkoutCalculations(workout)

            generatedWorkout = workout
            showPreview = true

            let generationTime = Int(Date().timeIntervalSince(startTime) * 1000)

            // Track success
            AnalyticsService.shared.trackWorkoutGenerated(
                workoutName: workout.name,
                generationTimeMs: generationTime,
                modelUsed: response.metadata.modelUsed
            )

            print("✅ Workout generated: \(workout.name)")

        } catch let backendError as BackendError {
            handleError(backendError)
        } catch {
            self.error = error.localizedDescription
            print("❌ Generation error: \(error)")

            // Track error
            AnalyticsService.shared.trackWorkoutGenerationFailed(
                errorType: "unknown_error",
                errorMessage: error.localizedDescription
            )
        }

        isGenerating = false
    }

    func exportToFitness() async {
        guard let workout = generatedWorkout else { return }

        // Block if max retries exceeded
        guard consecutiveExportFailures < Self.maxExportRetries else {
            self.error = String(localized: "Export failed multiple times. Please try again later.", comment: "Export max retries error")
            return
        }

        // Block if in cooldown
        guard !exportCooldown else { return }

        do {
            try await workoutKitManager.exportToFitnessApp(workout)

            // Success — reset failure counter
            consecutiveExportFailures = 0
            error = nil
            showSuccessAlert = true
            print("✅ Workout exported to Fitness app")

            // Note: export analytics already tracked by WorkoutKitManager with full details

        } catch let caughtError {
            if let kitError = caughtError as? WorkoutKitError, case .authorizationDenied = kitError {
                let isPermanent = exportAuthDenied

                // Authorization denied — check if this is a retry (already denied once)
                if exportAuthDenied {
                    // Second denial — disable export permanently
                    self.error = String(localized: "Workout export is not authorized. Open the Fitness app, then reopen Insight Run.", comment: "Export permanently denied error")
                } else {
                    exportAuthDenied = true
                    self.error = kitError.localizedDescription
                }
                AnalyticsService.shared.trackWorkoutExportAuthDenied(permanent: isPermanent)
                print("❌ Export authorization denied (permanent: \(exportAuthDenied))")
                return
            }
            consecutiveExportFailures += 1

            if consecutiveExportFailures >= Self.maxExportRetries {
                self.error = String(localized: "Export failed multiple times. Please try again later.", comment: "Export max retries error")
            } else {
                self.error = caughtError.localizedDescription
            }
            print("❌ Export error (\(consecutiveExportFailures)/\(Self.maxExportRetries)): \(caughtError)")

            // Note: detailed export failure is already tracked by WorkoutKitManager

            // Debounce: disable export for 2 seconds after failure
            exportCooldown = true
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            exportCooldown = false
        }
    }

    func clearWorkout() {
        generatedWorkout = nil
        showPreview = false
        promptText = ""
        error = nil
        showSuccessAlert = false
        pendingAction = nil
    }

    // MARK: - Helper Methods

    private func buildEnrichedUserContext() async -> WorkoutGenerationRequest.UserContext {
        // Get recent workouts to calculate average pace and trends
        let recentWorkouts = await healthKitManager.fetchWorkouts(limit: 20)

        let avgPace = recentWorkouts.averagePace
        let vo2Max = await healthKitManager.fetchLatestVO2Max()

        return WorkoutGenerationRequest.UserContext(
            avgPace: avgPace,
            vo2Max: vo2Max,
            recentWorkouts: recentWorkouts.count,
            fitnessLevel: determineFitnessLevel(avgPace: avgPace, vo2Max: vo2Max)
        )
    }


    private func determineFitnessLevel(avgPace: Double?, vo2Max: Double?) -> String {
        // Simple heuristic
        if let pace = avgPace {
            if pace < 4.5 {
                return "advanced"
            } else if pace < 5.5 {
                return "intermediate"
            } else {
                return "beginner"
            }
        }

        if let vo2 = vo2Max {
            if vo2 > 50 {
                return "advanced"
            } else if vo2 > 40 {
                return "intermediate"
            } else {
                return "beginner"
            }
        }

        return "intermediate"
    }

    private func calculateWeeklyVolumeChange(workouts: [WorkoutModel]) -> Double? {
        guard workouts.count >= 4 else { return nil }

        let now = Date()
        let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now)!
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: now)!

        let lastWeek = workouts.filter { $0.startDate > oneWeekAgo }
        let previousWeek = workouts.filter { $0.startDate > twoWeeksAgo && $0.startDate <= oneWeekAgo }

        let lastWeekDistance = lastWeek.compactMap { $0.distance }.reduce(0, +)
        let previousWeekDistance = previousWeek.compactMap { $0.distance }.reduce(0, +)

        guard previousWeekDistance > 0 else { return nil }

        return ((lastWeekDistance - previousWeekDistance) / previousWeekDistance) * 100
    }

    private func calculateDaysSinceLastWorkout(workouts: [WorkoutModel]) -> Int? {
        guard let lastWorkout = workouts.first else { return nil }
        return Calendar.current.dateComponents([.day], from: lastWorkout.startDate, to: Date()).day
    }

    private func convertToAIWorkout(_ workoutData: WorkoutGenerationResponse.GeneratedWorkoutData) -> AIGeneratedWorkout {
        let sport: AIGeneratedWorkout.WorkoutSportType
        switch workoutData.sport.lowercased() {
        case "running":
            sport = .running
        case "cycling":
            sport = .cycling
        case "swimming":
            sport = .swimming
        default:
            sport = .running
        }

        let steps = workoutData.steps.map { stepData -> WorkoutStep in
            let goalType: WorkoutGoal.GoalType
            switch stepData.goal.type.lowercased() {
            case "distance":
                goalType = .distance
            case "duration":
                goalType = .duration
            default:
                goalType = .open
            }

            let stepType: WorkoutStep.StepType
            switch stepData.type.lowercased() {
            case "warmup":
                stepType = .warmup
            case "work":
                stepType = .work
            case "recovery":
                stepType = .recovery
            case "cooldown":
                stepType = .cooldown
            case "interval":
                stepType = .interval
            default:
                stepType = .work
            }

            return WorkoutStep(
                type: stepType,
                goal: WorkoutGoal(type: goalType, value: stepData.goal.value),
                targetPace: stepData.targetPace,
                targetPaceMin: stepData.targetPaceMin,
                targetPaceMax: stepData.targetPaceMax,
                targetHeartRateZone: stepData.targetHeartRateZone,
                instructions: stepData.instructions
            )
        }

        return AIGeneratedWorkout(
            name: workoutData.name,
            description: workoutData.description,
            sport: sport,
            steps: steps,
            totalDistance: workoutData.totalDistance,
            estimatedDuration: workoutData.estimatedDuration
        )
    }

    private func validateWorkoutCalculations(_ workout: AIGeneratedWorkout) {
        // Compare backend values with calculated values to detect inconsistencies

        // Check distance
        if let backendDistance = workout.totalDistance, backendDistance > 0 {
            let calculatedDistance = workout.calculatedTotalDistance
            let distanceDiff = abs(backendDistance - calculatedDistance)
            let distanceDiffPercent = (distanceDiff / backendDistance) * 100

            if distanceDiffPercent > 5 {
                print("⚠️ Distance mismatch: backend=\(Int(backendDistance))m, calculated=\(Int(calculatedDistance))m (diff: \(String(format: "%.1f", distanceDiffPercent))%)")
            } else {
                print("✅ Distance coherent: backend=\(Int(backendDistance))m, calculated=\(Int(calculatedDistance))m")
            }
        } else {
            let calculatedDistance = workout.calculatedTotalDistance
            print("ℹ️ Backend didn't provide distance, using calculated: \(Int(calculatedDistance))m")
        }

        // Check duration
        if let backendDuration = workout.estimatedDuration, backendDuration > 0 {
            let calculatedDuration = workout.calculatedEstimatedDuration
            let durationDiff = abs(backendDuration - calculatedDuration)
            let durationDiffPercent = (durationDiff / backendDuration) * 100

            if durationDiffPercent > 5 {
                print("⚠️ Duration mismatch: backend=\(Int(backendDuration))s, calculated=\(Int(calculatedDuration))s (diff: \(String(format: "%.1f", durationDiffPercent))%)")
            } else {
                print("✅ Duration coherent: backend=\(Int(backendDuration))s, calculated=\(Int(calculatedDuration))s")
            }
        } else {
            let calculatedDuration = workout.calculatedEstimatedDuration
            print("ℹ️ Backend didn't provide duration, using calculated: \(Int(calculatedDuration))s")
        }
    }

    private func handleError(_ error: BackendError) {
        switch error {
        case .unauthorized:
            self.error = String(localized: "Authentication error", comment: "Workout generation error")
        case .blocked:
            self.error = String(localized: "Your account has been blocked. Please contact support.", comment: "Workout generation error")
        case .rateLimitExceeded:
            self.error = String(localized: "Too many requests. Please try again later.", comment: "Workout generation error")
        case .serverError:
            self.error = String(localized: "Server error. Please try again.", comment: "Workout generation error")
        case .invalidResponse:
            self.error = String(localized: "Invalid response from server", comment: "Workout generation error")
        case .unknownError(let code):
            self.error = String(localized: "Error %@", comment: "Workout generation error").replacingOccurrences(of: "%@", with: String(code))
        }

        AnalyticsService.shared.trackWorkoutGenerationFailed(
            errorType: "backend_error",
            errorMessage: self.error ?? "Unknown error"
        )
    }

    // MARK: - Smart Suggestion

    private var smartSuggestionTask: Task<Void, Never>?

    func cancelSmartSuggestion() {
        smartSuggestionTask?.cancel()
        smartSuggestionTask = nil
        isGeneratingSmartSuggestion = false
        smartSuggestionError = nil
        print("✅ Smart suggestion cancelled")
    }

    func generateSmartSuggestion() async {
        pendingAction = .generateSmartSuggestion

        guard ConsentService.shared.hasConsentedToAIDataSharing else {
            needsConsent = true
            return
        }

        if await HistoricalSummaryStorage.shared.requiresIndexation() {
            AnalyticsService.shared.trackIndexationGateTriggered(source: "smart_suggestion")
            needsIndexation = true
            return
        }

        pendingAction = nil
        isGeneratingSmartSuggestion = true
        smartSuggestionError = nil

        let startTime = Date()
        AnalyticsService.shared.trackSmartSuggestionRequested()

        do {
            // 1. Load last 15 workouts with metrics for better analysis
            let recentWorkouts = await healthKitManager.fetchWorkouts(limit: 15)
            try Task.checkCancellation()

            // 2. Load metrics in parallel
            var workoutsMetrics: [UUID: WorkoutMetrics] = [:]
            await withTaskGroup(of: (UUID, WorkoutMetrics?).self) { group in
                for workout in recentWorkouts {
                    group.addTask {
                        do {
                            let metrics = try await HealthKitManager.shared.fetchWorkoutMetrics(for: workout)
                            return (workout.id, metrics)
                        } catch {
                            print("Error loading metrics for workout \(workout.id): \(error)")
                            return (workout.id, nil)
                        }
                    }
                }

                for await (id, metrics) in group {
                    if let metrics = metrics {
                        workoutsMetrics[id] = metrics
                    }
                }
            }
            try Task.checkCancellation()

            // 3. Build enriched ChatRequestV2 payload with additional context
            let historicalSummary = HistoricalSummaryStorage.shared.load()

            let totalDistance = recentWorkouts.compactMap { $0.distance }.reduce(0, +)
            let totalDuration = recentWorkouts.map { $0.duration }.reduce(0, +)
            let totalCalories = recentWorkouts.compactMap { $0.totalEnergyBurned }.reduce(0, +)
            let avgPace = recentWorkouts.averagePace ?? 0

            // Calculate trends for better suggestions
            let weeklyVolumeChange = calculateWeeklyVolumeChange(workouts: recentWorkouts)
            let daysSinceLastWorkout = calculateDaysSinceLastWorkout(workouts: recentWorkouts)

            // Get VO2 Max for fitness level assessment
            _ = await healthKitManager.fetchLatestVO2Max()
            try Task.checkCancellation()

            let recentWorkoutsData = RecentWorkoutsData(
                workouts: recentWorkouts.map { workout in
                    convertToWorkoutData(workout: workout, metrics: workoutsMetrics[workout.id])
                },
                totalDistance: totalDistance,
                totalDuration: totalDuration,
                totalCalories: totalCalories,
                avgPace: avgPace,
                weeklyVolumeChange: weeklyVolumeChange,
                daysSinceLastWorkout: daysSinceLastWorkout
            )

            let language = Locale.current.language.languageCode?.identifier ?? "en"

            // 4. Call smart suggestion endpoint with enriched payload
            let response = try await backendClient.generateSmartWorkoutSuggestion(
                recentWorkoutsData: recentWorkoutsData,
                historicalSummary: historicalSummary?.summary,
                language: language
            )
            try Task.checkCancellation()

            // 5. Fill the prompt text field with the suggestion
            promptText = response.suggestion

            // Track successful generation
            let generationTime = Int(Date().timeIntervalSince(startTime) * 1000)
            AnalyticsService.shared.trackSmartSuggestionGenerated(
                suggestionLength: response.suggestion.count,
                generationTimeMs: generationTime
            )
            AnalyticsService.shared.trackSmartSuggestionApplied()

        } catch is CancellationError {
            print("✅ Smart suggestion cancelled by user")
        } catch let backendError as BackendError {
            smartSuggestionError = backendError.localizedDescription
            print("❌ Smart suggestion error: \(backendError)")

            AnalyticsService.shared.trackSmartSuggestionFailed(
                errorType: "BackendError",
                errorMessage: backendError.localizedDescription
            )
        } catch {
            smartSuggestionError = error.localizedDescription
            print("❌ Smart suggestion error: \(error)")

            AnalyticsService.shared.trackSmartSuggestionFailed(
                errorType: String(describing: type(of: error)),
                errorMessage: error.localizedDescription
            )
        }

        isGeneratingSmartSuggestion = false
    }

    func resumePendingAction() async {
        guard let pendingAction else { return }

        switch pendingAction {
        case .generateWorkout:
            await generateWorkout()
        case .generateSmartSuggestion:
            await generateSmartSuggestion()
        }
    }

    func clearPendingAction() {
        pendingAction = nil
    }

    private func convertToWorkoutData(workout: WorkoutModel, metrics: WorkoutMetrics?) -> WorkoutData {
        let heartRateData: HeartRateData?
        if let avgHR = metrics?.averageHeartRate {
            heartRateData = HeartRateData(
                avg: Int(avgHR),
                min: metrics?.minHeartRate.map { Int($0) },
                max: metrics?.maxHeartRate.map { Int($0) }
            )
        } else {
            heartRateData = nil
        }

        let splits: [SplitData]?
        if let metricsArray = metrics?.splits {
            splits = metricsArray.map { split in
                SplitData(
                    kilometer: split.kilometer,
                    pace: split.paceFormatted,
                    time: split.timeFormatted
                )
            }
        } else {
            splits = nil
        }

        return WorkoutData(
            date: workout.startDate.ISO8601Format(),
            duration: workout.duration,
            distance: workout.distance ?? 0,
            calories: workout.totalEnergyBurned,
            pace: workout.averagePace,
            speed: workout.averageSpeed,
            heartRate: heartRateData,
            minPace: metrics?.minPace,
            cadence: metrics?.averageCadence.map { Int($0) },
            strideLength: metrics?.strideLength,
            runningPower: metrics?.runningPower.map { Int($0) },
            vo2Max: metrics?.vo2Max,
            elevationGain: metrics?.totalElevationAscent,
            groundContactTime: metrics?.groundContactTime.map { Int($0) },
            verticalOscillation: metrics?.verticalOscillation,
            mobility: nil,
            splits: splits
        )
    }
}

struct WorkoutPlanView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = WorkoutPlanViewModel()
    @FocusState private var isTextFieldFocused: Bool
    @EnvironmentObject private var revenueCatManager: RevenueCatManager

    // Subscription state
    @State private var showSubscriptionPaywall = false

    // Edit mode state
    @State private var isEditing: Bool = false
    @State private var editedWorkoutName: String = ""
    @State private var editedSteps: [WorkoutStep] = []
    @State private var backupWorkoutName: String = ""
    @State private var backupSteps: [WorkoutStep] = []

    var body: some View {
        NavigationStack {
            ZStack {
                // Liquid Glass Background
                LinearGradient(
                    colors: [
                        Color(.systemBackground),
                        Color.blue.opacity(0.02),
                        Color.blue.opacity(0.01)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Check if user has AI access (subscription or TestFlight)
                        if !revenueCatManager.hasAIAccess {
                            // Show subscription CTA if no access
                            subscriptionCTAView
                        } else {
                            // Show normal UI if has access
                            if !viewModel.showPreview {
                                // Generation Screen
                                generationView
                            } else if let workout = viewModel.generatedWorkout {
                                // Preview Screen
                                workoutPreviewView(workout: workout)
                            }
                        }
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onTapGesture {
                    // Dismiss keyboard when tapping outside
                    isTextFieldFocused = false
                }
            }
            .navigationTitle(String(localized: "Workout Plan", comment: "Workout plan screen title"))
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                viewModel.loadDemoDataIfNeeded()
            }
            .sheet(isPresented: $showSubscriptionPaywall) {
                SubscriptionPaywallView(isInitialFlow: false)
                    .environmentObject(revenueCatManager)
            }
            .sheet(isPresented: $viewModel.needsConsent) {
                AIConsentSheet(
                    onConsent: {
                        viewModel.needsConsent = false
                        Task {
                            if await HistoricalSummaryStorage.shared.requiresIndexation() {
                                viewModel.needsIndexation = true
                            } else {
                                await viewModel.resumePendingAction()
                            }
                        }
                    },
                    onDecline: {
                        viewModel.needsConsent = false
                        viewModel.clearPendingAction()
                    }
                )
            }
            .indexationGate(isPresented: $viewModel.needsIndexation) {
                await viewModel.resumePendingAction()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("sheet-close")
                }

                if viewModel.showPreview {
                    if !isEditing {
                        // View Mode: Edit + New buttons
                        ToolbarItemGroup(placement: .navigationBarTrailing) {
                            Button(action: enterEditMode) {
                                Image(systemName: "pencil")
                            }

                            Button(String(localized: "New", comment: "Create new workout button")) {
                                withAnimation {
                                    viewModel.clearWorkout()
                                }
                            }
                        }
                    } else {
                        // Edit Mode: Cancel + Save buttons
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button(String(localized: "Cancel", comment: "Cancel editing button")) {
                                cancelEditing()
                            }
                        }

                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(String(localized: "Save", comment: "Save edits button")) {
                                saveEditing()
                            }
                            .fontWeight(.semibold)
                        }
                    }
                }
            }
            .sheet(isPresented: $viewModel.showSuccessAlert) {
                WorkoutExportSuccessView()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                guard viewModel.exportAuthDenied else { return }
                Task {
                    let authorized = await WorkoutKitManager.shared.checkAuthorizationStatus()
                    if authorized {
                        viewModel.exportAuthDenied = false
                        viewModel.error = nil
                        WorkoutKitManager.shared.exportError = nil
                    }
                }
            }
        }
    }

    // MARK: - Subscription CTA View

    private var subscriptionCTAView: some View {
        VStack(spacing: 20) {
            Spacer()

            // Icon with gradient
            ZStack {
                Circle()
                    .fill(Color.irCardBackground)
                    .frame(width: 100, height: 100)
                    .shadow(color: Color.irShadowStrong, radius: 20, y: 10)

                Image(systemName: "sparkles")
                    .font(.system(size: 44))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .padding(.top, 8)

            // Title & Description
            VStack(spacing: 8) {
                Text(String(localized: "AI Workout Generator", comment: "Subscription CTA title"))
                    .font(.title3)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text(String(localized: "Subscribe to unlock AI-powered workout generation, personalized training plans, and smart suggestions based on your training history.", comment: "Subscription CTA description"))
                    .font(.subheadline)
                    .foregroundStyle(Color.irTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // Features list
            VStack(alignment: .leading, spacing: 12) {
                WorkoutFeatureRow(icon: "sparkles", text: String(localized: "AI-powered workout generation", comment: "Feature"))
                WorkoutFeatureRow(icon: "brain.head.profile", text: String(localized: "Smart suggestions based on your history", comment: "Feature"))
                WorkoutFeatureRow(icon: "pencil", text: String(localized: "Editable workout plans", comment: "Feature"))
                WorkoutFeatureRow(icon: "applewatch", text: String(localized: "Export to Apple Fitness", comment: "Feature"))
            }
            .padding(.horizontal, 32)

            Spacer()

            // Subscribe button
            Button(action: {
                showSubscriptionPaywall = true
            }) {
                HStack {
                    Image(systemName: "sparkles")
                    Text(String(localized: "Subscribe Now", comment: "Subscribe button"))
                }
                .font(.subheadline)
                .fontWeight(.semibold)
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
            .padding(.horizontal, 32)

            // Restore purchases
            Button(action: {
                Task {
                    do {
                        try await revenueCatManager.restorePurchases()
                    } catch {
                        print("Error restoring purchases: \(error.localizedDescription)")
                    }
                }
            }) {
                Text(String(localized: "Restore Purchases", comment: "Restore button"))
                    .font(.subheadline)
                    .foregroundStyle(.blue)
            }
            .padding(.bottom, 16)
        }
    }

    // MARK: - Edit Mode Functions

    private func enterEditMode() {
        guard let workout = viewModel.generatedWorkout else { return }

        // Create backups for reverting
        backupWorkoutName = workout.name
        backupSteps = workout.steps

        // Initialize edited values
        editedWorkoutName = workout.name
        editedSteps = workout.steps

        // Track editing started
        AnalyticsService.shared.trackWorkoutEditingStarted(workoutName: workout.name)

        // Enable editing
        withAnimation {
            isEditing = true
        }
    }

    private func cancelEditing() {
        // Restore from backup (revert unsaved changes)
        if var workout = viewModel.generatedWorkout {
            workout.name = backupWorkoutName
            workout.steps = backupSteps
            viewModel.generatedWorkout = workout
        }

        // Track editing cancelled
        AnalyticsService.shared.trackWorkoutEditingCancelled()

        // Clear temporary state
        editedWorkoutName = ""
        editedSteps = []

        // Exit edit mode
        withAnimation {
            isEditing = false
        }
    }

    private func saveEditing() {
        guard var workout = viewModel.generatedWorkout else { return }

        // Validate workout name
        guard !editedWorkoutName.trimmingCharacters(in: .whitespaces).isEmpty else {
            viewModel.error = String(localized: "Workout name cannot be empty", comment: "Validation error")
            return
        }

        // Apply edits to the actual model
        workout.name = editedWorkoutName
        workout.steps = editedSteps

        // Update viewModel with edited workout
        viewModel.generatedWorkout = workout

        // Track editing saved
        AnalyticsService.shared.trackWorkoutEditingSaved(
            workoutName: editedWorkoutName,
            stepsCount: editedSteps.count
        )

        // Clear temporary state
        editedWorkoutName = ""
        editedSteps = []

        // Clear backups
        backupWorkoutName = ""
        backupSteps = []

        // Exit edit mode
        withAnimation {
            isEditing = false
        }

        print("✅ Workout edits saved")
    }

    // MARK: - Generation View

    private var generationView: some View {
        VStack(spacing: 24) {
            // Header Icon
            ZStack {
                Circle()
                    .fill(Color.irCardBackground)
                    .frame(width: 100, height: 100)
                    .shadow(color: Color.irShadowStrong, radius: 20, y: 10)

                Image(systemName: "figure.run")
                    .font(.system(size: 40))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .padding(.top, 20)

            // Title
            VStack(spacing: 8) {
                Text(String(localized: "AI Workout Generator", comment: "Workout generator title"))
                    .font(.title2)
                    .fontWeight(.bold)

                Text(String(localized: "Describe your workout and let AI create a personalized plan", comment: "Workout generator subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(Color.irTextSecondary)
                    .multilineTextAlignment(.center)
            }

            // Input Area
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "What workout do you want?", comment: "Prompt input label"))
                    .font(.headline)

                TextField(String(localized: "E.g., '10x400m speed intervals'", comment: "Prompt placeholder"), text: $viewModel.promptText, axis: .vertical)
                    .focused($isTextFieldFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        isTextFieldFocused = false
                    }
                    .padding()
                    .background(Color.irCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .lineLimit(3...6)
            }

            // Sample Prompts (only shown when input is empty)
            if viewModel.promptText.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: "Or try these", comment: "Sample prompts label"))
                        .font(.caption)
                        .foregroundStyle(Color.irTextSecondary)
                        .textCase(.uppercase)

                    // AI-Powered Smart Suggestion (NEW)
                    Button(action: {
                        Task {
                            await viewModel.generateSmartSuggestion()
                        }
                    }) {
                        HStack {
                            // Sparkles icon with gradient
                            Image(systemName: "sparkles")
                                .font(.caption)
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .cyan],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )

                            if viewModel.isGeneratingSmartSuggestion {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text(String(localized: "Generating suggestion...", comment: "AI suggestion loading"))
                                    .font(.subheadline)
                                    .foregroundStyle(Color.irTextPrimary)
                            } else {
                                Text(String(localized: "Suggest a workout based on my history", comment: "AI suggestion prompt"))
                                    .font(.subheadline)
                                    .foregroundStyle(Color.irTextPrimary)
                            }

                            Spacer()

                            if !viewModel.isGeneratingSmartSuggestion {
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundStyle(Color.irTextSecondary)
                            }
                        }
                        .padding(12)
                        .background(
                            // Gradient background to differentiate
                            LinearGradient(
                                colors: [
                                    Color.blue.opacity(0.08),
                                    Color.cyan.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .overlay(Color.irCardBackground)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    LinearGradient(
                                        colors: [.blue.opacity(0.3), .cyan.opacity(0.3)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(viewModel.isGeneratingSmartSuggestion)

                    // Error display for smart suggestion
                    if let error = viewModel.smartSuggestionError {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.irWarning)
                                .font(.caption)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(Color.irTextSecondary)
                        }
                        .padding(.horizontal, 12)
                    }

                    // Regular sample prompts
                    ForEach(viewModel.samplePrompts, id: \.self) { sample in
                        Button(action: {
                            viewModel.promptText = sample
                            isTextFieldFocused = false
                        }) {
                            HStack {
                                Image(systemName: "lightbulb.fill")
                                    .font(.caption)
                                    .foregroundStyle(Color.irWarning)
                                Text(sample)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.irTextPrimary)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundStyle(Color.irTextSecondary)
                            }
                            .padding(12)
                            .background(Color.irCardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }

            // Error Display
            if let error = viewModel.error {
                errorView(error)
            }

            Spacer()

            // Generate Button
            Button(action: {
                Task {
                    await viewModel.generateWorkout()
                }
            }) {
                HStack {
                    if viewModel.isGenerating {
                        ProgressView()
                            .tint(.white)
                        Text(String(localized: "Generating...", comment: "Generating button text"))
                    } else {
                        Image(systemName: "sparkles")
                        Text(String(localized: "Generate Workout", comment: "Generate button text"))
                    }
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    viewModel.promptText.isEmpty || viewModel.isGenerating ?
                    LinearGradient(colors: [.gray, .gray], startPoint: .leading, endPoint: .trailing) :
                    LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: viewModel.promptText.isEmpty ? .clear : .blue.opacity(0.4), radius: 8, y: 4)
            }
            .disabled(viewModel.promptText.isEmpty || viewModel.isGenerating)

            // Cancel Button (only visible during smart suggestion generation)
            if viewModel.isGeneratingSmartSuggestion {
                Button(action: {
                    viewModel.cancelSmartSuggestion()
                }) {
                    Text(String(localized: "Cancel", comment: "Cancel smart suggestion button"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.irCardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.red.opacity(0.3), lineWidth: 1)
                        )
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Preview View

    private func workoutPreviewView(workout: AIGeneratedWorkout) -> some View {
        VStack(spacing: 0) {
            // Workout Header (pinned to top)
            VStack(spacing: 8) {
                // Conditional workout name (editable in edit mode)
                if isEditing {
                    TextField(String(localized: "Workout name", comment: "Workout name placeholder"), text: $editedWorkoutName)
                        .font(.title3)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal)
                        .padding(8)
                        .background(Color.irCardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Text(workout.name)
                        .font(.title3)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal)
                }

                Text(workout.description)
                    .font(.caption)
                    .foregroundStyle(Color.irTextSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                // Stats
                HStack(spacing: 12) {
                    if let distance = workout.totalDistanceFormatted {
                        StatBadge(icon: "figure.run", value: distance)
                    }
                    if let duration = workout.estimatedDurationFormatted {
                        StatBadge(icon: "clock", value: duration)
                    }
                    StatBadge(icon: "list.bullet", value: "\(workout.steps.count) \(String(localized: "steps", comment: "Steps count unit"))")
                }
                .padding(.top, 4)
            }
            .padding()
            .background(Color.irCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.bottom, 16)

            // Scrollable Steps List
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Steps List
                    Text(String(localized: "Workout Steps", comment: "Steps section title"))
                        .font(.headline)
                        .padding(.top, 8)

                    ForEach(Array(workout.steps.enumerated()), id: \.element.id) { index, step in
                        EditableWorkoutStepRow(
                            step: step,
                            index: index + 1,
                            isEditing: isEditing,
                            onPaceChanged: { newPace in
                                if isEditing {
                                    editedSteps[index].targetPace = newPace
                                }
                            },
                            onDurationChanged: { newValue in
                                if isEditing && step.goal.type == .duration {
                                    editedSteps[index].goal.value = newValue
                                }
                            }
                        )
                    }

                    // Error Display
                    if let error = viewModel.error {
                        errorView(error)
                    }

                    // Export Button
                    Button(action: {
                        Task {
                            await viewModel.exportToFitness()
                        }
                    }) {
                        HStack {
                            if WorkoutKitManager.shared.isExporting {
                                ProgressView()
                                    .tint(.white)
                                Text(String(localized: "Exporting...", comment: "Exporting button text"))
                            } else {
                                Image(systemName: "applewatch")
                                Text(String(localized: "Export to Fitness App", comment: "Export button text"))
                            }
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .blue.opacity(0.4), radius: 8, y: 4)
                    }
                    .disabled(WorkoutKitManager.shared.isExporting || isEditing || viewModel.exportCooldown || viewModel.consecutiveExportFailures >= 3 || viewModel.exportAuthDenied)
                    .opacity(viewModel.exportAuthDenied ? 0.5 : 1.0)
                    .padding(.top, 8)
                }
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.irError)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.irTextSecondary)
                Spacer()
            }

            if let exportError = WorkoutKitManager.shared.exportError,
               case .authorizationDenied = exportError {
                if !viewModel.exportAuthDenied {
                    // First denial — offer retry
                    Button(action: {
                        viewModel.consecutiveExportFailures = 0
                        viewModel.error = nil
                        WorkoutKitManager.shared.exportError = nil
                        Task {
                            await viewModel.exportToFitness()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text(String(localized: "Retry", comment: "Retry export authorization button"))
                        }
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.blue)
                    }
                }
                // After second denial, exportAuthDenied=true, no retry button, export button is grayed out
            }
        }
        .padding()
        .background(Color.irError.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Supporting Views

struct StatBadge: View {
    let icon: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct WorkoutVisualization: View {
    let workout: AIGeneratedWorkout

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Workout Structure", comment: "Visualization title"))
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(workout.steps) { step in
                        Rectangle()
                            .fill(colorForStepType(step.type))
                            .frame(width: widthForStep(step), height: 60)
                            .overlay(
                                VStack(spacing: 2) {
                                    Image(systemName: iconForStepType(step.type))
                                        .font(.caption2)
                                    Text(step.displayName)
                                        .font(.system(size: 8))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(.white)
                            )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func colorForStepType(_ type: WorkoutStep.StepType) -> Color {
        switch type {
        case .warmup: return .blue
        case .work: return .red
        case .recovery: return .green
        case .cooldown: return .purple
        case .interval: return .orange
        }
    }

    private func iconForStepType(_ type: WorkoutStep.StepType) -> String {
        switch type {
        case .warmup: return "sunrise"
        case .work: return "bolt.fill"
        case .recovery: return "heart.fill"
        case .cooldown: return "sunset"
        case .interval: return "repeat"
        }
    }

    private func widthForStep(_ step: WorkoutStep) -> CGFloat {
        // Fixed width for better readability, allowing horizontal scroll
        return 70 // Consistent width for all steps
    }
}

struct WorkoutStepRow: View {
    let step: WorkoutStep
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Index badge
                Text("\(index)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(colorForStepType(step.type))
                    .clipShape(Circle())

                // Step type
                Text(step.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                // Goal
                Text(goalText(step.goal))
                    .font(.caption)
                    .foregroundStyle(Color.irTextSecondary)
            }

            // Details
            if let paceFormatted = step.paceFormatted {
                DetailRow(icon: "speedometer", text: paceFormatted)
            }

            if let hrZone = step.targetHeartRateZone {
                DetailRow(icon: "heart.fill", text: "\(String(localized: "Zone", comment: "Heart rate zone prefix")) \(hrZone)")
            }

            if let instructions = step.instructions {
                Text(instructions)
                    .font(.caption)
                    .foregroundStyle(Color.irTextSecondary)
                    .italic()
            }
        }
        .padding()
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func colorForStepType(_ type: WorkoutStep.StepType) -> Color {
        switch type {
        case .warmup: return .blue
        case .work: return .red
        case .recovery: return .green
        case .cooldown: return .purple
        case .interval: return .orange
        }
    }

    private func goalText(_ goal: WorkoutGoal) -> String {
        switch goal.type {
        case .distance:
            if let formatted = goal.distanceFormatted {
                return formatted
            }
            return "\(Int(goal.value))\(String(localized: "m", comment: "Meters unit abbreviation"))"
        case .duration:
            if let formatted = goal.durationFormatted {
                return formatted
            }
            return "\(Int(goal.value))\(String(localized: "s", comment: "Seconds unit abbreviation"))"
        case .open:
            return String(localized: "Open", comment: "Open goal type")
        }
    }
}

struct DetailRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(Color.irTextSecondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(Color.irTextSecondary)
        }
    }
}

struct EditableWorkoutStepRow: View {
    let step: WorkoutStep
    let index: Int
    let isEditing: Bool
    let onPaceChanged: (String?) -> Void
    let onDurationChanged: (Double) -> Void

    @State private var editedPace: String
    @State private var editedDuration: String

    // Picker values for pace (minutes:seconds)
    @State private var paceMinutes: Int = 0
    @State private var paceSeconds: Int = 0
    @State private var showPacePicker: Bool = false

    // Picker values for duration (minutes:seconds)
    @State private var durationMinutes: Int = 0
    @State private var durationSeconds: Int = 0
    @State private var showDurationPicker: Bool = false

    init(step: WorkoutStep, index: Int, isEditing: Bool = false, onPaceChanged: @escaping (String?) -> Void, onDurationChanged: @escaping (Double) -> Void) {
        self.step = step
        self.index = index
        self.isEditing = isEditing
        self.onPaceChanged = onPaceChanged
        self.onDurationChanged = onDurationChanged

        // Initialize editable values
        _editedPace = State(initialValue: step.targetPace ?? "")
        _editedDuration = State(initialValue: Self.formatGoalValue(step.goal))

        // Initialize pace picker values
        if let pace = step.targetPace {
            let components = pace.split(separator: ":")
            if components.count == 2,
               let min = Int(components[0]),
               let sec = Int(components[1]) {
                _paceMinutes = State(initialValue: min)
                _paceSeconds = State(initialValue: sec)
            }
        }

        // Initialize duration picker values
        let minutes = Int(step.goal.value / 60)
        let seconds = Int(step.goal.value.truncatingRemainder(dividingBy: 60))
        _durationMinutes = State(initialValue: minutes)
        _durationSeconds = State(initialValue: seconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Index badge
                Text("\(index)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(colorForStepType(step.type))
                    .clipShape(Circle())

                // Step type
                Text(step.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                // Goal (editable for duration in edit mode)
                if isEditing && step.goal.type == .duration {
                    Button(action: {
                        showDurationPicker = true
                    }) {
                        HStack(spacing: 2) {
                            Text("\(durationMinutes):\(String(format: "%02d", durationSeconds))")
                                .font(.caption)
                                .foregroundStyle(Color.irTextPrimary)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(Color.irTextSecondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.irCardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                } else {
                    Text(goalText(step.goal))
                        .font(.caption)
                        .foregroundStyle(Color.irTextSecondary)
                }
            }

            // Pace, Distance, and Heart Rate Zone
            HStack(spacing: 12) {
                // Pace (editable in edit mode)
                HStack(spacing: 4) {
                    Image(systemName: "speedometer")
                        .font(.subheadline)
                        .foregroundStyle(Color.irTextSecondary)

                    if isEditing {
                        Button(action: {
                            showPacePicker = true
                        }) {
                            HStack(spacing: 2) {
                                Text("\(paceMinutes):\(String(format: "%02d", paceSeconds))")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.irTextPrimary)
                                Text(String(localized: "/km", comment: "Pace unit suffix"))
                                    .font(.subheadline)
                                    .foregroundStyle(Color.irTextSecondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(Color.irTextSecondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.irCardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    } else {
                        Text(step.paceFormatted ?? "-")
                            .font(.subheadline)
                            .foregroundStyle(Color.irTextSecondary)
                    }
                }

                // Distance (calculated from duration + pace, or direct distance goal)
                if let distance = step.distanceFormatted {
                    HStack(spacing: 4) {
                        Image(systemName: "figure.run")
                            .font(.subheadline)
                            .foregroundStyle(Color.irTextSecondary)
                        Text(distance)
                            .font(.subheadline)
                            .foregroundStyle(Color.irTextSecondary)
                    }
                }

                // Heart Rate Zone (read-only)
                if let hrZone = step.targetHeartRateZone {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(.subheadline)
                            .foregroundStyle(Color.irTextSecondary)
                        Text("\(String(localized: "Zone", comment: "Heart rate zone prefix")) \(hrZone)")
                            .font(.subheadline)
                            .foregroundStyle(Color.irTextSecondary)
                    }
                }
            }

            // Instructions
            if let instructions = step.instructions {
                Text(instructions)
                    .font(.caption)
                    .foregroundStyle(Color.irTextSecondary)
                    .italic()
            }
        }
        .padding()
        .background {
            if isEditing {
                Color.irCardBackground
            } else {
                Color.clear.background(Color.irCardBackground)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $showPacePicker) {
            PacePickerView(
                minutes: $paceMinutes,
                seconds: $paceSeconds,
                onSave: {
                    let pace = "\(paceMinutes):\(String(format: "%02d", paceSeconds))"
                    onPaceChanged(pace)
                    showPacePicker = false
                }
            )
            .presentationDetents([.height(300)])
        }
        .sheet(isPresented: $showDurationPicker) {
            DurationPickerView(
                minutes: $durationMinutes,
                seconds: $durationSeconds,
                onSave: {
                    let totalSeconds = Double(durationMinutes * 60 + durationSeconds)
                    onDurationChanged(totalSeconds)
                    showDurationPicker = false
                }
            )
            .presentationDetents([.height(300)])
        }
    }

    private func colorForStepType(_ type: WorkoutStep.StepType) -> Color {
        switch type {
        case .warmup: return .blue
        case .work: return .red
        case .recovery: return .green
        case .cooldown: return .purple
        case .interval: return .orange
        }
    }

    private func goalText(_ goal: WorkoutGoal) -> String {
        switch goal.type {
        case .distance:
            if let formatted = goal.distanceFormatted {
                return formatted
            }
            return "\(Int(goal.value))\(String(localized: "m", comment: "Meters unit abbreviation"))"
        case .duration:
            if let formatted = goal.durationFormatted {
                return formatted
            }
            return "\(Int(goal.value))\(String(localized: "s", comment: "Seconds unit abbreviation"))"
        case .open:
            return String(localized: "Open", comment: "Open goal type")
        }
    }

    // MARK: - Helpers

    private static func formatGoalValue(_ goal: WorkoutGoal) -> String {
        switch goal.type {
        case .duration:
            let minutes = Int(goal.value / 60)
            let seconds = Int(goal.value.truncatingRemainder(dividingBy: 60))
            return String(format: "%d:%02d", minutes, seconds)
        default:
            return ""
        }
    }

    private static func parseDuration(_ text: String) -> Double? {
        let components = text.split(separator: ":")
        guard components.count == 2,
              let minutes = Double(components[0]),
              let seconds = Double(components[1]) else {
            return nil
        }
        return (minutes * 60) + seconds
    }

    private static func isValidPaceFormat(_ text: String) -> Bool {
        let components = text.split(separator: ":")
        guard components.count == 2,
              let _ = Double(components[0]),
              let _ = Double(components[1]) else {
            return false
        }
        return true
    }
}

// MARK: - Pace Picker View

struct PacePickerView: View {
    @Binding var minutes: Int
    @Binding var seconds: Int
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            VStack {
                HStack(spacing: 0) {
                    // Minutes picker
                    Picker("", selection: $minutes) {
                        ForEach(0..<60, id: \.self) { minute in
                            Text("\(minute)")
                                .tag(minute)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)

                    Text(":")
                        .font(.title)
                        .fontWeight(.semibold)

                    // Seconds picker
                    Picker("", selection: $seconds) {
                        ForEach(0..<60, id: \.self) { second in
                            Text(String(format: "%02d", second))
                                .tag(second)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)

                    Text(String(localized: "/km", comment: "Pace unit suffix"))
                        .font(.headline)
                        .foregroundStyle(Color.irTextSecondary)
                        .padding(.leading, 8)
                }
                .padding()
            }
            .navigationTitle(String(localized: "Pace", comment: "Pace picker title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done", comment: "Done button")) {
                        onSave()
                    }
                }
            }
        }
    }
}

// MARK: - Duration Picker View

struct DurationPickerView: View {
    @Binding var minutes: Int
    @Binding var seconds: Int
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            VStack {
                HStack(spacing: 0) {
                    // Minutes picker
                    Picker("", selection: $minutes) {
                        ForEach(0..<60, id: \.self) { minute in
                            Text("\(minute)")
                                .tag(minute)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)

                    Text(String(localized: "min", comment: "Minutes abbreviation"))
                        .font(.headline)
                        .foregroundStyle(Color.irTextSecondary)

                    // Seconds picker
                    Picker("", selection: $seconds) {
                        ForEach(0..<60, id: \.self) { second in
                            Text(String(format: "%02d", second))
                                .tag(second)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)

                    Text(String(localized: "sec", comment: "Seconds abbreviation"))
                        .font(.headline)
                        .foregroundStyle(Color.irTextSecondary)
                        .padding(.trailing, 8)
                }
                .padding()
            }
            .navigationTitle(String(localized: "Duration", comment: "Duration picker title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done", comment: "Done button")) {
                        onSave()
                    }
                }
            }
        }
    }
}

// MARK: - Workout Feature Row Component

struct WorkoutFeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 30)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.irTextPrimary)

            Spacer()
        }
    }
}

// MARK: - Workout Export Success View

struct WorkoutExportSuccessView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // Background gradient matching app style
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.05),
                    Color(.systemBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Success icon with animation
                ZStack {
                    Circle()
                        .fill(.green.opacity(0.15))
                        .frame(width: 120, height: 120)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.green.gradient)
                        .symbolEffect(.bounce)
                }

                // Success message
                VStack(spacing: 8) {
                    Text(String(localized: "Export Successful!", comment: "Success title after workout export"))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.irTextPrimary)

                    Text(String(localized: "Your workout has been exported successfully. Open the Fitness app to see it.", comment: "Success message after workout export"))
                        .font(.body)
                        .foregroundStyle(Color.irTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()

                // Continue button
                Button(action: {
                    dismiss()
                }) {
                    Text(String(localized: "Continue", comment: "Continue button after successful export"))
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .blue.opacity(0.4), radius: 8, y: 4)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
        .onAppear {
            // Trigger haptic feedback on success
            let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
            impactFeedback.impactOccurred()
        }
    }
}

#Preview {
    WorkoutPlanView()
        .environmentObject(RevenueCatManager.shared)
}
