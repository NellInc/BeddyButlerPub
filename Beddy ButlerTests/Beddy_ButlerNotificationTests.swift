import UserNotifications
import XCTest

@testable import Beddy_Butler

@MainActor
final class BeddyButlerNotificationTests: XCTestCase {
    func testDeniedAuthorizationCanBecomeAllowedAtRuntime() async {
        let defaults = makeDefaults()
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

    func testNotificationActionsRouteExplicitlyAndIgnoreDismissal() {
        let center = TestLocalNotificationCenter()
        let manager = LocalNotificationManager(center: center)
        var events: [String] = []
        manager.onAcknowledge = { events.append("acknowledge") }
        manager.onSnooze = { events.append("snooze") }
        manager.onPause = { events.append("pause") }
        manager.onOpen = { events.append("open") }

        manager.handleNotificationAction(LocalNotificationManager.acknowledgeAction)
        manager.handleNotificationAction(LocalNotificationManager.snoozeAction)
        manager.handleNotificationAction(LocalNotificationManager.pauseAction)
        manager.handleNotificationAction(UNNotificationDefaultActionIdentifier)
        manager.handleNotificationAction(UNNotificationDismissActionIdentifier)
        manager.handleNotificationAction("BEDDY_BUTLER_UNKNOWN_ACTION")

        XCTAssertEqual(events, ["acknowledge", "snooze", "pause", "open"])
    }

    func testDeliverVisualNudgeBuildsSilentGroupedRequestsAndSurfacesErrors() async throws {
        let center = TestLocalNotificationCenter()
        let manager = LocalNotificationManager(center: center)

        manager.deliverVisualNudge(count: 1, personality: nil)
        let silentSingle = try XCTUnwrap(center.addedRequests.last)
        XCTAssertEqual(silentSingle.identifier, LocalNotificationManager.notificationIdentifier)
        XCTAssertEqual(silentSingle.content.title, "Bedtime nudge")
        XCTAssertEqual(
            silentSingle.content.body,
            "A silent bedtime reminder is waiting in the menu bar."
        )
        XCTAssertEqual(
            silentSingle.content.categoryIdentifier,
            LocalNotificationManager.categoryIdentifier
        )
        XCTAssertEqual(
            silentSingle.content.threadIdentifier,
            LocalNotificationManager.notificationIdentifier
        )
        XCTAssertNil(silentSingle.content.sound)

        manager.deliverVisualNudge(count: 1, personality: .shy)
        let voicedSingle = try XCTUnwrap(center.addedRequests.last)
        XCTAssertEqual(
            voicedSingle.content.body,
            "Your shy butler is waiting in the menu bar."
        )

        manager.deliverVisualNudge(count: 3, personality: .zombie)
        let multiple = try XCTUnwrap(center.addedRequests.last)
        XCTAssertEqual(multiple.content.body, "3 bedtime nudges are waiting.")

        center.nextAddError = CocoaError(.coderInvalidValue)
        manager.deliverVisualNudge(count: 1, personality: nil)
        await settleMainActorTasks()
        XCTAssertNotNil(manager.lastError)
    }

    private func makeDefaults() -> UserDefaults {
        makeIsolatedDefaults(prefix: "BeddyButler.NotificationTests")
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

    private(set) var addedRequests: [UNNotificationRequest] = []
    private(set) var removedPendingIdentifiers: [String] = []
    private(set) var removedDeliveredIdentifiers: [String] = []
    var nextAddError: (any Error)?

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
        addedRequests.append(request)
        let error = nextAddError
        nextAddError = nil
        completionHandler(error)
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
