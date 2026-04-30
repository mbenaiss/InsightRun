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
        colors: [Color.irPrimaryAccent, Color.irPurple],
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
                            .init(color: Color.irTextPrimary.opacity(0.3), location: mid),
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
        VStack(alignment: .leading, spacing: Spacing.sm) {
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
        .padding(Spacing.md)
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
                .font(IRFont.microLabel)
                .foregroundStyle(Color.irTextSecondary)
                .padding(.horizontal, Spacing.sm)
            line
        }
        .padding(.horizontal, Spacing.xxl)
        .padding(.vertical, Spacing.xxs)
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
    @State private var pendingQuestion: String?

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
                            LazyVStack(spacing: Spacing.base) {
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
                            .padding(.vertical, Spacing.base)
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
                        } else {
                            await submitPendingQuestionIfNeeded()
                        }
                    }
                },
                onDecline: {
                    aiService.needsConsent = false
                    pendingQuestion = nil
                    isPresented = false
                }
            )
        }
        .indexationGate(isPresented: $aiService.needsIndexation) {
            await submitPendingQuestionIfNeeded()
        }
        .onAppear {
            loadConversationHistories()
            archivePersistedMessagesAndReset()
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
                .foregroundStyle(.linearGradient(colors: [Color.irPrimaryAccent, Color.irPurple], startPoint: .leading, endPoint: .trailing))
                .font(IRFont.title3)
                .symbolEffect(.pulse, isActive: aiService.isStreaming)

            if aiService.isStreaming {
                Text(String(localized: "Thinking...", comment: "Header title while AI is generating a response"))
                    .font(IRFont.headline)
                    .foregroundStyle(Color.irTextSecondary)
                    .shimmer()
            } else {
                Text(headerTitle)
                    .font(IRFont.headline)
            }

            Spacer()

            HStack(spacing: Spacing.base) {
                if !messages.isEmpty {
                    Button(action: startNewConversation) {
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(Color.irTextSecondary)
                    }
                }

                Button(action: showConversationHistory) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(Color.irTextSecondary)
                        .overlay(alignment: .topTrailing) {
                            if !conversationHistories.isEmpty {
                                Text("\(min(conversationHistories.count, 99))")
                                    .font(IRFont.microLabel)
                                    .foregroundStyle(Color.irTextPrimary)
                                    .padding(3)
                                    .background(Color.irPrimaryAccent)
                                    .clipShape(Circle())
                                    .offset(x: 6, y: -6)
                            }
                        }
                }

                if !messages.isEmpty {
                    Button(action: clearChat) {
                        Image(systemName: "trash")
                            .foregroundStyle(Color.irTextSecondary)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, Spacing.md)
        .background(.ultraThinMaterial)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(String(localized: "Quick questions", comment: "Section header for sample questions"))
                .font(IRFont.eyebrow)
                .tracking(IRTracking.eyebrow)
                .foregroundStyle(Color.irTextTertiary)
                .textCase(.uppercase)
                .padding(.horizontal, Spacing.xxs)

            let columns = [
                GridItem(.flexible(), spacing: Spacing.md),
                GridItem(.flexible(), spacing: Spacing.md)
            ]
            LazyVGrid(columns: columns, spacing: Spacing.md) {
                ForEach(Array(sampleQuestions.prefix(4).enumerated()), id: \.offset) { index, sample in
                    sampleQuestionCard(index: index, sample: sample)
                }
            }
        }
        .padding(.horizontal, Spacing.cardPadding)
        .padding(.vertical, Spacing.lg)
    }

    @ViewBuilder
    private func sampleQuestionCard(index: Int, sample: String) -> some View {
        let meta = sampleQuestionMeta(for: index)
        Button(action: {
            impactLight.impactOccurred()
            question = sample
            isTextFieldFocused = false
        }) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.xs)
                        .fill(meta.color.opacity(0.18))
                    Image(systemName: meta.icon)
                        .font(IRFont.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(meta.color)
                }
                .frame(width: 36, height: 36)

                Text(sample)
                    .font(IRFont.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.irTextPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .padding(Spacing.base)
            .background(Color.irCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .strokeBorder(Color.irBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func sampleQuestionMeta(for index: Int) -> (icon: String, color: Color) {
        let metas: [(String, Color)] = [
            ("bolt.fill", Color.irWarning),
            ("heart.fill", Color.irPurple),
            ("chart.bar.fill", Color.irSuccess),
            ("figure.run", Color.irPrimaryAccent)
        ]
        let m = metas[index % metas.count]
        return (m.0, m.1)
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
                .font(IRFont.caption)
                .foregroundStyle(Color.irTextSecondary)
            Spacer()
            Button(String(localized: "Dismiss", comment: "Button to dismiss error message")) {
                aiService.error = nil
            }
            .font(IRFont.caption)
        }
        .padding()
        .background(Color.irError.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
        .padding(.horizontal)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Suggested Questions View

    private var suggestedQuestionsView: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(Color.irWarning)
                    .font(IRFont.caption)
                Text(String(localized: "Suggested questions", comment: "Section header for AI-suggested questions"))
                    .font(IRFont.caption)
                    .foregroundStyle(Color.irTextSecondary)
                    .textCase(.uppercase)
            }
            .padding(.horizontal)
            .padding(.top, Spacing.sm)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(Array(aiService.suggestedQuestions.enumerated()), id: \.element) { index, suggestion in
                        Button(action: {
                            impactLight.impactOccurred()
                            question = suggestion
                            askQuestion()
                        }) {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: sampleQuestionIcon(for: index))
                                    .font(IRFont.microLabel)
                                    .foregroundStyle(.linearGradient(colors: [Color.irPrimaryAccent, Color.irPurple], startPoint: .leading, endPoint: .trailing))
                                Text(suggestion)
                                    .font(IRFont.body)
                                    .foregroundStyle(Color.irTextPrimary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(Color.irCardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.sm)
                                    .strokeBorder(Color.irPrimaryAccent.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, Spacing.sm)
        }
        .background(.thinMaterial)
    }

    // MARK: - Input Area

    private var inputArea: some View {
        HStack(spacing: Spacing.md) {
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
            .padding(Spacing.md)
            .background(Color.irCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))

            Button(action: askQuestion) {
                ZStack {
                    // Pulse ring during streaming
                    if aiService.isStreaming {
                        Circle()
                            .stroke(Color.irPrimaryAccent, lineWidth: 2)
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
                            (question.isEmpty && !aiService.isStreaming)
                                ? Color.irPrimaryAccent.opacity(0.4)
                                : Color.irPrimaryAccent
                        )
                        .frame(width: 44, height: 44)
                        .shadow(color: (question.isEmpty && !aiService.isStreaming) ? .clear : Color.irPrimaryAccent.opacity(0.3), radius: 8, y: 4)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: question.isEmpty)

                    if aiService.isStreaming {
                        Image(systemName: "stop.fill")
                            .foregroundStyle(Color.irCardBackground)
                            .font(IRFont.bodyEmphasized)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Image(systemName: "arrow.up")
                            .foregroundStyle(Color.irCardBackground)
                            .font(IRFont.bodyEmphasized)
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
        isTextFieldFocused = false
        Task {
            await handleQuestionSubmission(userQuestion)
        }
    }

    private func handleQuestionSubmission(_ userQuestion: String) async {
        pendingQuestion = userQuestion

        guard ConsentService.shared.hasConsentedToAIDataSharing else {
            await MainActor.run {
                aiService.needsConsent = true
            }
            return
        }

        if await HistoricalSummaryStorage.shared.requiresIndexation() {
            await MainActor.run {
                AnalyticsService.shared.trackIndexationGateTriggered(source: "ai_chat")
                aiService.needsIndexation = true
            }
            return
        }

        await submitQuestion(userQuestion)
    }

    private func submitPendingQuestionIfNeeded() async {
        guard let pendingQuestion else { return }
        await handleQuestionSubmission(pendingQuestion)
    }

    @MainActor
    private func contextTypeForCurrentMode() -> AIContextType {
        switch mode {
        case .singleWorkout, .recentWorkouts:
            return .workout
        case .recoveryCoaching:
            return .recovery
        case .unified:
            return UnifiedAIContextProvider.shared.currentPage == .recovery ? .recovery : .workout
        }
    }

    private func submitQuestion(_ userQuestion: String) async {
        await MainActor.run {
            pendingQuestion = nil

            impactMedium.impactOccurred()

            messages.append(ChatMessage(
                role: .user,
                content: userQuestion,
                timestamp: Date()
            ))
            isTyping = true
            saveMessages()

            AnalyticsService.shared.trackAIMessageSent(
                messageLength: userQuestion.count,
                contextType: contextTypeForCurrentMode()
            )

            let streamingId = UUID()
            streamingMessageId = streamingId
            messages.append(ChatMessage(
                id: streamingId,
                role: .assistant,
                content: "",
                timestamp: Date()
            ))

            messageStartTime = Date()
        }

        await aiService.askQuestion(
            question: userQuestion,
            mode: mode
        )

        await MainActor.run {
            isTyping = false

            let responseTime = messageStartTime.map { Int(Date().timeIntervalSince($0) * 1000) } ?? 0

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

            if aiService.error == nil && (!aiService.streamedResponse.isEmpty || aiService.lastFunctionResult != nil) {
                notificationFeedback.notificationOccurred(.success)

                AnalyticsService.shared.trackAIResponseReceived(
                    responseTimeMs: responseTime,
                    responseLength: aiService.streamedResponse.count
                )
            } else if aiService.error != nil {
                notificationFeedback.notificationOccurred(.error)

                AnalyticsService.shared.trackAIResponseError(
                    errorType: "ai_service_error",
                    errorMessage: aiService.error ?? "Unknown error"
                )

                if let streamingId = streamingMessageId,
                   let index = messages.firstIndex(where: { $0.id == streamingId }) {
                    messages.remove(at: index)
                }
            }

            streamingMessageId = nil
            aiService.streamedResponse = ""
            messageStartTime = nil

            saveMessages()

            if !messages.isEmpty && aiService.error == nil {
                saveCurrentConversationToHistory()
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

    /// On each chat open: archive any in-progress conversation into history and start fresh.
    private func archivePersistedMessagesAndReset() {
        if let data = UserDefaults.standard.data(forKey: "workout_chat_messages"),
           let decoded = try? JSONDecoder().decode([ChatMessage].self, from: data),
           !decoded.isEmpty {
            messages = decoded
            saveCurrentConversationToHistory()
            UserDefaults.standard.removeObject(forKey: "workout_chat_messages")
        }

        if !messages.isEmpty { messages = [] }
        currentConversationId = UUID()
        aiService.streamedResponse = ""
        aiService.error = nil
        streamingMessageId = nil
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
        HStack(alignment: .bottom, spacing: Spacing.xs) {
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
                        .font(IRFont.caption)
                        .foregroundStyle(.linearGradient(colors: [Color.irPrimaryAccent, Color.irPurple], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                .offset(y: -16)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: Spacing.xxs) {
                if message.role == .assistant {
                    if let workoutResult = message.workoutResult {
                        WorkoutCardView(workout: workoutResult, message: message.functionMessage)
                    } else if let trendResult = message.trendResult {
                        TrendAnalysisCardView(trend: trendResult, message: message.functionMessage)
                    } else if message.content.isEmpty && isStreaming {
                        SkeletonBubbleView()
                    } else {
                        MarkdownView(message.content)
                            .padding(Spacing.md)
                            .background(Color.irCardBackground)
                            .clipShape(ChatBubbleShape(isUser: false))
                            .shadow(color: Color.irShadow, radius: 8, y: 4)
                    }
                } else {
                    Text(message.content)
                        .font(IRFont.body)
                        .foregroundStyle(Color.irCardBackground)
                        .padding(Spacing.md)
                        .background(LinearGradient.irAccent)
                        .clipShape(ChatBubbleShape(isUser: true))
                        .shadow(color: Color.irPrimaryAccent.opacity(0.3), radius: 8, y: 4)
                }

                Text(Self.timeFormatter.string(from: message.timestamp))
                    .font(IRFont.microLabel)
                    .foregroundStyle(Color.irTextSecondary)
                    .padding(.horizontal, Spacing.xxs)
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
        HStack(spacing: Spacing.xxs) {
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
        .padding(Spacing.md)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
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
                        LazyVStack(spacing: Spacing.md) {
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
        VStack(spacing: Spacing.xl) {
            ZStack {
                Circle()
                    .fill(Color.irCardBackground)
                    .frame(width: 100, height: 100)
                    .shadow(color: Color.irShadowStrong, radius: 20, y: 10)

                Image(systemName: "clock.arrow.circlepath")
                    .font(IRFont.icon(size: 40))
                    .foregroundStyle(LinearGradient.irAccent)
            }

            VStack(spacing: Spacing.sm) {
                Text(String(localized: "No Conversations Yet", comment: "Empty state title for conversation history"))
                    .font(IRFont.title2)
                    .fontWeight(.bold)

                Text(String(localized: "Your past conversations will appear here", comment: "Empty state subtitle for conversation history"))
                    .font(IRFont.body)
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
            HStack(spacing: Spacing.md) {
                // Icon based on mode
                ZStack {
                    Circle()
                        .fill(Color.irCardBackground)
                        .frame(width: 44, height: 44)

                    Image(systemName: modeIcon)
                        .foregroundStyle(LinearGradient.irAccent)
                        .font(IRFont.icon(size: 18))
                }

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(history.title)
                        .font(IRFont.body)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.irTextPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: Spacing.sm) {
                        Text(formatDate(history.updatedAt))
                            .font(IRFont.caption)
                            .foregroundStyle(Color.irTextSecondary)

                        Text("•")
                            .foregroundStyle(Color.irTextSecondary)

                        Text(String(format: String(localized: "%lld messages", comment: "Number of messages in conversation"), history.messages.count))
                            .font(IRFont.caption)
                            .foregroundStyle(Color.irTextSecondary)
                    }
                }

                Spacer()

                // Delete button
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(Color.irTextSecondary)
                        .font(IRFont.bodyEmphasized)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(Spacing.base)
            .background(Color.irCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
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
