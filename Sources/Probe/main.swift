import AppKit
import BarNookCore
import Foundation

// The one process that touches the guest's screen in a VM test. The tests
// on the host run it over ssh and decode its JSON. Points are in
// Accessibility coordinates: origin at the top left of the primary display,
// the same as the frames in `layout`.
//
//   probe layout                       the menu bar items of every display
//   probe inspect [BUNDLE_ID]          the Accessibility tree of an app's windows, MenuBarAgent by default
//   probe menus                        the frames of the open menus
//   probe screens                      the frame and safe area insets of every screen
//   probe move X Y
//   probe click X Y [--option] [--command] [--right]
//   probe drag X1 Y1 X2 Y2 [--command]

struct ProbeError: Error, CustomStringConvertible {
    var description: String
}

struct Screen: Codable {
    var frame: CGRect
    var safeAreaTop: CGFloat
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func emit<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(value))
    FileHandle.standardOutput.write(Data("\n".utf8))
}

/// One node of an app's Accessibility tree, as JSON.
struct Node: Codable {
    var owner: String
    var role: String?
    var subrole: String?
    var title: String?
    var description: String?
    var value: String?
    var identifier: String?
    var frame: CGRect?
    var actions: [String]
    var children: [Node]
}

func node(_ element: AXUIElement, depth: Int) -> Node {
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)
    func string(_ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value else { return nil }
        return value as? String ?? (value as? NSNumber)?.stringValue
    }
    func axValue(_ name: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }
    var actions: CFArray?
    AXUIElementCopyActionNames(element, &actions)
    var frame: CGRect?
    var origin = CGPoint.zero
    var size = CGSize.zero
    if let position = axValue(kAXPositionAttribute), AXValueGetValue(position, .cgPoint, &origin),
       let extent = axValue(kAXSizeAttribute), AXValueGetValue(extent, .cgSize, &size) {
        frame = CGRect(origin: origin, size: size)
    }
    var children: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
    return Node(
        owner: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "pid \(pid)",
        role: string(kAXRoleAttribute),
        subrole: string(kAXSubroleAttribute),
        title: string(kAXTitleAttribute),
        description: string(kAXDescriptionAttribute),
        value: string(kAXValueAttribute),
        identifier: string(kAXIdentifierAttribute),
        frame: frame,
        actions: actions as? [String] ?? [],
        children: depth < 6 ? (children as? [AXUIElement] ?? []).map { node($0, depth: depth + 1) } : []
    )
}

func point(_ args: ArraySlice<String>) throws -> CGPoint {
    guard args.count >= 2, let x = Double(args[args.startIndex]), let y = Double(args[args.startIndex + 1]) else {
        throw ProbeError(description: "expected X Y")
    }
    return CGPoint(x: x, y: y)
}

func flags(_ options: Set<String>) -> CGEventFlags {
    var flags = CGEventFlags()
    if options.contains("--option") { flags.insert(.maskAlternate) }
    if options.contains("--command") { flags.insert(.maskCommand) }
    return flags
}

/// Posts one event and gives the window server time to deliver it.
func post(_ type: CGEventType, at point: CGPoint, button: CGMouseButton = .left, flags: CGEventFlags = []) throws {
    guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: button) else {
        throw ProbeError(description: "cannot make a \(type) event")
    }
    event.flags = flags
    event.post(tap: .cghidEventTap)
    usleep(50_000)
}

/// AX coordinates for a Cocoa rect on the primary display.
@MainActor
func flipped(_ rect: NSRect) -> CGRect {
    let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
    return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
}

let arguments = CommandLine.arguments.dropFirst()
let options = Set(arguments.filter { $0.hasPrefix("--") })
let positional = arguments.filter { !$0.hasPrefix("--") }
let button: CGMouseButton = options.contains("--right") ? .right : .left

do {
    switch positional.first {
    case "layout":
        guard let layout = MenuBarLayout.read() else { throw ProbeError(description: "MenuBarAgent did not answer") }
        try emit(layout)
    case "inspect":
        let bundleID = positional.dropFirst().first ?? "com.apple.MenuBarAgent"
        guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        else { throw ProbeError(description: "\(bundleID) is not running") }
        let app = AXUIElementCreateApplication(running.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 1)
        var windows: CFTypeRef?
        AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows)
        try emit((windows as? [AXUIElement] ?? []).map { node($0, depth: 0) })
    case "menus":
        try emit(MenuBarGeometry.openMenuFrames().map(flipped))
    case "screens":
        try emit(NSScreen.screens.map { Screen(frame: flipped($0.frame), safeAreaTop: $0.safeAreaInsets.top) })
    case "move":
        try post(.mouseMoved, at: try point(positional.dropFirst()))
    case "click":
        let p = try point(positional.dropFirst())
        try post(.mouseMoved, at: p)
        try post(button == .right ? .rightMouseDown : .leftMouseDown, at: p, button: button, flags: flags(options))
        try post(button == .right ? .rightMouseUp : .leftMouseUp, at: p, button: button, flags: flags(options))
    case "drag":
        let from = try point(positional.dropFirst())
        let to = try point(positional.dropFirst(3))
        try post(.mouseMoved, at: from)
        try post(.leftMouseDown, at: from, flags: flags(options))
        for step in 1...10 {
            let t = CGFloat(step) / 10
            let p = CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
            try post(.leftMouseDragged, at: p, flags: flags(options))
        }
        try post(.leftMouseUp, at: to, flags: flags(options))
    default:
        fail("usage: probe layout|menus|screens|move X Y|click X Y [--option] [--command] [--right]|drag X1 Y1 X2 Y2 [--command]")
    }
} catch {
    fail("\(error)")
}
