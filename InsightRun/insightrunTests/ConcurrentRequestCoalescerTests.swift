import XCTest
@testable import insightrun

@MainActor
final class ConcurrentRequestCoalescerTests: XCTestCase {
    func testConcurrentReadersShareOneRequestAndLaterReadsRefresh() async throws {
        let loader = ConcurrentRequestCoalescer<String, Int>()
        let started = expectation(description: "Request started")
        let joined = expectation(description: "Second reader joined")
        var release: CheckedContinuation<Void, Never>?
        var calls = 0

        let first = Task {
            try await loader.value(for: "workouts") {
                calls += 1
                await withCheckedContinuation { release = $0; started.fulfill() }
                return 42
            }
        }
        await fulfillment(of: [started], timeout: 2)
        let second = Task {
            joined.fulfill()
            return try await loader.value(for: "workouts") { calls += 1; return -1 }
        }
        await fulfillment(of: [joined], timeout: 2)
        release?.resume()
        let firstValue = try await first.value
        let secondValue = try await second.value
        XCTAssertEqual(firstValue, 42)
        XCTAssertEqual(secondValue, 42)
        XCTAssertEqual(calls, 1)

        let refreshed = try await loader.value(for: "workouts") { calls += 1; return 43 }
        XCTAssertEqual(refreshed, 43)
        XCTAssertEqual(calls, 2)
    }

    func testDifferentKeysDoNotWaitForEachOther() async throws {
        let loader = ConcurrentRequestCoalescer<String, Int>()
        let started = expectation(description: "First request started")
        var release: CheckedContinuation<Void, Never>?
        let first = Task {
            try await loader.value(for: "today") {
                await withCheckedContinuation { release = $0; started.fulfill() }
                return 1
            }
        }
        await fulfillment(of: [started], timeout: 2)
        let other = try await loader.value(for: "yesterday") { 2 }
        XCTAssertEqual(other, 2)
        release?.resume()
        let firstValue = try await first.value
        XCTAssertEqual(firstValue, 1)
    }

    func testFailureReachesEveryReaderAndAllowsRetry() async throws {
        enum Failure: Error { case unavailable }
        let loader = ConcurrentRequestCoalescer<String, Int>()
        let started = expectation(description: "Request started")
        let joined = expectation(description: "Second reader joined")
        var release: CheckedContinuation<Void, Never>?
        let first = Task {
            try await loader.value(for: "workouts") {
                await withCheckedContinuation { release = $0; started.fulfill() }
                throw Failure.unavailable
            }
        }
        await fulfillment(of: [started], timeout: 2)
        let second = Task {
            joined.fulfill()
            return try await loader.value(for: "workouts") { -1 }
        }
        await fulfillment(of: [joined], timeout: 2)
        release?.resume()
        for task in [first, second] {
            do {
                _ = try await task.value
                XCTFail("Expected shared failure")
            } catch {
                XCTAssertTrue(error is Failure)
            }
        }
        let retry = try await loader.value(for: "workouts") { 7 }
        XCTAssertEqual(retry, 7)
    }
}
