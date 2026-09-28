import Testing
@testable import BarNook

@Suite struct ClockCoverPolicyTests {
    typealias Facts = ClockCoverPolicy.Facts
    let ready = Facts(inBar: true, restrictionActive: true, permissionsGranted: true, isReplay: false, inFlight: false, sinceLastLift: nil)

    func with(_ change: (inout Facts) -> Void) -> Facts {
        var facts = ready
        change(&facts)
        return facts
    }

    @Test func aFirstClickInBarModeMayLift() {
        #expect(ClockCoverPolicy.mayIntercept(ready))
    }

    @Test func menuBarModeLeavesTheClickAlone() {
        #expect(!ClockCoverPolicy.mayIntercept(with { $0.inBar = false }))
    }

    @Test func nothingHiddenLeavesTheClickAlone() {
        #expect(!ClockCoverPolicy.mayIntercept(with { $0.restrictionActive = false }))
    }

    @Test func aMissingPermissionLeavesTheClickAlone() {
        #expect(!ClockCoverPolicy.mayIntercept(with { $0.permissionsGranted = false }))
    }

    @Test func theReplayedClickDoesNotLiftAgain() {
        #expect(!ClockCoverPolicy.mayIntercept(with { $0.isReplay = true }))
    }

    @Test func oneLiftAtATime() {
        #expect(!ClockCoverPolicy.mayIntercept(with { $0.inFlight = true }))
    }

    @Test func aDoubleClickLiftsOnce() {
        #expect(!ClockCoverPolicy.mayIntercept(with { $0.sinceLastLift = .milliseconds(299) }))
        #expect(ClockCoverPolicy.mayIntercept(with { $0.sinceLastLift = .milliseconds(300) }))
    }

    @Test func onlyAClickOnTheClockWithTheListClosedLifts() {
        #expect(ClockCoverPolicy.lifts(onClock: true, panelOpen: false))
        #expect(!ClockCoverPolicy.lifts(onClock: true, panelOpen: true))
        #expect(!ClockCoverPolicy.lifts(onClock: false, panelOpen: false))
    }

    // MARK: Phases

    @Test func aClickOffTheClockIsNeverQueued() {
        for phase in [ClockCoverPolicy.Phase.dwelling, .covering, .lifted, .restoring, .clickLift] {
            #expect(ClockCoverPolicy.route(phase: phase, onClock: false, isReplay: false, panelOpen: false) == .passThrough)
        }
    }

    @Test func theReplayedClickPassesThrough() {
        #expect(ClockCoverPolicy.route(phase: .idle, onClock: true, isReplay: true, panelOpen: false) == .passThrough)
        #expect(ClockCoverPolicy.route(phase: .covering, onClock: true, isReplay: true, panelOpen: false) == .passThrough)
    }

    @Test func aClickWhileCoveringWaitsForTheLift() {
        #expect(ClockCoverPolicy.route(phase: .dwelling, onClock: true, isReplay: false, panelOpen: false) == .queueForLift)
        #expect(ClockCoverPolicy.route(phase: .covering, onClock: true, isReplay: false, panelOpen: false) == .queueForLift)
    }

    /// Notification Center closes on the mouse-down itself; a replay after the
    /// lift would open it again.
    @Test func aClickThatClosesThePanelIsNotQueued() {
        #expect(ClockCoverPolicy.route(phase: .dwelling, onClock: true, isReplay: false, panelOpen: true) == .passThrough)
        #expect(ClockCoverPolicy.route(phase: .covering, onClock: true, isReplay: false, panelOpen: true) == .passThrough)
    }

    /// Idle too: the click path reads the panel about 100 ms later, after
    /// the click has begun to close it, and would reopen it.
    @Test func anIdleClickThatClosesThePanelNeverLifts() {
        #expect(ClockCoverPolicy.route(phase: .idle, onClock: true, isReplay: false, panelOpen: true) == .passThrough)
        #expect(ClockCoverPolicy.route(phase: .idle, onClock: false, isReplay: false, panelOpen: true) == .clickPath)
    }

    @Test func aClickWhileLiftedGoesStraightThrough() {
        #expect(ClockCoverPolicy.route(phase: .lifted, onClock: true, isReplay: false, panelOpen: false) == .passThrough)
        #expect(ClockCoverPolicy.route(phase: .clickLift, onClock: true, isReplay: false, panelOpen: false) == .passThrough)
    }

    /// A replay after the restore could reopen a panel this click closed.
    @Test func aClickWhileRestoringIsNeverReplayed() {
        #expect(ClockCoverPolicy.route(phase: .restoring, onClock: true, isReplay: false, panelOpen: false) == .passThrough)
    }

    /// Idle clicks go to the click path, which reads the clock itself: the
    /// cached layout may be stale.
    @Test func anIdleClickGoesToTheClickPath() {
        #expect(ClockCoverPolicy.route(phase: .idle, onClock: true, isReplay: false, panelOpen: false) == .clickPath)
        #expect(ClockCoverPolicy.route(phase: .idle, onClock: false, isReplay: false, panelOpen: false) == .clickPath)
    }

    @Test func onlyAnIdleBarModeRestOnTheClockPrelifts() {
        #expect(ClockCoverPolicy.startsPrelift(phase: .idle, onClock: true, inBar: true, restrictionActive: true, permissionsGranted: true))
        #expect(!ClockCoverPolicy.startsPrelift(phase: .restoring, onClock: true, inBar: true, restrictionActive: true, permissionsGranted: true))
        #expect(!ClockCoverPolicy.startsPrelift(phase: .idle, onClock: false, inBar: true, restrictionActive: true, permissionsGranted: true))
        #expect(!ClockCoverPolicy.startsPrelift(phase: .idle, onClock: true, inBar: false, restrictionActive: true, permissionsGranted: true))
        #expect(!ClockCoverPolicy.startsPrelift(phase: .idle, onClock: true, inBar: true, restrictionActive: false, permissionsGranted: true))
        #expect(!ClockCoverPolicy.startsPrelift(phase: .idle, onClock: true, inBar: true, restrictionActive: true, permissionsGranted: false))
    }
}
