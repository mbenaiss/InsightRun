//
//  ModelRouter.swift
//  InsightRun
//
//  ARCHITECTURE UPDATE (2025-01): Model selection now happens on backend
//  This file handles complexity classification only
//  The classification result is mapped to RequestType and sent to backend
//  Backend handles all model selection, quota management, and cost optimization
//
//  Previous: iOS selects model → sends to backend
//  Current:  iOS classifies complexity → maps to RequestType → backend selects model
//

import Foundation

@MainActor
class ModelRouter {
    static let shared = ModelRouter()

    private let backendClient = BackendAPIClient.shared

    private init() {}

    // MARK: - Main Classification

    /// Select optimal request type based on prompt complexity
    /// - Parameters:
    ///   - prompt: User's question
    ///   - mode: Context mode (single workout, recent workouts, recovery)
    /// - Returns: RequestType to send to backend
    func selectRequestType(
        for prompt: String,
        mode: AIAssistantMode
    ) async -> RequestType {

        // Classify prompt complexity via backend
        let complexity = await classifyPromptComplexity(
            prompt: prompt,
            mode: mode
        )

        // Map complexity to RequestType
        return mapComplexityToRequestType(complexity)
    }

    // MARK: - Classification Logic

    private func classifyPromptComplexity(
        prompt: String,
        mode: AIAssistantMode
    ) async -> PromptComplexity {

        // Backend selects optimal model based on RequestType.CLASSIFICATION
        print("🤖 ModelRouter: Requesting classification from backend")
        return await classifyWithBackend(prompt: prompt, mode: mode)
    }

    // MARK: - Backend Classification

    private func classifyWithBackend(
        prompt: String,
        mode: AIAssistantMode
    ) async -> PromptComplexity {

        let classificationPrompt = buildClassificationPrompt(
            userPrompt: prompt,
            mode: mode
        )

        do {
            let response = try await backendClient.classify(
                prompt: classificationPrompt,
                systemPrompt: "You are a query complexity classifier. Respond with ONLY one word: SIMPLE, MODERATE, or COMPLEX."
            )

            let complexity = parseComplexity(from: response)
            print("✅ ModelRouter: Backend classified as \(complexity)")
            return complexity

        } catch {
            print("⚠️ ModelRouter: Classification failed: \(error.localizedDescription)")
            print("🔄 ModelRouter: Defaulting to MODERATE complexity (safe fallback)")
            return .moderate // Safe default
        }
    }

    // MARK: - Classification Prompt Builder

    private func buildClassificationPrompt(
        userPrompt: String,
        mode: AIAssistantMode
    ) -> String {
        """
        Classify this running/fitness user question into ONE of three complexity levels:

        **SIMPLE** - Basic queries that need quick factual answers:
        - Statistics and metrics (pace, distance, time, calories, heart rate)
        - Simple comparisons (was this workout better than last?)
        - Motivational questions
        - Basic data retrieval and clarifications

        **MODERATE** - Questions requiring analysis and personalized advice:
        - Training plan creation or adjustment
        - Recovery recommendations based on metrics
        - Nutrition and hydration advice
        - Performance trend analysis over multiple workouts
        - Race strategy suggestions
        - Technique improvement tips

        **COMPLEX** - Critical health/medical questions requiring expert analysis:
        - Injury risk assessment or pain analysis
        - HRV interpretation and overtraining detection
        - Biomechanical issues (asymmetry, ground contact time)
        - Performance prediction using ML models
        - Medical contraindications or health concerns
        - Advanced physiological analysis

        Context: User is using "\(modeDescription(mode))" feature

        User Question: "\(userPrompt)"

        Respond with ONLY ONE WORD: SIMPLE, MODERATE, or COMPLEX
        """
    }

    private func modeDescription(_ mode: AIAssistantMode) -> String {
        switch mode {
        case .singleWorkout:
            return "single workout analysis"
        case .recentWorkouts:
            return "training history analysis"
        case .recoveryCoaching:
            return "recovery coaching"
        case .unified:
            return "unified AI coaching with full context"
        }
    }

    // MARK: - Parse Classification Response

    private func parseComplexity(from response: String) -> PromptComplexity {
        let cleaned = response
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        if cleaned.contains("SIMPLE") {
            return .simple
        } else if cleaned.contains("COMPLEX") {
            return .complex
        } else {
            // Default to moderate if unclear
            return .moderate
        }
    }

    // MARK: - Map Complexity to RequestType

    private func mapComplexityToRequestType(_ complexity: PromptComplexity) -> RequestType {
        switch complexity {
        case .simple:
            print("✅ ModelRouter: SIMPLE complexity → RequestType.simple")
            return .simple

        case .moderate:
            print("✅ ModelRouter: MODERATE complexity → RequestType.moderate")
            return .moderate

        case .complex:
            print("✅ ModelRouter: COMPLEX complexity → RequestType.complex")
            return .complex
        }
    }
}

// MARK: - Supporting Types

enum PromptComplexity {
    case simple      // Quick stats, basic questions
    case moderate    // Training plans, analysis, advice
    case complex     // Injury analysis, medical, advanced
}
