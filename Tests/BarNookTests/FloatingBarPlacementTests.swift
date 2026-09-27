import Foundation
import Testing
@testable import BarNook

struct FloatingBarPlacementTests {
    let screen = NSRect(x: 0, y: 0, width: 1024, height: 768)
    let menuBarBottom: CGFloat = 738

    @Test func hangsFromTheIconsRightEdge() {
        let frame = FloatingBarPlacement.frame(
            panelSize: NSSize(width: 120, height: 40),
            iconFrame: NSRect(x: 600, y: 738, width: 36, height: 30),
            screen: screen, menuBarBottom: menuBarBottom)
        #expect(frame.maxX == 636)
        #expect(frame.maxY == 734)
        #expect(frame.size == NSSize(width: 120, height: 40))
    }

    @Test func staysOnScreenAtTheLeft() {
        let frame = FloatingBarPlacement.frame(
            panelSize: NSSize(width: 300, height: 40),
            iconFrame: NSRect(x: 100, y: 738, width: 36, height: 30),
            screen: screen, menuBarBottom: menuBarBottom)
        #expect(frame.minX == 4)
    }

    @Test func staysOnScreenAtTheRight() {
        let frame = FloatingBarPlacement.frame(
            panelSize: NSSize(width: 120, height: 40),
            iconFrame: NSRect(x: 1000, y: 738, width: 36, height: 30),
            screen: screen, menuBarBottom: menuBarBottom)
        #expect(frame.maxX == 1020)
    }

    @Test func hangsFromTheScreenEdgeWithoutAnIcon() {
        let frame = FloatingBarPlacement.frame(
            panelSize: NSSize(width: 120, height: 40),
            iconFrame: nil,
            screen: screen, menuBarBottom: menuBarBottom)
        #expect(frame.maxX == 1020)
        #expect(frame.maxY == 734)
    }

    @Test func followsASecondaryScreensOrigin() {
        let second = NSRect(x: 1024, y: -200, width: 1920, height: 1080)
        let frame = FloatingBarPlacement.frame(
            panelSize: NSSize(width: 120, height: 40),
            iconFrame: NSRect(x: 2000, y: 850, width: 36, height: 30),
            screen: second, menuBarBottom: 850)
        #expect(frame.maxX == 2036)
        #expect(frame.maxY == 846)
    }
}
