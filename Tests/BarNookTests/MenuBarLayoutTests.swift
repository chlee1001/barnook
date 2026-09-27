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
            MenuBarLayout.Display(frame: CGRect(x: 0, y: 0, width: 1024, height: 30), items: [
                MenuBarLayout.Item(bundleIdentifier: "v", frame: CGRect(x: 626.5, y: 0, width: 70, height: 30)),
                MenuBarLayout.Item(systemIdentifier: MenuBarLayout.overflowIdentifier, frame: CGRect(x: 679.5, y: 1, width: 17.5, height: 27)),
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
