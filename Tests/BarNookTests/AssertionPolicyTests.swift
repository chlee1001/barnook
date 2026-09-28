import Testing
@testable import BarNook

@Suite struct AssertionPolicyTests {
    typealias Applied = AssertionPolicy.Applied

    @Test func noPreviousAssertionIsFresh() {
        #expect(AssertionPolicy.decide(Applied(allowList: ["a"], agentPID: 1), previous: nil)
            == .activate(reason: .fresh, added: ["a"], removed: []))
    }

    @Test func theSameListAndAgentIsSkipped() {
        let applied = Applied(allowList: ["a", "b"], agentPID: 100)
        #expect(AssertionPolicy.decide(applied, previous: applied) == .skip)
    }

    @Test func noAgentOnEitherSideIsSkipped() {
        let applied = Applied(allowList: ["a"], agentPID: nil)
        #expect(AssertionPolicy.decide(applied, previous: applied) == .skip)
    }

    @Test func aRestartedAgentIsAskedAgain() {
        #expect(AssertionPolicy.decide(Applied(allowList: ["a"], agentPID: 200), previous: Applied(allowList: ["a"], agentPID: 100))
            == .activate(reason: .agentRestarted, added: [], removed: []))
    }

    @Test func aVanishedAgentCountsAsRestarted() {
        #expect(AssertionPolicy.decide(Applied(allowList: ["a"], agentPID: nil), previous: Applied(allowList: ["a"], agentPID: 100))
            == .activate(reason: .agentRestarted, added: [], removed: []))
    }

    @Test func anAddedAppChangesTheList() {
        #expect(AssertionPolicy.decide(Applied(allowList: ["a", "b", "c"], agentPID: 1), previous: Applied(allowList: ["a", "b"], agentPID: 1))
            == .activate(reason: .allowListChanged, added: ["c"], removed: []))
    }

    @Test func aRemovedAppChangesTheList() {
        #expect(AssertionPolicy.decide(Applied(allowList: ["b"], agentPID: 1), previous: Applied(allowList: ["a", "b"], agentPID: 1))
            == .activate(reason: .allowListChanged, added: [], removed: ["a"]))
    }

    @Test func aRestartWinsOverAListChangeAndKeepsTheDeltas() {
        #expect(AssertionPolicy.decide(Applied(allowList: ["b", "c"], agentPID: 2), previous: Applied(allowList: ["a", "b"], agentPID: 1))
            == .activate(reason: .agentRestarted, added: ["c"], removed: ["a"]))
    }

    @Test func noPreviousListIsTheRunningAppsMinusHidden() {
        #expect(AssertionPolicy.allowList(running: ["a", "b", "h"], hidden: ["h"], previous: nil) == ["a", "b"])
    }

    @Test func aQuitAppStaysOnTheList() {
        #expect(AssertionPolicy.allowList(running: ["b"], hidden: [], previous: ["a", "b"]) == ["a", "b"])
    }

    @Test func aNewlyHiddenAppLeavesTheList() {
        #expect(AssertionPolicy.allowList(running: ["a", "b"], hidden: ["a"], previous: ["a", "b"]) == ["b"])
    }

    @Test func aNewLaunchJoins() {
        #expect(AssertionPolicy.allowList(running: ["a", "c"], hidden: [], previous: ["a"]) == ["a", "c"])
    }

    @Test func nothingRunningIsEmpty() {
        #expect(AssertionPolicy.allowList(running: [], hidden: [], previous: nil) == [])
    }

    @Test func theListIsSortedAndUnique() {
        #expect(AssertionPolicy.allowList(running: ["c", "a", "c"], hidden: [], previous: ["b", "a"]) == ["a", "b", "c"])
    }

    @Test func retriesBackOffThenStop() {
        #expect(AssertionPolicy.retryDelay(attempt: 1) == .milliseconds(250))
        #expect(AssertionPolicy.retryDelay(attempt: 2) == .seconds(1))
        #expect(AssertionPolicy.retryDelay(attempt: 3) == .seconds(4))
        #expect(AssertionPolicy.retryDelay(attempt: 4) == nil)
    }
}

@Suite struct AssertionLedgerTests {
    let keyA = AssertionPolicy.Applied(allowList: ["a"], agentPID: 1)
    let keyB = AssertionPolicy.Applied(allowList: ["b"], agentPID: 1)
    let keyC = AssertionPolicy.Applied(allowList: ["c"], agentPID: 1)

    @Test func theFirstAssertionDropsNothing() {
        var ledger = AssertionLedger<String>()
        ledger.requested("A", key: keyA)
        #expect(ledger.succeeded("A") == [])
        #expect(!ledger.isEmpty)
    }

    @Test func aReplacementDropsTheOldOneOnlyOnSuccess() {
        var ledger = AssertionLedger<String>()
        ledger.requested("A", key: keyA)
        _ = ledger.succeeded("A")
        ledger.requested("B", key: keyB)
        #expect(ledger.succeeded("B") == ["A"])
    }

    @Test func aFailedReplacementKeepsTheOldOne() {
        var ledger = AssertionLedger<String>()
        ledger.requested("A", key: keyA)
        _ = ledger.succeeded("A")
        ledger.requested("B", key: keyB)
        let outcome = ledger.failed("B")
        #expect(outcome.wasNewest)
        #expect(outcome.newestKey == keyA)
        #expect(!ledger.isEmpty)
    }

    @Test func aFailureBehindANewerRequestIsNotNewest() {
        var ledger = AssertionLedger<String>()
        ledger.requested("A", key: keyA)
        _ = ledger.succeeded("A")
        ledger.requested("B", key: keyB)
        ledger.requested("C", key: keyC)
        #expect(!ledger.failed("B").wasNewest)
        #expect(ledger.succeeded("C") == ["A"])
    }

    /// Two activations overlap and report out of order.
    @Test func aLateSuccessOfAnOlderRequestDropsNothingTwice() {
        var ledger = AssertionLedger<String>()
        ledger.requested("A", key: keyA)
        _ = ledger.succeeded("A")
        ledger.requested("B", key: keyB)
        ledger.requested("C", key: keyC)
        #expect(ledger.succeeded("C") == ["A", "B"])
        #expect(ledger.succeeded("B") == nil)
        #expect(ledger.releaseAll() == ["C"])
    }

    @Test func aFailureWithNothingLiveLeavesNothing() {
        var ledger = AssertionLedger<String>()
        ledger.requested("A", key: keyA)
        let outcome = ledger.failed("A")
        #expect(outcome.wasNewest)
        #expect(outcome.newestKey == nil)
        #expect(ledger.isEmpty)
    }

    @Test func aFailureAfterReleaseIsNotRetried() {
        var ledger = AssertionLedger<String>()
        ledger.requested("A", key: keyA)
        _ = ledger.releaseAll()
        let outcome = ledger.failed("A")
        #expect(!outcome.wasNewest)
        #expect(outcome.newestKey == nil)
    }

    @Test func releaseReturnsEveryTokenIncludingThoseInFlight() {
        var ledger = AssertionLedger<String>()
        ledger.requested("A", key: keyA)
        _ = ledger.succeeded("A")
        ledger.requested("B", key: keyB)
        #expect(ledger.releaseAll() == ["A", "B"])
        #expect(ledger.isEmpty)
    }

    /// An activation that reports after a release is unknown; the caller
    /// invalidates it so it cannot outlive the release.
    @Test func aSuccessAfterReleaseIsUnknown() {
        var ledger = AssertionLedger<String>()
        ledger.requested("A", key: keyA)
        _ = ledger.releaseAll()
        #expect(ledger.succeeded("A") == nil)
        #expect(ledger.isEmpty)
    }
}
