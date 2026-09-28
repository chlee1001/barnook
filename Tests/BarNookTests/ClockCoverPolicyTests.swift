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
}
