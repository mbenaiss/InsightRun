//
//  HistoricalAnalysisOnboardingView.swift
//  InsightRun
//
//  Onboarding view for generating historical workout summary
//  Part of the One-Time Deep Analysis strategy
//

import SwiftUI

@MainActor
class HistoricalAnalysisViewModel: ObservableObject {
    @Published var isGenerating = false
    @Published var progress: Double = 0.0
    @Published var statusMessage = ""
    @Published var errorMessage: String?
    @Published var isComplete = false

    private let healthKitManager = HealthKitManager.shared
    private let backendClient = BackendAPIClient.shared
    private let storage = HistoricalSummaryStorage.shared

    func startAnalysis() async {
        isGenerating = true
        progress = 0.0
        errorMessage = nil
        isComplete = false

        do {
            // Step 1: Fetch all workouts (20% progress)
            statusMessage = String(localized: "Fetching your workout history...", comment: "Status while fetching workouts")
            progress = 0.1

            let workouts = try await healthKitManager.fetchRunningWorkouts()

            guard !workouts.isEmpty else {
                errorMessage = String(localized: "No workouts found. Start running to build your profile!", comment: "Error when no workouts found")
                isGenerating = false
                return
            }

            print("📊 HistoricalAnalysis: Found \(workouts.count) workouts")
            progress = 0.2
            statusMessage = String(localized: "Found \(workouts.count) workouts", comment: "Status after finding workouts")

            // Step 2: Convert workouts to API format (40% progress)
            statusMessage = String(localized: "Preparing workout data...", comment: "Status while preparing data")
            progress = 0.3

            var workoutDataList: [WorkoutData] = []
            let maxWorkouts = min(workouts.count, 365) // Limit to 365 workouts

            for (index, workout) in workouts.prefix(maxWorkouts).enumerated() {
                let workoutData = convertToWorkoutData(workout: workout)
                workoutDataList.append(workoutData)

                // Update progress incrementally
                if index % 10 == 0 {
                    progress = 0.3 + (0.1 * Double(index) / Double(maxWorkouts))
                }
            }

            progress = 0.4
            print("📊 HistoricalAnalysis: Converted \(workoutDataList.count) workouts to API format")

            // Step 3: Send to backend for analysis (70% progress)
            statusMessage = String(localized: "Analyzing your training history...\nThis may take 10-20 seconds.", comment: "Status while analyzing")
            progress = 0.5

            let language = getUserLanguage()
            let model = "x-ai/grok-4-fast" // Fast model for historical analysis

            let response = try await backendClient.generateHistoricalSummary(
                workouts: workoutDataList,
                model: model,
                language: language
            )

            progress = 0.7
            print("✅ HistoricalAnalysis: Received summary from backend")

            // Step 4: Save to local storage (90% progress)
            statusMessage = String(localized: "Saving your profile...", comment: "Status while saving")
            progress = 0.8

            let summary = HistoricalSummary(
                summary: response.summary,
                workoutCount: response.workoutCount,
                dateRangeStart: workouts.last?.startDate ?? Date(),
                dateRangeEnd: workouts.first?.startDate ?? Date()
            )

            storage.save(summary)
            progress = 0.9

            // Step 5: Complete
            progress = 1.0
            statusMessage = String(localized: "Analysis complete!", comment: "Status when complete")
            isComplete = true

            print("✅ HistoricalAnalysis: Onboarding complete")

            // Wait a bit before dismissing
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        } catch let error as BackendError {
            print("❌ HistoricalAnalysis: Backend error: \(error)")
            errorMessage = error.localizedDescription
            isGenerating = false

        } catch {
            print("❌ HistoricalAnalysis: Error: \(error)")
            errorMessage = String(localized: "Failed to analyze workouts: \(error.localizedDescription)", comment: "Error during analysis")
            isGenerating = false
        }
    }

    private func getUserLanguage() -> String {
        let preferredLanguage = Locale.current.language.languageCode?.identifier ?? "en"
        let supportedLanguages = ["fr", "en", "es", "de", "it", "pt", "nl", "ja", "zh", "ko", "ar"]
        return supportedLanguages.contains(preferredLanguage) ? preferredLanguage : "en"
    }

    private func convertToWorkoutData(workout: WorkoutModel) -> WorkoutData {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        return WorkoutData(
            date: formatter.string(from: workout.startDate),
            duration: workout.duration,
            distance: workout.distance ?? 0,
            calories: workout.totalEnergyBurned,
            pace: workout.averagePace,
            speed: workout.averageSpeed,
            heartRate: nil, // Skip detailed metrics for bulk analysis
            minPace: nil,
            cadence: nil,
            strideLength: nil,
            runningPower: nil,
            vo2Max: nil,
            elevationGain: nil,
            groundContactTime: nil,
            verticalOscillation: nil,
            mobility: nil,
            splits: nil
        )
    }
}

struct HistoricalAnalysisOnboardingView: View {
    @StateObject private var viewModel = HistoricalAnalysisViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: viewModel.isComplete ? "checkmark.circle.fill" : "chart.line.uptrend.xyaxis")
                .font(.system(size: 60))
                .foregroundColor(viewModel.isComplete ? .green : .blue)
                .symbolEffect(.bounce, value: viewModel.isComplete)

            // Title
            Text(viewModel.isComplete ? "Analysis Complete!" : "Build Your Athletic Profile")
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            // Description
            if !viewModel.isGenerating {
                Text("We'll analyze your complete training history to provide personalized coaching insights.\n\nThis one-time process takes about 10-20 seconds.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }

            // Progress Section
            if viewModel.isGenerating || viewModel.isComplete {
                VStack(spacing: 16) {
                    ProgressView(value: viewModel.progress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 300)

                    Text("\(Int(viewModel.progress * 100))%")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .monospacedDigit()

                    Text(viewModel.statusMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(minHeight: 40)
                }
                .padding()
            }

            // Error Message
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
            }

            Spacer()

            // Action Buttons
            VStack(spacing: 12) {
                if !viewModel.isGenerating && !viewModel.isComplete {
                    Button(action: {
                        Task {
                            await viewModel.startAnalysis()
                        }
                    }) {
                        Text("Analyze My Training History")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)

                    Button(action: {
                        dismiss()
                    }) {
                        Text("Skip for Now")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else if viewModel.isComplete {
                    Button(action: {
                        dismiss()
                    }) {
                        Text("Get Started")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding()
    }
}

#Preview {
    HistoricalAnalysisOnboardingView()
}
