import Foundation

/// When a mouse-down on the clock in bar mode starts a covered lift, and the
/// timings of that lift. Measured on macOS 27.0 (`docs/phase9.md`, cover-lift
/// spike): MenuBarAgent ignores clicks on its own items while an assertion is
/// held, so the click is replayed after a short lift, with the menu bars
/// covered by a picture of themselves until the restriction has landed again.
enum ClockCoverPolicy {
    /// Tags the click BarNook replays, so its own monitor does not start
    /// another lift. The value is arbitrary.
    static let replayTag: Int64 = 0x4241_524E  // "BARN"

    /// Wait after the covers are ordered front, for one composite before the lift.
    static let coverComposite: Duration = .milliseconds(30)
    /// Lift to replayed click. 40 ms lost clicks in the Ice measurements; 80 ms did not.
    static let liftToPress: Duration = .milliseconds(80)
    /// Replayed click to reapply. Notification Center stays open after the reapply.
    static let pressToReapply: Duration = .milliseconds(150)
    /// After the layout no longer has a hidden app, the crossfade still runs.
    static let settledToUncover: Duration = .milliseconds(150)
    /// The longest wait for the layout; the cover comes off after it either way.
    static let settleCap: Duration = .seconds(3)
    /// Clicks closer together than this start one lift: a double click opens
    /// Notification Center once.
    static let debounce: Duration = .milliseconds(300)

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
