import AppKit
import ServiceManagement
import SwiftUI
import UserNotifications

@MainActor
enum MenuBarIcon {
    static func make(pendingVisualNudge: Bool = false) -> NSImage? {
        let baseImage =
            NSImage(
                systemSymbolName: pendingVisualNudge ? "bell.badge.fill" : "moon.zzz.fill",
                accessibilityDescription: "Beddy Butler"
            )
            ?? NSImage(
                systemSymbolName: pendingVisualNudge ? "exclamationmark.circle.fill" : "moon.fill",
                accessibilityDescription: "Beddy Butler"
            )
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        let image = baseImage?.withSymbolConfiguration(configuration)
        image?.isTemplate = true
        return image
    }
}

enum ExternalLinks {
    static let website = URL(string: "https://www.beddybutler.com/")
    static let feedback = URL(string: "https://github.com/NellInc/beddybutlerpub/issues/new/choose")
}

enum NotificationAuthorizationState: Equatable {
    case unknown
    case authorized
    case denied
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

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        center.delegate = self
        registerCategory()
        refreshAuthorizationState()
    }

    func setEnabled(_ enabled: Bool, settings: AppSettings) {
        guard enabled else {
            settings.updateNotificationAlertsEnabled(false)
            clearVisualNudges()
            return
        }

        center.requestAuthorization(options: [.alert]) { [weak self, weak settings] granted, error in
            Task { @MainActor in
                guard let self, let settings else { return }
                if let error {
                    self.lastError = error.localizedDescription
                    self.authorizationState = .denied
                    settings.updateNotificationAlertsEnabled(false)
                } else {
                    self.lastError = nil
                    self.authorizationState = granted ? .authorized : .denied
                    settings.updateNotificationAlertsEnabled(granted)
                }
            }
        }
    }

    func refreshAuthorizationState(settings: AppSettings? = nil) {
        center.getNotificationSettings { [weak self, weak settings] notificationSettings in
            let status = notificationSettings.authorizationStatus
            Task { @MainActor in
                guard let self else { return }
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
            )
        ) { [weak self] error in
            guard let error else { return }
            Task { @MainActor in
                self?.lastError = error.localizedDescription
            }
        }
    }

    func clearVisualNudges() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.notificationIdentifier])
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

@main
enum BeddyButlerApplication {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.finishLaunching()
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

@MainActor
struct TonightPopoverView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var scheduler: ButlerTimer

    let openPreferences: () -> Void
    let preview: () -> Void
    let acknowledge: () -> Void
    let snooze: () -> Void
    let togglePause: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 11) {
                Image(systemName: scheduler.visualNudgePending ? "bell.badge.fill" : "moon.zzz.fill")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(scheduler.visualNudgePending ? .orange : .indigo)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tonight")
                        .font(.headline)
                    Text(statusText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Label(settings.nudgeDelivery.title, systemImage: deliverySymbol)
                Text("·")
                    .accessibilityHidden(true)
                Text(settings.personality.title)
                Spacer()
                Text(settings.progressiveMode ? "Progressive" : "Steady")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()

            if scheduler.visualNudgePending {
                Button {
                    acknowledge()
                } label: {
                    Label("Acknowledge Badge", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("popover.acknowledge")
            }

            HStack(spacing: 8) {
                Button {
                    preview()
                } label: {
                    Label("Preview", systemImage: "play.fill")
                }
                .accessibilityIdentifier("popover.preview")

                Button {
                    snooze()
                } label: {
                    Label("Snooze", systemImage: "timer")
                }
                .disabled(!scheduler.canSnooze)
                .accessibilityIdentifier("popover.snooze")

                Button {
                    togglePause()
                } label: {
                    Label(
                        settings.isMuted() ? "Resume" : "Pause",
                        systemImage: settings.isMuted() ? "play.circle" : "pause.circle"
                    )
                }
                .accessibilityIdentifier("popover.pause")
            }
            .buttonStyle(.bordered)

            Divider()

            HStack {
                Button("Preferences…") {
                    openPreferences()
                }
                .keyboardShortcut(",")
                .accessibilityIdentifier("popover.preferences")
                Spacer()
                Button("Quit") {
                    quit()
                }
                .accessibilityIdentifier("popover.quit")
            }
            .buttonStyle(.plain)
            .font(.callout)
        }
        .padding(16)
        .frame(width: 340)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Beddy Butler Tonight panel")
    }

    private var statusText: String {
        if scheduler.visualNudgePending {
            return scheduler.pendingVisualNudgeCount == 1
                ? "One visual bedtime nudge is waiting."
                : "\(scheduler.pendingVisualNudgeCount) visual bedtime nudges are waiting."
        }
        if let mutedUntil = settings.mutedUntil, settings.isMuted() {
            return "Paused until \(LocalizedScheduleText.time(mutedUntil))."
        }
        if let nextNudge = scheduler.nextNudge {
            return
                "Next \(scheduler.nextPersonality.title.lowercased()) nudge at \(LocalizedScheduleText.time(nextNudge))."
        }
        return "No nudge is currently scheduled."
    }

    private var deliverySymbol: String {
        switch settings.nudgeDelivery {
        case .sound: "speaker.wave.2.fill"
        case .visual: "bell.badge.fill"
        case .both: "speaker.wave.2.bubble.fill"
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private lazy var settings: AppSettings = {
        let environment = ProcessInfo.processInfo.environment
        if let suiteName = environment["BEDDY_BUTLER_DEFAULTS_SUITE"],
            let defaults = UserDefaults(suiteName: suiteName)
        {
            return AppSettings(defaults: defaults)
        }
        return AppSettings()
    }()
    private lazy var audioPlayer = AudioPlayer()
    private lazy var notificationManager = LocalNotificationManager()
    private lazy var scheduler = ButlerTimer(
        settings: settings,
        audioPlayer: audioPlayer,
        visualNotifier: notificationManager
    )
    private lazy var loginItemManager = LoginItemManager()
    private lazy var preferencesWindowController = PreferencesWindowController(
        settings: settings,
        scheduler: scheduler,
        loginItemManager: loginItemManager,
        notificationManager: notificationManager
    )
    private lazy var statusPopover: NSPopover = {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.contentViewController = NSHostingController(
            rootView: TonightPopoverView(
                settings: settings,
                scheduler: scheduler,
                openPreferences: { [weak self] in self?.showPreferences(nil) },
                preview: { [weak self] in self?.previewButler(nil) },
                acknowledge: { [weak self] in self?.acknowledgeVisualNudge(nil) },
                snooze: { [weak self] in self?.snooze(nil) },
                togglePause: { [weak self] in self?.toggleMute(nil) },
                quit: { [weak self] in self?.quit(nil) }
            )
        )
        return popover
    }()

    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var nextNudgeItem: NSMenuItem?
    private var acknowledgeVisualItem: NSMenuItem?
    private var previewItem: NSMenuItem?
    private var snoozeItem: NSMenuItem?
    private var muteItem: NSMenuItem?
    private var launchAtLoginItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = scheduler
        configureNotificationActions()
        configureStatusItem()
        registerForSystemChanges()

        if !settings.hasCompletedOnboarding
            || ProcessInfo.processInfo.environment["BEDDY_BUTLER_OPEN_PREFERENCES"] == "1"
        {
            DispatchQueue.main.async { [weak self] in
                self?.showPreferences(nil)
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        scheduler.recalculate()
        loginItemManager.refresh()
        notificationManager.refreshAuthorizationState(settings: settings)
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshMenuState()
    }

    private func configureStatusItem() {
        // The sleeping-moon symbol is wider than a square status item. Let AppKit
        // size the item to the symbol so the Zs remain visible instead of clipped.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = MenuBarIcon.make()
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = "Beddy Butler"
            button.setAccessibilityLabel("Beddy Butler")
            button.target = self
            button.action = #selector(toggleStatusPanel)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let menu = NSMenu(title: "Beddy Butler")
        menu.delegate = self

        let status = NSMenuItem(title: "Next nudge: calculating…", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        nextNudgeItem = status

        let acknowledge = makeItem(
            "Acknowledge Visual Nudge",
            action: #selector(acknowledgeVisualNudge),
            keyEquivalent: "a"
        )
        acknowledge.isHidden = true
        menu.addItem(acknowledge)
        acknowledgeVisualItem = acknowledge

        menu.addItem(.separator())
        menu.addItem(makeItem("Preferences…", action: #selector(showPreferences), keyEquivalent: ","))

        let preview = makeItem("Hear a Butler Sample", action: #selector(previewButler), keyEquivalent: "p")
        menu.addItem(preview)
        previewItem = preview

        let snooze = makeItem("Snooze 30 Minutes", action: #selector(snooze), keyEquivalent: "s")
        snooze.toolTip = "Stay quiet for 30 minutes, then nudge immediately"
        menu.addItem(snooze)
        snoozeItem = snooze

        let mute = makeItem("Pause for Tonight", action: #selector(toggleMute))
        mute.toolTip = "Pause reminders for the current or next bedtime window"
        menu.addItem(mute)
        muteItem = mute

        menu.addItem(.separator())

        let launchAtLogin = makeItem("Open at Login", action: #selector(toggleLaunchAtLogin))
        menu.addItem(launchAtLogin)
        launchAtLoginItem = launchAtLogin

        menu.addItem(makeItem("Beddy Butler Website…", action: #selector(openWebsite), keyEquivalent: "w"))
        menu.addItem(makeItem("Send Feedback…", action: #selector(sendFeedback)))
        menu.addItem(makeItem("About Beddy Butler", action: #selector(showAbout)))
        menu.addItem(.separator())
        menu.addItem(makeItem("Quit Beddy Butler", action: #selector(quit), keyEquivalent: "q"))

        statusMenu = menu
        statusItem = item
        refreshMenuState()
    }

    @objc private func toggleStatusPanel(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            statusPopover.performClose(nil)
            statusMenu?.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
        } else if statusPopover.isShown {
            statusPopover.performClose(nil)
        } else {
            refreshMenuState()
            statusPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func makeItem(
        _ title: String,
        action: Selector,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func refreshMenuState() {
        if scheduler.visualNudgePending {
            nextNudgeItem?.title =
                scheduler.pendingVisualNudgeCount == 1
                ? "Visual bedtime nudge waiting"
                : "\(scheduler.pendingVisualNudgeCount) visual bedtime nudges waiting"
        } else if let mutedUntil = settings.mutedUntil, settings.isMuted() {
            nextNudgeItem?.title =
                "Paused until \(LocalizedScheduleText.time(mutedUntil))"
        } else if let nextNudge = scheduler.nextNudge {
            nextNudgeItem?.title = "Next nudge: \(LocalizedScheduleText.time(nextNudge))"
        } else {
            nextNudgeItem?.title = "Next nudge: none scheduled"
        }

        switch settings.nudgeDelivery {
        case .sound:
            previewItem?.title = "Hear a \(settings.personality.title) Sample"
        case .visual:
            previewItem?.title = "Preview Visual Badge"
        case .both:
            previewItem?.title = "Preview Sound + Badge"
        }
        acknowledgeVisualItem?.isHidden = !scheduler.visualNudgePending
        snoozeItem?.isHidden = settings.isMuted()
        snoozeItem?.isEnabled = scheduler.canSnooze
        muteItem?.title = settings.isMuted() ? "Resume Nudges" : "Pause for Tonight"
        muteItem?.state = settings.isMuted() ? .on : .off

        if let button = statusItem?.button {
            button.image = MenuBarIcon.make(pendingVisualNudge: scheduler.visualNudgePending)
            button.setAccessibilityLabel(
                scheduler.visualNudgePending
                    ? "Beddy Butler, \(pendingVisualDescription)"
                    : "Beddy Butler"
            )
            if scheduler.visualNudgePending {
                button.toolTip =
                    "Beddy Butler, \(pendingVisualDescription). Open the menu to acknowledge."
            } else if let mutedUntil = settings.mutedUntil, settings.isMuted() {
                button.toolTip =
                    "Beddy Butler is paused until \(LocalizedScheduleText.time(mutedUntil))"
            } else if let nextNudge = scheduler.nextNudge {
                button.toolTip =
                    "Beddy Butler, next \(scheduler.nextPersonality.title) nudge at \(LocalizedScheduleText.time(nextNudge))"
            } else {
                button.toolTip = "Beddy Butler, no nudge scheduled"
            }
        }

        loginItemManager.refresh()
        launchAtLoginItem?.state = loginItemManager.isEnabled ? .on : .off
        launchAtLoginItem?.toolTip =
            loginItemManager.state == .requiresApproval
            ? "Approval is required in System Settings"
            : nil
    }

    private func registerForSystemChanges() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(timeZoneDidChange),
            name: .NSSystemTimeZoneDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemClockDidChange),
            name: .NSSystemClockDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scheduleDidChange),
            name: .beddyScheduleDidChange,
            object: scheduler
        )
    }

    private var pendingVisualDescription: String {
        scheduler.pendingVisualNudgeCount == 1
            ? "one visual bedtime nudge waiting"
            : "\(scheduler.pendingVisualNudgeCount) visual bedtime nudges waiting"
    }

    private func configureNotificationActions() {
        notificationManager.onAcknowledge = { [weak self] in
            guard let self else { return }
            scheduler.acknowledgeVisualNudge()
            announce(scheduler.lastEvent)
            refreshMenuState()
        }
        notificationManager.onSnooze = { [weak self] in
            guard let self else { return }
            scheduler.acknowledgeVisualNudge()
            scheduler.snooze()
            announce(scheduler.lastEvent)
            refreshMenuState()
        }
        notificationManager.onPause = { [weak self] in
            guard let self else { return }
            scheduler.acknowledgeVisualNudge()
            scheduler.muteForCurrentWindow()
            announce(scheduler.lastEvent)
            refreshMenuState()
        }
        notificationManager.onOpen = { [weak self] in
            self?.showPreferences(nil)
        }
    }

    @objc private func showPreferences(_ sender: Any?) {
        preferencesWindowController.present()
    }

    @objc private func previewButler(_ sender: Any?) {
        scheduler.previewSelectedNudge()
        announce(scheduler.lastEvent)
        refreshMenuState()
    }

    @objc private func acknowledgeVisualNudge(_ sender: Any?) {
        scheduler.acknowledgeVisualNudge()
        announce(scheduler.lastEvent)
        refreshMenuState()
    }

    @objc private func snooze(_ sender: Any?) {
        scheduler.snooze()
        announce(scheduler.lastEvent)
        refreshMenuState()
    }

    @objc private func toggleMute(_ sender: Any?) {
        if settings.isMuted() {
            scheduler.resumeNudges()
        } else {
            scheduler.muteForCurrentWindow()
        }
        announce(scheduler.lastEvent)
        refreshMenuState()
    }

    @objc private func toggleLaunchAtLogin(_ sender: Any?) {
        loginItemManager.setEnabled(!loginItemManager.isEnabled)
        if loginItemManager.state == .requiresApproval {
            loginItemManager.openSystemSettings()
        }
        refreshMenuState()
    }

    @objc private func showAbout(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: ApplicationMetadata.aboutOptions)
    }

    @objc private func openWebsite(_ sender: Any?) {
        if let url = ExternalLinks.website {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func sendFeedback(_ sender: Any?) {
        if let url = ExternalLinks.feedback {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    @objc private func systemWillSleep(_ notification: Notification) {
        scheduler.timer?.invalidate()
    }

    @objc private func systemDidWake(_ notification: Notification) {
        scheduler.recalculate()
    }

    @objc private func timeZoneDidChange(_ notification: Notification) {
        NSTimeZone.resetSystemTimeZone()
        scheduler.recalculate()
    }

    @objc private func systemClockDidChange(_ notification: Notification) {
        scheduler.recalculate()
    }

    @objc private func scheduleDidChange(_ notification: Notification) {
        refreshMenuState()
    }

    private func announce(_ message: String) {
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSNumber(value: NSAccessibilityPriorityLevel.medium.rawValue),
            ]
        )
    }
}
