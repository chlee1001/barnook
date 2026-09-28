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
//   probe nc-state                     whether the Notification Center panel is open (Accessibility)
//   probe press-system ID [--display N]  AX-press a system item, com.apple.menuextra.clock and the like
//   probe key CODE [--fn] [--command] [--option] [--control]
//   probe click-press X Y --trigger none|press|key:CODE[+fn]|script --at down|up --delay MS
//                                      one click with a trigger at mouse-down or mouse-up, then
//                                      Notification Center polled every 20 ms for 1500 ms
//   probe double-click X Y --gap MS
//   probe watch-hidden ID,ID,... --for MS   layout reads until MS elapse; which IDs were ever drawn

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

/// The value after `name`, as in `--delay 20`.
func value(of name: String, in args: ArraySlice<String>) -> String? {
    guard let index = args.firstIndex(of: name), args.index(after: index) < args.endIndex else { return nil }
    return args[args.index(after: index)]
}

func milliseconds() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000 }

/// A system item's element from the layout. `display` picks one display;
/// otherwise the first match.
func systemItem(_ id: String, display: Int?) throws -> MenuBarLayout.Item {
    guard let layout = MenuBarLayout.read() else { throw ProbeError(description: "MenuBarAgent did not answer") }
    let displays = display.map { index in layout.displays.indices.contains(index) ? [layout.displays[index]] : [] } ?? layout.displays
    guard let item = displays.lazy.flatMap(\.items).first(where: { $0.systemIdentifier == id }) else {
        throw ProbeError(description: "\(id) is not in the layout")
    }
    return item
}

struct Pressed: Codable {
    var pressed: Bool
    var frame: CGRect
}

/// A key press. `--fn` sets the function (globe) modifier.
func key(_ code: CGKeyCode, options: Set<String>) throws {
    var keyFlags = flags(options)
    if options.contains("--fn") { keyFlags.insert(.maskSecondaryFn) }
    if options.contains("--control") { keyFlags.insert(.maskControl) }
    for down in [true, false] {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else {
            throw ProbeError(description: "cannot make a key event")
        }
        event.flags = keyFlags
        event.post(tap: .cghidEventTap)
        usleep(20_000)
    }
}

/// The trigger of `click-press`, fired at mouse-down or mouse-up.
func fire(_ trigger: String) throws {
    switch trigger {
    case "none":
        return
    case "press":
        _ = try systemItem(MenuBarLayout.clockIdentifier, display: nil).element?.press()
    case "script":
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", "tell application \"System Events\" to key code 45 using {function down}"]
        try task.run()
        task.waitUntilExit()
    case let spec where spec.hasPrefix("key:"):
        let parts = spec.dropFirst(4).split(separator: "+")
        guard let code = parts.first.flatMap({ CGKeyCode($0) }) else { throw ProbeError(description: "bad key trigger \(spec)") }
        try key(code, options: parts.contains("fn") ? ["--fn"] : [])
    default:
        throw ProbeError(description: "unknown trigger \(trigger)")
    }
}

struct ClickPress: Codable {
    var tDown: Double
    var tTrigger: Double?
    var tUp: Double
    var ncOpenedAtMs: Double?
    var openAtStart: Bool
    var openAtEnd: Bool
    /// Every change of the panel state, in ms after mouse-down.
    var transitions: [Double]
}

/// Mouse events posted without the 50 ms settle of `post`, for timing.
func postNow(_ type: CGEventType, at point: CGPoint) throws {
    guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else {
        throw ProbeError(description: "cannot make a \(type) event")
    }
    event.post(tap: .cghidEventTap)
}

@MainActor
func clickPress(at p: CGPoint, trigger: String, atDown: Bool, delay: Double) throws -> ClickPress {
    let openAtStart = NotificationCenterPanel.isOpenNow()
    try post(.mouseMoved, at: p)
    let start = milliseconds()
    try postNow(.leftMouseDown, at: p)
    var tTrigger: Double?
    if atDown {
        usleep(useconds_t(delay * 1000))
        tTrigger = milliseconds() - start
        try fire(trigger)
    }
    // A click lasts about 80 ms from a person.
    let upAt = max(80, (tTrigger ?? 0) + 10)
    while milliseconds() - start < upAt { usleep(1000) }
    let tUp = milliseconds() - start
    try postNow(.leftMouseUp, at: p)
    if !atDown {
        usleep(useconds_t(delay * 1000))
        tTrigger = milliseconds() - start
        try fire(trigger)
    }
    var state = openAtStart
    var transitions: [Double] = []
    var opened: Double?
    while milliseconds() - start < 1500 {
        let now = NotificationCenterPanel.isOpenNow()
        if now != state {
            let t = milliseconds() - start
            transitions.append(t)
            if now, opened == nil { opened = t }
            state = now
        }
        usleep(20_000)
    }
    return ClickPress(
        tDown: 0, tTrigger: trigger == "none" ? nil : tTrigger, tUp: tUp,
        ncOpenedAtMs: opened, openAtStart: openAtStart, openAtEnd: state, transitions: transitions
    )
}

struct Watched: Codable {
    var reads: Int
    /// The watched IDs drawn in any read.
    var drawn: [String]
}

let arguments = CommandLine.arguments.dropFirst()
let options = Set(arguments.filter { $0.hasPrefix("--") })
/// Values that follow an option, as in `--delay 20`, are not positional.
let optionValues: Set<Int> = Set(arguments.indices.filter { index in
    index > arguments.startIndex && arguments[index - 1].hasPrefix("--")
        && ["--display", "--trigger", "--at", "--delay", "--gap", "--for"].contains(arguments[index - 1])
})
let positional = arguments.indices.filter { !arguments[$0].hasPrefix("--") && !optionValues.contains($0) }.map { arguments[$0] }
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
    case "nc-state":
        try emit(["open": NotificationCenterPanel.isOpenNow()])
    case "press-system":
        guard let id = positional.dropFirst().first else { throw ProbeError(description: "expected ID") }
        let item = try systemItem(id, display: value(of: "--display", in: arguments).flatMap { Int($0) })
        try emit(Pressed(pressed: item.element?.press() ?? false, frame: item.frame))
    case "key":
        guard let code = positional.dropFirst().first.flatMap({ CGKeyCode($0) }) else { throw ProbeError(description: "expected CODE") }
        try key(code, options: options)
    case "click-press":
        let p = try point(positional.dropFirst())
        let at = value(of: "--at", in: arguments) ?? "down"
        guard at == "down" || at == "up" else { throw ProbeError(description: "--at is down or up") }
        try emit(try clickPress(
            at: p,
            trigger: value(of: "--trigger", in: arguments) ?? "none",
            atDown: at == "down",
            delay: value(of: "--delay", in: arguments).flatMap { Double($0) } ?? 0
        ))
    case "double-click":
        let p = try point(positional.dropFirst())
        let gap = value(of: "--gap", in: arguments).flatMap { Double($0) } ?? 100
        try post(.mouseMoved, at: p)
        for index in 0..<2 {
            try postNow(.leftMouseDown, at: p)
            usleep(60_000)
            try postNow(.leftMouseUp, at: p)
            if index == 0 { usleep(useconds_t(max(0, gap - 60) * 1000)) }
        }
    case "watch-hidden":
        guard let list = positional.dropFirst().first else { throw ProbeError(description: "expected ID,ID,...") }
        let ids = Set(list.split(separator: ",").map(String.init))
        let span = value(of: "--for", in: arguments).flatMap { Double($0) } ?? 1000
        let start = milliseconds()
        var reads = 0
        var drawn = Set<String>()
        while milliseconds() - start < span {
            if let layout = MenuBarLayout.read() {
                reads += 1
                drawn.formUnion(ids.filter { layout.drawnItem(of: $0) != nil })
            }
        }
        try emit(Watched(reads: reads, drawn: drawn.sorted()))
    default:
        fail("usage: probe layout|menus|screens|move X Y|click X Y [--option] [--command] [--right]|drag X1 Y1 X2 Y2 [--command]|nc-state|press-system ID [--display N]|key CODE [--fn]|click-press X Y --trigger T --at down|up --delay MS|double-click X Y --gap MS|watch-hidden IDS --for MS")
    }
} catch {
    fail("\(error)")
}
