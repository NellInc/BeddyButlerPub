import UserNotifications
import XCTest

@testable import Beddy_Butler

@MainActor
final class BeddyButlerNotificationTests: XCTestCase {
    func testDeniedAuthorizationCanBecomeAllowedAtRuntime() async {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
        let settings = AppSettings(defaults: defaults)
        let center = TestLocalNotificationCenter()
        let manager = LocalNotificationManager(center: center)

        center.completeNextStatus(.denied)
        await settleMainActorTasks()
        XCTAssertEqual(manager.authorizationState, .denied)

        manager.setEnabled(true, settings: settings)
        center.completeNextRequest(granted: true)
        await settleMainActorTasks()

        XCTAssertEqual(manager.authorizationState, .authorized)
        XCTAssertTrue(settings.notificationAlertsEnabled)
    }

    func testAuthorizationRefreshDisablesAlertsAfterPermissionIsRevoked() async {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
        let settings = AppSettings(defaults: defaults)
        let center = TestLocalNotificationCenter()
        let manager = LocalNotificationManager(center: center)

        center.completeNextStatus(.authorized)
        await settleMainActorTasks()
        manager.setEnabled(true, settings: settings)
        center.completeNextRequest(granted: true)
        await settleMainActorTasks()
        XCTAssertTrue(settings.notificationAlertsEnabled)

        manager.refreshAuthorizationState(settings: settings)
        center.completeNextStatus(.denied)
        await settleMainActorTasks()

        XCTAssertEqual(manager.authorizationState, .denied)
        XCTAssertFalse(settings.notificationAlertsEnabled)
    }

    func testOlderAuthorizationReplyCannotOverrideANewerChoice() async {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
        let settings = AppSettings(defaults: defaults)
        let center = TestLocalNotificationCenter()
        let manager = LocalNotificationManager(center: center)

        center.completeNextStatus(.notDetermined)
        await settleMainActorTasks()
        manager.setEnabled(true, settings: settings)
        manager.setEnabled(false, settings: settings)
        center.completeNextRequest(granted: true)
        await settleMainActorTasks()

        XCTAssertFalse(settings.notificationAlertsEnabled)
        XCTAssertEqual(center.removedPendingIdentifiers, [LocalNotificationManager.notificationIdentifier])
        XCTAssertEqual(center.removedDeliveredIdentifiers, [LocalNotificationManager.notificationIdentifier])
    }

    private func makeDefaults() -> UserDefaults {
        let name = "BeddyButler.NotificationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set(name, forKey: "testSuiteName")
        return defaults
    }

    private func defaultsSuiteName(_ defaults: UserDefaults) -> String {
        defaults.string(forKey: "testSuiteName")!
    }

    private func settleMainActorTasks() async {
        for _ in 0..<4 {
            await Task.yield()
        }
    }
}

@MainActor
private final class TestLocalNotificationCenter: LocalNotificationCenter {
    private var statusCompletions: [@Sendable (UNAuthorizationStatus) -> Void] = []
    private var requestCompletions: [@Sendable (Bool, (any Error)?) -> Void] = []

    private(set) var removedPendingIdentifiers: [String] = []
    private(set) var removedDeliveredIdentifiers: [String] = []

    func setDelegate(_ delegate: (any UNUserNotificationCenterDelegate)?) {}

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {}

    func requestAuthorization(
        options: UNAuthorizationOptions,
        completionHandler: @escaping @Sendable (Bool, (any Error)?) -> Void
    ) {
        requestCompletions.append(completionHandler)
    }

    func getAuthorizationStatus(
        _ completionHandler: @escaping @Sendable (UNAuthorizationStatus) -> Void
    ) {
        statusCompletions.append(completionHandler)
    }

    func add(
        _ request: UNNotificationRequest,
        withCompletionHandler completionHandler: @escaping @Sendable ((any Error)?) -> Void
    ) {
        completionHandler(nil)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedPendingIdentifiers = identifiers
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        removedDeliveredIdentifiers = identifiers
    }

    func completeNextStatus(_ status: UNAuthorizationStatus) {
        XCTAssertFalse(statusCompletions.isEmpty)
        statusCompletions.removeFirst()(status)
    }

    func completeNextRequest(granted: Bool, error: (any Error)? = nil) {
        XCTAssertFalse(requestCompletions.isEmpty)
        requestCompletions.removeFirst()(granted, error)
    }
}
