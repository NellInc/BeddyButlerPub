import AppKit
import Foundation
import XCTest

@testable import Beddy_Butler

final class BeddyButlerWallClockTests: XCTestCase {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return result
    }

    func testWallClockRoundTrip() {
        let expected = 22 * 3_600 + 45 * 60 + 12
        let date = WallClockTime.date(
            for: expected,
            relativeTo: Date(timeIntervalSince1970: 1_700_000_000),
            calendar: calendar
        )

        XCTAssertEqual(WallClockTime.seconds(from: date, calendar: calendar), expected)
    }

    func testWallClockInputIsClampedToOneDay() {
        let date = WallClockTime.date(
            for: 100_000,
            relativeTo: Date(timeIntervalSince1970: 1_700_000_000),
            calendar: calendar
        )

        XCTAssertEqual(WallClockTime.seconds(from: date, calendar: calendar), 86_399)
    }

    func testScheduleTimesRespectTwelveAndTwentyFourHourLocales() {
        let date = Date(timeIntervalSince1970: 1_700_001_000)
        let timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

        let twelveHourTime = LocalizedScheduleText.time(
            date,
            locale: Locale(identifier: "en_US"),
            timeZone: timeZone
        )
        XCTAssertTrue(twelveHourTime.hasPrefix("10:30"))
        XCTAssertTrue(twelveHourTime.hasSuffix("PM"))
        XCTAssertEqual(
            LocalizedScheduleText.time(
                date,
                locale: Locale(identifier: "en_GB"),
                timeZone: timeZone
            ),
            "22:30"
        )
    }

    func testExternalWebsiteAndFeedbackLinksUseSecureURLs() throws {
        let website = try XCTUnwrap(ExternalLinks.website)
        let feedback = try XCTUnwrap(ExternalLinks.feedback)

        XCTAssertEqual(website.scheme, "https")
        XCTAssertEqual(feedback.scheme, "https")
        XCTAssertEqual(website.host, "www.beddybutler.com")
        XCTAssertEqual(feedback.host, "github.com")
    }

    func testPopoverIsClampedBelowTheNotchAndInsideScreenEdges() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1_728, height: 1_117)
        let visibleFrame = NSRect(x: 0, y: 0, width: 1_728, height: 1_084)
        let safeInsets = NSEdgeInsets(top: 32, left: 0, bottom: 0, right: 0)
        let usableFrame = NotchSafePopoverPlacement.usableFrame(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            safeAreaInsets: safeInsets
        )

        let clippedAtTopLeft = NSRect(x: -20, y: 900, width: 390, height: 200)
        let adjustedTopLeft = NotchSafePopoverPlacement.clampedFrame(
            clippedAtTopLeft,
            inside: usableFrame
        )
        XCTAssertEqual(adjustedTopLeft.minX, 8)
        XCTAssertEqual(adjustedTopLeft.maxY, 1_076)

        let clippedAtBottomRight = NSRect(x: 1_500, y: -30, width: 390, height: 200)
        let adjustedBottomRight = NotchSafePopoverPlacement.clampedFrame(
            clippedAtBottomRight,
            inside: usableFrame
        )
        XCTAssertEqual(adjustedBottomRight.maxX, 1_720)
        XCTAssertEqual(adjustedBottomRight.minY, 8)
    }

    @MainActor
    func testMenuBarIconIsAVisibleTemplateSymbol() throws {
        let icon = try XCTUnwrap(MenuBarIcon.make())
        let pendingIcon = try XCTUnwrap(MenuBarIcon.make(pendingVisualNudge: true))

        XCTAssertTrue(icon.isTemplate)
        XCTAssertTrue(pendingIcon.isTemplate)
        XCTAssertGreaterThan(icon.size.width, 0)
        XCTAssertGreaterThan(icon.size.height, 0)
        XCTAssertNotNil(icon.tiffRepresentation)
        XCTAssertNotNil(pendingIcon.tiffRepresentation)
    }

    @MainActor
    func testPreferencesWindowHasAResizableModernLayout() async throws {
        let suiteName = "BeddyButlerPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let settings = AppSettings(defaults: defaults)
        let audioPlayer = AudioPlayer()
        let scheduler = ButlerTimer(
            settings: settings,
            audioPlayer: audioPlayer,
            intervalProvider: { $0.lowerBound },
            escalationProvider: { 2 }
        )
        let controller = PreferencesWindowController(
            settings: settings,
            scheduler: scheduler,
            loginItemManager: LoginItemManager(),
            notificationManager: LocalNotificationManager()
        )
        defer {
            scheduler.timer?.invalidate()
            controller.close()
            defaults.removePersistentDomain(forName: suiteName)
        }

        let window = try XCTUnwrap(controller.window)
        let contentView = try XCTUnwrap(window.contentView)
        contentView.layoutSubtreeIfNeeded()

        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertTrue(window.backgroundColor.isEqual(NSColor.clear))
        XCTAssertFalse(window.isRestorable)
        XCTAssertGreaterThanOrEqual(window.minSize.width, 640)
        XCTAssertGreaterThanOrEqual(window.minSize.height, 680)
        XCTAssertGreaterThanOrEqual(contentView.bounds.width, 640)
        XCTAssertGreaterThanOrEqual(contentView.bounds.height, 680)

        if let snapshotPath = ProcessInfo.processInfo.environment["BEDDY_BUTLER_SNAPSHOT_PATH"] {
            controller.showWindow(nil)
            window.makeKeyAndOrderFront(nil)
            try await Task.sleep(for: .milliseconds(500))
            try capture(contentView: contentView, at: snapshotPath)
        }

        let completedPath = ProcessInfo.processInfo.environment[
            "BEDDY_BUTLER_COMPLETED_SNAPSHOT_PATH"
        ]
        if let completedPath {
            settings.completeOnboarding()
            controller.showWindow(nil)
            window.makeKeyAndOrderFront(nil)
            try await Task.sleep(for: .milliseconds(500))
            try capture(contentView: contentView, at: completedPath)
        }

        if let darkPath = ProcessInfo.processInfo.environment["BEDDY_BUTLER_DARK_SNAPSHOT_PATH"] {
            settings.completeOnboarding()
            window.appearance = NSAppearance(named: .darkAqua)
            controller.showWindow(nil)
            window.makeKeyAndOrderFront(nil)
            try await Task.sleep(for: .milliseconds(500))
            try capture(contentView: contentView, at: darkPath)
            window.appearance = nil
        }

        if let minimumPath = ProcessInfo.processInfo.environment["BEDDY_BUTLER_MINIMUM_SNAPSHOT_PATH"] {
            settings.completeOnboarding()
            let topEdge = window.frame.maxY
            let minimumOrigin = NSPoint(
                x: window.frame.minX,
                y: topEdge - window.minSize.height
            )
            window.setFrame(NSRect(origin: minimumOrigin, size: window.minSize), display: true)
            controller.showWindow(nil)
            window.makeKeyAndOrderFront(nil)
            try await Task.sleep(for: .milliseconds(500))
            try capture(contentView: contentView, at: minimumPath)
        }
    }

    @MainActor
    private func capture(contentView: NSView, at path: String) throws {
        contentView.layoutSubtreeIfNeeded()
        contentView.displayIfNeeded()

        let representation = try XCTUnwrap(
            contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds)
        )
        contentView.cacheDisplay(in: contentView.bounds, to: representation)
        let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
