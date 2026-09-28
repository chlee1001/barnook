import Foundation

/// When a mouse-down on the clock in bar mode starts a covered lift, and the
/// timings of that lift (`ClockCover`; measurements in `docs/notification-center-clock.md`).
enum ClockCoverPolicy {
    /// Tags the click BarNook replays, so its own monitor does not start
    /// another lift. The value is arbitrary.
    static let replayTag: Int64 = 0x4241_524E  // "BARN"

    /// Wait after the covers are ordered front, for one composite before the lift.
    static let coverComposite: Duration = .milliseconds(30)
    /// Lift to replayed click. MenuBarAgent handles the replay late anyway
    /// (it lays out the lift first), and the reapply waits for the panel
    /// (`pressToReapplyCap`), so an early replay is not lost.
    static let liftToPress: Duration = .milliseconds(10)
    /// Replayed click to reapply, at least. Notification Center stays open after the reapply.
    static let pressToReapply: Duration = .milliseconds(150)
    /// Replayed click to reapply, at most. MenuBarAgent handles the replayed
    /// click up to about 450 ms late while it lays out the lift; a reapply
    /// before that swallows it, so the reapply waits until the panel opens.
    static let pressToReapplyCap: Duration = .milliseconds(900)
    /// After the layout no longer has a hidden app, the crossfade still runs.
    static let settledToUncover: Duration = .milliseconds(150)
    /// The longest wait for the layout; the cover comes off after it either way.
    static let settleCap: Duration = .seconds(3)
    /// The longest wait for MenuBarAgent to confirm the reapplied restriction.
    /// The settle check still guards the uncover after it.
    static let reapplyTimeout: Duration = .seconds(1)
    /// Mouse-down to mouse-up of the replayed click.
    static let replayClickHold: Duration = .milliseconds(60)
    /// The pointer rests this long on the clock before the menu bars are
    /// covered and the restriction lifts ahead of a click; a pass across the
    /// clock does nothing.
    static let hoverDwell: Duration = .milliseconds(60)
    /// Clicks closer together than this start one lift: a double click opens
    /// Notification Center once.
    static let debounce: Duration = .milliseconds(300)

    /// The bar-mode clock lift, from the pointer's first rest on the clock
    /// to the restriction's return.
    enum Phase: Equatable {
        /// Nothing lifted, nothing covered.
        case idle
        /// The pointer rests on the clock; the pre-lift has not covered yet.
        case dwelling
        /// The covers are up, the restriction is still active.
        case covering
        /// The covers are up and the restriction is lifted: clicks reach
        /// MenuBarAgent as they are.
        case lifted
        /// The restriction is coming back and the covers come off once it has.
        case restoring
        /// A covered lift for one click that came with no rest.
        case clickLift
    }

    enum ClickRoute: Equatable {
        /// Not BarNook's: BarNook's own replay, any click while Notification
        /// Center is believed open (it closes on the mouse-down itself), a
        /// click off the clock during a pre-lift, or a click MenuBarAgent
        /// takes as it is (lifted, a lift in flight, or a restore under way,
        /// where a replay later could reopen a panel this click just closed).
        case passThrough
        /// The pre-lift replays it once lifted.
        case queueForLift
        /// The click path decides: it checks the zone and reads the clock
        /// frame itself, since the cached layout may be stale.
        case clickPath
    }

    /// Where a mouse-down goes, by phase. `panelOpen` is whether BarNook
    /// believes Notification Center is open: a clock click then closes it
    /// natively, and replaying it after the lift would reopen it.
    static func route(phase: Phase, onClock: Bool, isReplay: Bool, panelOpen: Bool) -> ClickRoute {
        guard !isReplay else { return .passThrough }
        // Decided at the mouse-down: a poll that runs after it may already
        // see the panel closing. Whatever the cached hit test says: a click
        // off the clock never lifts anyway, and a stale cache (the clock
        // grew since the last read) must not let a closing click lift.
        if panelOpen { return .passThrough }
        switch phase {
        case .idle: return .clickPath
        case .dwelling, .covering: return onClock ? .queueForLift : .passThrough
        case .lifted, .clickLift, .restoring: return .passThrough
        }
    }

    /// Whether the pointer in bar mode on the clock starts a pre-lift.
    static func startsPrelift(phase: Phase, onClock: Bool, inBar: Bool, restrictionActive: Bool, permissionsGranted: Bool) -> Bool {
        phase == .idle && onClock && inBar && restrictionActive && permissionsGranted
    }

    struct Facts: Equatable {
        var inBar: Bool
        var restrictionActive: Bool
        var permissionsGranted: Bool
        var isReplay: Bool
        var inFlight: Bool
        var sinceLastLift: Duration?
    }

    /// Whether a mouse-down might start a lift, before the clock is looked
    /// up. A click in menu-bar mode, with nothing hidden, or without the
    /// permissions goes to MenuBarAgent as it is.
    static func mayIntercept(_ facts: Facts) -> Bool {
        guard facts.inBar, facts.restrictionActive, facts.permissionsGranted, !facts.isReplay, !facts.inFlight
        else { return false }
        return facts.sinceLastLift.map { $0 >= debounce } ?? true
    }

    /// Whether a mouse-down on the clock starts the lift. A click while the
    /// panel is open closes it: Notification Center dismisses on its own
    /// mouse-down watch, so no lift is needed.
    static func lifts(onClock: Bool, panelOpen: Bool) -> Bool {
        onClock && !panelOpen
    }
}
