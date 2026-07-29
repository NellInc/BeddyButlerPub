import AppKit
import ServiceManagement
import XCTest

@testable import Beddy_Butler

private final class FakeLoginItemService: LoginItemService {
    var status: SMAppService.Status
    var error: Error?

    init(status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {
        if let error { throw error }
        status = .enabled
    }

    func unregister() throws {
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
        XCTAssertEqual(ApplicationMetadata.versionDescription, "Version 2.0.1 · Build 611")
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
}
