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
            let language = AppLanguage.current

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
        case .unknownError(let code, _):
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

            let language = AppLanguage.current

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
                Color.irBackgroundApp.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Spacing.xl) {
                        if !revenueCatManager.hasAIAccess {
                            subscriptionCTAView
                        } else {
                            if !viewModel.showPreview {
                                generationView
                            } else if let workout = viewModel.generatedWorkout {
                                workoutPreviewView(workout: workout)
                            }
                        }
                    }
                    .padding(Spacing.base)
                }
                .scrollDismissesKeyboard(.interactively)
                .onTapGesture {
                    isTextFieldFocused = false
                }
            }
            .navigationTitle(String(localized: "Workout Plan", comment: "Workout plan screen title"))
            .navigationBarTitleDisplayMode(.inline)
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
                            .foregroundStyle(Color.irTextSecondary)
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
                            .accessibilityLabel(String(localized: "Edit workout", comment: "Edit workout accessibility label"))

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
        VStack(spacing: Spacing.lg) {
            Spacer()

            // Icon with gradient
            ZStack {
                Circle()
                    .fill(Color.irCardBackground)
                    .frame(width: 100, height: 100)
                    .shadow(color: Color.irShadowStrong, radius: 20, y: 10)

                Image(systemName: "sparkles")
                    .font(IRFont.numLG)
                    .foregroundStyle(LinearGradient.irAIAccent)
            }
            .padding(.top, Spacing.sm)

            // Title & Description
            VStack(spacing: Spacing.sm) {
                Text(String(localized: "AI Workout Generator", comment: "Subscription CTA title"))
                    .font(IRFont.title3)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text(String(localized: "Subscribe to unlock AI-powered workout generation, personalized training plans, and smart suggestions based on your training history.", comment: "Subscription CTA description"))
                    .font(IRFont.body)
                    .foregroundStyle(Color.irTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xxl)
            }

            // Features list
            VStack(alignment: .leading, spacing: Spacing.md) {
                WorkoutFeatureRow(icon: "sparkles", text: String(localized: "AI-powered workout generation", comment: "Feature"))
                WorkoutFeatureRow(icon: "brain.head.profile", text: String(localized: "Smart suggestions based on your history", comment: "Feature"))
                WorkoutFeatureRow(icon: "pencil", text: String(localized: "Editable workout plans", comment: "Feature"))
                WorkoutFeatureRow(icon: "applewatch", text: String(localized: "Export to Apple Fitness", comment: "Feature"))
            }
            .padding(.horizontal, Spacing.xxl)

            Spacer()

            // Subscribe button
            Button(action: {
                showSubscriptionPaywall = true
            }) {
                HStack {
                    Image(systemName: "sparkles")
                    Text(String(localized: "Subscribe Now", comment: "Subscribe button"))
                }
                .font(IRFont.body)
                .fontWeight(.semibold)
                .foregroundStyle(Color.irTextOnAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(Color.irPrimaryAccent)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            }
            .padding(.horizontal, Spacing.xxl)

            // Restore purchases
            Button(action: {
                Task {
                    do {
                        try await revenueCatManager.restorePurchases(source: "workout_plan")
                    } catch {
                        print("Error restoring purchases: \(error.localizedDescription)")
                    }
                }
            }) {
                Text(String(localized: "Restore Purchases", comment: "Restore button"))
                    .font(IRFont.body)
                    .foregroundStyle(Color.irPrimaryAccent)
            }
            .padding(.bottom, Spacing.base)
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
        VStack(alignment: .leading, spacing: Spacing.cardPadding) {
            heroTitle

            coachContextCard

            composer

            if let error = viewModel.error {
                errorView(error)
            }

            suggestionHero

            presetsGrid

            if viewModel.isGeneratingSmartSuggestion {
                Button {
                    viewModel.cancelSmartSuggestion()
                } label: {
                    Text(String(localized: "Cancel", comment: "Cancel smart suggestion button"))
                        .font(IRFont.body)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.irError)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .background(Color.irCardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.sm)
                                .stroke(Color.irError.opacity(0.3), lineWidth: 1)
                        )
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Hero title

    private var heroTitle: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            (Text(String(localized: "Which workout", comment: "Plan generator hero title prefix"))
                .foregroundStyle(Color.irTextPrimary)
             + Text("\n")
             + Text(String(localized: "for ", comment: "Plan generator hero title middle"))
                .foregroundStyle(Color.irTextPrimary)
             + Text(String(localized: "today", comment: "Plan generator hero title accent word"))
                .foregroundStyle(Color.irPrimaryAccent)
             + Text(String(localized: " ?", comment: "Plan generator hero title suffix"))
                .foregroundStyle(Color.irTextPrimary))
                .font(IRFont.title1)
                .kerning(IRTracking.title1)

            Text(String(localized: "Describe your intent, or let Coach suggest one based on today's readiness.", comment: "Plan generator subtitle"))
                .font(IRFont.body)
                .foregroundStyle(Color.irTextSecondary)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Coach context card

    private var coachContextCard: some View {
        let score = DailyMetricsCache.shared.getHistoricalReadinessScore(for: Date())
        let readiness = ReadinessLabel(score: score)

        return HStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .stroke(Color.irBorder, lineWidth: 5)

                Circle()
                    .trim(from: 0, to: CGFloat(readiness.progress))
                    .stroke(readiness.color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Text(readiness.scoreLabel)
                    .font(IRFont.numSM.weight(.heavy))
                    .foregroundStyle(Color.irTextPrimary)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "TODAY'S FORM", comment: "Plan generator readiness label"))
                    .font(IRFont.eyebrow)
                    .tracking(IRTracking.eyebrow)
                    .foregroundStyle(Color.irTextTertiary)

                (Text(String(localized: "Availability ", comment: "Plan generator readiness sentence prefix"))
                    .foregroundStyle(Color.irTextPrimary)
                 + Text(readiness.statusWord)
                    .foregroundStyle(readiness.color)
                 + Text(String(localized: " — aim for low-to-moderate load.", comment: "Plan generator readiness sentence suffix"))
                    .foregroundStyle(Color.irTextPrimary))
                    .font(IRFont.bodyEmphasized)
                    .lineSpacing(2)
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.dash)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    readiness.color.opacity(0.10),
                    Color.irCardBackground
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .detailCard()
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(
                String(localized: "E.g., '10x400m speed intervals with 1 min recovery'", comment: "Prompt placeholder"),
                text: $viewModel.promptText,
                axis: .vertical
            )
            .focused($isTextFieldFocused)
            .lineLimit(3...6)
            .submitLabel(.done)
            .onSubmit { isTextFieldFocused = false }
            .font(IRFont.bodyEmphasized)
            .padding(.horizontal, Spacing.base)
            .padding(.vertical, Spacing.dash)

            Divider().background(Color.irBorder)

            HStack {
                Spacer()

                Button {
                    Task { await viewModel.generateWorkout() }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        if viewModel.isGenerating {
                            ProgressView()
                                .controlSize(.small)
                                .tint(viewModel.promptText.isEmpty ? Color.irTextSecondary : Color.irTextOnAccent)
                        } else {
                            Image(systemName: "sparkles")
                                .font(IRFont.caption.weight(.bold))
                        }

                        Text(viewModel.isGenerating
                             ? String(localized: "Generating...", comment: "Generating button text")
                             : String(localized: "Generate", comment: "Generate workout button"))
                            .font(IRFont.caption.weight(.bold))
                    }
                    .foregroundStyle(viewModel.promptText.isEmpty ? Color.irTextSecondary : Color.irTextOnAccent)
                    .padding(.horizontal, Spacing.dash)
                    .padding(.vertical, Spacing.sm)
                    .background(
                        Capsule()
                            .fill(viewModel.promptText.isEmpty ? Color.irBorder : Color.irPrimaryAccent)
                    )
                    .shadow(color: viewModel.promptText.isEmpty
                            ? .clear
                            : Color.irPrimaryAccent.opacity(0.4),
                            radius: 12, y: 4)
                }
                .disabled(viewModel.promptText.isEmpty || viewModel.isGenerating)
            }
            .padding(Spacing.md)
        }
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(
                    viewModel.promptText.isEmpty ? Color.irBorder : Color.irPrimaryAccent,
                    lineWidth: 0.5
                )
        )
    }

    // MARK: - Suggestion hero (smart suggestion)

    private var suggestionHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            DashboardEyebrow(title: String(localized: "Suggested for you", comment: "Plan generator suggestion eyebrow"))

            Button {
                Task { await viewModel.generateSmartSuggestion() }
            } label: {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack {
                        HStack(spacing: Spacing.xs) {
                            ZStack {
                                RoundedRectangle(cornerRadius: Radius.xs)
                                    .fill(Color.irPrimaryAccent)
                                Image(systemName: "sparkles")
                                    .font(IRFont.microLabel)
                                    .foregroundStyle(Color.irTextOnAccent)
                            }
                            .frame(width: 18, height: 18)

                            Text(String(localized: "COACH RECOMMENDATION", comment: "Plan generator suggestion header"))
                                .font(IRFont.eyebrow)
                                .tracking(IRTracking.eyebrow)
                                .foregroundStyle(Color.irPrimaryAccent)
                        }

                        Spacer()

                        if viewModel.isGeneratingSmartSuggestion {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color.irPrimaryAccent)
                        } else {
                            Image(systemName: "arrow.up.right")
                                .font(IRFont.eyebrow)
                                .foregroundStyle(Color.irTextSecondary)
                        }
                    }

                    Text(String(localized: "Suggest a workout based on my history", comment: "AI suggestion prompt"))
                        .font(IRFont.headline)
                        .lineSpacing(1)
                        .foregroundStyle(Color.irTextPrimary)
                        .multilineTextAlignment(.leading)

                    Text(String(localized: "Coach reads your training load, recovery and recent sessions to pick a session that fits today.", comment: "Plan generator suggestion description"))
                        .font(IRFont.caption)
                        .lineSpacing(2)
                        .foregroundStyle(Color.irTextSecondary)
                        .multilineTextAlignment(.leading)

                    if let error = viewModel.smartSuggestionError {
                        Divider().background(Color.irBorder)
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(IRFont.caption)
                                .foregroundStyle(Color.irWarning)
                            Text(error)
                                .font(IRFont.caption)
                                .foregroundStyle(Color.irTextSecondary)
                        }
                    }
                }
                .padding(Spacing.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [
                            Color.irPrimaryAccent.opacity(0.10),
                            Color.irCardBackground
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .strokeBorder(Color.irPrimaryAccent.opacity(0.6), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isGeneratingSmartSuggestion)
        }
    }

    // MARK: - Presets grid

    private var presetsGrid: some View {
        VStack(alignment: .leading, spacing: 0) {
            DashboardEyebrow(title: String(localized: "Templates", comment: "Plan generator presets eyebrow"))

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: Spacing.sm), GridItem(.flexible(), spacing: Spacing.sm)],
                spacing: Spacing.sm
            ) {
                ForEach(WorkoutPreset.all) { preset in
                    Button {
                        viewModel.promptText = preset.promptSeed
                        isTextFieldFocused = false
                    } label: {
                        WorkoutPresetCard(preset: preset)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Preview View

    private func workoutPreviewView(workout: AIGeneratedWorkout) -> some View {
        VStack(spacing: 0) {
            // Workout Header (pinned to top)
            VStack(spacing: Spacing.sm) {
                // Conditional workout name (editable in edit mode)
                if isEditing {
                    TextField(String(localized: "Workout name", comment: "Workout name placeholder"), text: $editedWorkoutName)
                        .font(IRFont.title3)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal)
                        .padding(Spacing.sm)
                        .background(Color.irCardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
                } else {
                    Text(workout.name)
                        .font(IRFont.title3)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal)
                }

                Text(workout.description)
                    .font(IRFont.caption)
                    .foregroundStyle(Color.irTextSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                // Stats
                HStack(spacing: Spacing.md) {
                    if let distance = workout.totalDistanceFormatted {
                        StatBadge(icon: "figure.run", value: distance)
                    }
                    if let duration = workout.estimatedDurationFormatted {
                        StatBadge(icon: "clock", value: duration)
                    }
                    StatBadge(icon: "list.bullet", value: "\(workout.steps.count) \(String(localized: "steps", comment: "Steps count unit"))")
                }
                .padding(.top, Spacing.xxs)
            }
            .padding(Spacing.base)
            .background(Color.irCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .padding(.bottom, Spacing.base)

            // Scrollable Steps List
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.base) {
                    // Steps List
                    Text(String(localized: "Workout Steps", comment: "Steps section title"))
                        .font(IRFont.headline)
                        .padding(.top, Spacing.sm)

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
                                    .tint(Color.irTextOnAccent)
                                Text(String(localized: "Exporting...", comment: "Exporting button text"))
                            } else {
                                Image(systemName: "applewatch")
                                Text(String(localized: "Export to Fitness App", comment: "Export button text"))
                            }
                        }
                        .font(IRFont.headline)
                        .foregroundStyle(Color.irTextOnAccent)
                        .frame(maxWidth: .infinity)
                        .padding(Spacing.base)
                        .background(Color.irPrimaryAccent)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                        .shadow(color: Color.irPrimaryAccent.opacity(0.4), radius: 8, y: 4)
                    }
                    .disabled(WorkoutKitManager.shared.isExporting || isEditing || viewModel.exportCooldown || viewModel.consecutiveExportFailures >= 3 || viewModel.exportAuthDenied)
                    .opacity(viewModel.exportAuthDenied ? 0.5 : 1.0)
                    .padding(.top, Spacing.sm)
                }
                .padding(.bottom, Spacing.base)
            }
        }
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.irError)
                Text(error)
                    .font(IRFont.caption)
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
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: "arrow.clockwise")
                            Text(String(localized: "Retry", comment: "Retry export authorization button"))
                        }
                        .font(IRFont.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.irPrimaryAccent)
                    }
                }
                // After second denial, exportAuthDenied=true, no retry button, export button is grayed out
            }
        }
        .padding(Spacing.base)
        .background(Color.irError.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
    }
}


// MARK: - Readiness label helper

private struct ReadinessLabel {
    let scoreLabel: String
    let statusWord: String
    let color: Color
    let progress: Double

    init(score: Int?) {
        if let score {
            scoreLabel = "\(score)"
            progress = max(0, min(1, Double(score) / 100.0))
            switch score {
            case 80...100:
                statusWord = String(localized: "excellent", comment: "Readiness status word - excellent")
                color = .irSuccess
            case 60..<80:
                statusWord = String(localized: "good", comment: "Readiness status word - good")
                color = .irSuccess
            case 40..<60:
                statusWord = String(localized: "fair", comment: "Readiness status word - fair")
                color = .irWarning
            default:
                statusWord = String(localized: "low", comment: "Readiness status word - low")
                color = .irError
            }
        } else {
            scoreLabel = "—"
            progress = 0
            statusWord = String(localized: "unknown", comment: "Readiness status word - unknown")
            color = Color.irTextTertiary
        }
    }
}

// MARK: - Workout preset model

struct WorkoutPreset: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let durationLabel: String
    let intensityLabel: String
    let load: Int
    let color: Color
    let promptSeed: String

    static let all: [WorkoutPreset] = [
        WorkoutPreset(
            id: "intervals",
            title: String(localized: "Intervals", comment: "Workout preset - intervals"),
            subtitle: String(localized: "10 × 400 m", comment: "Workout preset subtitle - intervals"),
            durationLabel: "55 min",
            intensityLabel: "Z4",
            load: 4,
            color: .irError,
            promptSeed: String(localized: "10x400m speed intervals with 1 min recovery", comment: "Preset prompt - intervals")
        ),
        WorkoutPreset(
            id: "tempo",
            title: String(localized: "Tempo run", comment: "Workout preset - tempo"),
            subtitle: String(localized: "5 km at threshold pace", comment: "Workout preset subtitle - tempo"),
            durationLabel: "35 min",
            intensityLabel: "Z3",
            load: 3,
            color: .irWarning,
            promptSeed: String(localized: "5km tempo run at threshold pace", comment: "Preset prompt - tempo")
        ),
        WorkoutPreset(
            id: "pyramid",
            title: String(localized: "Pyramid", comment: "Workout preset - pyramid"),
            subtitle: String(localized: "400-800-1200-800-400", comment: "Workout preset subtitle - pyramid"),
            durationLabel: "50 min",
            intensityLabel: "Z3-4",
            load: 4,
            color: Color.irPrimaryAccent,
            promptSeed: String(localized: "Pyramid workout (400-800-1200-800-400) with active recovery", comment: "Preset prompt - pyramid")
        ),
        WorkoutPreset(
            id: "long",
            title: String(localized: "Long run", comment: "Workout preset - long run"),
            subtitle: String(localized: "12-15 km endurance", comment: "Workout preset subtitle - long run"),
            durationLabel: "1h25",
            intensityLabel: "Z2",
            load: 3,
            color: .irSuccess,
            promptSeed: String(localized: "Easy 12-15km endurance run at conversational pace", comment: "Preset prompt - long run")
        ),
        WorkoutPreset(
            id: "fartlek",
            title: String(localized: "Fartlek", comment: "Workout preset - fartlek"),
            subtitle: String(localized: "Free-form pace play", comment: "Workout preset subtitle - fartlek"),
            durationLabel: "40 min",
            intensityLabel: "Z2-4",
            load: 3,
            color: Color.irPrimaryAccent,
            promptSeed: String(localized: "40 min fartlek with free-form pace variations", comment: "Preset prompt - fartlek")
        )
    ]
}

private struct WorkoutPresetCard: View {
    let preset: WorkoutPreset

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .font(IRFont.eyebrow)
                    .foregroundStyle(preset.color)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.xs)
                            .fill(preset.color.opacity(0.18))
                    )

                Spacer()

                HStack(spacing: Spacing.xxs) {
                    ForEach(1...5, id: \.self) { idx in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(idx <= preset.load ? preset.color : Color.irBorder)
                            .frame(width: 4, height: 9)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(preset.title)
                    .font(IRFont.footnote.weight(.bold))
                    .kerning(-0.1)
                    .foregroundStyle(Color.irTextPrimary)

                Text(preset.subtitle)
                    .font(IRFont.eyebrow)
                    .foregroundStyle(Color.irTextSecondary)
                    .lineLimit(1)
            }

            Divider().background(Color.irBorder)

            HStack {
                Text(preset.durationLabel)
                    .font(IRFont.monoSM)
                    .foregroundStyle(Color.irTextSecondary)

                Spacer()

                Text(preset.intensityLabel)
                    .font(IRFont.monoSM.weight(.bold))
                    .foregroundStyle(preset.color)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(preset.color.opacity(0.14))
                    )
            }
        }
        .padding(Spacing.dash)
        .frame(maxWidth: .infinity, alignment: .leading)
        .detailCard()
    }
}

// MARK: - Supporting Views

struct StatBadge: View {
    let icon: String
    let value: String

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: icon)
                .font(IRFont.caption)
            Text(value)
                .font(IRFont.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xxs)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
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
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                // Index badge
                Text("\(index)")
                    .font(IRFont.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.irTextOnAccent)
                    .frame(width: 24, height: 24)
                    .background(colorForStepType(step.type))
                    .clipShape(Circle())

                // Step type
                Text(step.displayName)
                    .font(IRFont.body)
                    .fontWeight(.semibold)

                Spacer()

                // Goal (editable for duration in edit mode)
                if isEditing && step.goal.type == .duration {
                    Button(action: {
                        showDurationPicker = true
                    }) {
                        HStack(spacing: Spacing.xxs) {
                            Text(Formatters.paceClock(Double(durationMinutes * 60 + durationSeconds)))
                                .font(IRFont.caption)
                                .foregroundStyle(Color.irTextPrimary)
                            Image(systemName: "chevron.right")
                                .font(IRFont.microLabel)
                                .foregroundStyle(Color.irTextSecondary)
                        }
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xxs)
                        .background(Color.irCardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
                    }
                } else {
                    Text(goalText(step.goal))
                        .font(IRFont.caption)
                        .foregroundStyle(Color.irTextSecondary)
                }
            }

            // Pace, Distance, and Heart Rate Zone
            HStack(spacing: Spacing.md) {
                // Pace (editable in edit mode)
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "speedometer")
                        .font(IRFont.body)
                        .foregroundStyle(Color.irTextSecondary)

                    if isEditing {
                        Button(action: {
                            showPacePicker = true
                        }) {
                            HStack(spacing: Spacing.xxs) {
                                Text(Formatters.paceClock(Double(paceMinutes * 60 + paceSeconds)))
                                    .font(IRFont.body)
                                    .foregroundStyle(Color.irTextPrimary)
                                Text(Formatters.paceUnitSuffix())
                                    .font(IRFont.body)
                                    .foregroundStyle(Color.irTextSecondary)
                                Image(systemName: "chevron.right")
                                    .font(IRFont.caption)
                                    .foregroundStyle(Color.irTextSecondary)
                            }
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xxs)
                            .background(Color.irCardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
                        }
                    } else {
                        Text(step.paceFormatted ?? "-")
                            .font(IRFont.body)
                            .foregroundStyle(Color.irTextSecondary)
                    }
                }

                // Distance (calculated from duration + pace, or direct distance goal)
                if let distance = step.distanceFormatted {
                    HStack(spacing: Spacing.xxs) {
                        Image(systemName: "figure.run")
                            .font(IRFont.body)
                            .foregroundStyle(Color.irTextSecondary)
                        Text(distance)
                            .font(IRFont.body)
                            .foregroundStyle(Color.irTextSecondary)
                    }
                }

                // Heart Rate Zone (read-only)
                if let hrZone = step.targetHeartRateZone {
                    HStack(spacing: Spacing.xxs) {
                        Image(systemName: "heart.fill")
                            .font(IRFont.body)
                            .foregroundStyle(Color.irTextSecondary)
                        Text("\(String(localized: "Zone", comment: "Heart rate zone prefix")) \(hrZone)")
                            .font(IRFont.body)
                            .foregroundStyle(Color.irTextSecondary)
                    }
                }
            }

            // Instructions
            if let instructions = step.instructions {
                Text(instructions)
                    .font(IRFont.caption)
                    .foregroundStyle(Color.irTextSecondary)
                    .italic()
            }
        }
        .padding(Spacing.base)
        .background {
            if isEditing {
                Color.irCardBackground
            } else {
                Color.clear.background(Color.irCardBackground)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
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
        case .warmup: return Color.irPrimaryAccent
        case .work: return Color.irError
        case .recovery: return Color.irSuccess
        case .cooldown: return Color.irPrimaryAccent
        case .interval: return Color.irWarning
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
                        .font(IRFont.title2)
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

                    Text(Formatters.paceUnitSuffix())
                        .font(IRFont.headline)
                        .foregroundStyle(Color.irTextSecondary)
                        .padding(.leading, Spacing.sm)
                }
                .padding(Spacing.base)
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
                        .font(IRFont.headline)
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
                        .font(IRFont.headline)
                        .foregroundStyle(Color.irTextSecondary)
                        .padding(.trailing, Spacing.sm)
                }
                .padding(Spacing.base)
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
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(IRFont.title3)
                .foregroundStyle(LinearGradient.irAIAccent)
                .frame(width: 30)

            Text(text)
                .font(IRFont.body)
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
                    Color.irPrimaryAccent.opacity(0.05),
                    Color.irBackgroundApp
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: Spacing.xxl) {
                Spacer()

                // Success icon with animation
                ZStack {
                    Circle()
                        .fill(Color.irSuccess.opacity(0.15))
                        .frame(width: 120, height: 120)

                    Image(systemName: "checkmark.circle.fill")
                        .font(IRFont.numXL)
                        .foregroundStyle(Color.irSuccess.gradient)
                        .symbolEffect(.bounce)
                }

                // Success message
                VStack(spacing: Spacing.sm) {
                    Text(String(localized: "Export Successful!", comment: "Success title after workout export"))
                        .font(IRFont.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.irTextPrimary)

                    Text(String(localized: "Your workout has been exported successfully. Open the Fitness app to see it.", comment: "Success message after workout export"))
                        .font(IRFont.body)
                        .foregroundStyle(Color.irTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.xxl)
                }

                Spacer()

                // Continue button
                Button(action: {
                    dismiss()
                }) {
                    Text(String(localized: "Continue", comment: "Continue button after successful export"))
                        .font(IRFont.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.irTextOnAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.base)
                        .background(Color.irPrimaryAccent)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                        .shadow(color: Color.irPrimaryAccent.opacity(0.4), radius: 8, y: 4)
                }
                .padding(.horizontal, Spacing.xxl)
                .padding(.bottom, Spacing.xxl)
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
