// Modified by Chaehyeon Lee (2026): fork overflow marker identity; clock hit test and hidden-owner check; left split in menu bar order.
import AppKit
import ApplicationServices

/// The items MenuBarAgent shows on each display, read over Accessibility.
/// Each display has one MenuBarAgent window whose children are the item
/// slots. A slot's child is owned by the app that draws the item, or by
/// MenuBarAgent for a system item. Only MenuBarAgent is asked anything: the
/// owner comes from the element's pid, so an unresponsive app cannot stall
/// the read. Nothing here works without the Accessibility permission.
public struct MenuBarLayout: Sendable, Codable {
    public struct Item: Sendable, Codable {
        /// Bundle identifier of the app that owns the item, nil for a system item.
        public var bundleIdentifier: String?
        /// `com.apple.menuextra.clock` and the like, nil for an app item.
        public var systemIdentifier: String?
        /// Accessibility coordinates: origin at the top left of the primary display.
        public var frame: CGRect
        /// The element that draws the item, for `press`. Not encoded.
        public var element: AccessibilityElement?

        enum CodingKeys: CodingKey {
            case bundleIdentifier, systemIdentifier, frame
        }

        public init(
            bundleIdentifier: String? = nil,
            systemIdentifier: String? = nil,
            frame: CGRect,
            element: AccessibilityElement? = nil
        ) {
            self.bundleIdentifier = bundleIdentifier
            self.systemIdentifier = systemIdentifier
            self.frame = frame
            self.element = element
        }
    }

    /// An `AXUIElement` that may cross threads. The element is a token for
    /// an IPC endpoint; every call on it is its own round trip.
    public struct AccessibilityElement: @unchecked Sendable {
        let element: AXUIElement

        /// Presses the element as a click would, with a one-second timeout
        /// so an unresponsive app does not stall the caller. Off the main
        /// thread: it is an IPC.
        public nonisolated func press() -> Bool {
            AXUIElementSetMessagingTimeout(element, 1)
            return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
        }
    }

    public struct Display: Sendable, Codable {
        /// The menu bar, in Accessibility coordinates.
        public var frame: CGRect
        public var items: [Item]

        public init(frame: CGRect, items: [Item]) {
            self.frame = frame
            self.items = items
        }
    }

    public var displays: [Display]

    public init(displays: [Display]) {
        self.displays = displays
    }

    public static let clockIdentifier = "com.apple.menuextra.clock"

    /// The `«` button macOS 27 draws where it collapsed the items that did
    /// not fit. Not a menu extra: the identifier is ours.
    public static let overflowIdentifier = "com.chlee1001.BarNook.overflow"

    /// Points from the right edge of the menu bar to the left edge of the
    /// clock. System items sit at the same offset on every display.
    public var clockOffset: CGFloat? {
        for display in displays {
            if let clock = display.items.first(where: { $0.systemIdentifier == Self.clockIdentifier }) {
                return display.frame.maxX - clock.frame.minX
            }
        }
        return nil
    }

    /// The clock item under `point`, with a 2-point margin: a click on the
    /// clock's edge still counts. Accessibility coordinates.
    public func clock(at point: CGPoint) -> Item? {
        for display in displays {
            for item in display.items where item.systemIdentifier == Self.clockIdentifier {
                if item.frame.insetBy(dx: -2, dy: -2).contains(point) { return item }
            }
        }
        return nil
    }

    /// Whether an item of any app in `bundleIdentifiers` is in the layout,
    /// drawn or collapsed. After a restriction lands, a hidden app has none.
    public func containsItem(ofAny bundleIdentifiers: Set<String>) -> Bool {
        displays.contains { display in
            display.items.contains { $0.bundleIdentifier.map(bundleIdentifiers.contains) ?? false }
        }
    }

    /// The app items on the display that holds `point`, split by their left
    /// edge against `point.x`. Accessibility coordinates. `left` lists each
    /// app once, in menu bar order from left to right; items at the same x,
    /// as collapsed items are, keep their Accessibility order.
    public func appItems(splitAt point: CGPoint) -> (left: [String], right: Set<String>)? {
        guard let display = displays.first(where: { $0.frame.contains(point) }) else { return nil }
        let ordered = display.items.enumerated().sorted {
            ($0.element.frame.minX, $0.offset) < ($1.element.frame.minX, $1.offset)
        }
        var left: [String] = []
        var seen = Set<String>()
        var right = Set<String>()
        for (_, item) in ordered {
            guard let id = item.bundleIdentifier else { continue }
            if item.frame.minX < point.x {
                if seen.insert(id).inserted { left.append(id) }
            } else {
                right.insert(id)
            }
        }
        return (left, right)
    }

    /// The item of `bundleIdentifier`, if it is drawn. macOS 27 collapses
    /// the items that do not fit: they keep a frame, stacked on top of one
    /// another at the left end of the region, and the `«` button is drawn
    /// where the drawn items start. So an item is not on screen when its
    /// frame overlaps another's, or starts left of the button. The second
    /// test matters when one item alone collapses: nothing stacks on it.
    public func drawnItem(of bundleIdentifier: String) -> Item? {
        for display in displays {
            guard let item = display.items.first(where: { $0.bundleIdentifier == bundleIdentifier }) else { continue }
            let overlapped = display.items.contains { other in
                other.bundleIdentifier != bundleIdentifier
                    && other.frame.intersection(item.frame).width > 2
            }
            let overflow = display.items.first { $0.systemIdentifier == Self.overflowIdentifier }
            let collapsed = overflow.map { item.frame.minX < $0.frame.minX } ?? false
            return overlapped || collapsed ? nil : item
        }
        return nil
    }

    /// Reads until two reads in a row agree, since MenuBarAgent moves items
    /// for a while after a restriction changes. With `previous`, the layout
    /// must first differ from it: a new restriction takes a moment to land,
    /// and the old layout would pass as settled. Gives up after `attempts`
    /// reads and returns the last one. Off the main thread.
    public nonisolated static func readSettled(
        after previous: MenuBarLayout? = nil, attempts: Int = 8, interval: Duration = .milliseconds(250)
    ) async -> MenuBarLayout? {
        var last: MenuBarLayout?
        var changed = previous == nil
        for _ in 0..<attempts {
            try? await Task.sleep(for: interval)
            let now = read()
            if !changed {
                changed = now.map { previous.map($0.sameFrames(as:)) == false } ?? false
                if !changed { continue }
            }
            if let now, let last, now.sameFrames(as: last) { return now }
            last = now
        }
        return last
    }

    public func sameFrames(as other: MenuBarLayout) -> Bool {
        displays.count == other.displays.count && zip(displays, other.displays).allSatisfy { a, b in
            a.items.count == b.items.count && zip(a.items, b.items).allSatisfy {
                $0.bundleIdentifier == $1.bundleIdentifier && $0.systemIdentifier == $1.systemIdentifier && $0.frame == $1.frame
            }
        }
    }

    /// Nil when MenuBarAgent is not running or refuses, as it does without
    /// the permission. Off the main thread: every read is an IPC.
    public nonisolated static func read() -> MenuBarLayout? {
        guard let agent = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first
        else { return nil }
        let agentPID = agent.processIdentifier
        let app = AXUIElementCreateApplication(agentPID)
        AXUIElementSetMessagingTimeout(app, 1)
        guard let windows: [AXUIElement] = app.attribute(kAXWindowsAttribute) else { return nil }
        let displays = windows.map { window in
            let items = window.children.compactMap { slot -> Item? in
                guard let frame = slot.frame else { return nil }
                guard let owner = slot.children.first else {
                    // The `«` button is the one childless slot, an AXButton.
                    let role: String? = slot.attribute(kAXRoleAttribute)
                    return role == kAXButtonRole ? Item(systemIdentifier: overflowIdentifier, frame: frame) : nil
                }
                var pid: pid_t = 0
                AXUIElementGetPid(owner, &pid)
                if pid == agentPID {
                    let identifier: String? = owner.children.first?.attribute(kAXIdentifierAttribute)
                    return Item(systemIdentifier: identifier, frame: frame)
                }
                let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
                return Item(bundleIdentifier: bundleID, frame: frame, element: AccessibilityElement(element: owner))
            }
            return Display(frame: window.frame ?? .zero, items: items)
        }
        return MenuBarLayout(displays: displays)
    }
}

private extension AXUIElement {
    func attribute<T>(_ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    var children: [AXUIElement] {
        attribute(kAXChildrenAttribute) ?? []
    }

    var frame: CGRect? {
        guard let position: AXValue = attribute(kAXPositionAttribute),
              let size: AXValue = attribute(kAXSizeAttribute)
        else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        AXValueGetValue(position, .cgPoint, &origin)
        AXValueGetValue(size, .cgSize, &extent)
        return CGRect(origin: origin, size: extent)
    }
}
