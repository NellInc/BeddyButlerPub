import AppKit
import SwiftUI

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

enum NotchSafePopoverPlacement {
    static let screenMargin: CGFloat = 8

    static func usableFrame(
        screenFrame: NSRect,
        visibleFrame: NSRect,
        safeAreaInsets: NSEdgeInsets,
        margin: CGFloat = screenMargin
    ) -> NSRect {
        let safeAreaFrame = NSRect(
            x: screenFrame.minX + safeAreaInsets.left,
            y: screenFrame.minY + safeAreaInsets.bottom,
            width: max(0, screenFrame.width - safeAreaInsets.left - safeAreaInsets.right),
            height: max(0, screenFrame.height - safeAreaInsets.top - safeAreaInsets.bottom)
        )
        let unobscuredFrame = visibleFrame.intersection(safeAreaFrame)
        guard !unobscuredFrame.isNull, unobscuredFrame.width > margin * 2,
            unobscuredFrame.height > margin * 2
        else {
            return visibleFrame
        }
        return unobscuredFrame.insetBy(dx: margin, dy: margin)
    }

    static func clampedFrame(_ frame: NSRect, inside usableFrame: NSRect) -> NSRect {
        var result = frame
        result.size.width = min(result.width, usableFrame.width)
        result.size.height = min(result.height, usableFrame.height)
        result.origin.x = min(
            max(result.origin.x, usableFrame.minX),
            usableFrame.maxX - result.width
        )
        result.origin.y = min(
            max(result.origin.y, usableFrame.minY),
            usableFrame.maxY - result.height
        )
        return result
    }
}

enum ExternalLinks {
    static let website = URL(string: "https://www.beddybutler.com/")
    static let feedback = URL(string: "https://github.com/NellInc/beddybutlerpub/issues/new/choose")
}

enum NativeSnapshotValidation {
    static func hasVisibleContent(_ bitmap: NSBitmapImageRep) -> Bool {
        let sampleCount = 8
        var pixels = [UInt8](repeating: 0, count: sampleCount * sampleCount * 4)
        guard let image = bitmap.cgImage,
            let context = CGContext(
                data: &pixels,
                width: sampleCount,
                height: sampleCount,
                bitsPerComponent: 8,
                bytesPerRow: sampleCount * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return false
        }
        context.interpolationQuality = .low
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: sampleCount, height: sampleCount)
        )
        for index in stride(from: 0, to: pixels.count, by: 4) {
            if max(pixels[index], pixels[index + 1], pixels[index + 2]) > 2 {
                return true
            }
        }
        return false
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
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSPopoverDelegate {
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
    private lazy var aboutWindowController = AboutWindowController()
    private lazy var statusPopover: NSPopover = {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: makeTonightPopoverView())
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

        let environment = ProcessInfo.processInfo.environment
        if environment["BEDDY_BUTLER_OPEN_ABOUT"] == "1" {
            DispatchQueue.main.async { [weak self] in
                self?.showAbout(nil)
            }
        } else if !settings.hasCompletedOnboarding
            || environment["BEDDY_BUTLER_OPEN_PREFERENCES"] == "1"
        {
            DispatchQueue.main.async { [weak self] in
                self?.showPreferences(nil)
            }
        }

        if let outputDirectory = environment["BEDDY_BUTLER_CAPTURE_UI_DIR"] {
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
            button.setAccessibilityHelp("Open the Tonight panel. Right-click for more commands.")
            button.target = self
            button.action = #selector(toggleStatusPanel)
            button.sendAction(on: [.leftMouseUp])

            let secondaryClick = NSClickGestureRecognizer(
                target: self,
                action: #selector(showStatusMenuFromSecondaryClick)
            )
            secondaryClick.buttonMask = 0x2
            button.addGestureRecognizer(secondaryClick)
            button.setAccessibilityCustomActions([
                NSAccessibilityCustomAction(
                    name: "Show Commands",
                    target: self,
                    selector: #selector(showStatusMenuAccessibilityAction)
                )
            ])
        }

        let menu = NSMenu(title: "Beddy Butler")
        menu.delegate = self

        menu.addItem(makeItem("Open Tonight Panel", action: #selector(openTonightPanel)))
        menu.addItem(.separator())

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
        menu.addItem(makeItem("Show Welcome Guide", action: #selector(showWelcomeGuide)))
        menu.addItem(makeItem("About Beddy Butler", action: #selector(showAbout)))
        menu.addItem(.separator())
        menu.addItem(makeItem("Quit Beddy Butler", action: #selector(quit), keyEquivalent: "q"))

        statusMenu = menu
        statusItem = item
        refreshMenuState()
    }

    @objc private func toggleStatusPanel(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if statusPopover.isShown {
            statusPopover.performClose(nil)
        } else {
            refreshMenuState()
            showStatusPopover(relativeTo: button)
        }
    }

    @objc private func showStatusMenuFromSecondaryClick(_ recognizer: NSClickGestureRecognizer) {
        guard recognizer.state == .ended, let button = statusItem?.button else { return }
        statusPopover.performClose(nil)
        showStatusMenu(relativeTo: button)
    }

    @objc private func showStatusMenuAccessibilityAction(
        _ action: NSAccessibilityCustomAction
    ) -> Bool {
        guard let button = statusItem?.button else { return false }
        statusPopover.performClose(nil)
        showStatusMenu(relativeTo: button)
        return true
    }

    @objc private func openTonightPanel(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        refreshMenuState()
        showStatusPopover(relativeTo: button)
    }

    func popoverDidShow(_ notification: Notification) {
        positionStatusPopoverClearOfScreenObstructions()
    }

    private func showStatusPopover(relativeTo button: NSStatusBarButton) {
        statusPopover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        statusPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        guard statusPopover.isShown else {
            showStatusMenu(relativeTo: button)
            return
        }
        positionStatusPopoverClearOfScreenObstructions()
    }

    private func showStatusMenu(relativeTo button: NSStatusBarButton) {
        refreshMenuState()
        statusMenu?.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.height + 4),
            in: button
        )
    }

    private func positionStatusPopoverClearOfScreenObstructions() {
        guard statusPopover.isShown,
            let popoverWindow = statusPopover.contentViewController?.view.window,
            let screen = statusItem?.button?.window?.screen ?? popoverWindow.screen ?? NSScreen.main
        else {
            return
        }

        let usableFrame = NotchSafePopoverPlacement.usableFrame(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaInsets: screen.safeAreaInsets
        )
        let adjustedFrame = NotchSafePopoverPlacement.clampedFrame(
            popoverWindow.frame,
            inside: usableFrame
        )
        guard adjustedFrame != popoverWindow.frame else { return }
        popoverWindow.setFrame(adjustedFrame, display: true, animate: false)
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
            previewItem?.title = settings.personality.sampleLabel
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
        statusPopover.performClose(nil)
        aboutWindowController.present()
    }

    @objc private func showWelcomeGuide(_ sender: Any?) {
        settings.replayOnboarding()
        showPreferences(sender)
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
            try writeSnapshot(
                of: PreferencesView(
                    settings: settings,
                    scheduler: scheduler,
                    loginItemManager: loginItemManager,
                    notificationManager: notificationManager,
                    captureAllSections: true
                )
                .fixedSize(horizontal: false, vertical: true),
                proposedWidth: 720,
                to: directory.appendingPathComponent("preferences.png")
            )
            try writeSnapshot(
                of: makeTonightPopoverView().fixedSize(horizontal: false, vertical: true),
                proposedWidth: 390,
                to: directory.appendingPathComponent("tonight-popover.png")
            )
            print("Captured native UI to \(directory.path)")
        } catch {
            fputs("Beddy Butler UI capture failed: \(error)\n", stderr)
        }
    }

    private func writeSnapshot<Content: View>(
        of content: Content,
        proposedWidth: CGFloat,
        to destination: URL
    ) throws {
        let renderer = ImageRenderer(content: content.frame(width: proposedWidth))
        renderer.proposedSize = ProposedViewSize(width: proposedWidth, height: nil)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.cgImage else {
            throw CocoaError(.fileWriteUnknown)
        }
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard NativeSnapshotValidation.hasVisibleContent(bitmap),
            let pngData = bitmap.representation(using: .png, properties: [:]),
            !pngData.isEmpty
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        try pngData.write(to: destination, options: .atomic)
    }

    private func makeTonightPopoverView() -> TonightPopoverView {
        TonightPopoverView(
            settings: settings,
            scheduler: scheduler,
            openPreferences: { [weak self] in self?.showPreferences(nil) },
            openAbout: { [weak self] in self?.showAbout(nil) },
            preview: { [weak self] in self?.previewButler(nil) },
            acknowledge: { [weak self] in self?.acknowledgeVisualNudge(nil) },
            snooze: { [weak self] in self?.snooze(nil) },
            togglePause: { [weak self] in self?.toggleMute(nil) },
            quit: { [weak self] in self?.quit(nil) }
        )
    }
}
