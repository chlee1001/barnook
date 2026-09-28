import AppKit

/// D0 window-list signature for Notification Center's full-screen backing
/// window. A notification banner produces the same signature, so this is
/// diagnostic tooling, NOT a reliable product open/closed signal. Desktop
/// widgets use a different layer. The owner is the process bundle identifier
/// (not the localized window-server process name); frames are Cocoa coordinates.
///
/// `owners` and `panelLayer` are the D0 measurement in `docs/phase9.md`.
public enum NotificationCenterPanel {
    public struct Window: Sendable, Equatable {
        public var owner: String
        public var layer: Int
        public var frame: NSRect

        public init(owner: String, layer: Int, frame: NSRect) {
            self.owner = owner
            self.layer = layer
            self.frame = frame
        }
    }

    public struct Display: Sendable, Equatable {
        public var frame: NSRect
        public var visibleFrame: NSRect

        public init(frame: NSRect, visibleFrame: NSRect) {
            self.frame = frame
            self.visibleFrame = visibleFrame
        }
    }

    public static let owners: Set<String> = ["com.apple.notificationcenterui"]
    /// The host's panel backing window is full-display at layer 21.
    public static let panelLayer = 21

    /// Points of slack for the edge checks.
    static let slack: CGFloat = 2

    public static func isPanel(
        _ window: Window, displays: [Display],
        owners: Set<String> = owners, panelLayer: Int = panelLayer
    ) -> Bool {
        guard owners.contains(window.owner), window.layer == panelLayer else { return false }
        let mid = NSPoint(x: window.frame.midX, y: window.frame.midY)
        guard let display = displays.first(where: { $0.frame.contains(mid) }) else { return false }
        return abs(window.frame.minX - display.frame.minX) <= slack
            && abs(window.frame.minY - display.frame.minY) <= slack
            && abs(window.frame.maxX - display.frame.maxX) <= slack
            && abs(window.frame.maxY - display.frame.maxY) <= slack
    }

    public static func isOpen(
        _ windows: [Window], displays: [Display],
        owners: Set<String> = owners, panelLayer: Int = panelLayer
    ) -> Bool {
        windows.contains { isPanel($0, displays: displays, owners: owners, panelLayer: panelLayer) }
    }

    /// On-screen windows belonging to Notification Center, independent of
    /// the user's display language.
    @MainActor
    public static func currentWindows() -> [Window] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        // CG coordinates have their origin at the top-left of the primary screen.
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        return list.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.notificationcenterui",
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds)
            else { return nil }
            return Window(
                owner: "com.apple.notificationcenterui", layer: layer,
                frame: NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
            )
        }
    }

    @MainActor
    public static func currentDisplays() -> [Display] {
        NSScreen.screens.map { Display(frame: $0.frame, visibleFrame: $0.visibleFrame) }
    }

    @MainActor
    public static var isOpenNow: Bool { isOpen(currentWindows(), displays: currentDisplays()) }
}
