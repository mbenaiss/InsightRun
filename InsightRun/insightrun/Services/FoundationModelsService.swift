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
                error = "La langue actuelle (\(currentLocale.identifier)) n'est pas encore supportée par Apple Intelligence"
            }

            // Log supported languages
            let supportedLanguages = model.supportedLanguages
            let languageList = supportedLanguages.map { $0.languageCode?.identifier ?? $0.minimalIdentifier }.joined(separator: ", ")
            print("📝 FoundationModels: Supported languages: \(languageList)")

        case .unavailable(.deviceNotEligible):
            print("❌ FoundationModels: Device not eligible for Apple Intelligence")
            error = "This device doesn't support Apple Intelligence"
        case .unavailable(.appleIntelligenceNotEnabled):
            print("⚠️ FoundationModels: Apple Intelligence not enabled")
            error = "Please enable Apple Intelligence in Settings"
        case .unavailable(.modelNotReady):
            print("⏳ FoundationModels: Model downloading or not ready")
            error = "Model is downloading, please try again later"
        case .unavailable(let other):
            print("❌ FoundationModels: Unavailable - \(other)")
            error = "Model unavailable: \(other)"
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
        switch locale.identifier {
        case "fr_FR", "fr":
            return "French"
        case "es_ES", "es":
            return "Spanish"
        case "de_DE", "de":
            return "German"
        case "it_IT", "it":
            return "Italian"
        case "pt_PT", "pt":
            return "Portuguese"
        default:
            return locale.localizedString(forLanguageCode: locale.language.languageCode?.identifier ?? "en") ?? "English"
        }
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

            // Map locale to language name
            let languageName: String
            switch locale.identifier {
            case "fr_FR", "fr":
                languageName = "French"
            case "es_ES", "es":
                languageName = "Spanish"
            case "de_DE", "de":
                languageName = "German"
            case "it_IT", "it":
                languageName = "Italian"
            case "pt_PT", "pt":
                languageName = "Portuguese"
            default:
                languageName = locale.localizedString(forLanguageCode: locale.language.languageCode?.identifier ?? "en") ?? "English"
            }

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
            throw FoundationModelsError.inferenceError("Le prompt ne peut pas être vide")
        }

        guard trimmedPrompt.count >= 3 else {
            print("❌ FoundationModels: Prompt too short (\(trimmedPrompt.count) chars)")
            throw FoundationModelsError.inferenceError("Le prompt doit contenir au moins 3 caractères")
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
            throw FoundationModelsError.inferenceError("La langue \(currentLocale.identifier) n'est pas encore supportée")
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
                        self.error = "Erreur inattendue: \(error.localizedDescription)"
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
            return "⏳ Le modèle Apple Intelligence n'est pas disponible. Vérifiez qu'Apple Intelligence est activé et que les modèles sont téléchargés."

        case .guardrailViolation:
            print("🛡️ FoundationModels: Guardrail violation - Content blocked by safety guardrails")
            return "🛡️ Votre demande contient du contenu qui ne peut pas être traité pour des raisons de sécurité. Veuillez reformuler votre question."

        case .refusal(_, _):
            print("🚫 FoundationModels: Refusal - Model refused the request")
            return "🚫 Le modèle ne peut pas répondre à cette demande. Veuillez essayer une autre question."

        case .exceededContextWindowSize:
            print("📏 FoundationModels: Context window exceeded - Too much data in session")
            return "📏 Trop de données dans la conversation. Veuillez démarrer une nouvelle session."

        case .rateLimited:
            print("⏱️ FoundationModels: Rate limited - Too many requests")
            return "⏱️ Trop de requêtes. Veuillez patienter quelques instants avant de réessayer."

        case .concurrentRequests:
            print("🔄 FoundationModels: Concurrent requests - Multiple requests at once")
            return "🔄 Une requête est déjà en cours. Veuillez attendre qu'elle se termine."

        case .decodingFailure:
            print("🔧 FoundationModels: Decoding failure - Failed to decode response")
            return "🔧 Erreur de décodage de la réponse. Veuillez réessayer."

        case .unsupportedLanguageOrLocale:
            print("🌐 FoundationModels: Unsupported language/locale")
            return "🌐 La langue ou locale n'est pas supportée par le modèle."

        @unknown default:
            print("❓ FoundationModels: Unknown error - \(error)")
            return "❓ Erreur inconnue: \(error.localizedDescription)"
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
            return "Apple Foundation Model is not available on this device"
        case .sessionNotCreated:
            return "Failed to create language model session"
        case .inferenceError(let message):
            return "Inference error: \(message)"
        }
    }
}
