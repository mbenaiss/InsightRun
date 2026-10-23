import XCTest
@testable import insightrun

@MainActor
final class CancellationSurveyStoreTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private let annual = "com.altcode.insightrun.Annual"
    private let cancelledAt = Date(timeIntervalSince1970: 1_792_717_871)

    override func setUp() {
        suite = "cancellation-survey-\(UUID())"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
    }

    func testCancelledTrialIsSurveyedOnceThenNeverAgain() throws {
        let store = CancellationSurveyStore(defaults: defaults)
        let request = try XCTUnwrap(store.request(
            productId: annual, isTrial: true, willRenew: false,
            unsubscribeDetectedAt: cancelledAt, now: cancelledAt.addingTimeInterval(3600)))
        XCTAssertEqual(request, CancellationSurveyRequest(productId: annual, isTrial: true, unsubscribeDetectedAt: cancelledAt))

        store.markAsked(request)

        let relaunched = CancellationSurveyStore(defaults: defaults)
        XCTAssertNil(relaunched.request(
            productId: annual, isTrial: true, willRenew: false,
            unsubscribeDetectedAt: cancelledAt, now: cancelledAt.addingTimeInterval(7200)))
    }

    func testRenewingSubscriptionIsNeverSurveyed() {
        let store = CancellationSurveyStore(defaults: defaults)
        XCTAssertNil(store.request(productId: annual, isTrial: false, willRenew: true,
                                   unsubscribeDetectedAt: nil, now: cancelledAt))
        XCTAssertNil(store.request(productId: annual, isTrial: false, willRenew: false,
                                   unsubscribeDetectedAt: nil, now: cancelledAt))
    }

    func testCancellationOlderThanAWeekIsNotSurveyed() {
        let store = CancellationSurveyStore(defaults: defaults)
        XCTAssertNotNil(store.request(productId: annual, isTrial: false, willRenew: false,
                                      unsubscribeDetectedAt: cancelledAt,
                                      now: cancelledAt.addingTimeInterval(CancellationSurveyStore.maximumAge)))
        XCTAssertNil(store.request(productId: annual, isTrial: false, willRenew: false,
                                   unsubscribeDetectedAt: cancelledAt,
                                   now: cancelledAt.addingTimeInterval(CancellationSurveyStore.maximumAge + 60)))
    }

    func testResubscribingThenCancellingAgainAsksAgain() throws {
        let store = CancellationSurveyStore(defaults: defaults)
        let first = try XCTUnwrap(store.request(productId: annual, isTrial: true, willRenew: false,
                                                unsubscribeDetectedAt: cancelledAt, now: cancelledAt))
        store.markAsked(first)

        let secondCancellation = cancelledAt.addingTimeInterval(3 * 24 * 3600)
        XCTAssertNotNil(store.request(productId: annual, isTrial: false, willRenew: false,
                                      unsubscribeDetectedAt: secondCancellation, now: secondCancellation))
    }

    func testEveryReasonHasAStableAnalyticsValue() {
        XCTAssertEqual(CancellationReason.allCases.map(\.rawValue), [
            "too_expensive", "not_useful_enough", "just_trying_it", "missing_feature", "technical_issue", "other"
        ])
    }
}
