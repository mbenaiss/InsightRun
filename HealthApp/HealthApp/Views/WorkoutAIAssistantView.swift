//
//  WorkoutAIAssistantView.swift
//  HealthApp
//
//  AI Assistant for analyzing workouts with iOS 26 Liquid Glass design
//

import SwiftUI
import UIKit

struct ChatMessage: Identifiable, Equatable, Codable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date

    enum MessageRole: String, Codable {
        case user
        case assistant
    }

    init(id: UUID = UUID(), role: MessageRole, content: String, timestamp: Date) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

enum AIAssistantMode {
    case singleWorkout(WorkoutModel, WorkoutMetrics?)
    case recentWorkouts([WorkoutModel])
    case recoveryCoaching(RecoveryMetrics)
}

struct WorkoutAIAssistantView: View {
    let mode: AIAssistantMode
    @Binding var isPresented: Bool
    @StateObject private var aiService = WorkoutAIService()
    @State private var question = ""
    @State private var selectedModel: AIModel = .foundationModels
    @State private var messages: [ChatMessage] = []
    @State private var isTyping = false
    @State private var streamingMessageId: UUID?
    @State private var showingModelSelector = false
    @FocusState private var isTextFieldFocused: Bool
    @Namespace private var bottomID

    // Haptic feedback generators
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let notificationFeedback = UINotificationFeedbackGenerator()

    var body: some View {
        NavigationView {
            ZStack {
                // Liquid Glass Background (iOS 26)
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

                VStack(spacing: 0) {
                    // Header
                    headerView

                    Divider()

                    // Messages Area
                    ScrollViewReader { scrollProxy in
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                if messages.isEmpty {
                                    emptyStateView
                                        .padding(.top, 40)
                                } else {
                                    ForEach(messages) { message in
                                        MessageBubble(message: message)
                                            .transition(.asymmetric(
                                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                                removal: .opacity
                                            ))
                                    }
                                }

                                // Typing Indicator (only before streaming starts)
                                if isTyping && !aiService.isStreaming {
                                    HStack {
                                        TypingIndicator()
                                        Spacer()
                                    }
                                    .padding(.horizontal)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                                }

                                // Always have a bottom anchor
                                Color.clear
                                    .frame(height: 1)
                                    .id(bottomID)
                            }
                            .padding(.vertical, 16)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .onChange(of: aiService.streamedResponse) { _, newValue in
                            // Update streaming message in place
                            if let streamingId = streamingMessageId,
                               let index = messages.firstIndex(where: { $0.id == streamingId }) {
                                messages[index] = ChatMessage(
                                    id: streamingId,
                                    role: .assistant,
                                    content: newValue,
                                    timestamp: messages[index].timestamp
                                )
                            }
                        }
                    }

                    // Error Display
                    if let error = aiService.error {
                        errorView(error)
                    }

                    Divider()

                    // Suggested Questions
                    if !aiService.suggestedQuestions.isEmpty && !aiService.isStreaming {
                        suggestedQuestionsView
                    }

                    // Input Area
                    inputArea
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Fermer") {
                        isPresented = false
                    }
                }
            }
        }
        .sheet(isPresented: $showingModelSelector) {
            ModelSelectorSheet(selectedModel: $selectedModel, isPresented: $showingModelSelector)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            loadMessages()
            isTextFieldFocused = true

            // Prepare haptic generators for better responsiveness
            impactLight.prepare()
            impactMedium.prepare()
            notificationFeedback.prepare()
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack {
            Image(systemName: "sparkles")
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("Assistant IA")
                    .font(.headline)

                Text(modeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Model Selector Button
            Button(action: {
                showingModelSelector = true
            }) {
                HStack(spacing: 6) {
                    Text(selectedModel.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if selectedModel == .claudeSonnet {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                    }
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
            }

            if !messages.isEmpty {
                Button(action: clearChat) {
                    Image(systemName: "trash")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private var modeDescription: String {
        switch mode {
        case .singleWorkout:
            return "Analyse d'un workout"
        case .recentWorkouts(let workouts):
            return "\(workouts.count) derniers workouts"
        case .recoveryCoaching:
            return "Coaching de récupération"
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            // Animated Icon with Liquid Glass effect
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 100, height: 100)
                    .shadow(color: .black.opacity(0.1), radius: 20, y: 10)

                Image(systemName: "sparkles")
                    .font(.system(size: 40))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 8) {
                Text("Coach IA Running")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Posez vos questions sur vos performances")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Sample Questions
            VStack(alignment: .leading, spacing: 12) {
                Text("Questions rapides")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 4)

                VStack(spacing: 8) {
                    ForEach(sampleQuestions, id: \.self) { sample in
                        Button(action: {
                            impactLight.impactOccurred()
                            question = sample
                        }) {
                            HStack {
                                Image(systemName: "lightbulb.fill")
                                    .font(.caption)
                                    .foregroundColor(.yellow)
                                Text(sample)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(12)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .padding()
        }
        .padding()
    }

    private var sampleQuestions: [String] {
        switch mode {
        case .singleWorkout:
            return [
                "Comment était ma performance ?",
                "Quelle était ma meilleure allure ?",
                "Analyse ma fréquence cardiaque",
                "Donne-moi des conseils d'amélioration",
                "Comment était mon dénivelé ?"
            ]
        case .recentWorkouts:
            return [
                "Comment ont évolué mes performances ?",
                "Quelle est ma progression ?",
                "Quel est mon meilleur workout ?",
                "Suis-je en surcharge d'entraînement ?",
                "Analyse ma régularité"
            ]
        case .recoveryCoaching:
            return [
                "Puis-je m'entraîner aujourd'hui ?",
                "Comment améliorer ma récupération ?",
                "Pourquoi mon HRV est-elle faible ?",
                "Quel type d'entraînement est adapté ?",
                "Comment optimiser mon sommeil ?"
            ]
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
            Button("Ignorer") {
                aiService.error = nil
            }
            .font(.caption)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Suggested Questions View

    private var suggestedQuestionsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                    .font(.caption)
                Text("Questions suggérées")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(aiService.suggestedQuestions, id: \.self) { suggestion in
                        Button(action: {
                            impactLight.impactOccurred()
                            question = suggestion
                            askQuestion()
                        }) {
                            Text(suggestion)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(Color.blue.opacity(0.3), lineWidth: 1)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Input Area

    private var inputArea: some View {
        HStack(spacing: 12) {
            HStack {
                TextField("Posez une question...", text: $question, axis: .vertical)
                    .focused($isTextFieldFocused)
                    .disabled(aiService.isStreaming)
                    .lineLimit(1...4)
                    .onSubmit {
                        askQuestion()
                    }

                if !question.isEmpty && !aiService.isStreaming {
                    Button(action: { question = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))

            // Send Button
            Button(action: askQuestion) {
                ZStack {
                    Circle()
                        .fill(
                            question.isEmpty || aiService.isStreaming ?
                            LinearGradient(
                                colors: [Color.gray, Color.gray],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ) :
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .shadow(color: question.isEmpty ? .clear : .blue.opacity(0.3), radius: 8, y: 4)

                    if aiService.isStreaming {
                        Image(systemName: "stop.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 16))
                    } else {
                        Image(systemName: "arrow.up")
                            .foregroundColor(.white)
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
            }
            .disabled(question.isEmpty && !aiService.isStreaming)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Actions

    private func askQuestion() {
        guard !question.isEmpty else {
            // If empty question and streaming, just save the current response
            if aiService.isStreaming && !aiService.streamedResponse.isEmpty {
                messages.append(ChatMessage(
                    role: .assistant,
                    content: aiService.streamedResponse,
                    timestamp: Date()
                ))
                aiService.streamedResponse = ""
                saveMessages()
            }
            return
        }

        let userQuestion = question
        question = ""

        // Haptic feedback for sending message
        impactMedium.impactOccurred()

        // Add user message
        messages.append(ChatMessage(
            role: .user,
            content: userQuestion,
            timestamp: Date()
        ))
        isTyping = true
        saveMessages()

        // Hide keyboard
        isTextFieldFocused = false

        // Create temporary streaming message that will be updated in place
        let streamingId = UUID()
        streamingMessageId = streamingId
        messages.append(ChatMessage(
            id: streamingId,
            role: .assistant,
            content: "",
            timestamp: Date()
        ))

        // Generate context based on mode
        let context: String
        switch mode {
        case .singleWorkout(let workout, let metrics):
            context = aiService.generateSingleWorkoutContext(workout: workout, metrics: metrics)
        case .recentWorkouts(let workouts):
            context = aiService.generateRecentWorkoutsContext(workouts: workouts)
        case .recoveryCoaching(let recoveryMetrics):
            context = aiService.generateRecoveryCoachingContext(metrics: recoveryMetrics)
        }

        Task {
            await aiService.askQuestion(
                about: context,
                question: userQuestion,
                model: selectedModel
            )

            await MainActor.run {
                isTyping = false

                // Haptic feedback for response completion
                if aiService.error == nil && !aiService.streamedResponse.isEmpty {
                    notificationFeedback.notificationOccurred(.success)
                } else if aiService.error != nil {
                    notificationFeedback.notificationOccurred(.error)

                    // Remove empty streaming message if there was an error
                    if let streamingId = streamingMessageId,
                       let index = messages.firstIndex(where: { $0.id == streamingId }) {
                        messages.remove(at: index)
                    }
                }

                // Clear streaming state (message is already updated in messages array)
                streamingMessageId = nil
                aiService.streamedResponse = ""

                saveMessages()
            }
        }
    }

    private func clearChat() {
        withAnimation {
            messages.removeAll()
            aiService.streamedResponse = ""
            aiService.error = nil
            streamingMessageId = nil
        }
        saveMessages()
    }

    // MARK: - Message Persistence

    private func saveMessages() {
        if let encoded = try? JSONEncoder().encode(messages) {
            UserDefaults.standard.set(encoded, forKey: "workout_chat_messages")
        }
    }

    private func loadMessages() {
        if let data = UserDefaults.standard.data(forKey: "workout_chat_messages"),
           let decoded = try? JSONDecoder().decode([ChatMessage].self, from: data) {
            messages = decoded
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    @State private var appeared = false

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if message.role == .assistant {
                    MarkdownText(message.content)
                        .font(.body)
                        .foregroundColor(.primary)
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
                } else {
                    Text(message.content)
                        .font(.body)
                        .foregroundColor(.white)
                        .padding(12)
                        .background(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .blue.opacity(0.3), radius: 8, y: 4)
                }

                Text(formatTime(message.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .opacity(appeared ? 1 : 0)
            }
            .scaleEffect(appeared ? 1 : 0.95)
            .opacity(appeared ? 1 : 0)

            if message.role == .assistant {
                Spacer(minLength: 60)
            }
        }
        .padding(.horizontal)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                appeared = true
            }
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Markdown Text (simplified version)

struct MarkdownText: View {
    let content: String
    @State private var parsedElements: [MarkdownElement] = []

    init(_ content: String) {
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(parsedElements) { element in
                element.view
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .onAppear {
            if parsedElements.isEmpty {
                parsedElements = parseMarkdown(content)
            }
        }
        .onChange(of: content) { _, newContent in
            parsedElements = parseMarkdown(newContent)
        }
    }

    private func parseMarkdown(_ text: String) -> [MarkdownElement] {
        var elements: [MarkdownElement] = []
        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                continue
            }

            // Headers
            if trimmed.hasPrefix("### ") {
                elements.append(MarkdownElement(
                    type: .header3,
                    content: String(trimmed.dropFirst(4))
                ))
            } else if trimmed.hasPrefix("## ") {
                elements.append(MarkdownElement(
                    type: .header2,
                    content: String(trimmed.dropFirst(3))
                ))
            } else if trimmed.hasPrefix("# ") {
                elements.append(MarkdownElement(
                    type: .header1,
                    content: String(trimmed.dropFirst(2))
                ))
            }
            // Lists
            else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let content = trimmed.hasPrefix("- ") ? String(trimmed.dropFirst(2)) : String(trimmed.dropFirst(2))
                elements.append(MarkdownElement(
                    type: .listItem,
                    content: content
                ))
            }
            // Regular paragraph
            else {
                elements.append(MarkdownElement(
                    type: .paragraph,
                    content: trimmed
                ))
            }
        }

        return elements
    }
}

struct MarkdownElement: Identifiable {
    let id = UUID()
    let type: ElementType
    let content: String

    enum ElementType {
        case header1, header2, header3
        case paragraph
        case listItem
    }

    var view: some View {
        Group {
            switch type {
            case .header1:
                Text(parseInlineMarkdown(content))
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.top, 8)
            case .header2:
                Text(parseInlineMarkdown(content))
                    .font(.headline)
                    .fontWeight(.semibold)
                    .padding(.top, 6)
            case .header3:
                Text(parseInlineMarkdown(content))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.top, 4)
            case .listItem:
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                        .font(.body)
                    Text(parseInlineMarkdown(content))
                        .font(.body)
                }
                .padding(.leading, 8)
            case .paragraph:
                Text(parseInlineMarkdown(content))
                    .font(.body)
                    .padding(.top, 2)
            }
        }
    }

    private func parseInlineMarkdown(_ text: String) -> AttributedString {
        var result = AttributedString(text)

        // Bold **text**
        let boldPattern = "\\*\\*([^*]+)\\*\\*"
        if let regex = try? NSRegularExpression(pattern: boldPattern) {
            let nsString = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))

            for match in matches.reversed() {
                if match.numberOfRanges >= 2 {
                    let boldTextRange = match.range(at: 1)
                    let boldText = nsString.substring(with: boldTextRange)

                    if let range = Range(match.range, in: text) {
                        if let attrRange = Range(range, in: result) {
                            result.replaceSubrange(attrRange, with: AttributedString(boldText))
                            if let boldRange = result.range(of: boldText) {
                                result[boldRange].font = .body.bold()
                            }
                        }
                    }
                }
            }
        }

        return result
    }
}

// MARK: - Regex Cache for Better Performance
private enum MarkdownRegexCache {
    static let boldRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "\\*\\*([^*]+)\\*\\*")
    }()
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var animationPhase: Int = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 8, height: 8)
                    .scaleEffect(animationPhase == index ? 1.2 : 1.0)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever()
                        .delay(Double(index) * 0.2),
                        value: animationPhase
                    )
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear {
            animationPhase = 0
        }
    }
}

// MARK: - Model Selector Sheet

struct ModelSelectorSheet: View {
    @Binding var selectedModel: AIModel
    @Binding var isPresented: Bool

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    Text("Choisir le Modèle IA")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Sélectionnez le meilleur modèle pour vos besoins")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)
                .padding(.bottom, 24)

                // Model Cards
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(AIModel.allCases, id: \.self) { model in
                            ModelCard(
                                model: model,
                                isSelected: selectedModel == model,
                                onSelect: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        selectedModel = model
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                        isPresented = false
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("OK") {
                        isPresented = false
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct ModelCard: View {
    let model: AIModel
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: modelIcon)
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: modelGradientColors,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .font(.title3)

                            Text(model.displayName)
                                .font(.headline)
                                .foregroundColor(.primary)
                        }

                        if let badge = modelBadge {
                            HStack(spacing: 4) {
                                Image(systemName: badge.icon)
                                    .font(.caption2)
                                Text(badge.text)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(badge.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(badge.color.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .cyan],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .font(.title2)
                    }
                }

                Text(modelDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: isSelected ? Color.blue.opacity(0.3) : Color.black.opacity(0.05), radius: isSelected ? 12 : 8, y: 4)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isSelected ?
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ) :
                        LinearGradient(
                            colors: [.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var modelIcon: String {
        switch model {
        case .foundationModels:
            return "apple.logo"
        case .claudeSonnet:
            return "brain.head.profile"
        case .gpt5:
            return "cpu"
        case .grok4:
            return "bolt.fill"
        }
    }

    private var modelGradientColors: [Color] {
        switch model {
        case .foundationModels:
            return [.purple, .pink]
        case .claudeSonnet:
            return [.blue, .cyan]
        case .gpt5:
            return [.green, .mint]
        case .grok4:
            return [.orange, .red]
        }
    }

    private var modelBadge: (text: String, icon: String, color: Color)? {
        switch model {
        case .foundationModels:
            return ("Apple Intelligence", "apple.logo", .purple)
        case .claudeSonnet:
            return ("Recommandé", "star.fill", .yellow)
        case .gpt5:
            return ("Meilleure Qualité", "rosette", .green)
        case .grok4:
            return ("Plus Rapide", "hare.fill", .orange)
        }
    }

    private var modelDescription: String {
        switch model {
        case .foundationModels:
            return "Modèle Apple on-device. Privé, rapide et fonctionne sans internet. Nécessite Apple Intelligence."
        case .claudeSonnet:
            return "Meilleur équilibre entre vitesse et qualité pour l'analyse sportive."
        case .gpt5:
            return "Réponses de la plus haute qualité avec raisonnement approfondi."
        case .grok4:
            return "Réponses ultra-rapides pour les questions simples."
        }
    }
}
