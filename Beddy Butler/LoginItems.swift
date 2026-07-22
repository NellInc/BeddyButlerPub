import Combine
import ServiceManagement

protocol LoginItemService: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemService {}

enum LoginItemState: Equatable, Sendable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable

    init(status: SMAppService.Status) {
        switch status {
        case .notRegistered:
            self = .disabled
        case .enabled:
            self = .enabled
        case .requiresApproval:
            self = .requiresApproval
        case .notFound:
            self = .unavailable
        @unknown default:
            self = .unavailable
        }
    }
}

@MainActor
final class LoginItemManager: ObservableObject {
    @Published private(set) var state: LoginItemState
    @Published private(set) var lastError: String?

    private let service: LoginItemService

    init(service: LoginItemService = SMAppService.mainApp) {
        self.service = service
        state = LoginItemState(status: service.status)
    }

    var isEnabled: Bool {
        state == .enabled || state == .requiresApproval
    }

    func refresh() {
        state = LoginItemState(status: service.status)
    }

    func setEnabled(_ enabled: Bool) {
        lastError = nil

        do {
            if enabled {
                if service.status == .notRegistered {
                    try service.register()
                }
            } else if service.status != .notRegistered {
                try service.unregister()
            }
        } catch {
            lastError = error.localizedDescription
        }

        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
