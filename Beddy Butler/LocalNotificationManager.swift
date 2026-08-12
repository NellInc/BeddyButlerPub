import AppKit
import SwiftUI
import UserNotifications

enum NotificationAuthorizationState: Equatable {
    case unknown
    case authorized
    case denied
}

@MainActor
protocol LocalNotificationCenter: AnyObject {
    func setDelegate(_ delegate: (any UNUserNotificationCenterDelegate)?)
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
    func requestAuthorization(
        options: UNAuthorizationOptions,
        completionHandler: @escaping @Sendable (Bool, (any Error)?) -> Void
    )
    func getAuthorizationStatus(
        _ completionHandler: @escaping @Sendable (UNAuthorizationStatus) -> Void
    )
    func add(
        _ request: UNNotificationRequest,
        withCompletionHandler completionHandler: @escaping @Sendable ((any Error)?) -> Void
    )
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
}

@MainActor
final class SystemLocalNotificationCenter: LocalNotificationCenter {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func setDelegate(_ delegate: (any UNUserNotificationCenterDelegate)?) {
        center.delegate = delegate
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        center.setNotificationCategories(categories)
    }

    func requestAuthorization(
        options: UNAuthorizationOptions,
        completionHandler: @escaping @Sendable (Bool, (any Error)?) -> Void
    ) {
        center.requestAuthorization(options: options, completionHandler: completionHandler)
    }

    func getAuthorizationStatus(
        _ completionHandler: @escaping @Sendable (UNAuthorizationStatus) -> Void
    ) {
        center.getNotificationSettings { settings in
            completionHandler(settings.authorizationStatus)
        }
    }

    func add(
        _ request: UNNotificationRequest,
        withCompletionHandler completionHandler: @escaping @Sendable ((any Error)?) -> Void
    ) {
        center.add(request, withCompletionHandler: completionHandler)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

@MainActor
final class LocalNotificationManager: NSObject, ObservableObject, VisualNotificationDelivering,
    UNUserNotificationCenterDelegate
{
    static let categoryIdentifier = "BEDDY_BUTLER_VISUAL_NUDGE"
    static let acknowledgeAction = "BEDDY_BUTLER_ACKNOWLEDGE"
    static let snoozeAction = "BEDDY_BUTLER_SNOOZE"
    static let pauseAction = "BEDDY_BUTLER_PAUSE"
    static let notificationIdentifier = "BeddyButler.visualNudge"

    @Published private(set) var authorizationState: NotificationAuthorizationState = .unknown
    @Published private(set) var lastError: String?

    var onAcknowledge: (() -> Void)?
    var onSnooze: (() -> Void)?
    var onPause: (() -> Void)?
    var onOpen: (() -> Void)?

    private let center: any LocalNotificationCenter
    private var authorizationRequestID = UUID()
    private var authorizationRefreshID = UUID()

    init(center: any LocalNotificationCenter = SystemLocalNotificationCenter()) {
        self.center = center
        super.init()
        center.setDelegate(self)
        registerCategory()
        refreshAuthorizationState()
    }

    func setEnabled(_ enabled: Bool, settings: AppSettings) {
        lastError = nil
        authorizationRequestID = UUID()
        authorizationRefreshID = UUID()
        let requestID = authorizationRequestID
        guard enabled else {
            settings.updateNotificationAlertsEnabled(false)
            clearVisualNudges()
            return
        }

        center.requestAuthorization(options: [.alert]) { [weak self, weak settings] granted, error in
            Task { @MainActor in
                guard let self, let settings else { return }
                guard self.authorizationRequestID == requestID else { return }
                if let error {
                    self.lastError = error.localizedDescription
                    settings.updateNotificationAlertsEnabled(false)
                    self.refreshAuthorizationState(settings: settings)
                } else {
                    self.lastError = nil
                    self.authorizationState = granted ? .authorized : .denied
                    settings.updateNotificationAlertsEnabled(granted)
                }
            }
        }
    }

    func refreshAuthorizationState(settings: AppSettings? = nil) {
        authorizationRefreshID = UUID()
        let refreshID = authorizationRefreshID
        center.getAuthorizationStatus { [weak self, weak settings] status in
            Task { @MainActor in
                guard let self else { return }
                guard self.authorizationRefreshID == refreshID else { return }
                switch status {
                case .authorized, .provisional, .ephemeral:
                    self.authorizationState = .authorized
                case .denied:
                    self.authorizationState = .denied
                    settings?.updateNotificationAlertsEnabled(false)
                case .notDetermined:
                    self.authorizationState = .unknown
                @unknown default:
                    self.authorizationState = .unknown
                }
            }
        }
    }

    func deliverVisualNudge(count: Int, personality: ButlerPersonality?) {
        let content = UNMutableNotificationContent()
        content.title = "Bedtime nudge"
        if count > 1 {
            content.body = "\(count) bedtime nudges are waiting."
        } else if let personality {
            content.body = "Your \(personality.title.lowercased()) butler is waiting in the menu bar."
        } else {
            content.body = "A silent bedtime reminder is waiting in the menu bar."
        }
        content.categoryIdentifier = Self.categoryIdentifier
        content.sound = nil

        center.add(
            UNNotificationRequest(
                identifier: Self.notificationIdentifier,
                content: content,
                trigger: nil
            ),
            withCompletionHandler: { [weak self] error in
                guard let error else { return }
                Task { @MainActor in
                    self?.lastError = error.localizedDescription
                }
            }
        )
    }

    func clearVisualNudges() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.notificationIdentifier])
    }

    func openSystemSettings() {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
            )
        else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let actionIdentifier = response.actionIdentifier
        await MainActor.run { [weak self] in
            guard let self else { return }
            switch actionIdentifier {
            case Self.acknowledgeAction:
                onAcknowledge?()
            case Self.snoozeAction:
                onSnooze?()
            case Self.pauseAction:
                onPause?()
            default:
                onOpen?()
            }
        }
    }

    private func registerCategory() {
        let actions = [
            UNNotificationAction(
                identifier: Self.acknowledgeAction,
                title: "Acknowledge"
            ),
            UNNotificationAction(
                identifier: Self.snoozeAction,
                title: "Snooze 30 Minutes"
            ),
            UNNotificationAction(
                identifier: Self.pauseAction,
                title: "Pause Tonight"
            ),
        ]
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.categoryIdentifier,
                actions: actions,
                intentIdentifiers: []
            )
        ])
    }
}
