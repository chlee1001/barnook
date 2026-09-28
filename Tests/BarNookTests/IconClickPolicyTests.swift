import Testing
@testable import BarNook

@Suite struct IconClickPolicyTests {
    @Test func aHiddenSetShows() {
        #expect(IconClickPolicy.action(isShown: false, inBar: true, isBarOpen: false) == .show)
        #expect(IconClickPolicy.action(isShown: false, inBar: false, isBarOpen: false) == .show)
    }

    @Test func aClosedBarReopensFirst() {
        #expect(IconClickPolicy.action(isShown: true, inBar: true, isBarOpen: false) == .reopenBar)
    }

    @Test func anOpenBarHides() {
        #expect(IconClickPolicy.action(isShown: true, inBar: true, isBarOpen: true) == .hide)
    }

    @Test func menuBarModeHides() {
        #expect(IconClickPolicy.action(isShown: true, inBar: false, isBarOpen: false) == .hide)
        #expect(IconClickPolicy.action(isShown: true, inBar: false, isBarOpen: true) == .hide)
    }
}
