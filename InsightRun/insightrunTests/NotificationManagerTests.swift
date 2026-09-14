import XCTest
import UserNotifications
@testable import insightrun

@MainActor
final class NotificationManagerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var requests: [UNNotificationRequest] = []

    override func setUp() {
        super.setUp()
        suiteName = "com.insightrun.notifications.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        requests = []
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func manager(hour: Int = 19, pending: [UNNotificationRequest] = []) -> NotificationManager {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 13, hour: hour))!
        let manager = NotificationManager(
            userDefaults: defaults,
            now: { date },
            addNotification: { [weak self] request in
                await Task.yield()
                self?.requests.append(request)
            },
            pendingNotifications: { pending },
            removePendingNotifications: { _ in }
        )
        manager.isNotificationsEnabled = true
        return manager
    }

    private func send(_ manager: NotificationManager) async {
        await manager.sendWeeklyProgressNotification(runCount: 3, totalDistanceKm: 20, weekOverWeekChange: 10)
    }

    func testDisablingAllNotificationsSurvivesRelaunch() async {
        let first = manager()
        first.removeAllPendingNotifications()
        XCTAssertFalse(first.isNotificationsEnabled)
        let relaunched = manager()
        XCTAssertFalse(relaunched.areNotificationsAllowedByPreference)
    }

    func testWeeklyOptOutDoesNotSendOrReenableSummary() async {
        let manager = manager()
        await send(manager)
        XCTAssertTrue(requests.isEmpty)
        XCTAssertFalse(manager.isWeeklySummaryEnabled)
    }

    func testMorningLaunchDoesNotSendAnEarlySummary() async {
        let manager = manager(hour: 9)
        manager.isWeeklySummaryEnabled = true
        await send(manager)
        XCTAssertTrue(requests.isEmpty)
    }

    func testRecurringSummaryDoesNotGetAnExtraImmediateNotification() async {
        let reminder = UNNotificationRequest(identifier: "weekly-summary", content: UNMutableNotificationContent(), trigger: nil)
        let manager = manager(pending: [reminder])
        manager.isWeeklySummaryEnabled = true
        await send(manager)
        XCTAssertTrue(requests.isEmpty)
    }

    func testConcurrentLaunchesSendOnlyOneFallback() async {
        let manager = manager()
        manager.isWeeklySummaryEnabled = true
        async let first: Void = send(manager)
        async let second: Void = send(manager)
        _ = await (first, second)
        XCTAssertEqual(requests.filter { $0.identifier == "weekly-progress" }.count, 1)
        await send(manager)
        XCTAssertEqual(requests.filter { $0.identifier == "weekly-progress" }.count, 1)
    }

    func testSuccessfulFallbackRemainsThrottledAfterRelaunch() async {
        let first = manager()
        first.isWeeklySummaryEnabled = true
        await send(first)
        let relaunched = manager()
        relaunched.isWeeklySummaryEnabled = true
        await send(relaunched)
        XCTAssertEqual(requests.filter { $0.identifier == "weekly-progress" }.count, 1)
    }

    func testFailedFallbackCanBeRetried() async {
        var attempts = 0
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 13, hour: 19))!
        let manager = NotificationManager(
            userDefaults: defaults,
            now: { date },
            addNotification: { request in
                guard request.identifier == "weekly-progress" else { return }
                attempts += 1
                if attempts == 1 { throw URLError(.notConnectedToInternet) }
            },
            pendingNotifications: { [] },
            removePendingNotifications: { _ in }
        )
        manager.isNotificationsEnabled = true
        manager.isWeeklySummaryEnabled = true
        await send(manager)
        await send(manager)
        XCTAssertEqual(attempts, 2)
    }
}
