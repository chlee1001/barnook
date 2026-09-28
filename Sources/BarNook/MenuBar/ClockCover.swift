import AppKit
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
    }

    private static let log = Logger(subsystem: "com.chlee1001.BarNook", category: "clockCover")
    private var windows: [NSWindow] = []

    /// The strip left of the clock on every screen, from the clock's distance
    /// to the right edge (the same on every display).
    static func strips(clockOffset: CGFloat) -> [Strip] {
        NSScreen.screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            else { return nil }
            let height = screen.frame.maxY - screen.visibleFrame.maxY
            let width = screen.frame.width - clockOffset - 4
            guard height > 0, width > 0 else { return nil }
            return Strip(
                frame: NSRect(x: screen.frame.minX, y: screen.frame.maxY - height, width: width, height: height),
                displayID: id,
                local: CGRect(x: 0, y: 0, width: width, height: height)
            )
        }
    }

    /// Runs one covered lift. `lift` drops the restriction; `reapply` puts it
    /// back and returns once MenuBarAgent reported; `hiddenStillDrawn` reads
    /// the layout. Returns false, having lifted nothing, when a strip cannot
    /// be captured.
    func run(
        clickAt point: CGPoint,
        strips: [Strip],
        lift: () -> Void,
        reapply: () async -> Void,
        hiddenStillDrawn: @escaping @Sendable () async -> Bool
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
        Self.replayClick(at: point)
        try? await Task.sleep(for: ClockCoverPolicy.pressToReapply)
        await reapply()
        let settleStart = ContinuousClock.now
        var settled = false
        while ContinuousClock.now - settleStart < ClockCoverPolicy.settleCap {
            if !(await hiddenStillDrawn()) { settled = true; break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        try? await Task.sleep(for: ClockCoverPolicy.settledToUncover)
        hide()
        let elapsed = ContinuousClock.now - started
        Self.log.info("lift done settled=\(settled) covered=\(elapsed, privacy: .public)")
        return true
    }

    private func capture(_ strips: [Strip]) async -> [CGImage]? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else { return nil }
        var images: [CGImage] = []
        for strip in strips {
            guard let display = content.displays.first(where: { $0.displayID == strip.displayID }) else { return nil }
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = strip.local
            let scale = NSScreen.screens.first { $0.frame.contains(NSPoint(x: strip.frame.midX, y: strip.frame.midY)) }?.backingScaleFactor ?? 2
            configuration.width = Int(strip.local.width * scale)
            configuration.height = Int(strip.local.height * scale)
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

    /// Posts a click at `point`, tagged so BarNook's own monitor skips it.
    /// Cocoa coordinates in, CG (top-left) out.
    private static func replayClick(at point: CGPoint) {
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let location = CGPoint(x: point.x, y: primaryHeight - point.y)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: location, mouseButton: .left)
            else { continue }
            event.setIntegerValueField(.eventSourceUserData, value: ClockCoverPolicy.replayTag)
            event.post(tap: .cghidEventTap)
            if type == .leftMouseDown { usleep(60_000) }
        }
    }
}
