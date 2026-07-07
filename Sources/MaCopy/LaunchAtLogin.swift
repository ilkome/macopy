import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp`. The system Login Items state is the
/// source of truth - we never mirror it into UserDefaults, only read/write it.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns the resulting status. `.requiresApproval` means the user must flip
    /// the toggle in System Settings → General → Login Items for it to take hold.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> SMAppService.Status {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled { try service.register() }
            } else {
                if service.status == .enabled { try service.unregister() }
            }
        } catch {
            // Registration can fail when the app runs from a quarantined or
            // translocated location; the toggle just reflects the real status.
        }
        return service.status
    }
}
