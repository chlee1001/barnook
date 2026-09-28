import AppKit
import BarNookCore
import os
import ScreenCaptureKit

/// Opens Notification Center from a clock click in bar mode without showing
/// the hidden items. MenuBarAgent ignores clicks on its own items while an
/// assertion is held, and draws every hidden item the moment the assertion
/// lifts, on every display at once. So each menu bar's status strip is
/// covered with a picture of itself, the restriction lifts, the click is
/// replayed, the restriction returns, and the covers come off once the
/// layout no longer has a hidden app. Needs Screen Recording for the
/// pictures and Accessibility for the layout. See `docs/phase9.md`.
@MainActor
final class ClockCover {
    struct Strip {
        /// The status-item strip in Cocoa screen coordinates.
        var frame: NSRect
        var displayID: CGDirectDisplayID
        /// The same strip, local to the display, top-left origin; the band
        /// picture is cropped to it.
        var local: CGRect
    }

    private static let log = Logger(subsystem: "com.chlee1001.BarNook", category: "clockCover")

    private var windows: [NSWindow] = []

    /// A screen as the strip math needs it: its Cocoa frame, display and
    /// backing scale.
    struct Screen: Equatable {
        var frame: NSRect
        var displayID: CGDirectDisplayID
        var scale: CGFloat
    }

    static var currentScreens: [Screen] {
        NSScreen.screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            else { return nil }
            return Screen(frame: screen.frame, displayID: id, scale: screen.backingScaleFactor)
        }
    }

    /// The strip left of the clock on every distinct menu bar in `layout`,
    /// or nil when one of them yields none: a bar left uncovered would show
    /// every hidden item during the lift, so the lift does not happen. The
    /// layout, not `visibleFrame`, gives the bar: a display whose menu bar
    /// hides itself reports no menu bar in `visibleFrame`. `layout` is in
    /// Accessibility coordinates, top-left of the primary screen (`screens[0]`).
    nonisolated static func strips(layout: MenuBarLayout, screens: [Screen]) -> [Strip]? {
        guard let primaryHeight = screens.first?.frame.maxY else { return nil }
        var seen = Set<String>()
        var strips: [Strip] = []
        for display in layout.displays {
            let bar = display.frame
            guard seen.insert("\(bar)").inserted else { continue }  // one bar reported twice
            guard let clock = display.items.first(where: { $0.systemIdentifier == MenuBarLayout.clockIdentifier })
            else { return nil }
            let frame = NSRect(x: bar.minX, y: primaryHeight - bar.maxY, width: clock.frame.minX - bar.minX - 4, height: bar.height)
            guard frame.width > 0, frame.height > 0,
                  let screen = screens.first(where: { $0.frame.contains(NSPoint(x: frame.midX, y: frame.midY)) })
            else { return nil }
            strips.append(Strip(
                frame: frame,
                displayID: screen.displayID,
                local: CGRect(x: frame.minX - screen.frame.minX, y: screen.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
            ))
        }
        return strips.isEmpty ? nil : strips
    }

    /// Covers every strip with its picture. False, covering nothing, when a
    /// strip has no picture.
    func cover(_ strips: [Strip], bands: [Band]) -> Bool {
        guard let pictures = Self.crop(bands, to: strips) else {
            Self.log.error("capture missing for a menu bar; not covering")
            return false
        }
        show(pictures, strips: strips)
        return true
    }

    /// Removes the covers once the layout no longer has a hidden app, plus
    /// the crossfade: at most `settleCap` after the call, plus the last read
    /// and `settledToUncover`.
    func uncoverWhenSettled(_ hiddenStillDrawn: @escaping @Sendable () async -> Bool?) async -> (settled: Bool, readFailures: Int) {
        let result = await Self.settle(cap: ClockCoverPolicy.settleCap, poll: .milliseconds(20), hiddenStillDrawn)
        try? await Task.sleep(for: ClockCoverPolicy.settledToUncover)
        hide()
        return result
    }

    /// Polls `hiddenStillDrawn` until it reports false or `cap` passes. A nil
    /// read (the layout could not be read) is not a settled layout: it is
    /// counted and the wait goes on.
    static func settle(
        cap: Duration, poll: Duration, _ hiddenStillDrawn: @escaping @Sendable () async -> Bool?
    ) async -> (settled: Bool, readFailures: Int) {
        let start = ContinuousClock.now
        var readFailures = 0
        while ContinuousClock.now - start < cap {
            switch await hiddenStillDrawn() {
            case false?: return (true, readFailures)
            case true?: break
            case nil: readFailures += 1
            }
            try? await Task.sleep(for: poll)
        }
        return (false, readFailures)
    }

    /// Puts the restriction back, bounded by `reapplyTimeout`, then removes
    /// the covers once the layout has settled. Shared by the click path and
    /// the hover pre-lift.
    func restore(
        reapply: @escaping @MainActor () async -> Void,
        hiddenStillDrawn: @escaping @Sendable () async -> Bool?
    ) async -> (reapplied: Bool, settled: Bool, readFailures: Int) {
        let reapplied = await Self.bounded(ClockCoverPolicy.reapplyTimeout, reapply)
        if !reapplied {
            Self.log.error("reapply not confirmed within \(ClockCoverPolicy.reapplyTimeout, privacy: .public); uncovering on the layout check")
        }
        let (settled, readFailures) = await uncoverWhenSettled(hiddenStillDrawn)
        return (reapplied, settled, readFailures)
    }

    /// One covered lift for a click that MenuBarAgent ignored: cover, lift,
    /// replay the click, reapply once the panel opens (bounded), uncover.
    /// Returns whether the panel opened; false, having lifted nothing, when a
    /// strip has no picture.
    /// The covers come off at most `pressToReapplyCap` + `reapplyTimeout` +
    /// `settleCap` after the replay, plus the last read and `settledToUncover`.
    func run(
        clickAt point: CGPoint,
        strips: [Strip],
        bands: [Band],
        lift: () -> Void,
        reapply: @escaping @MainActor () async -> Void,
        panelOpen: @escaping @Sendable () async -> Bool,
        hiddenStillDrawn: @escaping @Sendable () async -> Bool?
    ) async -> Bool {
        let started = ContinuousClock.now
        guard cover(strips, bands: bands) else { return false }
        try? await Task.sleep(for: ClockCoverPolicy.coverComposite)
        lift()
        try? await Task.sleep(for: ClockCoverPolicy.liftToPress)
        await Self.replayClick(at: point)
        let opened = await Self.waitForPanel(panelOpen)
        let (reapplied, settled, readFailures) = await restore(reapply: reapply, hiddenStillDrawn: hiddenStillDrawn)
        let elapsed = ContinuousClock.now - started
        Self.log.info("lift done opened=\(opened) reapplied=\(reapplied) settled=\(settled) readFailures=\(readFailures) covered=\(elapsed, privacy: .public)")
        return opened
    }

    /// Waits for the panel after a replayed click: MenuBarAgent handles it up
    /// to about 450 ms late while it lays out the lift, and a reapply before
    /// then swallows it.
    static func waitForPanel(
        floor: Duration = ClockCoverPolicy.pressToReapply,
        cap: Duration = ClockCoverPolicy.pressToReapplyCap,
        poll: Duration = .milliseconds(25),
        _ panelOpen: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        try? await Task.sleep(for: floor)
        let deadline = ContinuousClock.now + (cap - floor)
        // The cap bounds the whole wait, a hung read included; the polling
        // task stops at the deadline on its own.
        return await raced(cap - floor, timeout: false) {
            while ContinuousClock.now < deadline {
                if await panelOpen() { return true }
                try? await Task.sleep(for: poll)
            }
            return false
        }
    }

    /// The top of one display, captured before the layout is known, so the
    /// capture runs alongside the layout read.
    struct Band {
        var displayID: CGDirectDisplayID
        var image: CGImage
        /// Points to pixels.
        var scale: CGFloat
    }

    /// The display list ScreenCaptureKit needs, kept between clicks: asking
    /// for it costs about 100 ms. Refreshed when the screens change or a
    /// display is missing.
    private var content: SCShareableContent?

    func screensChanged() {
        content = nil
    }

    /// The top `ClockCover.bandHeight` points of every screen.
    func captureBands(_ screens: [Screen]) async -> [Band]? {
        if content == nil || screens.contains(where: { screen in !(content?.displays.contains { $0.displayID == screen.displayID } ?? false) }) {
            do {
                content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            } catch {
                Self.log.error("display list failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        guard let content else { return nil }
        var bands: [Band] = []
        for screen in screens {
            guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else { return nil }
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = CGRect(x: 0, y: 0, width: screen.frame.width, height: Self.bandHeight)
            configuration.width = Int(screen.frame.width * screen.scale)
            configuration.height = Int(Self.bandHeight * screen.scale)
            configuration.showsCursor = false
            let filter = SCContentFilter(display: display, excludingWindows: [])
            do {
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                bands.append(Band(displayID: screen.displayID, image: image, scale: screen.scale))
            } catch {
                // A display that changed under the cached list fails here;
                // the next capture fetches the list again.
                self.content = nil
                Self.log.error("capture failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        return bands
    }

    /// Tall enough for any menu bar; the strips crop it to the bar's height.
    /// The clock pre-filter uses the same band.
    static let bandHeight: CGFloat = 40

    /// Each strip's picture, cut from its display's band; nil when a strip
    /// has no band.
    nonisolated static func crop(_ bands: [Band], to strips: [Strip]) -> [CGImage]? {
        var pictures: [CGImage] = []
        for strip in strips {
            guard let band = bands.first(where: { $0.displayID == strip.displayID }) else { return nil }
            let rect = CGRect(
                x: strip.local.minX * band.scale, y: strip.local.minY * band.scale,
                width: strip.local.width * band.scale, height: strip.local.height * band.scale
            ).integral
            // A strip outside the band would be cropped short and stretched.
            guard CGRect(x: 0, y: 0, width: band.image.width, height: band.image.height).contains(rect),
                  let picture = band.image.cropping(to: rect)
            else { return nil }
            pictures.append(picture)
        }
        return pictures
    }

    private func show(_ pictures: [CGImage], strips: [Strip]) {
        hide()
        for (picture, strip) in zip(pictures, strips) {
            let window = NSWindow(contentRect: strip.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
            window.isOpaque = true
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            // The default window animation zooms the cover in from a smaller
            // frame and fades it out: its picture scales, so the status icons
            // appear to jump and slide back. The cover must appear and go at once.
            window.animationBehavior = .none
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            let view = NSImageView(frame: NSRect(origin: .zero, size: strip.frame.size))
            view.imageScaling = .scaleAxesIndependently
            view.image = NSImage(cgImage: picture, size: strip.frame.size)
            window.contentView = view
            window.setFrame(strip.frame, display: false)
            window.orderFrontRegardless()
            window.display()
            windows.append(window)
        }
    }

    /// Takes the covers down at once, when a lift does not happen.
    func hideNow() {
        hide()
    }

    private func hide() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    /// Resumes one continuation once, with the first answer.
    @MainActor private final class Race<T: Sendable> {
        var continuation: CheckedContinuation<T, Never>?
        func finish(_ value: sending T) {
            continuation?.resume(returning: value)
            continuation = nil
        }
    }

    /// The first of `work` and a `limit` timer; the timer answers `timeout`.
    /// A task group would wait for a stuck child (a synchronous
    /// Accessibility read, a private XPC reply that never comes), so `work`
    /// runs as its own task and whichever finishes first answers; the loser
    /// finishes on its own.
    static func raced<T: Sendable>(_ limit: Duration, timeout: T, _ work: @escaping @MainActor () async -> T) async -> T {
        let race = Race<T>()
        return await withCheckedContinuation { continuation in
            race.continuation = continuation
            Task { @MainActor in
                race.finish(await work())
            }
            Task { @MainActor in
                try? await Task.sleep(for: limit)
                race.finish(timeout)
            }
        }
    }

    /// Runs `work`, giving up after `limit`. MenuBarAgent's reply to an
    /// activation is a private XPC completion; one that never comes must not
    /// leave the covers up. Returns whether `work` finished in time.
    static func bounded(_ limit: Duration, _ work: @escaping @MainActor () async -> Void) async -> Bool {
        await raced(limit, timeout: false) {
            await work()
            return true
        }
    }

    /// Posts a click at `point`, tagged so BarNook's own monitor skips it.
    /// Cocoa coordinates in, CG (top-left) out.
    static func replayClick(at point: CGPoint) async {
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let location = CGPoint(x: point.x, y: primaryHeight - point.y)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: location, mouseButton: .left)
            else { continue }
            event.setIntegerValueField(.eventSourceUserData, value: ClockCoverPolicy.replayTag)
            event.post(tap: .cghidEventTap)
            if type == .leftMouseDown { try? await Task.sleep(for: ClockCoverPolicy.replayClickHold) }
        }
    }
}
