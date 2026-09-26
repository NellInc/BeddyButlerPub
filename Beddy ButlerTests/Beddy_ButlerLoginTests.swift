import AppKit
import ServiceManagement
import XCTest

@testable import Beddy_Butler

private final class FakeLoginItemService: LoginItemService {
    var status: SMAppService.Status
    var error: Error?
    var registerCount = 0
    var unregisterCount = 0

    init(status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {
        registerCount += 1
        if let error { throw error }
        status = .enabled
    }

    func unregister() throws {
        unregisterCount += 1
        if let error { throw error }
        status = .notRegistered
    }
}

private struct TestLoginError: LocalizedError {
    var errorDescription: String? { "Login item test failure" }
}

final class BeddyButlerLoginTests: XCTestCase {
    func testAboutPanelCreditsBothDesignersAndEngineers() throws {
        XCTAssertEqual(
            ApplicationMetadata.creditLine,
            "Design and engineering by Nell Watson and David Garces."
        )
        XCTAssertEqual(ApplicationMetadata.qaCreditLine, "QA by Filip Alimpić.")
        XCTAssertEqual(ApplicationMetadata.versionDescription, "Version 2.0.3 · Build 614")
        XCTAssertEqual(ApplicationMetadata.copyrightLine, "© 2015–2026 Nell Watson Inc.")
    }

    func testSystemStatusesMapToPresentationState() {
        XCTAssertEqual(LoginItemState(status: .notRegistered), .disabled)
        XCTAssertEqual(LoginItemState(status: .enabled), .enabled)
        XCTAssertEqual(LoginItemState(status: .requiresApproval), .requiresApproval)
        XCTAssertEqual(LoginItemState(status: .notFound), .unavailable)
    }

    @MainActor
    func testManagerRegistersAndUnregisters() {
        let service = FakeLoginItemService(status: .notRegistered)
        let manager = LoginItemManager(service: service)

        manager.setEnabled(true)
        XCTAssertTrue(manager.isEnabled)

        manager.setEnabled(false)
        XCTAssertFalse(manager.isEnabled)
    }

    @MainActor
    func testManagerSurfacesRegistrationErrors() {
        let service = FakeLoginItemService(status: .notRegistered)
        service.error = TestLoginError()
        let manager = LoginItemManager(service: service)

        manager.setEnabled(true)

        XCTAssertEqual(manager.lastError, "Login item test failure")
        XCTAssertFalse(manager.isEnabled)
    }

    @MainActor
    func testManagerAttemptsRegistrationWhenServiceIsNotFound() {
        let service = FakeLoginItemService(status: .notFound)
        let manager = LoginItemManager(service: service)
        XCTAssertEqual(manager.state, .unavailable)

        manager.setEnabled(true)

        XCTAssertEqual(service.registerCount, 1)
        XCTAssertEqual(manager.state, .enabled)
    }

    @MainActor
    func testManagerSurfacesNotFoundRegistrationErrors() {
        let service = FakeLoginItemService(status: .notFound)
        service.error = TestLoginError()
        let manager = LoginItemManager(service: service)

        manager.setEnabled(true)
        XCTAssertEqual(manager.lastError, "Login item test failure")

        manager.setEnabled(false)
        XCTAssertEqual(service.unregisterCount, 0)
        XCTAssertEqual(manager.state, .unavailable)
    }

    @MainActor
    func testManagerKeepsPendingApprovalWhenEnablingAgain() {
        let service = FakeLoginItemService(status: .requiresApproval)
        let manager = LoginItemManager(service: service)

        manager.setEnabled(true)

        XCTAssertEqual(service.registerCount, 0)
        XCTAssertEqual(service.unregisterCount, 0)
        XCTAssertEqual(manager.state, .requiresApproval)
        XCTAssertTrue(manager.isEnabled)
    }

    @MainActor
    func testControlClickOnStatusItemRequestsTheMenu() {
        XCTAssertTrue(AppDelegate.isMenuRequest(type: .rightMouseUp, modifierFlags: []))
        XCTAssertTrue(AppDelegate.isMenuRequest(type: .leftMouseUp, modifierFlags: [.control]))
        XCTAssertFalse(AppDelegate.isMenuRequest(type: .leftMouseUp, modifierFlags: []))
        XCTAssertFalse(AppDelegate.isMenuRequest(type: .leftMouseUp, modifierFlags: [.option]))
        XCTAssertFalse(AppDelegate.isMenuRequest(type: nil, modifierFlags: []))
    }

    @MainActor
    func testTestHostDoesNotStartTheApp() {
        // A live AppDelegate would arm real nudges from the developer's own defaults.
        XCTAssertNil(NSApp.delegate)
    }

    @MainActor
    func testMainMenuProvidesStandardKeyEquivalents() throws {
        // The test host runs without an AppDelegate, so build the menu from one directly.
        let delegate = AppDelegate()
        defer { withExtendedLifetime(delegate) {} }
        let mainMenu = delegate.makeMainMenu()
        func item(_ action: Selector, _ key: String, _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem? {
            mainMenu.items.compactMap(\.submenu).flatMap(\.items).first {
                $0.action == action && $0.keyEquivalent == key && $0.keyEquivalentModifierMask == modifiers
            }
        }

        XCTAssertNotNil(item(#selector(NSApplication.terminate(_:)), "q"))
        XCTAssertNotNil(item(#selector(NSApplication.hide(_:)), "h"))
        XCTAssertNotNil(item(Selector(("undo:")), "z"))
        XCTAssertNotNil(item(Selector(("redo:")), "z", [.command, .shift]))
        XCTAssertNotNil(item(#selector(NSText.cut(_:)), "x"))
        XCTAssertNotNil(item(#selector(NSText.copy(_:)), "c"))
        XCTAssertNotNil(item(#selector(NSText.paste(_:)), "v"))
        XCTAssertNotNil(item(#selector(NSText.selectAll(_:)), "a"))
        XCTAssertNotNil(item(#selector(NSWindow.performClose(_:)), "w"))
        XCTAssertNotNil(item(#selector(NSWindow.performMiniaturize(_:)), "m"))
        let preferences = try XCTUnwrap(
            mainMenu.items.compactMap(\.submenu).flatMap(\.items).first { $0.keyEquivalent == "," }
        )
        XCTAssertTrue(preferences.target is AppDelegate)
    }
}
