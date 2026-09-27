import AppKit
import BarNookCore
import Observation

/// The BarNook icon as the divider, like the Ice and Bartender icons:
/// Cmd-drag items across it. Apps left of it join the hidden set, apps
/// right of it leave. Positions come from `MenuBarLayout`, so this needs
/// the Accessibility permission. The icon's own window frame gives the
/// split point.
@MainActor
final class IconDivider {
    private let state: AppState
    private let sets: HiddenSets
    private let permission: AccessibilityPermission
    private let iconFrame: () -> NSRect?
    private var dragMonitors: [Any] = []
    private var launchObserver: Task<Void, Never>?
    private var pending: Task<Void, Never>?

    /// Items settle after a drag or a restriction change. A read before
    /// that sees them mid-move.
    private static let settleDelay: Duration = .milliseconds(400)

    /// `iconFrame` is the icon's window frame in Cocoa screen coordinates.
    init(
        state: AppState,
        sets: HiddenSets,
        permission: AccessibilityPermission,
        iconFrame: @escaping () -> NSRect?
    ) {
        self.state = state
        self.sets = sets
        self.permission = permission
        self.iconFrame = iconFrame
        update()
        observe()
    }

    var isActive: Bool { !dragMonitors.isEmpty }

    /// Reads the menu bar after a moment and updates the hidden set.
    func scheduleRead() {
        guard isActive else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled else { return }
            self?.read()
        }
    }

    func release() {
        stop()
    }

    private func update() {
        if state.hidesAppsLeftOfIcon, permission.isTrusted {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard !isActive else { return }
        // A Cmd-drag ends with a mouse-up. A drag of the icon itself reaches
        // only the local monitor, a drag of another app's item only the
        // global one.
        let handler: (NSEvent) -> Void = { [weak self] event in
            guard event.modifierFlags.contains(.command) else { return }
            Task { @MainActor in
                self?.scheduleRead()
            }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: handler) {
            dragMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp, handler: { handler($0); return $0 }) {
            dragMonitors.append(local)
        }
        // A newly launched app lands wherever its item was last.
        launchObserver = Task { [weak self] in
            for await _ in NSWorkspace.runningApplicationChanges() {
                self?.scheduleRead()
            }
        }
        scheduleRead()
    }

    private func stop() {
        pending?.cancel()
        launchObserver?.cancel()
        dragMonitors.forEach(NSEvent.removeMonitor)
        dragMonitors.removeAll()
    }

    private func read() {
        guard let frame = iconFrame() else { return }
        // Accessibility coordinates: same x, y from the top of the primary display.
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? frame.maxY
        let point = CGPoint(x: frame.midX, y: primaryHeight - frame.midY)
        let own = Bundle.main.bundleIdentifier
        let isShown = sets.isHiddenSetShown
        Task.detached(priority: .userInitiated) { [weak self] in
            let split = MenuBarLayout.read()?.appItems(splitAt: point)
            await MainActor.run {
                guard let self, let split, self.sets.isHiddenSetShown == isShown else { return }
                let hidden = DividerPolicy.hiddenSet(
                    current: self.sets.hidden,
                    alwaysHidden: self.sets.alwaysHidden,
                    own: own,
                    left: split.left,
                    right: split.right,
                    isShown: isShown
                )
                if hidden != self.sets.hidden {
                    self.sets.hidden = hidden
                }
            }
        }
    }

    /// A show puts every item on screen, so that is when the whole set is
    /// read again.
    private func observe() {
        withObservationTracking {
            _ = state.hidesAppsLeftOfIcon
            _ = permission.isTrusted
            _ = sets.isHiddenSetShown
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.update()
                if self.sets.isHiddenSetShown {
                    self.scheduleRead()
                }
                self.observe()
            }
        }
    }
}
