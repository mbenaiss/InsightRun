//
//  FoundationModelsService.swift
//  HealthApp
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

    // MARK: - Session Management

    private func createSession(systemPrompt: String) {
        let instructions = systemPrompt.isEmpty
            ? "You are a helpful AI assistant for a health and fitness app."
            : systemPrompt

        currentSession = LanguageModelSession(instructions: instructions)
        print("📝 FoundationModels: Created new session with instructions")
    }

    // MARK: - Inference

    func generate(prompt: String, systemPrompt: String) async throws -> AsyncStream<String> {
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

        // Create new session for each request
        createSession(systemPrompt: systemPrompt)

        guard let session = currentSession else {
            print("❌ FoundationModels: Session not created")
            throw FoundationModelsError.sessionNotCreated
        }

        isLoading = true
        isStreaming = true
        streamedResponse = ""
        error = nil

        print("🚀 FoundationModels: Starting inference...")
        print("📝 FoundationModels: Prompt length: \(trimmedPrompt.count) chars")

        return AsyncStream { continuation in
            currentTask = Task {
                do {
                    // Get response from the model
                    print("⚙️ FoundationModels: Calling respond(to:)...")
                    let response = try await session.respond(to: trimmedPrompt)
                    let responseText = response.content

                    await MainActor.run {
                        self.isLoading = false
                    }

                    print("✅ FoundationModels: Got response (\(responseText.count) chars)")

                    if responseText.isEmpty {
                        print("⚠️ FoundationModels: WARNING - Empty response!")
                        error = "The model returned an empty response"
                        isStreaming = false
                        currentTask = nil
                        continuation.finish()
                        return
                    }

                    print("📝 FoundationModels: Response preview: \(responseText.prefix(200))...")

                    // Check if cancelled before streaming
                    guard !Task.isCancelled else {
                        isStreaming = false
                        currentTask = nil
                        continuation.finish()
                        return
                    }

                    // Stream character by character for progressive response
                    for char in responseText {
                        guard !Task.isCancelled else {
                            isStreaming = false
                            currentTask = nil
                            continuation.finish()
                            return
                        }

                        let charString = String(char)
                        continuation.yield(charString)
                        streamedResponse += charString

                        // Small delay to simulate streaming
                        try? await Task.sleep(nanoseconds: 10_000_000)
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

        case .refusal(let refusal, _):
            print("🚫 FoundationModels: Refusal - Model refused the request")
            // The refusal object may contain more details
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
