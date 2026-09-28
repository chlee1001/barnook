import Foundation
import Testing
@testable import BarNook
import BarNookCore

struct RehidePolicyTests {
    // One 1000x800 screen with a 24-point menu bar.
    private let menuBar = MenuBarGeometry(frames: [NSRect(x: 0, y: 776, width: 1000, height: 24)])
    // A menu hanging from a status item at x 700.
    private let statusMenu = NSRect(x: 700, y: 576, width: 200, height: 200)

    @Test func clickOnDesktopHides() {
        #expect(RehidePolicy.shouldHide(afterClickAt: NSPoint(x: 500, y: 300), menuBar: menuBar, menus: []))
    }

    @Test func clickInMenuBarDoesNotHide() {
        #expect(!RehidePolicy.shouldHide(afterClickAt: NSPoint(x: 500, y: 790), menuBar: menuBar, menus: []))
    }

    @Test func clickInsideOpenMenuDoesNotHide() {
        #expect(!RehidePolicy.shouldHide(afterClickAt: NSPoint(x: 750, y: 700), menuBar: menuBar, menus: [statusMenu]))
    }

    @Test func clickBesideOpenMenuHides() {
        #expect(RehidePolicy.shouldHide(afterClickAt: NSPoint(x: 100, y: 700), menuBar: menuBar, menus: [statusMenu]))
    }

    @Test func menuHangingFromMenuBarCountsAsOpen() {
        #expect(RehidePolicy.isMenuOpen([statusMenu], menuBar: menuBar))
    }

    @Test func menuWithSmallGapBelowMenuBarCountsAsOpen() {
        let menu = NSRect(x: 700, y: 570, width: 200, height: 200)
        #expect(RehidePolicy.isMenuOpen([menu], menuBar: menuBar))
    }

    @Test func popUpElsewhereOnScreenDoesNotCount() {
        let popUp = NSRect(x: 300, y: 300, width: 150, height: 100)
        #expect(!RehidePolicy.isMenuOpen([popUp], menuBar: menuBar))
        #expect(RehidePolicy.shouldHide(afterClickAt: NSPoint(x: 350, y: 350), menuBar: menuBar, menus: [popUp]))
    }

    // The floating bar under the menu bar.
    private let panel = NSRect(x: 600, y: 700, width: 200, height: 40)

    @Test func anOpenMenuWaits() {
        #expect(RehidePolicy.shouldWait(menus: [statusMenu], menuBar: menuBar, panel: nil, pointer: NSPoint(x: 10, y: 10)))
    }

    @Test func thePointerOnTheBarWaits() {
        #expect(RehidePolicy.shouldWait(menus: [], menuBar: menuBar, panel: panel, pointer: NSPoint(x: 650, y: 720)))
        #expect(RehidePolicy.shouldWait(menus: [], menuBar: menuBar, panel: panel, pointer: NSPoint(x: 600, y: 700)))
    }

    @Test func thePointerOffTheBarDoesNotWait() {
        #expect(!RehidePolicy.shouldWait(menus: [], menuBar: menuBar, panel: panel, pointer: NSPoint(x: 800, y: 720)))
        #expect(!RehidePolicy.shouldWait(menus: [], menuBar: menuBar, panel: nil, pointer: NSPoint(x: 650, y: 720)))
    }

    @Test func aPopUpElsewhereDoesNotWait() {
        let popUp = NSRect(x: 300, y: 300, width: 150, height: 100)
        #expect(!RehidePolicy.shouldWait(menus: [popUp], menuBar: menuBar, panel: panel, pointer: NSPoint(x: 350, y: 350)))
    }

    @Test func menuOnAnotherScreenDoesNotCount() {
        let menu = NSRect(x: 1200, y: 576, width: 200, height: 200)
        #expect(!RehidePolicy.isMenuOpen([menu], menuBar: menuBar))
    }
}

struct MenuBarGeometryTests {
    private let menuBar = MenuBarGeometry(frames: [NSRect(x: 0, y: 776, width: 1000, height: 24)])

    @Test func containsMenuBarPoints() {
        #expect(menuBar.contains(NSPoint(x: 10, y: 780)))
        #expect(!menuBar.contains(NSPoint(x: 10, y: 770)))
    }

    @Test func clockZoneIsTrailingStrip() {
        #expect(menuBar.clockZoneContains(NSPoint(x: 900, y: 780), width: 300))
        #expect(!menuBar.clockZoneContains(NSPoint(x: 600, y: 780), width: 300))
        #expect(!menuBar.clockZoneContains(NSPoint(x: 900, y: 700), width: 300))
    }
}
