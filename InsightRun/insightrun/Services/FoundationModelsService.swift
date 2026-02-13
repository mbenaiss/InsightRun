//
//  FoundationModelsService.swift
//  InsightRun
//
//  Service for running on-device LLM inference using Apple's FoundationModels framework
//

import Foundation
import Combine
import FoundationModels

@available(iOS 26.0, *)
@MainActor
class FoundationModelsService: ObservableObject {
    static let shared = FoundationModelsService()

    @Published var isLoading = false
    @Published var isStreaming = false
    @Published var streamedResponse = ""
    @Published var error: String?
    @Published var availability: SystemLanguageModel.Availability?

    private let model = SystemLanguageModel.default
    private var currentSession: LanguageModelSession?
    private var currentTask: Task<Void, Never>?

    private init() {
        // Check model availability on initialization
        Task {
            await checkAvailability()
        }
    }

    // MARK: - Model Availability

    func checkAvailability() async {
        availability = model.availability

        switch model.availability {
        case .available:
            print("✅ FoundationModels: Model available")

            // Check locale support
            let currentLocale = Locale.current
            let isLocaleSupported = model.supportsLocale(currentLocale)
            print("🌐 FoundationModels: Current locale: \(currentLocale.identifier)")
            print("🌐 FoundationModels: Locale supported: \(isLocaleSupported)")

            if !isLocaleSupported {
                print("⚠️ FoundationModels: Current locale not supported")
                error = String(localized: "Current language (\(currentLocale.identifier)) is not yet supported by Apple Intelligence")
            }

            // Log supported languages
            let supportedLanguages = model.supportedLanguages
            let languageList = supportedLanguages.map { $0.languageCode?.identifier ?? $0.minimalIdentifier }.joined(separator: ", ")
            print("📝 FoundationModels: Supported languages: \(languageList)")

        case .unavailable(.deviceNotEligible):
            print("❌ FoundationModels: Device not eligible for Apple Intelligence")
            error = String(localized: "This device doesn't support Apple Intelligence")
        case .unavailable(.appleIntelligenceNotEnabled):
            print("⚠️ FoundationModels: Apple Intelligence not enabled")
            error = String(localized: "Please enable Apple Intelligence in Settings")
        case .unavailable(.modelNotReady):
            print("⏳ FoundationModels: Model downloading or not ready")
            error = String(localized: "Model is downloading, please try again later")
        case .unavailable(let other):
            print("❌ FoundationModels: Unavailable - \(other)")
            error = String(localized: "Model unavailable: \(String(describing: other))")
        }
    }

    var isAvailable: Bool {
        if case .available = model.availability {
            return true
        }
        return false
    }

    // MARK: - Locale Instructions (Apple's recommended approach)

    /// Get human-readable language name from locale
    private func getLanguageName(for locale: Locale) -> String {
        locale.englishLanguageName
    }

    /// Generate locale-specific instructions following Apple's documentation
    /// Reference: https://developer.apple.com/documentation/foundationmodels/support-languages-and-locales-with-foundation-models/
    private func localeInstructions(for locale: Locale = Locale.current) -> String {
        if Locale.Language(identifier: "en_US").isEquivalent(to: locale.language) {
            // Skip the locale phrase for U.S. English
            return ""
        } else {
            // Use the EXACT phrase from Apple's training
            let localePhrase = "The person's locale is \(locale.identifier)."

            let languageName = locale.englishLanguageName

            let languageInstruction = "You MUST respond in \(languageName) and be mindful of \(languageName) spelling, vocabulary, entities, and other cultural contexts."

            print("🌐 FoundationModels: Locale instructions - \(locale.identifier) -> \(languageName)")

            return """
            \(localePhrase)
            \(languageInstruction)

            """
        }
    }

    // MARK: - Session Management

    private func createSession(systemPrompt: String, locale: Locale) {
        // Prepend locale instructions to system prompt
        let localePrefix = localeInstructions(for: locale)

        let instructions = systemPrompt.isEmpty
            ? "You are a helpful AI assistant for a health and fitness app."
            : "\(localePrefix)\(systemPrompt)"

        currentSession = LanguageModelSession(instructions: instructions)
        print("📝 FoundationModels: Created new session with locale: \(locale.identifier)")
    }

    // MARK: - Inference

    func generate(prompt: String, systemPrompt: String, locale: Locale = Locale.current) async throws -> AsyncStream<String> {
        // Validate prompt
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            print("❌ FoundationModels: Empty prompt")
            throw FoundationModelsError.inferenceError(String(localized: "The prompt cannot be empty", comment: "Error when user submits empty prompt"))
        }

        guard trimmedPrompt.count >= 3 else {
            print("❌ FoundationModels: Prompt too short (\(trimmedPrompt.count) chars)")
            throw FoundationModelsError.inferenceError(String(localized: "The prompt must contain at least 3 characters", comment: "Error when prompt is too short"))
        }

        // Wrap user's prompt with strong language instruction if not English
        let finalPrompt: String
        if !Locale.Language(identifier: "en_US").isEquivalent(to: locale.language) {
            let languageName = getLanguageName(for: locale)
            finalPrompt = """
            CRITICAL INSTRUCTION: You MUST respond ENTIRELY in \(languageName). Every single word, header, bullet point, and emoji label must be in \(languageName).

            User's question:
            \(trimmedPrompt)

            REMINDER: Your complete response must be in \(languageName). Do not use any English words.
            """
            print("🌐 FoundationModels: Wrapped prompt with \(languageName) language instruction")
        } else {
            finalPrompt = trimmedPrompt
        }

        // Check availability first
        guard isAvailable else {
            print("❌ FoundationModels: Model not available")
            throw FoundationModelsError.modelNotAvailable
        }

        // Check locale support
        let currentLocale = Locale.current
        guard model.supportsLocale(currentLocale) else {
            print("❌ FoundationModels: Locale \(currentLocale.identifier) not supported")
            throw FoundationModelsError.inferenceError(String(localized: "Language \(currentLocale.identifier) is not yet supported", comment: "Error when locale is not supported"))
        }

        // Create new session for each request with locale
        createSession(systemPrompt: systemPrompt, locale: locale)

        guard let session = currentSession else {
            print("❌ FoundationModels: Session not created")
            throw FoundationModelsError.sessionNotCreated
        }

        isLoading = true
        isStreaming = true
        streamedResponse = ""
        error = nil

        print("🚀 FoundationModels: Starting inference...")
        print("📝 FoundationModels: Prompt length: \(finalPrompt.count) chars")

        return AsyncStream { continuation in
            currentTask = Task {
                do {
                    // Use streaming response from the model
                    print("⚙️ FoundationModels: Calling streamResponse(to:)...")

                    await MainActor.run {
                        self.isLoading = false
                    }

                    let stream = session.streamResponse(to: finalPrompt)

                    // Stream snapshots as they arrive
                    // Note: snapshot.content contains ALL text generated so far, not just the delta
                    var previousContent = ""
                    for try await snapshot in stream {
                        guard !Task.isCancelled else {
                            isStreaming = false
                            currentTask = nil
                            continuation.finish()
                            return
                        }

                        let currentContent = snapshot.content

                        // Calculate the delta (new text only)
                        // Use String.Index to handle emojis and multi-byte characters correctly
                        if currentContent.hasPrefix(previousContent) {
                            let startIndex = currentContent.index(currentContent.startIndex, offsetBy: previousContent.count)
                            let delta = String(currentContent[startIndex...])
                            if !delta.isEmpty {
                                print("📤 FoundationModels: Delta (\(delta.count) chars): \(delta.prefix(50))...")
                                continuation.yield(delta)
                                streamedResponse += delta
                            }
                        } else {
                            // If not a continuation, reset and yield full content
                            print("🔄 FoundationModels: Full content reset (\(currentContent.count) chars)")
                            continuation.yield(currentContent)
                            streamedResponse = currentContent
                        }

                        previousContent = currentContent
                    }

                    isStreaming = false
                    currentTask = nil
                    continuation.finish()
                    print("🎉 FoundationModels: Streaming completed")

                } catch let error as LanguageModelSession.GenerationError {
                    print("❌ FoundationModels: GenerationError - \(error)")

                    let errorMessage = self.handleGenerationError(error)

                    await MainActor.run {
                        self.error = errorMessage
                        self.isLoading = false
                        self.isStreaming = false
                        self.currentTask = nil
                    }
                    continuation.finish()

                } catch {
                    print("❌ FoundationModels: Unexpected error - \(error)")

                    await MainActor.run {
                        self.error = String(localized: "Unexpected error: \(error.localizedDescription)")
                        self.isLoading = false
                        self.isStreaming = false
                        self.currentTask = nil
                    }
                    continuation.finish()
                }
            }
        }
    }

    func stopGeneration() {
        currentTask?.cancel()
        currentTask = nil
        isStreaming = false
    }

    // MARK: - Helper Methods

    func getModelInfo() -> String? {
        guard isAvailable else { return nil }

        return """
        Model: Apple Foundation Model
        Type: On-device (Apple Intelligence)
        Status: Available
        """
    }

    func clearSession() {
        currentSession = nil
        streamedResponse = ""
    }

    // MARK: - Error Handling

    private func handleGenerationError(_ error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .assetsUnavailable:
            print("🔴 FoundationModels: Assets unavailable - Model assets may be deleted or downloading")
            return String(localized: "Apple Intelligence model is not available. Check that Apple Intelligence is enabled and models are downloaded.", comment: "Error: AI model assets unavailable")

        case .guardrailViolation:
            print("🛡️ FoundationModels: Guardrail violation - Content blocked by safety guardrails")
            return String(localized: "Your request contains content that cannot be processed for safety reasons. Please rephrase your question.", comment: "Error: content blocked by safety guardrails")

        case .refusal(_, _):
            print("🚫 FoundationModels: Refusal - Model refused the request")
            return String(localized: "The model cannot respond to this request. Please try another question.", comment: "Error: model refused request")

        case .exceededContextWindowSize:
            print("📏 FoundationModels: Context window exceeded - Too much data in session")
            return String(localized: "Too much data in the conversation. Please start a new session.", comment: "Error: context window exceeded")

        case .rateLimited:
            print("⏱️ FoundationModels: Rate limited - Too many requests")
            return String(localized: "Too many requests. Please wait a moment before trying again.", comment: "Error: rate limited")

        case .concurrentRequests:
            print("🔄 FoundationModels: Concurrent requests - Multiple requests at once")
            return String(localized: "A request is already in progress. Please wait for it to finish.", comment: "Error: concurrent requests")

        case .decodingFailure:
            print("🔧 FoundationModels: Decoding failure - Failed to decode response")
            return String(localized: "Response decoding error. Please try again.", comment: "Error: decoding failure")

        case .unsupportedLanguageOrLocale:
            print("🌐 FoundationModels: Unsupported language/locale")
            return String(localized: "The language or locale is not supported by the model.", comment: "Error: unsupported language")

        case .unsupportedGuide:
            print("⚠️ FoundationModels: Unsupported guide - \(error)")
            return String(localized: "Unsupported generation format: \(error.localizedDescription)", comment: "Error: unsupported guide")

        @unknown default:
            print("❓ FoundationModels: Unknown error - \(error)")
            return String(localized: "Unknown error: \(error.localizedDescription)", comment: "Error: unknown")
        }
    }
}

// MARK: - Errors

enum FoundationModelsError: LocalizedError {
    case modelNotAvailable
    case sessionNotCreated
    case inferenceError(String)

    var errorDescription: String? {
        switch self {
        case .modelNotAvailable:
            return String(localized: "Apple Foundation Model is not available on this device", comment: "Error: model not available")
        case .sessionNotCreated:
            return String(localized: "Failed to create language model session", comment: "Error: session creation failed")
        case .inferenceError(let message):
            return String(localized: "Inference error: \(message)", comment: "Error: inference error with details")
        }
    }
}
