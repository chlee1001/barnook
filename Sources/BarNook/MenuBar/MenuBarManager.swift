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
    /// Height of the band at the top of a screen that counts as its menu
    /// bar for the clock pre-filter; the Accessibility clock frame decides.
    private static let menuBarBand = ClockCover.bandHeight
    /// The apps the restriction hides now, for the cover's settle check.
    private var hiddenNow: Set<String> = []
    private let clockCover = ClockCover()
    private var clockClickMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var clockLift: Task<Void, Never>?
    private var lastClockLift: ContinuousClock.Instant?
    /// A covered lift owns the restriction until it reapplies.
    private var isCoverLifting = false
    /// Bar mode: while the pointer rests on the clock the covers are up and
    /// the restriction is lifted, so a click there reaches MenuBarAgent as it
    /// is instead of waiting for a lift (`ClockCoverPolicy.Phase`).
    private var clockPhase: ClockCoverPolicy.Phase = .idle
    private var clockPrelift: Task<Void, Never>?
    /// A click on the clock while the pre-lift was dwelling or covering,
    /// replayed once lifted. Cleared on every pre-lift exit.
    private var pendingClockClick: NSPoint?
    /// Ends the pre-lift hold: the pointer left the clock, the screens or the
    /// placement changed.
    private var clockHoldEnded = false
    /// Notification Center is open, as far as BarNook knows: a lift opened it,
    /// or it was open when a pre-lift ended. A click on the clock then closes
    /// it natively (Notification Center watches mouse-downs itself), and an
    /// Accessibility read after that click would already see it closing, so
    /// `ClockCoverPolicy.route` decides on this at the mouse-down. Cleared by
    /// a poll once the panel is closed.
    private var panelBelievedOpen = false
    private var panelWatch: Task<Void, Never>?
    /// The last layout read, for the hover hit test; refreshed by each lift.
    private var cachedLayout: MenuBarLayout?

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
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // A menu bar that appears during the hold would draw the
                // hidden items uncovered.
                self?.clockHoldEnded = true
                self?.clockCover.screensChanged()
                self?.refreshCachedLayout()
            }
        }
        refreshCachedLayout()

        // A newly launched app is not in the allow-list snapshot, so it would hide.
        launchObserver = Task { [weak self] in
            for await _ in NSWorkspace.runningApplicationChanges() {
                // Reassert whenever something should be hidden, not only
                // while an assertion is live: one whose activation gave up
                // after its retries leaves none, and a launch retries it.
                guard let self, !self.hiddenNow.isEmpty else { continue }
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
        if !inBar, clockPhase != .idle {
            clockHoldEnded = true  // a switch to menu-bar mode ends the bar-mode pre-lift
        }
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
        clockPrelift?.cancel()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
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
                // A clock lift, and its restore, draw every hidden item: no
                // verdict from that layout.
                if self.clockPhase != .idle { continue }
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
    /// `ClockZone` sizes the zone. In bar mode the same monitor drives the
    /// pre-lift: the restriction lifts only under covers, while the pointer
    /// rests on the clock (`prelift`); a click with no rest lifts behind a
    /// cover instead (`installClockClick`).
    private func installClockHover() {
        pointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            let point = NSEvent.mouseLocation
            Task { @MainActor in
                self?.pointerMoved(to: point)
            }
        }
    }

    private func pointerMoved(to point: NSPoint) {
        if state.hiddenItemsPlacement == .floatingBar {
            barPointerMoved(to: point)
        }
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

    // MARK: Clock pre-lift in bar mode

    private func notePanelOpen() {
        panelBelievedOpen = true
        panelWatch?.cancel()
        panelWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                let open = await Task.detached { NotificationCenterPanel.isOpenNow() }.value
                guard let self, !Task.isCancelled else { return }
                if !open {
                    self.panelBelievedOpen = false
                    return
                }
            }
        }
    }

    /// The clock moves only with the displays or the clock format; a read
    /// at launch, on a display change and on each lift keeps the hover hit
    /// test off the Accessibility IPC.
    private func refreshCachedLayout() {
        Task { [weak self] in
            let layout = await Task.detached(priority: .utility) { MenuBarLayout.read() }.value
            if let layout { self?.cachedLayout = layout }
        }
    }

    private func clockHit(_ point: NSPoint, layout: MenuBarLayout?) -> Bool {
        guard let layout else { return false }
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        return layout.clock(at: CGPoint(x: point.x, y: primaryHeight - point.y)) != nil
    }

    private func barPointerMoved(to point: NSPoint) {
        let onClock = clockHit(point, layout: cachedLayout)
        if clockPhase == .lifted, !onClock {
            clockHoldEnded = true
        }
        if ClockCoverPolicy.startsPrelift(
            phase: clockPhase, onClock: onClock, inBar: state.hiddenItemsPlacement == .floatingBar,
            restrictionActive: restriction.isActive, permissionsGranted: permission.areGranted
        ) {
            clockPhase = .dwelling
            clockHoldEnded = false
            clockPrelift = Task { [weak self] in await self?.prelift() }
        }
    }

    /// Covers the menu bars and lifts the restriction while the pointer
    /// rests on the clock; restores both once it leaves, the screens change
    /// or the placement does. A pass across the clock shorter than
    /// `ClockCoverPolicy.hoverDwell` does nothing.
    private func prelift() async {
        defer {
            clockPrelift = nil
            clockPhase = .idle
            pendingClockClick = nil
        }
        try? await Task.sleep(for: ClockCoverPolicy.hoverDwell)
        permission.refresh()
        guard !Task.isCancelled, pendingClockClick != nil || clockHit(NSEvent.mouseLocation, layout: cachedLayout),
              restriction.isActive, permission.areGranted
        else {
            if pendingClockClick != nil { Self.log.info("clock hover: not lifting; queued click dropped") }
            return
        }
        async let bands = clockCover.captureBands(ClockCover.currentScreens)
        let layout = await Task.detached(priority: .userInitiated) { MenuBarLayout.read() }.value
        let pictures = await bands
        cachedLayout = layout ?? cachedLayout
        guard let layout else {
            Self.log.error("clock hover: no layout; not lifting\(self.pendingClockClick == nil ? "" : "; queued click dropped", privacy: .public)")
            return
        }
        guard pendingClockClick != nil || clockHit(NSEvent.mouseLocation, layout: layout) else { return }
        guard let strips = ClockCover.strips(layout: layout, screens: ClockCover.currentScreens), let pictures,
              clockCover.cover(strips, bands: pictures)
        else {
            Self.log.error("clock hover: no cover for every menu bar; not lifting\(self.pendingClockClick == nil ? "" : "; queued click dropped", privacy: .public)")
            return
        }
        clockPhase = .covering
        try? await Task.sleep(for: ClockCoverPolicy.coverComposite)
        // A display or placement change while dwelling or covering: the
        // covers match the old displays, so do not lift.
        guard !clockHoldEnded, state.hiddenItemsPlacement == .floatingBar else {
            clockCover.hideNow()
            Self.log.info("clock hover: displays or placement changed before the lift; not lifting")
            return
        }
        isCoverLifting = true
        clockPhase = .lifted
        restriction.release()
        Self.log.info("clock hover: pre-lifted")
        if let click = pendingClockClick {
            pendingClockClick = nil
            try? await Task.sleep(for: ClockCoverPolicy.liftToPress)
            await ClockCover.replayClick(at: click)
            if await ClockCover.waitForPanel({ await Task.detached { NotificationCenterPanel.isOpenNow() }.value }) {
                notePanelOpen()
            }
        }
        // Hold while the pointer stays on the clock. The pointer monitor
        // ends it at once; the poll catches moves it cannot see.
        while !Task.isCancelled, !clockHoldEnded, clockHit(NSEvent.mouseLocation, layout: cachedLayout) {
            try? await Task.sleep(for: Self.hoverWatchInterval)
        }
        clockPhase = .restoring
        isCoverLifting = false
        if Task.isCancelled { return }  // release() at quit already dropped every assertion
        let result = await clockCover.restore(
            reapply: { [weak self] in
                guard let self else { return }
                self.applyCurrentState()
                await self.restriction.waitUntilActivated()
            },
            hiddenStillDrawn: { [weak self] in
                // The set as it is now: a set or placement change during the hold counts.
                let hidden = await MainActor.run { self?.hiddenNow ?? [] }
                return await Task.detached { MenuBarLayout.read()?.containsItem(ofAny: hidden) }.value
            }
        )
        Self.log.info("clock hover: restored reapplied=\(result.reapplied) settled=\(result.settled) readFailures=\(result.readFailures)")
        // A click during the hold went to MenuBarAgent as it is; if it opened
        // the panel, the next clock click closes it and must not lift.
        if await Task.detached(operation: { NotificationCenterPanel.isOpenNow() }).value {
            notePanelOpen()
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
        switch ClockCoverPolicy.route(
            phase: clockPhase, onClock: clockHit(point, layout: cachedLayout), isReplay: isReplay, panelOpen: panelBelievedOpen
        ) {
        case .passThrough:
            // A click elsewhere while a clock click waits means the user moved on.
            if !isReplay { pendingClockClick = nil }
            return
        case .queueForLift:
            pendingClockClick = point
            return
        case .clickPath:
            break
        }
        let facts = ClockCoverPolicy.Facts(
            inBar: state.hiddenItemsPlacement == .floatingBar,
            restrictionActive: restriction.isActive,
            permissionsGranted: permission.areGranted,
            isReplay: isReplay,
            inFlight: clockLift != nil,
            sinceLastLift: lastClockLift.map { ContinuousClock.now - $0 }
        )
        // The top band of each screen, not `visibleFrame`: a menu bar that
        // hides itself reports none there, and the clicked one is revealed.
        let bands = MenuBarGeometry(topBandsOf: NSScreen.screens.map(\.frame), height: Self.menuBarBand)
        let inZone = bands.clockZoneContains(point, width: state.clockZoneWidth)
        guard ClockCoverPolicy.mayIntercept(facts), inZone else {
            if inZone {
                Self.log.debug("clock click: not intercepted \(String(describing: facts), privacy: .public)")
            }
            return
        }
        permission.refresh()
        guard permission.areGranted else { return }
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let axPoint = CGPoint(x: point.x, y: primaryHeight - point.y)
        clockPhase = .clickLift
        clockLift = Task { [weak self] in
            defer {
                self?.clockLift = nil
                self?.clockPhase = .idle
            }
            guard let self else { return }
            // The pictures are taken while the layout is read: both take
            // about 100 ms, and the click waits for both.
            async let bands = self.clockCover.captureBands(ClockCover.currentScreens)
            async let layoutRead = Task.detached(priority: .userInitiated) { MenuBarLayout.read() }.value
            async let panelRead = Task.detached(priority: .userInitiated) { NotificationCenterPanel.isOpenNow() }.value
            let read = (await layoutRead, await panelRead)
            let pictures = await bands
            guard let layout = read.0 else {
                Self.log.error("clock click: no layout; not lifting")
                return
            }
            self.cachedLayout = layout
            let onClock = layout.clock(at: axPoint) != nil
            // The belief was checked at the mouse-down (`route`). This read is
            // best effort for a panel opened outside BarNook (Fn+N, the
            // trackpad): it may already see such a panel closing.
            let panelOpen = read.1
            guard ClockCoverPolicy.lifts(onClock: onClock, panelOpen: panelOpen) else {
                Self.log.info("clock click: no lift onClock=\(onClock) panelOpen=\(panelOpen)")
                return
            }
            self.lastClockLift = .now
            guard let strips = ClockCover.strips(layout: layout, screens: ClockCover.currentScreens) else {
                Self.log.error("clock click: a menu bar has no strip to cover; not lifting")
                return
            }
            guard let pictures else {
                Self.log.error("clock click: capture failed; not lifting")
                return
            }
            let hidden = self.hiddenNow
            Self.log.info("clock click: covered lift")
            let opened = await self.clockCover.run(
                clickAt: point,
                strips: strips,
                bands: pictures,
                lift: {
                    self.isCoverLifting = true
                    self.restriction.release()
                },
                reapply: {
                    self.isCoverLifting = false
                    self.applyCurrentState()
                    await self.restriction.waitUntilActivated()
                },
                panelOpen: {
                    await Task.detached { NotificationCenterPanel.isOpenNow() }.value
                },
                hiddenStillDrawn: {
                    await Task.detached { MenuBarLayout.read()?.containsItem(ofAny: hidden) }.value
                }
            )
            if opened { self.notePanelOpen() }
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
