import Observation
import ServiceManagement

/// Launch-at-login through `SMAppService`. The service is the source of truth;
/// nothing is persisted here.
@MainActor
@Observable
final class LaunchAtLogin {
    private(set) var status: SMAppService.Status = .notRegistered
    private(set) var error: String?

    var isEnabled: Bool { status == .enabled }

    /// The user turned it off in System Settings › Login Items, or macOS is
    /// waiting for them to approve it there.
    var needsApproval: Bool { status == .requiresApproval }

    init() {
        refresh()
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
