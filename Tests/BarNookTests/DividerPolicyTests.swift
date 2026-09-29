import Foundation
import Testing
@testable import BarNook
import BarNookCore

struct DividerPolicyTests {
    @Test func leftJoinsAndRightLeavesWhileShown() {
        let result = DividerPolicy.hiddenSet(
            current: ["a", "b"], alwaysHidden: [], own: "me",
            left: ["c"], right: ["b"], isShown: true
        )
        #expect(result == ["a", "c"])
    }

    @Test func rightStaysWhileHidden() {
        let result = DividerPolicy.hiddenSet(
            current: ["a", "b"], alwaysHidden: [], own: "me",
            left: ["c"], right: ["b"], isShown: false
        )
        #expect(result == ["a", "b", "c"])
    }

    @Test func anItemOnEachSideHides() {
        let result = DividerPolicy.hiddenSet(
            current: [], alwaysHidden: [], own: "me",
            left: ["a"], right: ["a"], isShown: true
        )
        #expect(result == ["a"])
    }

    @Test func alwaysHiddenAndSelfAreLeftAlone() {
        let result = DividerPolicy.hiddenSet(
            current: [], alwaysHidden: ["x"], own: "me",
            left: ["x", "me", "a"], right: [], isShown: true
        )
        #expect(result == ["a"])
    }

    @Test func invisibleAppsKeepTheirMembership() {
        let result = DividerPolicy.hiddenSet(
            current: ["gone"], alwaysHidden: [], own: nil,
            left: [], right: [], isShown: true
        )
        #expect(result == ["gone"])
    }
}

struct MenuBarLayoutSplitTests {
    private let layout = MenuBarLayout(displays: [
        MenuBarLayout.Display(frame: CGRect(x: -1000, y: 0, width: 1000, height: 30), items: [
            MenuBarLayout.Item(bundleIdentifier: "other", frame: CGRect(x: -300, y: 0, width: 40, height: 30)),
        ]),
        MenuBarLayout.Display(frame: CGRect(x: 0, y: 0, width: 2000, height: 30), items: [
            MenuBarLayout.Item(bundleIdentifier: "a", frame: CGRect(x: 1700, y: 0, width: 40, height: 30)),
            MenuBarLayout.Item(bundleIdentifier: "b", frame: CGRect(x: 1800, y: 0, width: 40, height: 30)),
            MenuBarLayout.Item(systemIdentifier: MenuBarLayout.clockIdentifier, frame: CGRect(x: 1900, y: 0, width: 80, height: 30)),
        ]),
    ])

    @Test func splitsAppItemsOnTheDisplayThatHoldsThePoint() {
        let split = layout.appItems(splitAt: CGPoint(x: 1780, y: 15))
        #expect(split?.left == ["a"])
        #expect(split?.right == ["b"])
    }

    @Test func noDisplayMeansNoSplit() {
        #expect(layout.appItems(splitAt: CGPoint(x: 5000, y: 15)) == nil)
    }

    @Test func splitKeepsMenuBarOrderOnTheLeft() {
        let layout = MenuBarLayout(displays: [
            MenuBarLayout.Display(frame: CGRect(x: 0, y: 0, width: 2000, height: 30), items: [
                MenuBarLayout.Item(bundleIdentifier: "b", frame: CGRect(x: 1600, y: 0, width: 40, height: 30)),
                MenuBarLayout.Item(bundleIdentifier: "a", frame: CGRect(x: 1500, y: 0, width: 40, height: 30)),
                MenuBarLayout.Item(bundleIdentifier: "a", frame: CGRect(x: 1650, y: 0, width: 40, height: 30)),
                MenuBarLayout.Item(bundleIdentifier: "c", frame: CGRect(x: 1800, y: 0, width: 40, height: 30)),
            ]),
        ])
        let split = layout.appItems(splitAt: CGPoint(x: 1750, y: 15))
        #expect(split?.left == ["a", "b"])
        #expect(split?.right == ["c"])
    }

    @Test func equalMinXFallsBackToAXOrder() {
        let layout = MenuBarLayout(displays: [
            MenuBarLayout.Display(frame: CGRect(x: 0, y: 0, width: 2000, height: 30), items: [
                MenuBarLayout.Item(bundleIdentifier: "q", frame: CGRect(x: 1500, y: 0, width: 40, height: 30)),
                MenuBarLayout.Item(bundleIdentifier: "p", frame: CGRect(x: 1500, y: 0, width: 40, height: 30)),
            ]),
        ])
        #expect(layout.appItems(splitAt: CGPoint(x: 1750, y: 15))?.left == ["q", "p"])
    }
}
