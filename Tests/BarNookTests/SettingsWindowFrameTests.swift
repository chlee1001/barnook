import AppKit
import Testing
@testable import BarNook

struct SettingsWindowFrameTests {
    // A 1000-point-high visible area from y 100 (a Dock below it), and a
    // title bar plus toolbar of 88 points.
    private let visible = NSRect(x: 0, y: 100, width: 1500, height: 1000)
    private let chrome: CGFloat = 88

    @Test func capIsTheVisibleHeightLessTheChrome() {
        #expect(SettingsWindowFrame.heightCap(visible: visible, chrome: chrome) == 912)
    }

    @Test func aPaneThatFitsKeepsTheTopEdge() throws {
        let current = NSRect(x: 200, y: 500, width: 500, height: 548)
        let frame = try #require(SettingsWindowFrame.fitted(
            current: current, content: CGSize(width: 500, height: 300), chrome: chrome, visible: visible))
        #expect(frame.height == 388)
        #expect(frame.maxY == current.maxY)
        #expect(frame.minX == 200)
    }

    @Test func aPaneTallerThanTheScreenIsCapped() throws {
        let current = NSRect(x: 200, y: 500, width: 500, height: 548)
        let frame = try #require(SettingsWindowFrame.fitted(
            current: current, content: CGSize(width: 500, height: 2000), chrome: chrome, visible: visible))
        #expect(frame.height == 1000)
        #expect(frame.minY >= visible.minY)
        #expect(frame.maxY <= visible.maxY)
    }

    @Test func aWindowNearTheBottomMovesUpInsteadOfGoingPastIt() throws {
        let current = NSRect(x: 200, y: 110, width: 500, height: 300)
        let frame = try #require(SettingsWindowFrame.fitted(
            current: current, content: CGSize(width: 500, height: 700), chrome: chrome, visible: visible))
        #expect(frame.minY == visible.minY)
        #expect(frame.height == 788)
    }

    @Test(arguments: [
        NSRect(x: 1400, y: 1000, width: 500, height: 548), // past the top and the right
        NSRect(x: -300, y: 400, width: 500, height: 548),  // past the left
        NSRect(x: 600, y: 2000, width: 500, height: 548),  // above the screen
        NSRect(x: 600, y: -500, width: 500, height: 548),  // below the screen
    ])
    func aDisplacedWindowComesBackInside(current: NSRect) throws {
        let frame = try #require(SettingsWindowFrame.fitted(
            current: current, content: CGSize(width: 500, height: 300), chrome: chrome, visible: visible))
        #expect(visible.contains(frame))
        #expect(frame.size == CGSize(width: 500, height: 388))
    }

    @Test func aWindowInsideKeepsItsPosition() throws {
        let current = NSRect(x: 300, y: 400, width: 500, height: 548)
        let frame = try #require(SettingsWindowFrame.fitted(
            current: current, content: CGSize(width: 500, height: 460), chrome: chrome, visible: visible))
        #expect(frame == current)
    }

    @Test func aWindowWiderThanTheScreenKeepsItsLeftEdgeOnScreen() throws {
        let narrow = NSRect(x: 50, y: 100, width: 400, height: 1000)
        let current = NSRect(x: 300, y: 400, width: 500, height: 548)
        let frame = try #require(SettingsWindowFrame.fitted(
            current: current, content: CGSize(width: 500, height: 300), chrome: chrome, visible: narrow))
        #expect(frame.minX == narrow.minX)
    }

    @Test func noFrameBeforeThePaneHasASize() {
        let current = NSRect(x: 0, y: 0, width: 500, height: 500)
        #expect(SettingsWindowFrame.fitted(current: current, content: .zero, chrome: chrome, visible: visible) == nil)
    }
}
