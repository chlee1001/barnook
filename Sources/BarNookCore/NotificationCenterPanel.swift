import AppKit
import ApplicationServices

/// Whether Notification Center's panel is open, read from its Accessibility
/// tree. A banner and the panel share one full-display window at layer 21,
/// so the window list cannot tell them apart (`docs/phase9.md`, D0). In the
/// tree, a banner-only window holds `AXNotificationCenterBanner` groups. The
/// open panel holds the `AXNotificationListItems` group when it lists
/// notifications, and the widget editor button (`widget-editor-button`)
/// either way, so a panel with no notifications still reads open. Needs the
/// Accessibility permission.
public enum NotificationCenterPanel {
    public static let bundleIdentifier = "com.apple.notificationcenterui"
    static let windowTitle = "Notification Center"
    static let panelIdentifiers: Set<String> = ["AXNotificationListItems", "widget-editor-button"]

    /// One node of the tree, reduced to what the decision reads.
    public struct Node: Sendable, Equatable {
        public var identifier: String?
        public var children: [Node]

        public init(identifier: String? = nil, children: [Node] = []) {
            self.identifier = identifier
            self.children = children
        }
    }

    /// Whether any window titled "Notification Center" holds a panel marker (`panelIdentifiers`).
    public static func isOpen(windows: [(title: String?, root: Node)]) -> Bool {
        windows.contains { window in
            window.title == windowTitle && contains(panelIdentifiers, in: window.root, depth: 0)
        }
    }

    private static func contains(_ identifiers: Set<String>, in node: Node, depth: Int) -> Bool {
        if let identifier = node.identifier, identifiers.contains(identifier) { return true }
        guard depth < 6 else { return false }
        return node.children.contains { contains(identifiers, in: $0, depth: depth + 1) }
    }

    /// Reads Notification Center's windows over Accessibility, with a
    /// one-second timeout. Off the main thread: every read is an IPC.
    public nonisolated static func isOpenNow() -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
        else { return false }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 1)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement]
        else { return false }
        return isOpen(windows: windows.map { (string($0, kAXTitleAttribute), node($0, depth: 0)) })
    }

    private static func node(_ element: AXUIElement, depth: Int) -> Node {
        var value: CFTypeRef?
        var children: [Node] = []
        if depth < 6, AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
           let elements = value as? [AXUIElement] {
            children = elements.map { node($0, depth: depth + 1) }
        }
        return Node(identifier: string(element, kAXIdentifierAttribute), children: children)
    }

    private static func string(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
