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

    @Test func noFrameBeforeThePaneHasASize() {
        let current = NSRect(x: 0, y: 0, width: 500, height: 500)
        #expect(SettingsWindowFrame.fitted(current: current, content: .zero, chrome: chrome, visible: visible) == nil)
    }
}
