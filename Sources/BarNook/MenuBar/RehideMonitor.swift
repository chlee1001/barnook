// Modified by Chaehyeon Lee (2026): keep pinned items visible during rehide checks.
import AppKit
import BarNookCore

/// Hides the shown sets again after a timeout, a click outside the menu bar,
/// or a focus change. Each condition has its own setting. Armed while the
/// hidden set is shown.
@MainActor
final class RehideMonitor {
    private let state: AppState
    private let sets: HiddenSets

    private(set) var isArmed = false
    /// The floating bar's frame while it is visible. A click in it is not outside.
    var panelFrame: () -> NSRect? = { nil }
    /// Whether a pin is up. A pin is an item the user put in the menu bar
    /// to click, so no rehide condition takes it away; the icon ends it.
    var hasPins: () -> Bool = { false }
    private var timer: Task<Void, Never>?
    private var clickMonitor: Any?
    private var focusObservers: [NSObjectProtocol] = []
    private var retry: Task<Void, Never>?

    init(state: AppState, sets: HiddenSets) {
        self.state = state
        self.sets = sets
        observeSettings()
    }

    func arm() {
        isArmed = true
        install()
    }

    /// Reinstalls the conditions, so the timeout starts over. Called when a
    /// pin is added or removed: the user keeps the whole timeout once the
    /// last pin is gone.
    func rearm() {
        guard isArmed else { return }
        install()
    }

    func disarm() {
        guard isArmed else { return }
        isArmed = false
        uninstall()
    }

    /// Delay between checks while a menu keeps a hide waiting.
    private static let retryInterval: Duration = .milliseconds(300)

    private func install() {
        uninstall()
        if state.rehideOnTimeout {
            let timeout = state.rehideTimeout
            timer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                guard !Task.isCancelled else { return }
                self?.requestHide()
            }
        }
        if state.rehideOnClickOutside {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                let point = NSEvent.mouseLocation
                Task { @MainActor in
                    self?.clicked(at: point)
                }
            }
        }
        if state.rehideOnFocusChange {
            let center = NSWorkspace.shared.notificationCenter
            let ownPID = ProcessInfo.processInfo.processIdentifier
            focusObservers = [
                center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                    let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                    // Opening Settings activates BarNook. That is not a focus change.
                    guard app?.processIdentifier != ownPID else { return }
                    Task { @MainActor in
                        self?.requestHide()
                    }
                },
                center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in
                        self?.requestHide()
                    }
                },
            ]
        }
    }

    private func uninstall() {
        timer?.cancel()
        timer = nil
        retry?.cancel()
        retry = nil
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
        let center = NSWorkspace.shared.notificationCenter
        for observer in focusObservers {
            center.removeObserver(observer)
        }
        focusObservers = []
    }

    private func clicked(at point: NSPoint) {
        guard isArmed else { return }
        let menuBar = MenuBarGeometry.current
        let menus = MenuBarGeometry.openMenuFrames()
        if RehidePolicy.shouldHide(afterClickAt: point, menuBar: menuBar, menus: menus, panel: panelFrame()) {
            requestHide()
        }
    }

    /// Hides now, or once the open menu closes. A hide while a menu from a
    /// shown item is open would pull the item out from under the menu. A
    /// pin is an item the user put in the menu bar to click, so no rehide
    /// condition takes it away: the icon ends it.
    private func requestHide() {
        guard isArmed, !hasPins() else { return }
        retry?.cancel()
        if RehidePolicy.isMenuOpen(MenuBarGeometry.openMenuFrames(), menuBar: .current) {
            retry = Task { [weak self] in
                try? await Task.sleep(for: Self.retryInterval)
                guard !Task.isCancelled else { return }
                self?.requestHide()
            }
        } else {
            sets.hide()
        }
    }

    /// A settings change while armed reinstalls the monitors, so a new
    /// timeout or a switched-off condition takes effect at once.
    private func observeSettings() {
        withObservationTracking {
            _ = state.rehideOnTimeout
            _ = state.rehideOnClickOutside
            _ = state.rehideOnFocusChange
            _ = state.rehideTimeout
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.isArmed {
                    self.install()
                }
                self.observeSettings()
            }
        }
    }
}
