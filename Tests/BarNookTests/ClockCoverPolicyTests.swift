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
        for phase in [ClockCoverPolicy.Phase.idle, .dwelling, .covering, .lifted, .restoring, .clickLift] {
            #expect(ClockCoverPolicy.route(phase: phase, onClock: false, isReplay: false) == .native)
        }
    }

    @Test func theReplayedClickPassesThrough() {
        #expect(ClockCoverPolicy.route(phase: .idle, onClock: true, isReplay: true) == .native)
        #expect(ClockCoverPolicy.route(phase: .covering, onClock: true, isReplay: true) == .native)
    }

    @Test func aClickWhileCoveringIsQueued() {
        #expect(ClockCoverPolicy.route(phase: .dwelling, onClock: true, isReplay: false) == .queue)
        #expect(ClockCoverPolicy.route(phase: .covering, onClock: true, isReplay: false) == .queue)
    }

    @Test func aClickWhileLiftedGoesStraightThrough() {
        #expect(ClockCoverPolicy.route(phase: .lifted, onClock: true, isReplay: false) == .native)
        #expect(ClockCoverPolicy.route(phase: .clickLift, onClock: true, isReplay: false) == .native)
    }

    @Test func aClickWhileIdleOrRestoringNeedsACoveredLift() {
        #expect(ClockCoverPolicy.route(phase: .idle, onClock: true, isReplay: false) == .coveredLift)
        #expect(ClockCoverPolicy.route(phase: .restoring, onClock: true, isReplay: false) == .coveredLift)
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
