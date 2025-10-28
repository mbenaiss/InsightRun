//
//  ModelRouter.swift
//  HealthApp
//
//  Intelligent model selection based on prompt complexity
//  Uses LLM classification (Foundation Models or Grok) to route to optimal model
//

import Foundation
import FoundationModels

@MainActor
class ModelRouter {
    static let shared = ModelRouter()

    private let backendClient = BackendAPIClient.shared

    // MARK: - Sonnet Quota Management (Cost Control)

    /// Maximum Sonnet requests per user per month to maintain profitability
    /// Based on pricing analysis: 17% of 60 requests = 10 requests/month
    /// Cost: $0.346/user/month, Margin: 93.1% @ $4.99/month
    private let sonnetQuotaPerMonth = 10

    /// UserDefaults keys for quota tracking
    private let sonnetUsageKey = "ai_sonnet_usage_count"
    private let sonnetResetDateKey = "ai_sonnet_reset_date"

    private init() {}

    /// Check if user has Sonnet quota remaining this month
    private func hasSonnetQuotaRemaining() -> Bool {
        resetQuotaIfNeeded()

        let currentUsage = UserDefaults.standard.integer(forKey: sonnetUsageKey)
        let hasQuota = currentUsage < sonnetQuotaPerMonth

        if !hasQuota {
            print("⚠️ ModelRouter: Sonnet quota exceeded (\(currentUsage)/\(sonnetQuotaPerMonth))")
        }

        return hasQuota
    }

    /// Increment Sonnet usage counter
    private func incrementSonnetUsage() {
        let currentUsage = UserDefaults.standard.integer(forKey: sonnetUsageKey)
        let newUsage = currentUsage + 1
        UserDefaults.standard.set(newUsage, forKey: sonnetUsageKey)

        print("💰 ModelRouter: Sonnet usage: \(newUsage)/\(sonnetQuotaPerMonth) this month")
    }

    /// Reset quota counter if we're in a new month
    private func resetQuotaIfNeeded() {
        let now = Date()
        let calendar = Calendar.current

        if let lastReset = UserDefaults.standard.object(forKey: sonnetResetDateKey) as? Date {
            // Check if we're in a different month
            let lastResetMonth = calendar.component(.month, from: lastReset)
            let lastResetYear = calendar.component(.year, from: lastReset)
            let currentMonth = calendar.component(.month, from: now)
            let currentYear = calendar.component(.year, from: now)

            if lastResetMonth != currentMonth || lastResetYear != currentYear {
                // New month, reset counter
                UserDefaults.standard.set(0, forKey: sonnetUsageKey)
                UserDefaults.standard.set(now, forKey: sonnetResetDateKey)
                print("🔄 ModelRouter: Sonnet quota reset for new month")
            }
        } else {
            // First time, initialize
            UserDefaults.standard.set(0, forKey: sonnetUsageKey)
            UserDefaults.standard.set(now, forKey: sonnetResetDateKey)
        }
    }

    /// Get current Sonnet quota status (for UI display)
    func getSonnetQuotaStatus() -> (used: Int, total: Int, remaining: Int) {
        resetQuotaIfNeeded()
        let used = UserDefaults.standard.integer(forKey: sonnetUsageKey)
        let remaining = max(0, sonnetQuotaPerMonth - used)
        return (used: used, total: sonnetQuotaPerMonth, remaining: remaining)
    }

    // MARK: - Main Classification

    /// Select optimal AI model based on prompt complexity
    /// - Parameters:
    ///   - prompt: User's question
    ///   - mode: Context mode (single workout, recent workouts, recovery)
    /// - Returns: Optimal AIModel to use
    func selectOptimalModel(
        for prompt: String,
        mode: AIAssistantMode
    ) async -> AIModel {

        // Classify prompt complexity using LLM
        let complexity = await classifyPromptComplexity(
            prompt: prompt,
            mode: mode
        )

        // Route to appropriate model
        return mapComplexityToModel(complexity)
    }

    // MARK: - Classification Logic

    private func classifyPromptComplexity(
        prompt: String,
        mode: AIAssistantMode
    ) async -> PromptComplexity {

        // Try Apple Intelligence first (free, fast, local)
        if #available(iOS 26.0, *) {
            let service = FoundationModelsService.shared
            if service.isAvailable {
                print("🍎 ModelRouter: Using Foundation Models for classification (free)")
                if let complexity = await classifyWithFoundationModels(prompt: prompt, mode: mode) {
                    return complexity
                }
                print("⚠️ ModelRouter: Foundation Models classification failed, fallback to Grok")
            }
        }

        // Fallback to Grok classification (cheap: $0.0004)
        print("🤖 ModelRouter: Using Grok for classification ($0.0004)")
        return await classifyWithGrok(prompt: prompt, mode: mode)
    }

    // MARK: - Foundation Models Classification (Free, Local)

    @available(iOS 26.0, *)
    private func classifyWithFoundationModels(
        prompt: String,
        mode: AIAssistantMode
    ) async -> PromptComplexity? {

        let classificationPrompt = buildClassificationPrompt(
            userPrompt: prompt,
            mode: mode
        )

        let service = FoundationModelsService.shared

        do {
            let stream = try await service.generate(
                prompt: classificationPrompt,
                systemPrompt: "You are a query complexity classifier. Respond with ONLY one word: SIMPLE, MODERATE, or COMPLEX.",
                locale: Locale.current
            )

            var response = ""
            for await chunk in stream {
                response += chunk
            }

            let complexity = parseComplexity(from: response)
            print("✅ ModelRouter: Foundation Models classified as \(complexity)")
            return complexity

        } catch {
            print("⚠️ ModelRouter: Foundation Models classification error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Grok Classification (Cheap Fallback)

    private func classifyWithGrok(
        prompt: String,
        mode: AIAssistantMode
    ) async -> PromptComplexity {

        let classificationPrompt = buildClassificationPrompt(
            userPrompt: prompt,
            mode: mode
        )

        do {
            let response = try await backendClient.chat(
                prompt: classificationPrompt,
                systemPrompt: "You are a query complexity classifier. Respond with ONLY one word: SIMPLE, MODERATE, or COMPLEX.",
                model: "x-ai/grok-4-fast"
            )

            let complexity = parseComplexity(from: response)
            print("✅ ModelRouter: Grok classified as \(complexity)")
            return complexity

        } catch {
            print("⚠️ ModelRouter: Grok classification failed: \(error.localizedDescription)")
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

    // MARK: - Map Complexity to Model

    private func mapComplexityToModel(_ complexity: PromptComplexity) -> AIModel {
        switch complexity {
        case .simple:
            print("✅ ModelRouter: SIMPLE → Routing to Grok")
            return .grok4

        case .moderate:
            print("✅ ModelRouter: MODERATE → Routing to Haiku")
            return .claudeHaiku

        case .complex:
            // Check Sonnet quota before routing
            if hasSonnetQuotaRemaining() {
                incrementSonnetUsage()
                print("✅ ModelRouter: COMPLEX → Routing to Sonnet (quota OK)")
                return .claudeSonnet
            } else {
                // Quota exceeded, fallback to Haiku
                print("⚠️ ModelRouter: COMPLEX → Fallback to Haiku (Sonnet quota exceeded)")
                print("💡 ModelRouter: Haiku can handle 80% of complex cases acceptably")
                return .claudeHaiku
            }
        }
    }
}

// MARK: - Supporting Types

enum PromptComplexity {
    case simple      // Grok - Quick stats, basic questions
    case moderate    // Haiku - Training plans, analysis, advice
    case complex     // Sonnet - Injury analysis, medical, advanced
}
