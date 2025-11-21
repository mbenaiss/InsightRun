//
//  WorkoutAIAssistantView.swift
//  InsightRun
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

struct ConversationHistory: Identifiable, Codable {
    let id: UUID
    let title: String
    let messages: [ChatMessage]
    let createdAt: Date
    let updatedAt: Date
    let mode: String // Store mode as string for persistence

    init(id: UUID = UUID(), title: String, messages: [ChatMessage], createdAt: Date, updatedAt: Date, mode: String) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.mode = mode
    }

    // Generate title from first user message or use default
    static func generateTitle(from messages: [ChatMessage]) -> String {
        if let firstUserMessage = messages.first(where: { $0.role == .user }) {
            let content = firstUserMessage.content
            let maxLength = 50
            if content.count > maxLength {
                return String(content.prefix(maxLength)) + "..."
            }
            return content
        }
        return String(localized: "Untitled Conversation", comment: "Default title for conversation without messages")
    }
}

enum AIAssistantMode {
    case singleWorkout(WorkoutModel, WorkoutMetrics?)
    case recentWorkouts([WorkoutModel], [UUID: WorkoutMetrics]) // Now includes metrics dictionary
    case recoveryCoaching(RecoveryMetrics)
}

struct WorkoutAIAssistantView: View {
    let mode: AIAssistantMode
    @Binding var isPresented: Bool
    @StateObject private var aiService = WorkoutAIService()
    @State private var question = ""
    @State private var messages: [ChatMessage] = []
    @State private var isTyping = false
    @State private var streamingMessageId: UUID?
    @State private var messageStartTime: Date?
    @FocusState private var isTextFieldFocused: Bool
    @Namespace private var bottomID
    @State private var showingHistory = false
    @State private var conversationHistories: [ConversationHistory] = []
    @State private var currentConversationId: UUID?
    @State private var showIndexationBanner = false
    @State private var showIndexationSheet = false

    // Haptic feedback generators
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let notificationFeedback = UINotificationFeedbackGenerator()

    var body: some View {
        NavigationStack {
            ZStack {
                // Liquid Glass Background (iOS 26)
                LinearGradient(
                    colors: [
                        Color.irBackgroundApp,
                        Color.irPrimaryAccent.opacity(0.02),
                        Color.irPrimaryAccent.opacity(0.01)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header
                    headerView

                    Divider()

                    // Indexation Banner (if no historical summary)
                    if showIndexationBanner {
                        IndexationBannerView(
                            onSyncTapped: {
                                // Track sync tapped
                                AnalyticsService.shared.trackIndexationBannerSyncTapped()
                                showIndexationSheet = true
                            },
                            onDismiss: {
                                // Track banner dismissed
                                AnalyticsService.shared.trackIndexationBannerDismissed()
                                withAnimation {
                                    showIndexationBanner = false
                                }
                            }
                        )
                        .padding()
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

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
                        .onTapGesture {
                            // Hide keyboard when tapping outside of input field
                            isTextFieldFocused = false
                        }
                        .onChange(of: aiService.streamedResponse) { oldValue, newValue in
                            // Update streaming message in place only if value actually changed
                            guard oldValue != newValue else { return }
                            guard let streamingId = streamingMessageId,
                                  let index = messages.firstIndex(where: { $0.id == streamingId }) else {
                                return
                            }

                            // Avoid updating if already the same content
                            if messages[index].content != newValue {
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
                    Button(String(localized: "Close", comment: "Close AI assistant button")) {
                        isPresented = false
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    EmptyView()
                }
            }
        }
        .sheet(isPresented: $showingHistory) {
            ConversationHistoryView(
                histories: $conversationHistories,
                onSelectConversation: loadConversation,
                onDeleteConversation: deleteConversation
            )
        }
        .sheet(isPresented: $showIndexationSheet) {
            HistoricalIndexationSheet()
        }
        .onAppear {
            loadMessages()
            loadConversationHistories()
            // Don't auto-focus keyboard on appear to avoid taking up screen space
            // isTextFieldFocused = true

            // Prepare haptic generators for better responsiveness
            impactLight.prepare()
            impactMedium.prepare()
            notificationFeedback.prepare()

            // Check if historical summary exists
            Task {
                let hasSummary = await HistoricalSummaryStorage.shared.hasSummary
                await MainActor.run {
                    // Show banner only if no summary exists
                    showIndexationBanner = !hasSummary

                    // Track banner shown
                    if !hasSummary {
                        AnalyticsService.shared.trackIndexationBannerShown()
                    }
                }
            }

            // Track AI chat opened
            AnalyticsService.shared.trackAIChatOpened()
        }
        .onChange(of: showIndexationSheet) { oldValue, newValue in
            // When sheet is dismissed, check if summary was created
            if oldValue && !newValue {
                Task {
                    let hasSummary = await HistoricalSummaryStorage.shared.hasSummary
                    await MainActor.run {
                        // Hide banner if summary now exists
                        if hasSummary {
                            withAnimation {
                                showIndexationBanner = false
                            }
                        }
                    }
                }
            }
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

            Text(String(localized: "AI Assistant", comment: "AI assistant header title"))
                .font(.headline)

            Spacer()

            if !messages.isEmpty {
                HStack(spacing: 16) {
                    // New conversation button
                    Button(action: startNewConversation) {
                        Image(systemName: "square.and.pencil")
                            .foregroundColor(.irTextSecondary)
                    }

                    // Conversation history button
                    Button(action: showConversationHistory) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(.irTextSecondary)
                    }

                    // Clear chat button
                    Button(action: clearChat) {
                        Image(systemName: "trash")
                            .foregroundColor(.irTextSecondary)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color.irCardBackground)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            // Animated Icon with Liquid Glass effect
            ZStack {
                Circle()
                    .fill(Color.irCardBackground)
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
                Text(String(localized: "Running AI Coach", comment: "Empty state title for AI assistant"))
                    .font(.title2)
                    .fontWeight(.bold)

                Text(String(localized: "Ask questions about your performance", comment: "Empty state subtitle for AI assistant"))
                    .font(.subheadline)
                    .foregroundColor(.irTextSecondary)
                    .multilineTextAlignment(.center)
            }

            // Sample Questions
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "Quick questions", comment: "Section header for sample questions"))
                    .font(.caption)
                    .foregroundColor(.irTextSecondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 4)

                VStack(spacing: 8) {
                    ForEach(sampleQuestions, id: \.self) { sample in
                        Button(action: {
                            impactLight.impactOccurred()
                            question = sample
                            isTextFieldFocused = false
                        }) {
                            HStack {
                                Image(systemName: "lightbulb.fill")
                                    .font(.caption)
                                    .foregroundColor(.irWarning)
                                Text(sample)
                                    .font(.subheadline)
                                    .foregroundColor(.irTextPrimary)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundColor(.irTextSecondary)
                            }
                            .padding(12)
                            .background(Color.irCardBackground)
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
                String(localized: "How was my performance?", comment: "Sample question for single workout analysis"),
                String(localized: "What was my best pace?", comment: "Sample question about best pace"),
                String(localized: "Analyze my heart rate", comment: "Sample question about heart rate analysis"),
                String(localized: "Give me improvement tips", comment: "Sample question asking for improvement advice"),
                String(localized: "How was my elevation?", comment: "Sample question about elevation gain")
            ]
        case .recentWorkouts:
            return [
                String(localized: "How have my performances evolved?", comment: "Sample question about performance evolution"),
                String(localized: "What is my progression?", comment: "Sample question about training progression"),
                String(localized: "What is my best workout?", comment: "Sample question asking for best workout"),
                String(localized: "Am I overtraining?", comment: "Sample question about overtraining risk"),
                String(localized: "Analyze my consistency", comment: "Sample question about training consistency")
            ]
        case .recoveryCoaching:
            return [
                String(localized: "Can I train today?", comment: "Sample question asking if ready to train"),
                String(localized: "How to improve my recovery?", comment: "Sample question about recovery improvement"),
                String(localized: "Why is my HRV low?", comment: "Sample question about low HRV"),
                String(localized: "What type of training is suitable?", comment: "Sample question about suitable training type"),
                String(localized: "How to optimize my sleep?", comment: "Sample question about sleep optimization")
            ]
        }
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.irError)
            Text(error)
                .font(.caption)
                .foregroundColor(.irTextSecondary)
            Spacer()
            Button(String(localized: "Dismiss", comment: "Button to dismiss error message")) {
                aiService.error = nil
            }
            .font(.caption)
        }
        .padding()
        .background(Color.irError.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Suggested Questions View

    private var suggestedQuestionsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.irWarning)
                    .font(.caption)
                Text(String(localized: "Suggested questions", comment: "Section header for AI-suggested questions"))
                    .font(.caption)
                    .foregroundColor(.irTextSecondary)
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
                                .foregroundColor(.irTextPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.irCardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(Color.irPrimaryAccent.opacity(0.3), lineWidth: 1)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 8)
        }
        .background(Color.irCardBackground)
    }

    // MARK: - Input Area

    private var inputArea: some View {
        HStack(spacing: 12) {
            HStack {
                TextField(String(localized: "Ask a question...", comment: "Placeholder text for question input field"), text: $question, axis: .vertical)
                    .focused($isTextFieldFocused)
                    .disabled(aiService.isStreaming)
                    .lineLimit(1...4)
                    .onSubmit {
                        askQuestion()
                    }

                if !question.isEmpty && !aiService.isStreaming {
                    Button(action: { question = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.irTextSecondary)
                    }
                }
            }
            .padding(12)
            .background(Color.irCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20))

            // Send Button
            Button(action: askQuestion) {
                ZStack {
                    Circle()
                        .fill(
                            question.isEmpty || aiService.isStreaming ?
                            LinearGradient(
                                colors: [Color.irTextSecondary, Color.irTextSecondary],
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
                            .foregroundColor(.irCardBackground)
                            .font(.system(size: 16))
                    } else {
                        Image(systemName: "arrow.up")
                            .foregroundColor(.irCardBackground)
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
            }
            .disabled(question.isEmpty && !aiService.isStreaming)
        }
        .padding()
        .background(Color.irCardBackground)
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

        // Track AI message sent
        let contextType: AIContextType
        switch mode {
        case .singleWorkout:
            contextType = .workout
        case .recentWorkouts:
            contextType = .workout
        case .recoveryCoaching:
            contextType = .recovery
        }
        AnalyticsService.shared.trackAIMessageSent(
            messageLength: userQuestion.count,
            contextType: contextType
        )

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

        // Start tracking response time
        messageStartTime = Date()

        // Backend will build the context from mode data
        Task {
            await aiService.askQuestion(
                question: userQuestion,
                mode: mode
            )

            await MainActor.run {
                isTyping = false

                // Calculate response time
                let responseTime = messageStartTime.map { Int(Date().timeIntervalSince($0) * 1000) } ?? 0

                // Haptic feedback for response completion
                if aiService.error == nil && !aiService.streamedResponse.isEmpty {
                    notificationFeedback.notificationOccurred(.success)

                    // Track AI response received
                    AnalyticsService.shared.trackAIResponseReceived(
                        responseTimeMs: responseTime,
                        responseLength: aiService.streamedResponse.count
                    )
                } else if aiService.error != nil {
                    notificationFeedback.notificationOccurred(.error)

                    // Track AI response error
                    AnalyticsService.shared.trackAIResponseError(
                        errorType: "ai_service_error",
                        errorMessage: aiService.error ?? "Unknown error"
                    )

                    // Remove empty streaming message if there was an error
                    if let streamingId = streamingMessageId,
                       let index = messages.firstIndex(where: { $0.id == streamingId }) {
                        messages.remove(at: index)
                    }
                }

                // Clear streaming state (message is already updated in messages array)
                streamingMessageId = nil
                aiService.streamedResponse = ""
                messageStartTime = nil

                saveMessages()

                // Auto-save to history after each response
                if !messages.isEmpty && aiService.error == nil {
                    saveCurrentConversationToHistory()
                }
            }
        }
    }

    private func startNewConversation() {
        // Save current conversation if it has messages
        if !messages.isEmpty {
            saveCurrentConversationToHistory()
        }

        withAnimation {
            messages.removeAll()
            aiService.streamedResponse = ""
            aiService.error = nil
            streamingMessageId = nil
            currentConversationId = UUID()
        }
        saveMessages()

        // Track new conversation started
        AnalyticsService.shared.trackAIChatOpened()
    }

    private func showConversationHistory() {
        loadConversationHistories()
        showingHistory = true
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

    private func loadConversation(_ history: ConversationHistory) {
        withAnimation {
            messages = history.messages
            currentConversationId = history.id
        }
        showingHistory = false
    }

    private func deleteConversation(_ history: ConversationHistory) {
        conversationHistories.removeAll { $0.id == history.id }
        saveConversationHistories()
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

    // MARK: - Conversation History Persistence

    private func saveCurrentConversationToHistory() {
        guard !messages.isEmpty else { return }

        let modeString = modeToString(mode)
        let title = ConversationHistory.generateTitle(from: messages)
        let conversationId = currentConversationId ?? UUID()

        let conversation = ConversationHistory(
            id: conversationId,
            title: title,
            messages: messages,
            createdAt: messages.first?.timestamp ?? Date(),
            updatedAt: Date(),
            mode: modeString
        )

        // Update existing or add new
        if let index = conversationHistories.firstIndex(where: { $0.id == conversationId }) {
            conversationHistories[index] = conversation
        } else {
            conversationHistories.insert(conversation, at: 0)
        }

        // Keep only last 50 conversations
        if conversationHistories.count > 50 {
            conversationHistories = Array(conversationHistories.prefix(50))
        }

        saveConversationHistories()
    }

    private func saveConversationHistories() {
        if let encoded = try? JSONEncoder().encode(conversationHistories) {
            UserDefaults.standard.set(encoded, forKey: "workout_conversation_histories")
        }
    }

    private func loadConversationHistories() {
        if let data = UserDefaults.standard.data(forKey: "workout_conversation_histories"),
           let decoded = try? JSONDecoder().decode([ConversationHistory].self, from: data) {
            conversationHistories = decoded
        }
    }

    private func modeToString(_ mode: AIAssistantMode) -> String {
        switch mode {
        case .singleWorkout:
            return "single_workout"
        case .recentWorkouts:
            return "recent_workouts"
        case .recoveryCoaching:
            return "recovery_coaching"
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
                    MarkdownView(message.content)
                        .padding(12)
                        .background(Color.irCardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
                } else {
                    Text(message.content)
                        .font(.body)
                        .foregroundColor(.irCardBackground)
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
                    .foregroundColor(.irTextSecondary)
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



// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var animationPhase: Int = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.irTextSecondary)
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
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear {
            animationPhase = 0
        }
    }
}

// MARK: - Conversation History View

struct ConversationHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var histories: [ConversationHistory]
    let onSelectConversation: (ConversationHistory) -> Void
    let onDeleteConversation: (ConversationHistory) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                // Liquid Glass Background
                LinearGradient(
                    colors: [
                        Color.irBackgroundApp,
                        Color.irPrimaryAccent.opacity(0.02),
                        Color.irPrimaryAccent.opacity(0.01)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                if histories.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(histories) { history in
                                ConversationHistoryRow(
                                    history: history,
                                    onSelect: {
                                        onSelectConversation(history)
                                    },
                                    onDelete: {
                                        withAnimation {
                                            onDeleteConversation(history)
                                        }
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle(String(localized: "Conversation History", comment: "Title for conversation history view"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(String(localized: "Done", comment: "Close conversation history button")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.irCardBackground)
                    .frame(width: 100, height: 100)
                    .shadow(color: .black.opacity(0.1), radius: 20, y: 10)

                Image(systemName: "clock.arrow.circlepath")
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
                Text(String(localized: "No Conversations Yet", comment: "Empty state title for conversation history"))
                    .font(.title2)
                    .fontWeight(.bold)

                Text(String(localized: "Your past conversations will appear here", comment: "Empty state subtitle for conversation history"))
                    .font(.subheadline)
                    .foregroundColor(.irTextSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }
}

// MARK: - Conversation History Row

struct ConversationHistoryRow: View {
    let history: ConversationHistory
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Icon based on mode
                ZStack {
                    Circle()
                        .fill(Color.irCardBackground)
                        .frame(width: 44, height: 44)

                    Image(systemName: modeIcon)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .font(.system(size: 18))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(history.title)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.irTextPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 8) {
                        Text(formatDate(history.updatedAt))
                            .font(.caption)
                            .foregroundColor(.irTextSecondary)

                        Text("•")
                            .foregroundColor(.irTextSecondary)

                        Text(String(format: String(localized: "%lld messages", comment: "Number of messages in conversation"), history.messages.count))
                            .font(.caption)
                            .foregroundColor(.irTextSecondary)
                    }
                }

                Spacer()

                // Delete button
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.irTextSecondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(16)
            .background(Color.irCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var modeIcon: String {
        switch history.mode {
        case "single_workout":
            return "figure.run"
        case "recent_workouts":
            return "chart.line.uptrend.xyaxis"
        case "recovery_coaching":
            return "heart.text.square"
        default:
            return "sparkles"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()

        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            let timeString = formatter.string(from: date)
            return String(localized: "Today at %@", comment: "Date format for today with time").replacingOccurrences(of: "%@", with: timeString)
        } else if calendar.isDateInYesterday(date) {
            return String(localized: "Yesterday", comment: "Yesterday label")
        } else if let daysAgo = calendar.dateComponents([.day], from: date, to: now).day, daysAgo < 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }
}

