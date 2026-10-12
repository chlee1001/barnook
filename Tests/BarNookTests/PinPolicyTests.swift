import Foundation
import Testing
@testable import BarNook
import BarNookCore

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

/// `PinPolicy.room` on a notch MacBook's menu bar, as BarNook read it after
/// a pin of Shottr (`s`): Shottr, Clipy and the BarNook icon collapsed at
/// 873–877, `«` at 894, the drawn app items up to 1281.
struct PinRoomTests {
    private func item(_ id: String, _ x: CGFloat, _ width: CGFloat) -> MenuBarLayout.Item {
        MenuBarLayout.Item(bundleIdentifier: id, frame: CGRect(x: x, y: 0, width: width, height: 33))
    }

    private func system(_ id: String, _ x: CGFloat, _ width: CGFloat) -> MenuBarLayout.Item {
        MenuBarLayout.Item(systemIdentifier: id, frame: CGRect(x: x, y: 0, width: width, height: 33))
    }

    private func layout(_ items: [MenuBarLayout.Item]) -> MenuBarLayout {
        MenuBarLayout(displays: [
            MenuBarLayout.Display(frame: CGRect(x: 0, y: 0, width: 1512, height: 33), items: items),
        ])
    }

    /// 468 points of app items in 408 points: 60 short.
    private var notchBar: MenuBarLayout {
        layout([
            item("s", 873, 38),
            item("clipy", 877, 34),
            item("barnook", 877, 34),
            system(MenuBarLayout.overflowIdentifier, 894, 17),
            item("codexbar", 919, 34),
            item("poketoken", 953, 89),
            item("wireguard", 1042, 38),
            item("runcat", 1080, 44),
            item("aldente", 1124, 75),
            item("textinput", 1199, 44),
            item("itsycal", 1243, 38),
            system("com.apple.menuextra.controlcenter", 1289, 26),
            system(MenuBarLayout.clockIdentifier, 1331, 161),
        ])
    }

    private let everyOtherApp: Set<String> = [
        "s", "clipy", "codexbar", "poketoken", "wireguard", "runcat", "aldente", "textinput", "itsycal",
    ]

    @Test func aDrawnPinNeedsNoRoom() {
        let drawn = layout([item("barnook", 848, 36), item("p", 884, 30), item("a", 914, 30)])
        #expect(PinPolicy.room(for: ["p"], in: drawn, hideable: ["a"]).isEmpty)
    }

    /// One app wide enough beats two narrow ones: fewer items go.
    @Test func theLeftmostAppThatCoversTheShortfallGoesAlone() {
        #expect(PinPolicy.room(for: ["s"], in: notchBar, hideable: everyOtherApp) == ["poketoken"])
    }

    /// A collapsed app needs its width too, so hiding it counts.
    @Test func withoutOneWideEnoughAppsGoFromTheLeft() {
        #expect(PinPolicy.room(for: ["s"], in: notchBar, hideable: ["clipy", "codexbar", "wireguard"]) == ["clipy", "codexbar"])
    }

    @Test func onlyHideableAppsMakeRoom() {
        #expect(PinPolicy.room(for: ["s"], in: notchBar, hideable: ["aldente", "itsycal"]) == ["aldente"])
    }

    @Test func noHideableAppMeansNoRoom() {
        #expect(PinPolicy.room(for: ["s"], in: notchBar, hideable: []).isEmpty)
    }

    @Test func anotherPinNeverMakesRoom() {
        #expect(PinPolicy.room(for: ["s", "poketoken"], in: notchBar, hideable: everyOtherApp) == ["aldente"])
    }

    /// `a` has two items of 20: together they cover the 35-point shortfall
    /// that `b`'s 30 does not.
    @Test func anAppWithTwoItemsFreesBoth() {
        let twoItems = layout([
            item("p", 700, 55),
            item("x", 702, 40),
            system(MenuBarLayout.overflowIdentifier, 744, 16),
            item("a", 760, 20),
            item("b", 780, 30),
            item("a", 810, 20),
        ])
        #expect(PinPolicy.room(for: ["p"], in: twoItems, hideable: ["a", "b"]) == ["a"])
    }
}
