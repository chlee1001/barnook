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
        /// The same strip, local to the display, top-left origin, for ScreenCaptureKit.
        var local: CGRect
        var scale: CGFloat
    }

    private static let log = Logger(subsystem: "com.chlee1001.BarNook", category: "clockCover")

    /// Resumes one continuation once, with the first answer.
    @MainActor private final class BoundedRace {
        var continuation: CheckedContinuation<Bool, Never>?
        func finish(_ value: Bool) {
            continuation?.resume(returning: value)
            continuation = nil
        }
    }
    private var windows: [NSWindow] = []

    /// A screen as the strip math needs it: its Cocoa frame and display.
    struct Screen: Equatable {
        var frame: NSRect
        var displayID: CGDirectDisplayID
        var scale: CGFloat
    }

    @MainActor static var currentScreens: [Screen] {
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
                local: CGRect(x: frame.minX - screen.frame.minX, y: screen.frame.maxY - frame.maxY, width: frame.width, height: frame.height),
                scale: screen.scale
            ))
        }
        return strips.isEmpty ? nil : strips
    }

    /// Runs one covered lift. `lift` drops the restriction; `reapply` puts it
    /// back and waits for MenuBarAgent, bounded by `reapplyTimeout`;
    /// `hiddenStillDrawn` reads the layout and returns nil when the read
    /// fails. Returns false, having lifted nothing, when a strip cannot be
    /// captured. The covers always come off, by `settleCap` at the latest.
    func run(
        clickAt point: CGPoint,
        strips: [Strip],
        lift: () -> Void,
        reapply: @escaping @MainActor () async -> Void,
        hiddenStillDrawn: @escaping @Sendable () async -> Bool?
    ) async -> Bool {
        let started = ContinuousClock.now
        guard let pictures = await capture(strips) else {
            Self.log.error("capture failed; clock click not replayed")
            return false
        }
        show(pictures, strips: strips)
        try? await Task.sleep(for: ClockCoverPolicy.coverComposite)
        lift()
        try? await Task.sleep(for: ClockCoverPolicy.liftToPress)
        await Self.replayClick(at: point)
        try? await Task.sleep(for: ClockCoverPolicy.pressToReapply)
        let reapplied = await Self.bounded(ClockCoverPolicy.reapplyTimeout, reapply)
        let settleStart = ContinuousClock.now
        var settled = false
        var readFailures = 0
        while ContinuousClock.now - settleStart < ClockCoverPolicy.settleCap {
            switch await hiddenStillDrawn() {
            case false?: settled = true
            case true?: break
            case nil: readFailures += 1  // an unreadable layout is not a settled one
            }
            if settled { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        try? await Task.sleep(for: ClockCoverPolicy.settledToUncover)
        hide()
        let elapsed = ContinuousClock.now - started
        Self.log.info("lift done reapplied=\(reapplied) settled=\(settled) readFailures=\(readFailures) covered=\(elapsed, privacy: .public)")
        return true
    }

    private func capture(_ strips: [Strip]) async -> [CGImage]? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else { return nil }
        var images: [CGImage] = []
        for strip in strips {
            guard let display = content.displays.first(where: { $0.displayID == strip.displayID }) else { return nil }
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = strip.local
            configuration.width = Int(strip.local.width * strip.scale)
            configuration.height = Int(strip.local.height * strip.scale)
            configuration.showsCursor = false
            let filter = SCContentFilter(display: display, excludingWindows: [])
            guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            else { return nil }
            images.append(image)
        }
        return images
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

    private func hide() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    /// Runs `work`, giving up after `limit`. MenuBarAgent's reply to an
    /// activation is a private XPC completion; one that never comes must not
    /// leave the covers up. Returns whether `work` finished in time.
    /// A task group would wait for the stuck child, so `work` runs as its
    /// own task and whichever of it or the timer finishes first answers.
    static func bounded(_ limit: Duration, _ work: @escaping @MainActor () async -> Void) async -> Bool {
        let race = BoundedRace()
        return await withCheckedContinuation { continuation in
            race.continuation = continuation
            Task { @MainActor in
                await work()
                race.finish(true)
            }
            Task { @MainActor in
                try? await Task.sleep(for: limit)
                race.finish(false)
            }
        }
    }

    /// Posts a click at `point`, tagged so BarNook's own monitor skips it.
    /// Cocoa coordinates in, CG (top-left) out.
    private static func replayClick(at point: CGPoint) async {
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
