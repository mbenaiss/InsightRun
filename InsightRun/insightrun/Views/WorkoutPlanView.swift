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
    @Published var promptText = ""
    @Published var isGenerating = false
    @Published var generatedWorkout: AIGeneratedWorkout?
    @Published var error: String?
    @Published var showPreview = false

    private let backendClient = BackendAPIClient.shared
    private let workoutKitManager = WorkoutKitManager.shared
    private let healthKitManager = HealthKitManager.shared

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

        isGenerating = true
        error = nil
        generatedWorkout = nil

        // Track generation requested
        AnalyticsService.shared.trackWorkoutGenerationRequested(
            prompt: promptText,
            userLevel: nil
        )

        let startTime = Date()

        do {
            // Get user context from HealthKit
            let userContext = await buildUserContext()

            // Get user language
            let language = Locale.current.language.languageCode?.identifier ?? "en"

            // Call backend
            let response = try await backendClient.generateWorkout(
                userQuestion: promptText,
                language: language,
                userContext: userContext,
                model: nil // Use default (Gemini Flash)
            )

            // Convert backend response to AIGeneratedWorkout
            let workout = convertToAIWorkout(response.workout)

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

        do {
            try await workoutKitManager.exportToFitnessApp(workout)

            // Success feedback
            error = nil
            print("✅ Workout exported to Fitness app")

        } catch {
            self.error = error.localizedDescription
            print("❌ Export error: \(error)")
        }
    }

    func clearWorkout() {
        generatedWorkout = nil
        showPreview = false
        promptText = ""
        error = nil
    }

    // MARK: - Helper Methods

    private func buildUserContext() async -> WorkoutGenerationRequest.UserContext {
        // Get recent workouts to calculate average pace
        let recentWorkouts = await healthKitManager.fetchWorkouts(limit: 10)

        let avgPace = calculateAveragePace(workouts: recentWorkouts)
        let vo2Max = await healthKitManager.fetchLatestVO2Max()

        return WorkoutGenerationRequest.UserContext(
            avgPace: avgPace,
            vo2Max: vo2Max,
            recentWorkouts: recentWorkouts.count,
            fitnessLevel: determineFitnessLevel(avgPace: avgPace, vo2Max: vo2Max)
        )
    }

    private func calculateAveragePace(workouts: [WorkoutModel]) -> Double? {
        let paces = workouts.compactMap { $0.averagePace }
        guard !paces.isEmpty else { return nil }
        return paces.reduce(0, +) / Double(paces.count)
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

    private func handleError(_ error: BackendError) {
        switch error {
        case .unauthorized:
            self.error = String(localized: "Authentication error", comment: "Workout generation error")
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
}

struct WorkoutPlanView: View {
    @StateObject private var viewModel = WorkoutPlanViewModel()
    @FocusState private var isTextFieldFocused: Bool

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
                        if !viewModel.showPreview {
                            // Generation Screen
                            generationView
                        } else if let workout = viewModel.generatedWorkout {
                            // Preview Screen
                            workoutPreviewView(workout: workout)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(String(localized: "Workout Plan", comment: "Workout plan screen title"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
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
                    .fill(.ultraThinMaterial)
                    .frame(width: 100, height: 100)
                    .shadow(color: .black.opacity(0.1), radius: 20, y: 10)

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
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Input Area
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "What workout do you want?", comment: "Prompt input label"))
                    .font(.headline)

                TextField(String(localized: "E.g., '10x400m speed intervals'", comment: "Prompt placeholder"), text: $viewModel.promptText, axis: .vertical)
                    .focused($isTextFieldFocused)
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .lineLimit(3...6)
            }

            // Sample Prompts (only shown when input is empty)
            if viewModel.promptText.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: "Or try these", comment: "Sample prompts label"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    ForEach(viewModel.samplePrompts, id: \.self) { sample in
                        Button(action: {
                            viewModel.promptText = sample
                            isTextFieldFocused = false
                        }) {
                            HStack {
                                Image(systemName: "lightbulb.fill")
                                    .font(.caption)
                                    .foregroundColor(.yellow)
                                Text(sample)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(12)
                            .background(.ultraThinMaterial)
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
                .foregroundColor(.white)
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
                        .background(Color(.systemGray6))
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
                    .foregroundColor(.secondary)
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
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.bottom, 16)

            // Scrollable Steps List
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Visual Representation
                    if workout.steps.count <= 15 {
                        WorkoutVisualization(workout: workout)
                    }

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
                }
                .padding(.bottom, 100) // Space for button
            }

            // Error Display
            if let error = viewModel.error {
                errorView(error)
                    .padding(.horizontal)
            }

            // Export Button (pinned to bottom)
            VStack {
                Divider()
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
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .blue.opacity(0.4), radius: 8, y: 4)
                }
                .disabled(WorkoutKitManager.shared.isExporting || isEditing)
                .padding()
            }
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(error)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.1))
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
        .background(.ultraThinMaterial)
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
                                    Text(step.type.rawValue)
                                        .font(.system(size: 8))
                                        .lineLimit(1)
                                }
                                .foregroundColor(.white)
                            )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
        .background(.ultraThinMaterial)
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
                    .foregroundColor(.white)
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
                    .foregroundColor(.secondary)
            }

            // Details
            if let pace = step.targetPace {
                DetailRow(icon: "speedometer", text: "\(pace)\(String(localized: "/km", comment: "Pace unit suffix"))")
            }

            if let hrZone = step.targetHeartRateZone {
                DetailRow(icon: "heart.fill", text: "\(String(localized: "Zone", comment: "Heart rate zone prefix")) \(hrZone)")
            }

            if let instructions = step.instructions {
                Text(instructions)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding()
        .background(.ultraThinMaterial)
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
            return "\(Int(goal.value))m"
        case .duration:
            if let formatted = goal.durationFormatted {
                return formatted
            }
            return "\(Int(goal.value))s"
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
                .foregroundColor(.secondary)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
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
                    .foregroundColor(.white)
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
                                .foregroundColor(.primary)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                } else {
                    Text(goalText(step.goal))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Pace and Heart Rate Zone on same line
            HStack(spacing: 12) {
                // Pace (editable in edit mode)
                HStack(spacing: 4) {
                    Image(systemName: "speedometer")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if isEditing {
                        Button(action: {
                            showPacePicker = true
                        }) {
                            HStack(spacing: 2) {
                                Text("\(paceMinutes):\(String(format: "%02d", paceSeconds))")
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                Text(String(localized: "/km", comment: "Pace unit suffix"))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    } else {
                        Text(step.targetPace != nil ? "\(step.targetPace!)\(String(localized: "/km", comment: "Pace unit suffix"))" : "-")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                // Heart Rate Zone (read-only)
                if let hrZone = step.targetHeartRateZone {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("\(String(localized: "Zone", comment: "Heart rate zone prefix")) \(hrZone)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Instructions
            if let instructions = step.instructions {
                Text(instructions)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding()
        .background {
            if isEditing {
                Color(.systemGray6)
            } else {
                Color.clear.background(.ultraThinMaterial)
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
            return "\(Int(goal.value))m"
        case .duration:
            if let formatted = goal.durationFormatted {
                return formatted
            }
            return "\(Int(goal.value))s"
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
                        .foregroundColor(.secondary)
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
                        .foregroundColor(.secondary)

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
                        .foregroundColor(.secondary)
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

#Preview {
    WorkoutPlanView()
}
