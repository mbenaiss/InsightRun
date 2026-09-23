import XCTest
@testable import insightrun

final class AgentStreamParserTests: XCTestCase {
    func testCompleteStreamPreservesContent() throws {
        var parser = BackendAPIClient.AgentStreamParser()
        guard case .content(let text) = try parser.consume("data: {\"type\":\"content\",\"content\":\"Hello.\"}") else {
            return XCTFail("Expected text content")
        }
        XCTAssertEqual(text, "Hello.")
        _ = try parser.consume("data: [DONE]")
        XCTAssertNoThrow(try parser.finish())
    }

    func testInterruptedStreamIsNotReportedAsSuccessful() throws {
        var parser = BackendAPIClient.AgentStreamParser()
        _ = try parser.consume("data: {\"type\":\"content\",\"content\":\"Partial answer\"}")
        XCTAssertThrowsError(try parser.finish())
    }

    func testEmptyCompletionIsRejected() {
        var parser = BackendAPIClient.AgentStreamParser()
        XCTAssertThrowsError(try parser.consume("data: [DONE]"))
    }

    func testServerErrorInterruptsPartialContent() throws {
        var parser = BackendAPIClient.AgentStreamParser()
        _ = try parser.consume("data: {\"type\":\"content\",\"content\":\"Partial\"}")
        XCTAssertThrowsError(try parser.consume("data: {\"type\":\"error\"}"))
    }

    func testFunctionResultCanCompleteWithoutText() throws {
        var parser = BackendAPIClient.AgentStreamParser()
        guard case .functionResult(let result) = try parser.consume("data:{\"type\":\"function_result\",\"function\":\"generate_workout\",\"message\":\"Ready\",\"result\":{\"steps\":[]}}") else {
            return XCTFail("Expected function result")
        }
        XCTAssertEqual(result.functionName, "generate_workout")
        _ = try parser.consume("data:[DONE]")
        XCTAssertNoThrow(try parser.finish())
    }
}

@MainActor
final class AgentStreamCompletionTests: XCTestCase {
    private let payload = AgentChatRequest(
        userQuestion: "How was my run?", language: "en",
        data: ChatDataPayload(workout: nil, recovery: nil, profile: nil, baseline: nil, recentWorkouts: nil,
                              historicalSummary: nil, trainingPlan: nil),
        conversationHistory: nil)

    override func setUp() {
        super.setUp()
        StreamingStubProtocol.reset()
        URLProtocol.registerClass(StreamingStubProtocol.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(StreamingStubProtocol.self)
        StreamingStubProtocol.reset()
        super.tearDown()
    }

    private static func content(_ text: String) -> String {
        "data: {\"type\":\"content\",\"content\":\"\(text)\"}"
    }

    func testCompleteStreamEndsWithTheServerMarkerAndIsCountedOnce() async throws {
        StreamingStubProtocol.lines = [Self.content("Your run was steady."), "data: [DONE]"]
        var events: [String] = []
        for try await event in try await BackendAPIClient.shared.agentChatStream(payload: payload) {
            switch event {
            case .content(let text): events.append(text)
            case .functionResult: events.append("function")
            case .completed: events.append("completed")
            }
        }
        XCTAssertEqual(events, ["Your run was steady.", "completed"])

        var counted = 0
        let service = WorkoutAIService(countFreeRequest: { counted += 1 })
        await service.receiveAgentStream(requiresCompleteResponse: false) {
            try await BackendAPIClient.shared.agentChatStream(payload: self.payload)
        }
        XCTAssertEqual(service.streamedResponse, "Your run was steady.")
        XCTAssertNil(service.error)
        XCTAssertEqual(counted, 1)
    }

    func testStreamClosedWithoutTheServerMarkerIsNeitherKeptNorCounted() async {
        StreamingStubProtocol.lines = [Self.content("Partial answer.")]
        var counted = 0
        let service = WorkoutAIService(countFreeRequest: { counted += 1 })
        await service.receiveAgentStream(requiresCompleteResponse: false) {
            try await BackendAPIClient.shared.agentChatStream(payload: self.payload)
        }
        XCTAssertEqual(service.streamedResponse, "")
        XCTAssertNotNil(service.error)
        XCTAssertFalse(service.isStreaming)
        XCTAssertEqual(counted, 0)
    }

    func testStalledStreamCancelledByTheCallerIsNeitherKeptNorCounted() async throws {
        StreamingStubProtocol.lines = [Self.content("Partial answer.")]
        StreamingStubProtocol.finishes = false
        let torndown = expectation(description: "The stalled request was cancelled")
        torndown.assertForOverFulfill = false
        StreamingStubProtocol.onStop = { torndown.fulfill() }
        var counted = 0
        let service = WorkoutAIService(countFreeRequest: { counted += 1 })
        service.isStreaming = true
        let request = Task {
            await service.receiveAgentStream(requiresCompleteResponse: false) {
                try await BackendAPIClient.shared.agentChatStream(payload: self.payload)
            }
        }
        let deadline = Date().addingTimeInterval(5)
        while service.streamedResponse.isEmpty, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(service.streamedResponse, "Partial answer.")

        request.cancel()
        await request.value
        await fulfillment(of: [torndown], timeout: 5)

        XCTAssertEqual(service.streamedResponse, "")
        XCTAssertNotNil(service.error)
        XCTAssertFalse(service.isStreaming)
        XCTAssertEqual(counted, 0)
    }
}

nonisolated private final class StreamingStubProtocol: URLProtocol {
    nonisolated(unsafe) static var lines: [String] = []
    nonisolated(unsafe) static var finishes = true
    nonisolated(unsafe) static var onStop: (() -> Void)?

    static func reset() {
        lines = []
        finishes = true
        onStop = nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.path == "/api/agent/chat"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Type": "text/event-stream"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for line in Self.lines {
            client?.urlProtocol(self, didLoad: Data((line + "\n").utf8))
        }
        if Self.finishes {
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        Self.onStop?()
    }
}
