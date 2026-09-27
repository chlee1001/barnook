import AppKit

/// The menu bar rectangle of every screen, in Cocoa screen coordinates.
public struct MenuBarGeometry: Sendable {
    public var frames: [NSRect]

    public init(frames: [NSRect]) {
        self.frames = frames
    }

    /// The menu bar is the strip between `visibleFrame.maxY` and `frame.maxY`.
    public init(screens: [NSScreen]) {
        frames = screens.map { screen in
            let frame = screen.frame
            let bottom = screen.visibleFrame.maxY
            return NSRect(x: frame.minX, y: bottom, width: frame.width, height: frame.maxY - bottom)
        }
    }

    @MainActor
    public static var current: MenuBarGeometry { MenuBarGeometry(screens: NSScreen.screens) }

    public func contains(_ point: NSPoint) -> Bool {
        frames.contains { $0.contains(point) }
    }

    /// The menu bar under `point`, if any.
    public func frame(containing point: NSPoint) -> NSRect? {
        frames.first { $0.contains(point) }
    }

    /// The trailing `width` points of any menu bar, where the clock lives.
    public func clockZoneContains(_ point: NSPoint, width: CGFloat) -> Bool {
        frames.contains { bar in
            NSRect(x: bar.maxX - width, y: bar.minY, width: width, height: bar.height).contains(point)
        }
    }

    /// Frames of the menus open on screen, in Cocoa coordinates. Menus are
    /// windows at the pop-up menu level. The window list reads with no
    /// permission; only window names need Screen Recording.
    @MainActor
    public static func openMenuFrames() -> [NSRect] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        // CG coordinates have their origin at the top-left of the primary screen.
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        return list.compactMap { info in
            guard info[kCGWindowLayer as String] as? Int == menuLevel,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds)
            else { return nil }
            return NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
        }
    }
}
