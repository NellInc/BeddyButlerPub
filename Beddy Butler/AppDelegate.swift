import AppKit
import SwiftUI

@MainActor
enum MenuBarIcon {
    enum State {
        case normal
        case muted
        case pendingVisualNudge
    }

    static func make(state: State = .normal) -> NSImage? {
        let symbols: (primary: String, fallback: String) =
            switch state {
            case .normal: ("moon.zzz.fill", "moon.fill")
            case .muted: ("moon.zzz", "moon")
            case .pendingVisualNudge: ("bell.badge.fill", "exclamationmark.circle.fill")
            }
        let baseImage =
            NSImage(systemSymbolName: symbols.primary, accessibilityDescription: "Beddy Butler")
            ?? NSImage(systemSymbolName: symbols.fallback, accessibilityDescription: "Beddy Butler")
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
        // As the XCTest host, run without the app itself: no scheduler, status item or windows, and no real defaults.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            application.setActivationPolicy(.accessory)
            application.run()
            return
        }
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
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
    private var resumeItem: NSMenuItem?
    /// Set while this copy defers to an earlier running copy and waits to quit.
    private var isHandingOff = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if handOffToRunningInstance() { return }
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

        #if DEBUG
            if let directory = environment["BEDDY_MENU_PROOF_DIR"] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    self?.captureMenuProof(directory)
                }
            }
        #endif

        if let outputDirectory = environment["BEDDY_BUTLER_CAPTURE_UI_DIR"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.captureUI(to: URL(fileURLWithPath: outputDirectory, isDirectory: true))
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !isHandingOff else { return false }
        // Relaunching is the way back in when the status item is hidden, so always show Preferences.
        statusPopover.performClose(nil)
        showPreferences(nil)
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard !isHandingOff else { return }
        scheduler.recalculate(preservingPendingNudge: true)
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

    /// An accessory app shows no menu bar, but key equivalents such as Close, Copy and Paste
    /// still route through the main menu.
    func makeMainMenu() -> NSMenu {
        let appMenu = NSMenu(title: "Beddy Butler")
        appMenu.addItem(makeItem("About Beddy Butler", action: #selector(showAbout)))
        appMenu.addItem(.separator())
        appMenu.addItem(makeItem("Preferences…", action: #selector(showPreferences), keyEquivalent: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(
            NSMenuItem(title: "Hide Beddy Butler", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        )
        appMenu.addItem(
            NSMenuItem(
                title: "Quit Beddy Butler",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowMenu.addItem(
            NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        )

        let mainMenu = NSMenu(title: "Main Menu")
        for submenu in [appMenu, editMenu, windowMenu] {
            let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            mainMenu.addItem(item)
        }
        return mainMenu
    }

    /// Returns true when another copy is already running; that copy is brought forward and this one quits.
    private func handOffToRunningInstance() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        let isolatedRunKeys = [
            "XCTestConfigurationFilePath", "BEDDY_BUTLER_DEFAULTS_SUITE", "BEDDY_BUTLER_CAPTURE_UI_DIR",
            "BEDDY_MENU_PROOF_DIR", "BEDDY_BUTLER_OPEN_ABOUT", "BEDDY_BUTLER_OPEN_PREFERENCES",
        ]
        let currentProcess = ProcessInfo.processInfo.processIdentifier
        guard NSClassFromString("XCTestCase") == nil,
            !isolatedRunKeys.contains(where: { environment[$0] != nil }),
            let bundleIdentifier = Bundle.main.bundleIdentifier,
            let ownLaunch = NSRunningApplication.current.launchDate,
            // Only an earlier copy wins, so two copies launched together never both quit.
            let other = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                .filter({
                    !$0.isTerminated && $0.processIdentifier != currentProcess
                        && ($0.launchDate.map { $0 < ownLaunch } ?? false)
                })
                .min(by: { ($0.launchDate ?? .distantFuture) < ($1.launchDate ?? .distantFuture) })
        else { return false }

        isHandingOff = true

        other.activate()
        guard let otherURL = other.bundleURL else {
            NSApp.terminate(nil)
            return true
        }
        // Opening a running app sends it a reopen event, so it presents Preferences.
        NSWorkspace.shared.openApplication(at: otherURL, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
        // This copy never creates a status item, so it must not linger if the handoff stalls.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { NSApp.terminate(nil) }
        return true
    }

    static func isMenuRequest(type: NSEvent.EventType?, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        type == .rightMouseUp || (type == .leftMouseUp && modifierFlags.contains(.control))
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
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityCustomActions([
                NSAccessibilityCustomAction(
                    name: "Show Commands",
                    target: self,
                    selector: #selector(showStatusMenuAccessibilityAction)
                )
            ])
        }

        let menu = NSMenu(title: "Beddy Butler")
        menu.autoenablesItems = false
        menu.delegate = self

        menu.addItem(makeItem("Open Tonight Panel", action: #selector(openTonightPanel)))
        menu.addItem(.separator())

        let status = NSMenuItem(title: "Next nudge: calculating…", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        nextNudgeItem = status

        let acknowledge = makeItem(
            "Acknowledge Badge",
            action: #selector(acknowledgeVisualNudge)
        )
        acknowledge.isHidden = true
        menu.addItem(acknowledge)
        acknowledgeVisualItem = acknowledge

        menu.addItem(.separator())
        menu.addItem(makeItem("Preferences…", action: #selector(showPreferences), keyEquivalent: ","))

        let preview = makeItem("Hear a Butler Sample", action: #selector(previewButler))
        menu.addItem(preview)
        previewItem = preview

        let snooze = makeItem("Snooze 30 Minutes", action: #selector(snooze))
        snooze.toolTip = "Stay quiet for 30 minutes, then nudge immediately"
        menu.addItem(snooze)
        snoozeItem = snooze

        let mute = makeItem("Pause for Tonight", action: #selector(toggleMute))
        mute.toolTip = "Pause reminders for the current or next bedtime window"
        menu.addItem(mute)
        muteItem = mute

        // While snoozed, the toggle above offers Pause for Tonight, so Resume needs its own item.
        let resume = makeItem("Resume Nudges", action: #selector(resumeFromMenu))
        resume.isHidden = true
        menu.addItem(resume)
        resumeItem = resume

        menu.addItem(.separator())

        let launchAtLogin = makeItem("Open at Login", action: #selector(toggleLaunchAtLogin))
        menu.addItem(launchAtLogin)
        launchAtLoginItem = launchAtLogin

        menu.addItem(makeItem("Beddy Butler Website…", action: #selector(openWebsite)))
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
        let event = NSApp.currentEvent
        if Self.isMenuRequest(type: event?.type, modifierFlags: event?.modifierFlags ?? []) {
            statusPopover.performClose(nil)
            showStatusMenu(relativeTo: button)
        } else if statusPopover.isShown {
            statusPopover.performClose(nil)
        } else {
            refreshMenuState()
            showStatusPopover(relativeTo: button)
        }
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
        // Highlighting synchronously is cleared when the click that opened the popover ends.
        DispatchQueue.main.async { [weak self] in
            guard let self, statusPopover.isShown else { return }
            statusItem?.button?.highlight(true)
        }
    }

    func popoverWillClose(_ notification: Notification) {
        statusItem?.button?.highlight(false)
    }

    private func showStatusPopover(relativeTo button: NSStatusBarButton) {
        // The popover is built once; refresh clock-dependent state such as an ended pause.
        scheduler.refreshTimeDependentState()
        statusPopover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        statusPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        guard statusPopover.isShown else {
            showStatusMenu(relativeTo: button)
            return
        }
        positionStatusPopoverClearOfScreenObstructions()
    }

    #if DEBUG
        // Opt-in local acceptance capture; never reads or changes the user's real defaults.
        private func captureMenuProof(_ directory: String) {
            guard
                ProcessInfo.processInfo.environment["BEDDY_BUTLER_DEFAULTS_SUITE"]?.hasPrefix("BeddyButler.MenuProof.")
                    == true,
                statusMenu != nil, let button = statusItem?.button
            else { return }
            let output = URL(fileURLWithPath: directory)
            try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            NSApp.activate(ignoringOtherApps: true)
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            for state in ["setup", "active", "paused"] {
                if state == "active" { settings.completeOnboarding() }
                if state == "paused" { scheduler.muteForCurrentWindow() }
                for _ in 0..<3 {
                    let timer = Timer(timeInterval: 0.6, repeats: false) { _ in
                        MainActor.assumeIsolated {
                            guard let menu = self.statusMenu else { return }
                            let items = menu.items.filter { !$0.isSeparatorItem && !$0.isHidden }
                                .map { ["title": $0.title, "enabled": $0.isEnabled] as [String: Any] }
                            if let data = try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted])
                            {
                                try? data.write(to: output.appendingPathComponent("menu-\(state).json"))
                            }
                            if let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
                                as? [[String: Any]],
                                let window = windows.first(where: {
                                    ($0[kCGWindowOwnerPID as String] as? Int)
                                        == Int(ProcessInfo.processInfo.processIdentifier)
                                        && ($0[kCGWindowLayer as String] as? Int ?? 0) > 0
                                }), let id = window[kCGWindowNumber as String] as? Int
                            {
                                let capture = Process()
                                capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                                capture.arguments = [
                                    "-x", "-l", String(id), output.appendingPathComponent("menu-\(state).png").path,
                                ]
                                try? capture.run()
                                capture.waitUntilExit()
                            }
                            menu.cancelTracking()
                        }
                    }
                    RunLoop.main.add(timer, forMode: .common)
                    showStatusMenu(relativeTo: button)
                    timer.invalidate()
                    if let data = try? Data(contentsOf: output.appendingPathComponent("menu-\(state).png")),
                        let bitmap = NSBitmapImageRep(data: data),
                        (bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.alphaComponent ?? 0) > 0.1
                    {
                        break
                    }
                    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
                }
            }
            NSApp.terminate(nil)
        }
    #endif

    private func showStatusMenu(relativeTo button: NSStatusBarButton) {
        refreshMenuState()
        // Attaching the menu for one click lets AppKit place it and highlight the button while it is open.
        statusItem?.menu = statusMenu
        button.performClick(nil)
        statusItem?.menu = nil
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
                "Paused until \(LocalizedScheduleText.dayAndTime(mutedUntil))"
        } else if let nextNudge = scheduler.nextNudge {
            nextNudgeItem?.title = "Next nudge: \(LocalizedScheduleText.dayAndTime(nextNudge))"
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
        previewItem?.isEnabled = !scheduler.hasFinishedTonight
        acknowledgeVisualItem?.isHidden = !scheduler.visualNudgePending
        snoozeItem?.title = "Snooze \(settings.snoozeMinutes) Minutes"
        snoozeItem?.toolTip = "Stay quiet for \(settings.snoozeMinutes) minutes, or until bedtime if sooner"
        snoozeItem?.isHidden = settings.isMuted()
        snoozeItem?.isEnabled = scheduler.canSnooze
        // While snoozed, the menu still offers Pause for Tonight.
        let offersResume = settings.isMuted() && !scheduler.isSnoozed
        muteItem?.title = offersResume ? "Resume Nudges" : "Pause for Tonight"
        muteItem?.isEnabled = settings.hasActivatedSchedule
        resumeItem?.isHidden = !(settings.isMuted() && scheduler.isSnoozed)

        if let button = statusItem?.button {
            let mutedUntil = settings.isMuted() ? settings.mutedUntil : nil
            if scheduler.visualNudgePending {
                button.image = MenuBarIcon.make(state: .pendingVisualNudge)
                button.setAccessibilityLabel("Beddy Butler, \(pendingVisualDescription)")
            } else if let mutedUntil {
                button.image = MenuBarIcon.make(state: .muted)
                button.setAccessibilityLabel(
                    "Beddy Butler, paused until \(LocalizedScheduleText.dayAndTime(mutedUntil))"
                )
            } else {
                button.image = MenuBarIcon.make(state: .normal)
                button.setAccessibilityLabel("Beddy Butler")
            }
            if scheduler.visualNudgePending {
                button.toolTip =
                    "Beddy Butler, \(pendingVisualDescription). Open the menu to acknowledge."
            } else if let mutedUntil {
                button.toolTip =
                    "Beddy Butler is paused until \(LocalizedScheduleText.dayAndTime(mutedUntil))"
            } else if let nextNudge = scheduler.nextNudge {
                let nudgeName =
                    settings.nudgeDelivery == .visual ? "nudge" : "\(scheduler.nextPersonality.title) nudge"
                button.toolTip =
                    "Beddy Butler, next \(nudgeName): \(LocalizedScheduleText.dayAndTime(nextNudge))"
            } else {
                button.toolTip = "Beddy Butler, no nudge scheduled"
            }
        }

        loginItemManager.refresh()
        switch loginItemManager.state {
        case .enabled: launchAtLoginItem?.state = .on
        case .requiresApproval: launchAtLoginItem?.state = .mixed
        case .disabled, .unavailable: launchAtLoginItem?.state = .off
        }
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
        if settings.isMuted() && !scheduler.isSnoozed {
            resumeNudges()
        } else {
            pauseTonight()
        }
    }

    @objc private func resumeFromMenu(_ sender: Any?) {
        resumeNudges()
    }

    private func togglePopoverPause() {
        if settings.isMuted() {
            resumeNudges()
        } else {
            pauseTonight()
        }
    }

    private func resumeNudges() {
        scheduler.resumeNudges()
        announce(scheduler.lastEvent)
        refreshMenuState()
    }

    private func pauseTonight() {
        scheduler.muteForCurrentWindow()
        announce(scheduler.lastEvent)
        refreshMenuState()
    }

    @objc private func toggleLaunchAtLogin(_ sender: Any?) {
        loginItemManager.refresh()
        // Waiting for approval: unregistering here would lose the request, so send the user to Settings.
        if loginItemManager.state == .requiresApproval {
            loginItemManager.openSystemSettings()
            refreshMenuState()
            return
        }
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
        scheduler.invalidateTimers()
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
            // Written before the renderer files, which the capture harness waits for.
            captureNativePreferencesWindow(to: directory.appendingPathComponent("preferences-window.png"))
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
                proposedWidth: 420,
                to: directory.appendingPathComponent("tonight-popover.png")
            )
            print("Captured native UI to \(directory.path)")
        } catch {
            fputs("Beddy Butler UI capture failed: \(error)\n", stderr)
        }
    }

    /// Optional: offscreen caching can come back blank, so a failure is logged rather than fatal.
    private func captureNativePreferencesWindow(to destination: URL) {
        guard let contentView = preferencesWindowController.window?.contentView else {
            fputs("Beddy Butler native Preferences capture skipped: no window\n", stderr)
            return
        }
        contentView.layoutSubtreeIfNeeded()
        guard let bitmap = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else {
            fputs("Beddy Butler native Preferences capture skipped: no bitmap\n", stderr)
            return
        }
        contentView.cacheDisplay(in: contentView.bounds, to: bitmap)
        guard NativeSnapshotValidation.hasVisibleContent(bitmap),
            let data = bitmap.representation(using: .png, properties: [:])
        else {
            fputs("Beddy Butler native Preferences capture skipped: blank frame\n", stderr)
            return
        }
        do {
            try data.write(to: destination, options: .atomic)
        } catch {
            fputs("Beddy Butler native Preferences capture failed: \(error)\n", stderr)
        }
    }

    private func writeSnapshot<Content: View>(
        of content: Content,
        proposedWidth: CGFloat,
        to destination: URL
    ) throws {
        // ImageRenderer has no host to honour .preferredColorScheme(.dark), so set the scheme directly.
        let renderer = ImageRenderer(
            content: content.frame(width: proposedWidth).environment(\.colorScheme, .dark)
        )
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
            togglePause: { [weak self] in self?.togglePopoverPause() },
            pauseTonight: { [weak self] in self?.pauseTonight() },
            quit: { [weak self] in self?.quit(nil) }
        )
    }
}
