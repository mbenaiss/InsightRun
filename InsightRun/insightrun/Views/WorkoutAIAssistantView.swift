//
//  WorkoutAIAssistantView.swift
//  InsightRun
//
//  AI Assistant for analyzing workouts with iOS 26 Liquid Glass design
//

import SwiftUI
import UIKit

// MARK: - Shared Gradient

extension LinearGradient {
    static let irAccent = LinearGradient(
        colors: [.blue, .cyan],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Chat Bubble Shape (asymmetric corners like iMessage)

struct ChatBubbleShape: Shape {
    let isUser: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 16
        let tailRadius: CGFloat = 4

        let topLeft = isUser ? radius : radius
        let topRight = isUser ? radius : radius
        let bottomLeft = isUser ? radius : tailRadius
        let bottomRight = isUser ? tailRadius : radius

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + topLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topRight, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                     tangent2End: CGPoint(x: rect.maxX, y: rect.minY + topRight),
                     radius: topRight)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                     tangent2End: CGPoint(x: rect.maxX - bottomRight, y: rect.maxY),
                     radius: bottomRight)
        path.addLine(to: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                     tangent2End: CGPoint(x: rect.minX, y: rect.maxY - bottomLeft),
                     radius: bottomLeft)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeft))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                     tangent2End: CGPoint(x: rect.minX + topLeft, y: rect.minY),
                     radius: topLeft)
        path.closeSubpath()
        return path
    }
}

// MARK: - Shimmer Effect

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    stops: {
                        let low = max(0, min(phase - 0.3, 1))
                        let mid = max(0, min(phase, 1))
                        let high = max(0, min(phase + 0.3, 1))
                        return [
                            .init(color: .clear, location: low),
                            .init(color: .white.opacity(0.3), location: mid),
                            .init(color: .clear, location: high)
                        ]
                    }(),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .mask(content)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1.3
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Skeleton Loader for Streaming Bubble

struct SkeletonBubbleView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.irTextSecondary.opacity(0.15))
                .frame(height: 12)
                .frame(maxWidth: .infinity)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.irTextSecondary.opacity(0.15))
                .frame(height: 12)
                .frame(width: 180)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.irTextSecondary.opacity(0.15))
                .frame(height: 12)
                .frame(width: 120)
        }
        .shimmer()
        .padding(12)
        .frame(maxWidth: 260, alignment: .leading)
        .background(Color.irCardBackground)
        .clipShape(ChatBubbleShape(isUser: false))
        .shadow(color: Color.irShadow, radius: 8, y: 4)
    }
}

// MARK: - Temporal Separator

struct TimeSeparatorView: View {
    let date: Date

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        HStack {
            line
            Text(Self.dateFormatter.string(from: date))
                .font(.caption2)
                .foregroundStyle(Color.irTextSecondary)
                .padding(.horizontal, 8)
            line
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 4)
    }

    private var line: some View {
        Rectangle()
            .fill(Color.irTextSecondary.opacity(0.2))
            .frame(height: 0.5)
    }
}

// MARK: - Data Models

struct ChatMessage: Identifiable, Equatable, Codable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date
    let functionName: String?
    let functionResult: Data?
    let functionMessage: String?

    enum MessageRole: String, Codable {
        case user
        case assistant
    }

    init(id: UUID = UUID(), role: MessageRole, content: String, timestamp: Date, functionName: String? = nil, functionResult: Data? = nil, functionMessage: String? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.functionName = functionName
        self.functionResult = functionResult
        self.functionMessage = functionMessage
    }

    // MARK: - Codable (backward-compatible)

    enum CodingKeys: String, CodingKey {
        case id, role, content, timestamp, functionName, functionResult, functionMessage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(MessageRole.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        functionName = try container.decodeIfPresent(String.self, forKey: .functionName)
        functionResult = try container.decodeIfPresent(Data.self, forKey: .functionResult)
        functionMessage = try container.decodeIfPresent(String.self, forKey: .functionMessage)
    }

    // MARK: - Agent Card Helpers

    var isWorkoutCard: Bool {
        functionName == "generate_workout" && functionResult != nil
    }

    var isTrendCard: Bool {
        functionName == "analyze_trend" && functionResult != nil
    }

    var workoutResult: AgentWorkoutResult? {
        guard isWorkoutCard, let data = functionResult else { return nil }
        return try? JSONDecoder().decode(AgentWorkoutResult.self, from: data)
    }

    var trendResult: AgentTrendResult? {
        guard isTrendCard, let data = functionResult else { return nil }
        return try? JSONDecoder().decode(AgentTrendResult.self, from: data)
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id && lhs.content == rhs.content && lhs.functionName == rhs.functionName
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
    case unified // Unified mode - loads all data from UnifiedAIContextProvider
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
    @State private var lastHapticDate = Date.distantPast
    @State private var emptyStateIconScale: CGFloat = 0.9
    @State private var sendButtonPulse = false

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

                    // Messages Area
                    ScrollViewReader { scrollProxy in
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                if messages.isEmpty {
                                    emptyStateView
                                        .padding(.top, 40)
                                } else {
                                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                                        // Temporal separator if gap > 5 minutes
                                        if index > 0, shouldShowTimeSeparator(between: messages[index - 1], and: message) {
                                            TimeSeparatorView(date: message.timestamp)
                                        }

                                        MessageBubble(
                                            message: message,
                                            isStreaming: message.id == streamingMessageId
                                        )
                                        .transition(.asymmetric(
                                            insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .opacity
                                        ))
                                    }
                                }

                                // Skeleton loader before streaming starts
                                if isTyping && !aiService.isStreaming {
                                    HStack {
                                        SkeletonBubbleView()
                                        Spacer()
                                    }
                                    .padding(.horizontal)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                                }

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

                                // Haptic pulse while streaming (throttled to ~4 per second)
                                let now = Date()
                                if now.timeIntervalSince(lastHapticDate) >= 0.25 {
                                    lastHapticDate = now
                                    impactLight.impactOccurred()
                                }
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
                    .accessibilityIdentifier("sheet-close")
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
        .sheet(isPresented: $aiService.needsConsent) {
            AIConsentSheet(
                onConsent: {
                    aiService.needsConsent = false
                    Task {
                        if await HistoricalSummaryStorage.shared.requiresIndexation() {
                            await MainActor.run { aiService.needsIndexation = true }
                        }
                    }
                },
                onDecline: {
                    aiService.needsConsent = false
                    isPresented = false
                }
            )
        }
        .indexationGate(isPresented: $aiService.needsIndexation)
        .onAppear {
            loadMessages()
            loadConversationHistories()
            // Don't auto-focus keyboard on appear to avoid taking up screen space
            // isTextFieldFocused = true

            // Prepare haptic generators for better responsiveness
            impactLight.prepare()
            impactMedium.prepare()
            notificationFeedback.prepare()

            // Track AI chat opened
            AnalyticsService.shared.trackAIChatOpened()
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack {
            Image(systemName: "sparkles")
                .foregroundStyle(.linearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing))
                .font(.title3)
                .symbolEffect(.pulse, isActive: aiService.isStreaming)

            if aiService.isStreaming {
                Text(String(localized: "Thinking...", comment: "Header title while AI is generating a response"))
                    .font(.headline)
                    .foregroundStyle(Color.irTextSecondary)
                    .shimmer()
            } else {
                Text(headerTitle)
                    .font(.headline)
            }

            Spacer()

            if !messages.isEmpty {
                HStack(spacing: 16) {
                    Button(action: startNewConversation) {
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(Color.irTextSecondary)
                    }

                    Button(action: showConversationHistory) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(Color.irTextSecondary)
                            .overlay(alignment: .topTrailing) {
                                if !conversationHistories.isEmpty {
                                    Text("\(min(conversationHistories.count, 99))")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(3)
                                        .background(Color.irPrimaryAccent)
                                        .clipShape(Circle())
                                        .offset(x: 6, y: -6)
                                }
                            }
                    }

                    Button(action: clearChat) {
                        Image(systemName: "trash")
                            .foregroundStyle(Color.irTextSecondary)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.irCardBackground)
                    .frame(width: 100, height: 100)
                    .shadow(color: Color.irShadowStrong, radius: 20, y: 10)

                Image(systemName: "sparkles")
                    .font(.system(size: 40))
                    .foregroundStyle(.linearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .scaleEffect(emptyStateIconScale)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                            emptyStateIconScale = 1.1
                        }
                    }
            }

            VStack(spacing: 8) {
                Text(String(localized: "Running AI Coach", comment: "Empty state title for AI assistant"))
                    .font(.title2)
                    .fontWeight(.bold)

                Text(String(localized: "Ask questions about your performance", comment: "Empty state subtitle for AI assistant"))
                    .font(.subheadline)
                    .foregroundStyle(Color.irTextSecondary)
                    .multilineTextAlignment(.center)
            }

            // 2-column grid for sample questions
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "Quick questions", comment: "Section header for sample questions"))
                    .font(.caption)
                    .foregroundStyle(Color.irTextSecondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 4)

                let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(sampleQuestions.enumerated()), id: \.offset) { index, sample in
                        Button(action: {
                            impactLight.impactOccurred()
                            question = sample
                            isTextFieldFocused = false
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: sampleQuestionIcon(for: index))
                                    .font(.caption)
                                    .foregroundStyle(.linearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing))
                                Text(sample)
                                    .font(.caption)
                                    .foregroundStyle(Color.irTextPrimary)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                            .padding(10)
                            .background(Color.irCardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: Color.irShadow, radius: 4, y: 2)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .padding()
        }
        .padding()
    }

    private func sampleQuestionIcon(for index: Int) -> String {
        let icons = ["bolt.fill", "heart.fill", "chart.bar.fill", "figure.run", "moon.fill"]
        return icons[index % icons.count]
    }

    private var headerTitle: String {
        switch mode {
        case .singleWorkout:
            return String(localized: "Workout Analyst", comment: "AI context title for workout detail")
        case .recentWorkouts:
            return String(localized: "Training Coach", comment: "AI context title for workouts")
        case .recoveryCoaching:
            return String(localized: "Recovery Coach", comment: "AI context title for recovery")
        case .unified:
            return UnifiedAIContextProvider.shared.getContextTitle()
        }
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
        case .unified:
            // Use contextual suggestions from UnifiedAIContextProvider
            return UnifiedAIContextProvider.shared.getSampleQuestions()
        }
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.irError)
            Text(error)
                .font(.caption)
                .foregroundStyle(Color.irTextSecondary)
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
                    .foregroundStyle(Color.irWarning)
                    .font(.caption)
                Text(String(localized: "Suggested questions", comment: "Section header for AI-suggested questions"))
                    .font(.caption)
                    .foregroundStyle(Color.irTextSecondary)
                    .textCase(.uppercase)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(aiService.suggestedQuestions.enumerated()), id: \.element) { index, suggestion in
                        Button(action: {
                            impactLight.impactOccurred()
                            question = suggestion
                            askQuestion()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: sampleQuestionIcon(for: index))
                                    .font(.caption2)
                                    .foregroundStyle(.linearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing))
                                Text(suggestion)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.irTextPrimary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
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
        .background(.thinMaterial)
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
                            .foregroundStyle(Color.irTextSecondary)
                    }
                }
            }
            .padding(12)
            .background(Color.irCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20))

            Button(action: askQuestion) {
                ZStack {
                    // Pulse ring during streaming
                    if aiService.isStreaming {
                        Circle()
                            .stroke(LinearGradient.irAccent, lineWidth: 2)
                            .frame(width: 52, height: 52)
                            .scaleEffect(sendButtonPulse ? 1.2 : 1.0)
                            .opacity(sendButtonPulse ? 0 : 0.6)
                            .onAppear {
                                withAnimation(.easeOut(duration: 1.0).repeatForever(autoreverses: false)) {
                                    sendButtonPulse = true
                                }
                            }
                            .onDisappear { sendButtonPulse = false }
                    }

                    Circle()
                        .fill(
                            aiService.isStreaming ? LinearGradient.irAccent :
                            (question.isEmpty ?
                                LinearGradient(colors: [Color.irTextSecondary, Color.irTextSecondary], startPoint: .topLeading, endPoint: .bottomTrailing) :
                                LinearGradient.irAccent)
                        )
                        .frame(width: 44, height: 44)
                        .shadow(color: (question.isEmpty && !aiService.isStreaming) ? .clear : .blue.opacity(0.3), radius: 8, y: 4)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: question.isEmpty)

                    if aiService.isStreaming {
                        Image(systemName: "stop.fill")
                            .foregroundStyle(Color.irCardBackground)
                            .font(.system(size: 16))
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Image(systemName: "arrow.up")
                            .foregroundStyle(Color.irCardBackground)
                            .font(.system(size: 16, weight: .semibold))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.3), value: aiService.isStreaming)
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

        // Track AI message sent
        let contextType: AIContextType
        switch mode {
        case .singleWorkout:
            contextType = .workout
        case .recentWorkouts:
            contextType = .workout
        case .recoveryCoaching:
            contextType = .recovery
        case .unified:
            // For unified mode, determine context based on current page
            contextType = UnifiedAIContextProvider.shared.currentPage == .recovery ? .recovery : .workout
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

                // Handle function result — replace streaming message with card message
                if let funcResult = aiService.lastFunctionResult {
                    if let streamingId = streamingMessageId,
                       let index = messages.firstIndex(where: { $0.id == streamingId }) {
                        messages[index] = ChatMessage(
                            id: streamingId,
                            role: .assistant,
                            content: aiService.streamedResponse.isEmpty ? funcResult.message : aiService.streamedResponse,
                            timestamp: messages[index].timestamp,
                            functionName: funcResult.functionName,
                            functionResult: funcResult.result,
                            functionMessage: funcResult.message
                        )
                    }
                }

                // Haptic feedback for response completion
                if aiService.error == nil && (!aiService.streamedResponse.isEmpty || aiService.lastFunctionResult != nil) {
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

    private func shouldShowTimeSeparator(between previous: ChatMessage, and current: ChatMessage) -> Bool {
        current.timestamp.timeIntervalSince(previous.timestamp) > 300 // 5 minutes
    }

    private func modeToString(_ mode: AIAssistantMode) -> String {
        switch mode {
        case .singleWorkout:
            return "single_workout"
        case .recentWorkouts:
            return "recent_workouts"
        case .recoveryCoaching:
            return "recovery_coaching"
        case .unified:
            return "unified"
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    var isStreaming: Bool = false
    @State private var appeared = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            // Assistant avatar
            if message.role == .assistant {
                ZStack {
                    Circle()
                        .fill(Color.irCardBackground)
                        .frame(width: 28, height: 28)
                        .shadow(color: Color.irShadow, radius: 4, y: 2)
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                        .foregroundStyle(.linearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                .offset(y: -16)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if message.role == .assistant {
                    if let workoutResult = message.workoutResult {
                        WorkoutCardView(workout: workoutResult, message: message.functionMessage)
                    } else if let trendResult = message.trendResult {
                        TrendAnalysisCardView(trend: trendResult, message: message.functionMessage)
                    } else if message.content.isEmpty && isStreaming {
                        SkeletonBubbleView()
                    } else {
                        MarkdownView(message.content)
                            .padding(12)
                            .background(Color.irCardBackground)
                            .clipShape(ChatBubbleShape(isUser: false))
                            .shadow(color: Color.irShadow, radius: 8, y: 4)
                    }
                } else {
                    Text(message.content)
                        .font(.body)
                        .foregroundStyle(Color.irCardBackground)
                        .padding(12)
                        .background(LinearGradient.irAccent)
                        .clipShape(ChatBubbleShape(isUser: true))
                        .shadow(color: .blue.opacity(0.3), radius: 8, y: 4)
                }

                Text(Self.timeFormatter.string(from: message.timestamp))
                    .font(.caption2)
                    .foregroundStyle(Color.irTextSecondary)
                    .padding(.horizontal, 4)
                    .opacity(appeared ? 1 : 0)
            }
            .offset(y: appeared ? 0 : 12)
            .opacity(appeared ? 1 : 0)

            if message.role == .assistant {
                Spacer(minLength: 40)
            }
        }
        .padding(.horizontal)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                appeared = true
            }
        }
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
                    .shadow(color: Color.irShadowStrong, radius: 20, y: 10)

                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 40))
                    .foregroundStyle(LinearGradient.irAccent)
            }

            VStack(spacing: 8) {
                Text(String(localized: "No Conversations Yet", comment: "Empty state title for conversation history"))
                    .font(.title2)
                    .fontWeight(.bold)

                Text(String(localized: "Your past conversations will appear here", comment: "Empty state subtitle for conversation history"))
                    .font(.subheadline)
                    .foregroundStyle(Color.irTextSecondary)
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
                        .foregroundStyle(LinearGradient.irAccent)
                        .font(.system(size: 18))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(history.title)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.irTextPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 8) {
                        Text(formatDate(history.updatedAt))
                            .font(.caption)
                            .foregroundStyle(Color.irTextSecondary)

                        Text("•")
                            .foregroundStyle(Color.irTextSecondary)

                        Text(String(format: String(localized: "%lld messages", comment: "Number of messages in conversation"), history.messages.count))
                            .font(.caption)
                            .foregroundStyle(Color.irTextSecondary)
                    }
                }

                Spacer()

                // Delete button
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(Color.irTextSecondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(16)
            .background(Color.irCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.irShadow, radius: 8, y: 4)
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
        case "unified":
            return "sparkles"
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

