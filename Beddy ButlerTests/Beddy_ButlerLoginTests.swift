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
        let credits = try XCTUnwrap(
            ApplicationMetadata.aboutOptions[.credits] as? NSAttributedString
        )

        XCTAssertTrue(
            credits.string.contains(
                "Designed and engineered by Nell Watson and David Garces."
            )
        )
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
