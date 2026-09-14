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
