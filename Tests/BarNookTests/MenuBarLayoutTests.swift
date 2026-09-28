import Foundation
import Testing
@testable import BarNook
import BarNookCore

struct MenuBarLayoutTests {
    @Test func clockOffsetIsMeasuredFromTheRightEdge() {
        let layout = MenuBarLayout(displays: [
            MenuBarLayout.Display(frame: CGRect(x: -1000, y: 0, width: 1000, height: 30), items: [
                MenuBarLayout.Item(bundleIdentifier: "a", frame: CGRect(x: -300, y: 0, width: 40, height: 30)),
            ]),
            MenuBarLayout.Display(frame: CGRect(x: 0, y: 0, width: 2000, height: 30), items: [
                MenuBarLayout.Item(systemIdentifier: MenuBarLayout.clockIdentifier, frame: CGRect(x: 1900, y: 0, width: 80, height: 30)),
            ]),
        ])
        #expect(layout.clockOffset == 100)
    }

    private var twoBars: MenuBarLayout {
        MenuBarLayout(displays: [
            MenuBarLayout.Display(frame: CGRect(x: 0, y: 0, width: 1512, height: 33), items: [
                MenuBarLayout.Item(bundleIdentifier: "a", frame: CGRect(x: 900, y: 0, width: 30, height: 33)),
                MenuBarLayout.Item(systemIdentifier: "com.apple.menuextra.controlcenter", frame: CGRect(x: 1297, y: 0, width: 26, height: 33)),
                MenuBarLayout.Item(systemIdentifier: MenuBarLayout.clockIdentifier, frame: CGRect(x: 1339, y: 0, width: 153, height: 33)),
            ]),
            MenuBarLayout.Display(frame: CGRect(x: 1512, y: 982, width: 1920, height: 30), items: [
                MenuBarLayout.Item(bundleIdentifier: "b", frame: CGRect(x: 2800, y: 982, width: 30, height: 30)),
                MenuBarLayout.Item(systemIdentifier: MenuBarLayout.clockIdentifier, frame: CGRect(x: 3259, y: 982, width: 153, height: 30)),
            ]),
        ])
    }

    /// `v` collapsed behind the `«` button.
    private var collapsedV: [MenuBarLayout.Item] {
        [
            MenuBarLayout.Item(bundleIdentifier: "v", frame: CGRect(x: 626.5, y: 0, width: 70, height: 30)),
            MenuBarLayout.Item(systemIdentifier: MenuBarLayout.overflowIdentifier, frame: CGRect(x: 679.5, y: 1, width: 17.5, height: 27)),
        ]
    }

    @Test func aPointOnTheClockHitsIt() {
        #expect(twoBars.clock(at: CGPoint(x: 1400, y: 16)) != nil)
    }

    @Test func theClockHasATwoPointMargin() {
        #expect(twoBars.clock(at: CGPoint(x: 1337.5, y: 16)) != nil)
        #expect(twoBars.clock(at: CGPoint(x: 1336, y: 16)) == nil)
    }

    @Test func theClockOnTheSecondBarHits() {
        #expect(twoBars.clock(at: CGPoint(x: 3300, y: 997))?.frame.minX == 3259)
    }

    @Test func anotherSystemItemIsNotTheClock() {
        #expect(twoBars.clock(at: CGPoint(x: 1305, y: 16)) == nil)
    }

    @Test func containsItemFindsAnyListedOwner() {
        #expect(twoBars.containsItem(ofAny: ["b"]))
        #expect(twoBars.containsItem(ofAny: ["z", "a"]))
    }

    @Test func containsItemIgnoresAbsentAppsAndSystemItems() {
        #expect(!twoBars.containsItem(ofAny: ["z"]))
        #expect(!twoBars.containsItem(ofAny: []))
        #expect(!twoBars.containsItem(ofAny: [MenuBarLayout.clockIdentifier]))
    }

    /// A collapsed item is still in the layout: the restriction has not landed.
    @Test func containsItemCountsACollapsedItem() {
        let collapsed = MenuBarLayout(displays: [
            MenuBarLayout.Display(frame: CGRect(x: 0, y: 0, width: 1024, height: 30), items: collapsedV),
        ])
        #expect(collapsed.drawnItem(of: "v") == nil)
        #expect(collapsed.containsItem(ofAny: ["v"]))
    }

    @Test func noClockMeansNoOffset() {
        let layout = MenuBarLayout(displays: [
            MenuBarLayout.Display(frame: CGRect(x: 0, y: 0, width: 2000, height: 30), items: [
                MenuBarLayout.Item(bundleIdentifier: "a", frame: CGRect(x: 1900, y: 0, width: 80, height: 30)),
            ]),
        ])
        #expect(layout.clockOffset == nil)
    }

    /// One item alone collapses: nothing stacks on its frame, so only the
    /// `«` button, drawn to its right, tells.
    @Test func anItemLeftOfTheOverflowButtonIsNotDrawn() {
        let layout = MenuBarLayout(displays: [
            MenuBarLayout.Display(frame: CGRect(x: 0, y: 0, width: 1024, height: 30), items: collapsedV + [
                MenuBarLayout.Item(bundleIdentifier: "icon", frame: CGRect(x: 704.5, y: 0, width: 28, height: 30)),
                MenuBarLayout.Item(bundleIdentifier: "a", frame: CGRect(x: 732.5, y: 0, width: 70, height: 30)),
            ]),
        ])
        #expect(layout.drawnItem(of: "v") == nil)
        #expect(layout.drawnItem(of: "icon") != nil)
        #expect(layout.drawnItem(of: "a") != nil)
    }

    @Test func stackedItemsAreNotDrawn() {
        let layout = MenuBarLayout(displays: [
            MenuBarLayout.Display(frame: CGRect(x: 0, y: 0, width: 1024, height: 30), items: [
                MenuBarLayout.Item(bundleIdentifier: "w", frame: CGRect(x: 580, y: 0, width: 74, height: 30)),
                MenuBarLayout.Item(bundleIdentifier: "c", frame: CGRect(x: 583, y: 0, width: 70, height: 30)),
                MenuBarLayout.Item(bundleIdentifier: "a", frame: CGRect(x: 700, y: 0, width: 70, height: 30)),
            ]),
        ])
        #expect(layout.drawnItem(of: "w") == nil)
        #expect(layout.drawnItem(of: "c") == nil)
        #expect(layout.drawnItem(of: "a") != nil)
    }
}
