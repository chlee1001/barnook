import AppKit
import BarNookCore
import Observation

/// Keeps `AppState.clockZoneWidth` close to the clock. With the Accessibility
/// permission the width comes from the clock item's frame, read from
/// MenuBarAgent at launch, when the permission arrives, and when Settings
/// opens. Without it, the user clicks the clock once from Settings.
@MainActor
@Observable
final class ClockZone {
    static let defaultWidth: Double = 300

    /// Points added left of the clock. The restriction lifts over XPC when
    /// the pointer enters the zone, so the zone starts before the clock or a
    /// fast move-and-click lands while the restriction is still active.
    /// Measured: a 2-point margin already opens Notification Center from a
    /// synthetic 10,000 points/s approach. 30 keeps the zone off Control
    /// Center, which sits 30 points left of the clock.
    static let margin: Double = 30

    private let state: AppState
    private let permission: AccessibilityPermission
    private var clickMonitors: [Any] = []

    /// The width came from the clock item, not from a click or the default.
    private(set) var isMeasured = false
    private(set) var isWaitingForClick = false

    init(state: AppState, permission: AccessibilityPermission) {
        self.state = state
        self.permission = permission
        measureIfTrusted()
        observePermission()
    }

    /// Reads the clock frame from MenuBarAgent, off the main thread.
    func measureIfTrusted() {
        guard permission.isTrusted else {
            isMeasured = false
            return
        }
        Task.detached(priority: .userInitiated) { [weak self] in
            let offset = MenuBarLayout.read()?.clockOffset
            await MainActor.run {
                guard let self, let offset else { return }
                self.state.clockZoneWidth = offset + Self.margin
                self.isMeasured = true
            }
        }
    }

    /// The next click in a menu bar sets the width. The click goes through,
    /// so a click on the clock also opens Notification Center.
    func waitForClick() {
        cancelClick()
        isWaitingForClick = true
        let handler: (NSEvent) -> Void = { [weak self] _ in
            let point = NSEvent.mouseLocation
            Task { @MainActor in
                self?.clicked(at: point)
            }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: handler) {
            clickMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown, handler: { handler($0); return $0 }) {
            clickMonitors.append(local)
        }
    }

    func cancelClick() {
        isWaitingForClick = false
        clickMonitors.forEach(NSEvent.removeMonitor)
        clickMonitors.removeAll()
    }

    func reset() {
        state.clockZoneWidth = Self.defaultWidth
        isMeasured = false
    }

    private func clicked(at point: NSPoint) {
        guard let bar = MenuBarGeometry.current.frame(containing: point) else { return }
        state.clockZoneWidth = bar.maxX - point.x + Self.margin
        isMeasured = false
        cancelClick()
    }

    private func observePermission() {
        withObservationTracking {
            _ = permission.isTrusted
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.measureIfTrusted()
                self.observePermission()
            }
        }
    }
}
