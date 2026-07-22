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
        ZStack {
            BeddyBackdrop()

            VStack(alignment: .leading, spacing: 18) {
                panelHeader
                nextNudgeCard
                scheduleSummary

                if scheduler.visualNudgePending {
                    Button {
                        acknowledge()
                    } label: {
                        Label("Acknowledge Badge", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BeddyPrimaryButtonStyle(glow: BeddyPalette.blue))
                    .accessibilityIdentifier("popover.acknowledge")
                }

                actionGrid
                progressionFooter
                utilityFooter
            }
            .padding(24)
        }
        .frame(width: 390)
        .foregroundStyle(BeddyPalette.ink)
        .tint(BeddyPalette.blue)
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Beddy Butler Tonight panel")
    }

    private var panelHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("TONIGHT")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(BeddyPalette.blue)
                Text(panelTitle)
                    .font(.system(size: 21, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(BeddyPalette.ink)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: statusColor, radius: 4)
                Text(statusTitle)
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(statusColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(statusColor.opacity(0.12), in: Capsule())
            .accessibilityLabel("Status: \(statusTitle)")
        }
    }

    private var nextNudgeCard: some View {
        HStack(spacing: 15) {
            ZStack {
                LinearGradient(
                    colors: [BeddyPalette.blueBright, Color(red: 100 / 255, green: 143 / 255, blue: 228 / 255)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: nextCardSymbol)
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(Color(red: 16 / 255, green: 37 / 255, blue: 66 / 255))
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .shadow(color: BeddyPalette.blue.opacity(0.27), radius: 13, y: 7)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(nextCardEyebrow)
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Color(red: 145 / 255, green: 170 / 255, blue: 200 / 255))
                Text(nextCardValue)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .tracking(-0.7)
                    .foregroundStyle(BeddyPalette.ink)
                Text(nextCardDetail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(BeddyPalette.muted)
            }

            Spacer(minLength: 0)
        }
        .padding(17)
        .background {
            LinearGradient(
                colors: [BeddyPalette.blue.opacity(0.18), Color.white.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var scheduleSummary: some View {
        HStack(spacing: 14) {
            Text(scheduleName)
                .foregroundStyle(BeddyPalette.muted)
            Spacer(minLength: 8)
            Text(scheduleWindowText)
                .fontWeight(.semibold)
                .foregroundStyle(Color(red: 219 / 255, green: 232 / 255, blue: 248 / 255))
                .monospacedDigit()
        }
        .font(.system(size: 11))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(scheduleName), \(scheduleWindowText)")
    }

    private var actionGrid: some View {
        VStack(spacing: 9) {
            HStack(spacing: 9) {
                Button {
                    preview()
                } label: {
                    Label("Hear sample", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BeddySecondaryButtonStyle())
                .accessibilityIdentifier("popover.preview")

                Button {
                    snooze()
                } label: {
                    Label("Snooze 30 min", systemImage: "timer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BeddySecondaryButtonStyle())
                .disabled(!scheduler.canSnooze)
                .accessibilityIdentifier("popover.snooze")
            }

            Button {
                togglePause()
            } label: {
                Label(
                    settings.isMuted() ? "Resume nudges" : "Pause tonight",
                    systemImage: settings.isMuted() ? "play.circle.fill" : "pause.circle"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(BeddySecondaryButtonStyle())
            .accessibilityIdentifier("popover.pause")
        }
    }

    private var progressionFooter: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(settings.progressiveMode ? "Progressive mode" : "Steady mode")
                .foregroundStyle(BeddyPalette.faint)
            Spacer(minLength: 8)
            Text(settings.progressiveMode ? "Shy  →  Insistent  →  Zombie" : settings.personality.title)
                .fontWeight(.semibold)
                .foregroundStyle(BeddyPalette.blue)
        }
        .font(.system(size: 10))
        .padding(.top, 16)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.09))
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var utilityFooter: some View {
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
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(BeddyPalette.faint)
    }

    private var panelTitle: String {
        if scheduler.visualNudgePending {
            return "A nudge is waiting"
        }
        if settings.isMuted() {
            return "Rest easy for now"
        }
        return scheduler.nextNudge == nil ? "Evening at ease" : "Wind down gently"
    }

    private var statusTitle: String {
        if scheduler.visualNudgePending { return "Waiting" }
        if settings.isMuted() { return "Paused" }
        return scheduler.nextNudge == nil ? "At ease" : "Active"
    }

    private var statusColor: Color {
        if scheduler.visualNudgePending || settings.isMuted() { return BeddyPalette.warm }
        return scheduler.nextNudge == nil ? BeddyPalette.faint : BeddyPalette.success
    }

    private var nextCardEyebrow: String {
        if scheduler.visualNudgePending { return "NUDGE WAITING" }
        if settings.isMuted() { return "PAUSED UNTIL" }
        return "NEXT NUDGE"
    }

    private var nextCardValue: String {
        if scheduler.visualNudgePending {
            return scheduler.pendingVisualNudgeCount == 1
                ? "Ready"
                : "\(scheduler.pendingVisualNudgeCount) waiting"
        }
        if let mutedUntil = settings.mutedUntil, settings.isMuted() {
            return LocalizedScheduleText.time(mutedUntil)
        }
        if let nextNudge = scheduler.nextNudge {
            return LocalizedScheduleText.time(nextNudge)
        }
        return "No plans"
    }

    private var nextCardDetail: String {
        if scheduler.visualNudgePending {
            return "A persistent badge is waiting for you"
        }
        if settings.isMuted() {
            return "Tonight’s reminders are taking a break"
        }
        return "\(scheduler.nextPersonality.title) Butler · \(deliveryTitle)"
    }

    private var nextCardSymbol: String {
        if scheduler.visualNudgePending { return "bell.badge.fill" }
        if settings.isMuted() { return "pause.fill" }
        return "moon.zzz.fill"
    }

    private var deliveryTitle: String {
        switch settings.nudgeDelivery {
        case .sound: "Sound"
        case .visual: "Badge"
        case .both: "Sound + badge"
        }
    }

    private var scheduleName: String {
        settings.tonightOverrideIsActive() ? "Tonight’s adjustment" : settings.primaryScheduleName
    }

    private var scheduleWindowText: String {
        let calendar = Calendar.autoupdatingCurrent
        let schedule = WeeklyBedtimeSchedule(
            startSeconds: settings.startSeconds,
            bedSeconds: settings.bedSeconds,
            activeWeekdays: settings.activeWeekdays,
            alternateScheduleEnabled: settings.alternateScheduleEnabled,
            alternateWeekdays: settings.alternateScheduleWeekdays,
            alternateStartSeconds: settings.alternateStartSeconds,
            alternateBedSeconds: settings.alternateBedSeconds,
            alternatePattern: settings.alternateSchedulePattern,
            rotationAnchorDate: settings.rotationAnchorDate,
            rotationPrimaryDays: settings.rotationPrimaryDays,
            rotationAlternateDays: settings.rotationAlternateDays,
            oneNightOverride: settings.tonightOverrideDate.map {
                OneNightScheduleOverride(
                    anchorDate: $0,
                    startSeconds: settings.tonightOverrideStartSeconds,
                    bedSeconds: settings.tonightOverrideBedSeconds
                )
            }
        )
        guard
            let window = ScheduleCalculator(calendar: calendar).window(
                containingOrAfter: Date(),
                schedule: schedule
            )
        else {
            return "No active nights"
        }
        return "\(LocalizedScheduleText.time(window.start))  →  \(LocalizedScheduleText.time(window.end))"
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

        if let outputDirectory = ProcessInfo.processInfo.environment["BEDDY_BUTLER_CAPTURE_UI_DIR"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.captureUI(to: URL(fileURLWithPath: outputDirectory, isDirectory: true))
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

    private func captureUI(to directory: URL) {
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            guard let preferencesWindow = preferencesWindowController.window else {
                throw CocoaError(.fileNoSuchFile)
            }
            try writeSnapshot(
                of: preferencesWindow,
                to: directory.appendingPathComponent("preferences.png")
            )

            guard let button = statusItem?.button else {
                throw CocoaError(.featureUnsupported)
            }
            statusPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self, let popoverView = statusPopover.contentViewController?.view else {
                    return
                }
                do {
                    try writeSnapshot(
                        of: popoverView,
                        to: directory.appendingPathComponent("tonight-popover.png")
                    )
                    print("Captured native UI to \(directory.path)")
                } catch {
                    fputs("Beddy Butler UI capture failed: \(error)\n", stderr)
                }
            }
        } catch {
            fputs("Beddy Butler UI capture failed: \(error)\n", stderr)
        }
    }

    private func writeSnapshot(of view: NSView, to destination: URL) throws {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        view.window?.displayIfNeeded()
        let scale = view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0,
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int((bounds.width * scale).rounded()),
                pixelsHigh: Int((bounds.height * scale).rounded()),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        else {
            throw CocoaError(.fileWriteUnknown)
        }

        bitmap.size = bounds.size
        view.cacheDisplay(in: bounds, to: bitmap)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try pngData.write(to: destination, options: .atomic)
    }

    private func writeSnapshot(of window: NSWindow, to destination: URL) throws {
        window.displayIfNeeded()
        guard
            let image = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                CGWindowID(window.windowNumber),
                [.boundsIgnoreFraming, .bestResolution]
            )
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try pngData.write(to: destination, options: .atomic)
    }
}
