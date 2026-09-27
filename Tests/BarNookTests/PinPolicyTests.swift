import Testing
@testable import BarNook

struct PinPolicyTests {
    @Test func aClickPins() {
        #expect(PinPolicy.toggling("a", in: []) == ["a"])
    }

    @Test func aClickOnAPinnedAppUnpinsIt() {
        #expect(PinPolicy.toggling("a", in: ["a", "b"]) == ["b"])
    }

    @Test func pinsStayOldestFirst() {
        #expect(PinPolicy.toggling("c", in: ["a", "b"]) == ["a", "b", "c"])
    }

    @Test func aClickPastTheLimitDropsTheOldestPin() {
        #expect(PinPolicy.toggling("d", in: ["a", "b", "c"]) == ["b", "c", "d"])
    }

    @Test func unpinningTheMiddleKeepsTheOrder() {
        #expect(PinPolicy.toggling("b", in: ["a", "b", "c"]) == ["a", "c"])
    }

    @Test func theLimitIsThree() {
        #expect(PinPolicy.limit == 3)
    }
}
