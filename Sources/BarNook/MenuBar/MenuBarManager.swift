// Modified by Chaehyeon Lee (2026): added temporary floating-bar pins, fit checks and selectable icons;
// the bar-mode clock opens Notification Center behind a cover instead of a hover lift.
import AppKit
import BarNookCore
import Observation
import os

/// Owns the BarNook icon and the restriction, and keeps the restriction in
/// step with the hidden sets.
@MainActor
@Observable
final class MenuBarManager {
    let sets: HiddenSets
    let state: AppState

    private let restriction: MenuBarRestriction
    private let rehide: RehideMonitor
    private let updater: Updater
    private let permission: Permissions
    private var floatingBar: FloatingBar?
    /// The apps a bar click pinned, oldest first. While the set is shown,
    /// the restriction lets their items through, so the user clicks them in
    /// the menu bar as they would any other item. At most `PinPolicy.limit`.
    private var pins: [String] = []
    /// Set once the pinned items turn out not to fit: every other app then
    /// hides so they do.
    private var pinsNeedRoom = false
    private var pinFit: Task<Void, Never>?
    /// Whether the floating bar is on screen. A pin closes it and leaves
    /// the item in the menu bar; the icon brings it back for another pin.
    private var isBarOpen = false
    private var barPlacement: Task<Void, Never>?
    private static let log = Logger(subsystem: "com.chlee1001.BarNook", category: "pins")
    private let openSettingsHandler: () -> Void
    private let icon = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var launchObserver: Task<Void, Never>?
    private var pointerMonitor: Any?
    private var clockHover: Task<Void, Never>?
    private var isPointerInClockZone = false
    /// Menu-bar mode: the pointer is over the clock and the restriction is
    /// lifted. A set change, a launch or a rehide waits until it leaves,
    /// or its reapply would land under the pointer and the click would go
    /// nowhere (`applyCurrentState`).
    private var isHoverReleased = false
    /// A global monitor is blind while the pointer is over BarNook's own
    /// windows, so the lift also checks the pointer on this interval.
    private static let hoverWatchInterval: Duration = .milliseconds(200)
    /// The apps the restriction hides now, for the cover's settle check.
    private var hiddenNow: Set<String> = []
    private let clockCover = ClockCover()
    private var clockClickMonitor: Any?
    private var clockLift: Task<Void, Never>?
    private var lastClockLift: ContinuousClock.Instant?
    /// A covered lift owns the restriction until it reapplies.
    private var isCoverLifting = false

    init(
        restriction: MenuBarRestriction,
        sets: HiddenSets,
        state: AppState,
        permission: Permissions,
        updater: Updater,
        openSettings: @escaping () -> Void
    ) {
        self.restriction = restriction
        self.sets = sets
        self.state = state
        self.permission = permission
        self.updater = updater
        self.openSettingsHandler = openSettings
        self.rehide = RehideMonitor(state: state, sets: sets)
        rehide.panelFrame = { [weak self] in self?.floatingBar?.frame }
        rehide.hasPins = { [weak self] in self?.pins.isEmpty == false }

        // A relaunch with the set shown in bar mode opens the bar again.
        isBarOpen = sets.isHiddenSetShown && state.hiddenItemsPlacement == .floatingBar

        icon.autosaveName = "barnook.icon"
        if let button = icon.button {
            button.target = self
            button.action = #selector(iconClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        applyCurrentState()
        observeChanges()
        observeIconChanges()
        installClockHover()
        installClockClick()

        // A newly launched app is not in the allow-list snapshot, so it would hide.
        launchObserver = Task { [weak self] in
            for await _ in NSWorkspace.runningApplicationChanges() {
                guard let self, restriction.isActive else { continue }
                self.applyCurrentState()
            }
        }
    }

    /// The icon's window frame in screen coordinates, for the divider.
    var iconFrame: NSRect? { icon.button?.window?.frame }

    // MARK: Show and hide

    /// A normal click toggles the hidden set. An Option click toggles both
    /// sets. In bar mode a pin closes the bar and leaves the item in the
    /// menu bar, so the icon brings the bar back for another pin, and hides
    /// everything only once the bar is open again.
    func toggle(includingAlwaysHidden: Bool) {
        let isShown = includingAlwaysHidden ? sets.isAlwaysHiddenSetShown : sets.isHiddenSetShown
        switch IconClickPolicy.action(isShown: isShown, inBar: state.hiddenItemsPlacement == .floatingBar, isBarOpen: isBarOpen) {
        case .show:
            show(includingAlwaysHidden: includingAlwaysHidden)
        case .reopenBar:
            isBarOpen = true
            applyCurrentState()
        case .hide:
            hide()
        }
    }

    func show(includingAlwaysHidden: Bool) {
        isBarOpen = true
        sets.show(includingAlwaysHidden: includingAlwaysHidden)
    }

    func hide() {
        sets.hide()
    }

    func applyCurrentState() {
        let inBar = state.hiddenItemsPlacement == .floatingBar
        if !sets.isHiddenSetShown || !inBar {
            pins = []
            pinsNeedRoom = false
            isBarOpen = false
        }
        var hidden: Set<String>
        if inBar {
            // The bar shows the set; the menu bar keeps hiding it.
            hidden = sets.hidden.union(state.isAlwaysHiddenEnabled ? sets.alwaysHidden : [])
        } else {
            hidden = sets.identifiersToHide(isAlwaysHiddenEnabled: state.isAlwaysHiddenEnabled)
        }
        if !pins.isEmpty {
            if pinsNeedRoom {
                // The apps a picker lists. A list that also names background
                // processes is ignored by MenuBarAgent as a whole.
                let running = NSWorkspace.shared.runningApplications
                    .filter { [.regular, .accessory].contains($0.activationPolicy) }
                    .compactMap(\.bundleIdentifier)
                hidden = Set(running).subtracting(pins + [Bundle.main.bundleIdentifier ?? ""])
            } else {
                hidden.subtract(pins)
            }
        }
        hiddenNow = hidden
        if inBar, isHoverReleased {
            // A switch to bar mode ends a menu-bar hover lift.
            isHoverReleased = false
            isPointerInClockZone = false
            clockHover?.cancel()
        }
        if isCoverLifting || isHoverReleased {
            // The lift in progress reapplies when it ends.
        } else if hidden.isEmpty {
            restriction.release()
        } else {
            restriction.apply(hiddenBundleIdentifiers: hidden)
        }
        updateIcon()
        updateFloatingBar(inBar: inBar)

        // Arm once per show, not on every reapply, so the timeout is not reset
        // by unrelated changes such as the clock hover.
        if sets.isHiddenSetShown {
            if !rehide.isArmed {
                rehide.arm()
            }
        } else {
            rehide.disarm()
        }
    }

    func release() {
        rehide.disarm()
        pinFit?.cancel()
        barPlacement?.cancel()
        floatingBar?.hide()
        launchObserver?.cancel()
        clockHover?.cancel()
        clockLift?.cancel()
        if let pointerMonitor {
            NSEvent.removeMonitor(pointerMonitor)
        }
        if let clockClickMonitor {
            NSEvent.removeMonitor(clockClickMonitor)
        }
        restriction.release()
    }

    /// Reapplies the restriction whenever a set or a related setting changes,
    /// from any caller. `onChange` fires once per registration, before the
    /// write lands, so it hops to the next run-loop turn and re-registers.
    private func observeChanges() {
        withObservationTracking {
            _ = sets.hidden
            _ = sets.alwaysHidden
            _ = sets.isHiddenSetShown
            _ = sets.isAlwaysHiddenSetShown
            _ = state.isAlwaysHiddenEnabled
            _ = state.hiddenItemsPlacement
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.applyCurrentState()
                self.observeChanges()
            }
        }
    }

    private func observeIconChanges() {
        withObservationTracking {
            _ = state.hiddenMenuBarIcon
            _ = state.shownMenuBarIcon
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.updateIcon()
                self.observeIconChanges()
            }
        }
    }

    private func updateIcon() {
        guard let button = icon.button else { return }
        let isShown = sets.isHiddenSetShown
        button.image = (isShown ? state.shownMenuBarIcon : state.hiddenMenuBarIcon).image
        button.setAccessibilityLabel(isShown ? "Hide items" : "Show hidden items")
    }

    // MARK: The floating bar

    private func updateFloatingBar(inBar: Bool) {
        guard inBar, sets.isHiddenSetShown, isBarOpen else {
            floatingBar?.hide()
            return
        }
        if floatingBar == nil {
            floatingBar = FloatingBar { [weak self] id in
                self?.barClicked(id)
            }
        }
        var shown = sets.hidden
        if sets.isAlwaysHiddenSetShown {
            shown.formUnion(sets.alwaysHidden)
        }
        let screen = icon.button?.window?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        floatingBar?.show(
            apps: FloatingBar.apps(for: shown),
            pinned: Set(pins),
            unreachable: MenuBarRestriction.unreachableRunningApps(),
            hint: permission.isTrusted ? nil : "the other items give way while it is pinned",
            iconFrame: iconFrame,
            screen: screen
        )
        // The icon can move once MenuBarAgent lays out the new restriction;
        // the bar follows it.
        barPlacement?.cancel()
        barPlacement = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self, let bar = floatingBar, bar.isVisible else { return }
            bar.place(iconFrame: iconFrame, screen: icon.button?.window?.screen ?? screen)
        }
    }

    /// A click in the bar pins the app, spec F8. The restriction lets its
    /// item through and the bar closes, so the user clicks the item itself
    /// in the menu bar, as they would any other item. Nothing is pressed on
    /// the user's behalf: the press raced the layout and lost the item its
    /// menu. A click on a pinned app unpins it. Up to `PinPolicy.limit`
    /// items are pinned at once. Without the Accessibility permission
    /// nothing can be read, so every other app hides at once, which is the
    /// one arrangement that always leaves the pinned item on screen. With
    /// the permission, the pins are checked against the layout once it
    /// settles, and every other app hides only if a pinned item does not
    /// fit. No rehide condition takes a pin away; the icon ends it.
    private func barClicked(_ id: String) {
        Self.log.info("bar click on \(id, privacy: .public); trusted: \(self.permission.isTrusted)")
        pins = PinPolicy.toggling(id, in: pins)
        if pins.isEmpty {
            pinsNeedRoom = false
        } else if !permission.isTrusted {
            pinsNeedRoom = true
        }
        isBarOpen = false
        // While a pin is up no rehide condition fires; the timeout starts
        // over once the last pin is gone.
        rehide.rearm()
        applyCurrentState()
        checkPinsFit()
    }

    /// Whether every pinned item is on screen. Nothing can be read without
    /// the Accessibility permission, so the check only runs with it. Reads
    /// happen off the main thread; every read is an IPC.
    ///
    /// The verdict watches the pins alone, not the whole layout. One menu
    /// bar item that animates — a timer, a meter, a running cat — moves on
    /// every read, so a whole-layout settle never arrives and the check
    /// would either never run or run on an animation frame, where items
    /// overlap mid-flight and every pin reads as collapsed.
    private func checkPinsFit() {
        pinFit?.cancel()
        guard permission.isTrusted, !pins.isEmpty, sets.isHiddenSetShown else { return }
        pinFit = Task { [weak self] in
            // MenuBarAgent lays out only after the newest assertion reports
            // back, and animates for about a second after that.
            await self?.restriction.waitUntilActivated()
            var previousVerdict: Set<String>?
            for _ in 0..<16 {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self, !self.pins.isEmpty, self.sets.isHiddenSetShown else { return }
                // An app the allow-list cannot reach stays hidden whatever
                // the restriction says, so hiding every other app for it
                // would empty the menu bar and still not draw it.
                let unreachable = MenuBarRestriction.unreachableRunningApps()
                let pins = self.pins.filter { !unreachable.contains($0) }
                guard !pins.isEmpty else { return }
                let layout = await Task.detached(priority: .userInitiated) { MenuBarLayout.read() }.value
                guard let layout else { continue }
                // `drawnItem`, not membership in the layout table: a
                // collapsed item keeps a frame, stacked at the left end.
                let drawn = Set(pins.filter { layout.drawnItem(of: $0) != nil })
                defer { previousVerdict = drawn }
                // Two reads in a row that agree: the pins have stopped moving.
                guard previousVerdict == drawn else { continue }
                let fits = drawn.count == pins.count
                if !fits, !self.pinsNeedRoom {
                    Self.log.info("a pinned item is collapsed; hiding every other app")
                    self.pinsNeedRoom = true
                    self.applyCurrentState()
                } else if fits, self.pinsNeedRoom {
                    Self.log.info("the pins fit again; letting the other apps back")
                    self.pinsNeedRoom = false
                    self.applyCurrentState()
                }
                return
            }
            Self.log.info("the pins never held still; leaving them as they are")
        }
    }

    // MARK: Clock hover

    /// Notification Center does not open from a clock click while a
    /// restriction is active, and MenuBarAgent decides that at mouse-down.
    /// In menu-bar mode the restriction lifts while the pointer is in the
    /// trailing zone of the menu bar and returns shortly after it leaves;
    /// the hidden items show meanwhile, as the set does when shown there.
    /// `ClockZone` sizes the zone. Bar mode never lifts on hover: a clock
    /// click lifts behind a cover instead (`installClockClick`).
    private func installClockHover() {
        pointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            let point = NSEvent.mouseLocation
            Task { @MainActor in
                self?.pointerMoved(to: point)
            }
        }
    }

    private func pointerMoved(to point: NSPoint) {
        let inZone = state.hiddenItemsPlacement == .menuBar
            && MenuBarGeometry.current.clockZoneContains(point, width: state.clockZoneWidth)
        guard inZone != isPointerInClockZone else { return }
        isPointerInClockZone = inZone
        clockHover?.cancel()
        if inZone {
            liftForClock()
        } else if isHoverReleased {
            clockHover = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, !Task.isCancelled else { return }
                self.isHoverReleased = false
                self.applyCurrentState()
            }
        }
    }

    private func liftForClock() {
        isHoverReleased = true
        restriction.release()
        clockHover = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.hoverWatchInterval)
                guard let self, !Task.isCancelled else { return }
                let point = NSEvent.mouseLocation
                if !MenuBarGeometry.current.clockZoneContains(point, width: self.state.clockZoneWidth) {
                    self.pointerMoved(to: point)
                    return
                }
            }
        }
    }

    // MARK: Clock click in bar mode

    /// A global monitor sees the click MenuBarAgent is about to ignore; it
    /// cannot swallow it. A click on the clock starts one covered lift that
    /// replays it (`ClockCover`, `ClockCoverPolicy`).
    private func installClockClick() {
        clockClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            let point = NSEvent.mouseLocation
            let isReplay = event.cgEvent?.getIntegerValueField(.eventSourceUserData) == ClockCoverPolicy.replayTag
            Task { @MainActor in
                self?.clockClicked(at: point, isReplay: isReplay)
            }
        }
    }

    private func clockClicked(at point: NSPoint, isReplay: Bool) {
        let facts = ClockCoverPolicy.Facts(
            inBar: state.hiddenItemsPlacement == .floatingBar,
            restrictionActive: restriction.isActive,
            permissionsGranted: permission.areGranted,
            isReplay: isReplay,
            inFlight: clockLift != nil,
            sinceLastLift: lastClockLift.map { ContinuousClock.now - $0 }
        )
        guard ClockCoverPolicy.mayIntercept(facts),
              MenuBarGeometry.current.clockZoneContains(point, width: state.clockZoneWidth)
        else { return }
        permission.refresh()
        guard permission.areGranted else { return }
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let axPoint = CGPoint(x: point.x, y: primaryHeight - point.y)
        clockLift = Task { [weak self] in
            defer { self?.clockLift = nil }
            let read = await Task.detached(priority: .userInitiated) {
                (MenuBarLayout.read(), NotificationCenterPanel.isOpenNow())
            }.value
            guard let self, let layout = read.0, let offset = layout.clockOffset,
                  ClockCoverPolicy.lifts(onClock: layout.clock(at: axPoint) != nil, panelOpen: read.1)
            else { return }
            self.lastClockLift = .now
            let hidden = self.hiddenNow
            Self.log.info("clock click: covered lift")
            _ = await self.clockCover.run(
                clickAt: point,
                strips: ClockCover.strips(clockOffset: offset),
                lift: {
                    self.isCoverLifting = true
                    self.restriction.release()
                },
                reapply: {
                    self.isCoverLifting = false
                    self.applyCurrentState()
                    await self.restriction.waitUntilActivated()
                },
                hiddenStillDrawn: {
                    await Task.detached { MenuBarLayout.read()?.containsItem(ofAny: hidden) ?? false }.value
                }
            )
        }
    }

    // MARK: Icon clicks

    @objc private func iconClicked() {
        // On macOS 27 the event that reaches the action carries no modifier
        // flags, so read the keyboard state directly.
        let flags = NSEvent.modifierFlags
        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
        if isRightClick || flags.contains(.control) {
            showMenu()
        } else {
            toggle(includingAlwaysHidden: flags.contains(.option))
        }
    }

    /// A status item with a `menu` opens it on every click, so the menu is
    /// attached only for the duration of one click.
    private func showMenu() {
        let menu = NSMenu()

        let alwaysHidden = NSMenuItem(
            title: "Show always-hidden items",
            action: #selector(toggleAlwaysHiddenShown),
            keyEquivalent: ""
        )
        alwaysHidden.target = self
        alwaysHidden.state = sets.isAlwaysHiddenSetShown ? .on : .off
        alwaysHidden.isEnabled = state.isAlwaysHiddenEnabled
        menu.addItem(alwaysHidden)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let update = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        update.target = self
        update.isEnabled = updater.canCheckForUpdates
        menu.addItem(update)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit BarNook", action: #selector(NSApplication.terminate), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        icon.menu = menu
        icon.button?.performClick(nil)
        icon.menu = nil
    }

    @objc private func toggleAlwaysHiddenShown() {
        show(includingAlwaysHidden: !sets.isAlwaysHiddenSetShown)
    }

    @objc private func openSettings() {
        openSettingsHandler()
    }

    @objc private func checkForUpdates() {
        updater.checkForUpdates()
    }
}
