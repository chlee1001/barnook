import AppKit
import BarNookCore
import Testing
@testable import BarNook

/// The strips over the user's three displays: a 1512x982 primary, a
/// 1920x1200 display right of and below it, and a 2560x1440 display right
/// of and above it (Cocoa coordinates, as NSScreen reports them).
@MainActor
@Suite struct ClockCoverStripTests {
    typealias Screen = ClockCover.Screen
    let screens = [
        Screen(frame: NSRect(x: 0, y: 0, width: 1512, height: 982), displayID: 1, scale: 2),
        Screen(frame: NSRect(x: 1512, y: -1200, width: 1920, height: 1200), displayID: 2, scale: 1),
        Screen(frame: NSRect(x: 1512, y: 0, width: 2560, height: 1440), displayID: 3, scale: 1),
    ]

    func display(_ frame: CGRect, clockX: CGFloat?) -> MenuBarLayout.Display {
        var items = [MenuBarLayout.Item(bundleIdentifier: "a", frame: CGRect(x: frame.minX + 100, y: frame.minY, width: 30, height: frame.height))]
        if let clockX {
            items.append(MenuBarLayout.Item(systemIdentifier: MenuBarLayout.clockIdentifier, frame: CGRect(x: clockX, y: frame.minY, width: 153, height: frame.height)))
        }
        return MenuBarLayout.Display(frame: frame, items: items)
    }

    /// Accessibility frames as `probe layout` read them on the host.
    var main: MenuBarLayout.Display { display(CGRect(x: 0, y: 0, width: 1512, height: 33), clockX: 1339) }
    var below: MenuBarLayout.Display { display(CGRect(x: 1512, y: 982, width: 1920, height: 30), clockX: 3259) }
    var above: MenuBarLayout.Display { display(CGRect(x: 1512, y: -458, width: 2560, height: 30), clockX: 3899) }

    @Test func everyBarGetsTheStripLeftOfItsClock() throws {
        let strips = try #require(ClockCover.strips(layout: MenuBarLayout(displays: [main, below, above]), screens: screens))
        #expect(strips.map(\.displayID) == [1, 2, 3])
        #expect(strips[0].frame == NSRect(x: 0, y: 949, width: 1335, height: 33))
        #expect(strips[1].frame == NSRect(x: 1512, y: -30, width: 1743, height: 30))
        #expect(strips[2].frame == NSRect(x: 1512, y: 1410, width: 2383, height: 30))
    }

    @Test func theCaptureRectIsLocalToItsDisplayFromTheTop() throws {
        let strips = try #require(ClockCover.strips(layout: MenuBarLayout(displays: [main, below, above]), screens: screens))
        #expect(strips[0].local == CGRect(x: 0, y: 0, width: 1335, height: 33))
        #expect(strips[1].local == CGRect(x: 0, y: 0, width: 1743, height: 30))
        #expect(strips[2].local == CGRect(x: 0, y: 0, width: 2383, height: 30))
        #expect(strips.map(\.scale) == [2, 1, 1])
    }

    @Test func aBarReportedTwiceIsCoveredOnce() throws {
        let strips = try #require(ClockCover.strips(layout: MenuBarLayout(displays: [above, main, above]), screens: screens))
        #expect(strips.count == 2)
    }

    @Test func aBarWithoutAClockRefusesTheLift() {
        let noClock = display(CGRect(x: 1512, y: 982, width: 1920, height: 30), clockX: nil)
        #expect(ClockCover.strips(layout: MenuBarLayout(displays: [main, noClock]), screens: screens) == nil)
    }

    @Test func aBarOnNoKnownScreenRefusesTheLift() {
        let gone = display(CGRect(x: 9000, y: 0, width: 1000, height: 30), clockX: 9800)
        #expect(ClockCover.strips(layout: MenuBarLayout(displays: [main, gone]), screens: screens) == nil)
    }

    @Test func aClockAtTheLeftEdgeRefusesTheLift() {
        let squeezed = display(CGRect(x: 0, y: 0, width: 1512, height: 33), clockX: 2)
        #expect(ClockCover.strips(layout: MenuBarLayout(displays: [squeezed]), screens: screens) == nil)
    }

    @Test func noBarsRefusesTheLift() {
        #expect(ClockCover.strips(layout: MenuBarLayout(displays: []), screens: screens) == nil)
    }

    /// A reply from MenuBarAgent that never comes must not hold the cover.
    @Test func aStuckWaitIsCutOff() async {
        let finished = await ClockCover.bounded(.milliseconds(50)) {
            await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
        }
        #expect(!finished)
    }

    @Test func aPromptWaitFinishes() async {
        let finished = await ClockCover.bounded(.seconds(2)) {}
        #expect(finished)
    }
}
