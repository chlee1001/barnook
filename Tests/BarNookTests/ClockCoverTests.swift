import AppKit
import BarNookCore
import Testing
@testable import BarNook

/// A synchronous call that blocks for a second and ignores cancellation,
/// as a hung Accessibility read does.
nonisolated func blockingRead() {
    usleep(1_000_000)
}

/// The strips over the host's three displays: a 1512x982 primary, a
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

    /// A reply from MenuBarAgent that never comes must not hold the cover:
    /// the stuck work ignores cancellation, as a blocking read does.
    @Test func aStuckWaitIsCutOff() async {
        let start = ContinuousClock.now
        let finished = await ClockCover.bounded(.milliseconds(50)) {
            await Task.detached { blockingRead() }.value
        }
        #expect(!finished)
        #expect(ContinuousClock.now - start < .milliseconds(500))
    }

    @Test func aPromptWaitFinishes() async {
        let finished = await ClockCover.bounded(.seconds(2)) {}
        #expect(finished)
    }
}

/// The uncover wait: an unreadable layout is not a settled one.
@Suite struct ClockCoverSettleTests {
    /// Answers the reads in order, then repeats the last.
    final class Reads: @unchecked Sendable {
        private var answers: [Bool?]
        private let lock = NSLock()
        init(_ answers: [Bool?]) { self.answers = answers }
        func next() -> Bool? {
            lock.lock(); defer { lock.unlock() }
            return answers.count > 1 ? answers.removeFirst() : answers.first ?? nil
        }
    }

    @Test func aFailedReadDoesNotEndTheWait() async {
        let reads = Reads([nil, nil, false])
        let result = await ClockCover.settle(cap: .seconds(1), poll: .milliseconds(1)) { reads.next() }
        #expect(result.settled)
        #expect(result.readFailures == 2)
    }

    @Test func onlyFailedReadsNeverSettle() async {
        let result = await ClockCover.settle(cap: .milliseconds(30), poll: .milliseconds(1)) { nil }
        #expect(!result.settled)
        #expect(result.readFailures > 0)
    }

    @Test func hiddenItemsStillDrawnWaitForTheCap() async {
        let result = await ClockCover.settle(cap: .milliseconds(30), poll: .milliseconds(1)) { true }
        #expect(!result.settled)
        #expect(result.readFailures == 0)
    }

    @Test func aSettledLayoutEndsAtOnce() async {
        let reads = Reads([true, false])
        let result = await ClockCover.settle(cap: .seconds(1), poll: .milliseconds(1)) { reads.next() }
        #expect(result.settled)
    }
}

@Suite struct ClockCoverPanelWaitTests {
    @Test func aPanelThatOpensEndsTheWait() async {
        let opened = await ClockCover.waitForPanel(floor: .milliseconds(1), cap: .seconds(1), poll: .milliseconds(1)) { true }
        #expect(opened)
    }

    @Test func aPanelThatNeverOpensStopsAtTheCap() async {
        let start = ContinuousClock.now
        let opened = await ClockCover.waitForPanel(floor: .milliseconds(1), cap: .milliseconds(40), poll: .milliseconds(1)) { false }
        #expect(!opened)
        #expect(ContinuousClock.now - start < .milliseconds(500))
    }

    /// A read that hangs (a blocking Accessibility call, which ignores
    /// cancellation) still ends at the cap.
    @Test func aHangingReadStopsAtTheCap() async {
        let start = ContinuousClock.now
        let opened = await ClockCover.waitForPanel(floor: .milliseconds(1), cap: .milliseconds(40), poll: .milliseconds(1)) {
            await Task.detached { blockingRead(); return true }.value
        }
        #expect(!opened)
        #expect(ContinuousClock.now - start < .milliseconds(500))
    }
}

@Suite struct ClockCoverCropTests {
    /// A width x height image, every pixel opaque.
    func image(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.3, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    func strip(_ local: CGRect, display: CGDirectDisplayID = 1) -> ClockCover.Strip {
        ClockCover.Strip(frame: NSRect(origin: .zero, size: local.size), displayID: display, local: local)
    }

    @Test func aRetinaBandCropsInPixels() throws {
        let band = ClockCover.Band(displayID: 1, image: image(width: 3024, height: 80), scale: 2)
        let pictures = try #require(ClockCover.crop([band], to: [strip(CGRect(x: 0, y: 0, width: 1335, height: 33))]))
        #expect(pictures[0].width == 2670)
        #expect(pictures[0].height == 66)
    }

    @Test func anOffsetStripOnAPlainBandCropsInPoints() throws {
        let band = ClockCover.Band(displayID: 2, image: image(width: 2560, height: 40), scale: 1)
        let pictures = try #require(ClockCover.crop([band], to: [strip(CGRect(x: 100, y: 0, width: 2283, height: 30), display: 2)]))
        #expect(pictures[0].width == 2283)
        #expect(pictures[0].height == 30)
    }

    @Test func aStripWithoutABandHasNoPicture() {
        let band = ClockCover.Band(displayID: 1, image: image(width: 3024, height: 80), scale: 2)
        #expect(ClockCover.crop([band], to: [strip(CGRect(x: 0, y: 0, width: 100, height: 30), display: 9)]) == nil)
    }

    /// A bar taller than the band would be cropped short and stretched.
    @Test func aStripTallerThanTheBandHasNoPicture() {
        let band = ClockCover.Band(displayID: 1, image: image(width: 3024, height: 80), scale: 2)
        #expect(ClockCover.crop([band], to: [strip(CGRect(x: 0, y: 0, width: 1335, height: 44))]) == nil)
    }
}
