// Modified by Chaehyeon Lee (2026): fork bundle IDs for guest fixtures.
import EllipsisCore
import Foundation
import Testing

/// The Tart guest named by `ELLIPSIS_VM`, reached through `scripts/vm.sh`.
/// The apps and the probe are already in the guest: `scripts/vm-test.sh`
/// puts them there before `swift test` starts.
struct Guest: Sendable {
    static let name = ProcessInfo.processInfo.environment["ELLIPSIS_VM"]
    static var isConfigured: Bool { name != nil }

    static let appIdentifier = "com.chlee1001.BarNookDev"
    static let appName = "BarNookDev"

    struct CommandFailure: Error, CustomStringConvertible {
        var command: String
        var status: Int32
        var output: String
        var description: String { "`\(command)` exited \(status): \(output)" }
    }

    private static let script = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("scripts/vm.sh").path

    /// Runs a shell command in the guest and returns its output.
    @discardableResult
    func run(_ command: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.script)
        process.arguments = ["ssh", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw CommandFailure(command: command, status: process.terminationStatus, output: output)
        }
        return output
    }

    func probe<T: Decodable>(_ arguments: String, as type: T.Type = T.self) throws -> T {
        let output = try run("./probe \(arguments)")
        return try JSONDecoder().decode(type, from: Data(output.utf8))
    }

    func probe(_ arguments: String) throws {
        try run("./probe \(arguments)")
    }

    // MARK: Apps

    func launch(_ app: String) throws {
        try run("open /Applications/\(app).app")
    }

    func quit(_ app: String) throws {
        try run("pkill -x \(app) || true")
        try waitUntil("\(app) quits") { try run("pgrep -x \(app) || true").isEmpty }
    }

    func kill(_ app: String) throws {
        try run("pkill -9 -x \(app) || true")
    }

    func frontmostApp() throws -> String {
        try run("osascript -e 'tell application \"System Events\" to get name of first process whose frontmost is true'")
    }

    func isRunning(_ app: String) throws -> Bool {
        try !run("pgrep -x \(app) || true").isEmpty
    }

    /// MenuBarAgent's layout table. It remembers where each status item
    /// was, as points from the right edge, across launches of the app. A
    /// Cmd-drag in one test would move the icon for every test after it.
    private static let layoutTable = "\"$HOME/Library/Group Containers/com.apple.MenuBar/Library/Preferences/com.apple.MenuBar\""

    private func setPosition(_ key: String, _ pointsFromRight: Int) throws {
        try run("defaults write \(Self.layoutTable) TrailingItemPreferredPositions -dict-add '\(key)' -float \(pointsFromRight)")
    }

    /// Where the icon lands when Ellipsis launches, left of the fixtures.
    static let iconPosition = 500

    /// Where a quit fixture lands at its next launch.
    func placeFixture(_ identifier: String, pointsFromRight: Int) throws {
        try setPosition("status:\(identifier)::Item-0", pointsFromRight)
    }

    /// The fixtures' remembered positions, points from the right edge.
    private func fixturePositions() throws -> [String: Double] {
        let json = try run("plutil -convert json -o - \(Self.layoutTable).plist")
        let table = try JSONDecoder().decode([String: [String: Double]].self, from: Data(json.utf8))
        var positions: [String: Double] = [:]
        for id in Fixture.all {
            positions[id] = table["TrailingItemPreferredPositions"]?["status:\(id)::Item-0"]
        }
        return positions
    }

    private func visibleFixtures() throws -> [String] {
        try items().compactMap(\.bundleIdentifier).filter { Fixture.all.contains($0) }
    }

    /// Every test starts with no Ellipsis and the three fixtures in the
    /// menu bar in the order A, B, C, right of where the icon will launch,
    /// whatever the last test left behind. A test that moved a fixture, or
    /// relaunched one elsewhere, gets them all relaunched in place. The
    /// layout table lags behind a drag and the bar lags behind a relaunch,
    /// so both are checked.
    func startFixtures() throws {
        try quit(Self.appName)
        try quit(Fixture.wideName)
        try quit(Fixture.widerName)
        try run("pkill -x 'System Settings' || true")  // a stray click on a notification opens it
        try waitUntilSettled()
        let positions = try fixturePositions()
        let ordered = Fixture.all.map { positions[$0] ?? .infinity }
        let inPlace = ordered == ordered.sorted(by: >) && ordered.allSatisfy { $0 < Double(Self.iconPosition) }
        if try !inPlace || visibleFixtures() != Fixture.all {
            for id in Fixture.all {
                try quit(Fixture.name(id))
            }
            // MenuBarAgent saves its own positions a moment after an item
            // leaves, over anything written before that.
            let wanted = Dictionary(uniqueKeysWithValues: Fixture.all.enumerated().map { ($1, Double(300 - $0 * 50)) })
            try waitUntil("the fixture positions are written") {
                for (id, position) in wanted {
                    try placeFixture(id, pointsFromRight: Int(position))
                }
                Thread.sleep(forTimeInterval: 0.5)
                return try fixturePositions() == wanted
            }
            for id in Fixture.all {
                try launch(Fixture.name(id))
            }
        }
        try waitUntil("the fixtures are in the menu bar in order") { try visibleFixtures() == Fixture.all }
    }

    // MARK: Ellipsis

    /// Quits Ellipsis, replaces its settings with `settings` plus what a test
    /// needs to run unattended (no permission dialog, no rehide unless asked
    /// for), and launches it again.
    func launchEllipsis(_ settings: [String: Setting] = [:]) throws {
        try quit(Self.appName)
        try run("defaults delete \(Self.appIdentifier) 2>/dev/null || true")
        try setPosition("status:\(Self.appIdentifier)::barnook.icon", Self.iconPosition)
        var all: [String: Setting] = [
            "accessibilityDeclined": .bool(true),
            "rehideOnTimeout": .bool(false),
            "rehideOnClickOutside": .bool(false),
            "rehideOnFocusChange": .bool(false),
            // The default, 300, covers the icon on the guest's 1024-point
            // display, and the pointer in the zone lifts the restriction.
            "clockZoneWidth": .double(150),
        ]
        all.merge(settings) { _, new in new }
        for (key, value) in all.sorted(by: { $0.key < $1.key }) {
            try run("defaults write \(Self.appIdentifier) \(key) \(value.argument)")
        }
        try launch(Self.appName)
        try waitUntil("the BarNook icon appears") { try iconFrame() != nil }
        try waitUntilSettled()
    }

    /// A new item appears, then MenuBarAgent moves it to its remembered
    /// place. Two reads that agree mean the layout is done.
    func waitUntilSettled(sourceLocation: SourceLocation = #_sourceLocation) throws {
        var last = try items().map(\.frame)
        try waitUntil("the layout settles", sourceLocation: sourceLocation) {
            let now = try items().map(\.frame)
            defer { last = now }
            return now == last
        }
    }

    func setting(_ key: String) throws -> String {
        try run("defaults read \(Self.appIdentifier) \(key)")
    }

    enum Setting {
        case bool(Bool)
        case double(Double)
        case string(String)
        case strings([String])

        var argument: String {
            switch self {
            case .bool(let value): "-bool \(value)"
            case .double(let value): "-float \(value)"
            case .string(let value): "-string '\(value)'"
            case .strings(let values): "-array " + values.map { "'\($0)'" }.joined(separator: " ")
            }
        }
    }

    // MARK: Menu bar

    func layout() throws -> MenuBarLayout {
        try probe("layout")
    }

    /// The items on the guest's one display, left to right.
    func items() throws -> [MenuBarLayout.Item] {
        try layout().displays.first?.items.sorted { $0.frame.minX < $1.frame.minX } ?? []
    }

    func appItems() throws -> Set<String> {
        Set(try items().compactMap(\.bundleIdentifier))
    }

    /// Whether the app's item is on screen: in the layout and not collapsed.
    func isDrawn(_ bundleIdentifier: String) throws -> Bool {
        try layout().drawnItem(of: bundleIdentifier) != nil
    }

    func frame(of bundleIdentifier: String) throws -> CGRect? {
        try items().first { $0.bundleIdentifier == bundleIdentifier }?.frame
    }

    func iconFrame() throws -> CGRect? {
        try frame(of: Self.appIdentifier)
    }

    func click(_ frame: CGRect, option: Bool = false, right: Bool = false) throws {
        var arguments = "click \(Int(frame.midX)) \(Int(frame.midY))"
        if option { arguments += " --option" }
        if right { arguments += " --right" }
        try probe(arguments)
    }

    /// Clicks the icon and parks the pointer on the desktop, out of the
    /// clock zone and off the menu bar.
    func clickIcon(option: Bool = false) throws {
        guard let frame = try iconFrame() else { throw CommandFailure(command: "icon", status: 1, output: "no BarNook icon") }
        try click(frame, option: option)
        try probe("move 400 400")
    }

    func openMenus() throws -> [CGRect] {
        try probe("menus")
    }

    // MARK: Accessibility trees

    struct AXNode: Decodable {
        var role: String?
        var description: String?
        var title: String?
        var frame: CGRect?
        var children: [AXNode]

        var all: [AXNode] { [self] + children.flatMap(\.all) }
    }

    func accessibilityTree(of bundleIdentifier: String) throws -> [AXNode] {
        try probe("inspect \(bundleIdentifier)")
    }

    /// macOS 27 draws this button where it collapsed the items that did not fit.
    func hasOverflowButton() throws -> Bool {
        try accessibilityTree(of: "com.apple.MenuBarAgent").flatMap(\.all)
            .contains { $0.description == "Show Hidden Menu Bar Items" }
    }

    /// The floating bar's buttons by app name, left to right, or nil while
    /// the bar is not on screen.
    func barButtons() throws -> [(name: String, frame: CGRect)]? {
        let windows = (try? accessibilityTree(of: Self.appIdentifier)) ?? []
        guard let bar = windows.first else { return nil }
        return bar.all.filter { $0.role == "AXButton" }
            .compactMap { node in node.frame.map { (node.description ?? node.title ?? "", $0) } }
            .sorted { $0.frame.minX < $1.frame.minX }
    }

    func barFrame() throws -> CGRect? {
        try accessibilityTree(of: Self.appIdentifier).first?.frame
    }

    func screenshot(_ name: String) throws {
        try run("mkdir -p screenshots && screencapture -x screenshots/\(name).png")
    }

    /// Polls until `condition` holds. `MenuBarAgent` lays out after the event
    /// that caused it, so no read right after a click is final.
    func waitUntil(
        _ what: String, timeout: TimeInterval = 5, interval: TimeInterval = 0.2,
        sourceLocation: SourceLocation = #_sourceLocation, _ condition: () throws -> Bool
    ) throws {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            if try condition() { return }
            Thread.sleep(forTimeInterval: interval)
        }
        Issue.record("timed out waiting until \(what)", sourceLocation: sourceLocation)
    }

    /// Waits until the condition holds and stays for `settle` seconds, for
    /// checks that something did not happen.
    func expectStable(
        _ what: String, for settle: TimeInterval = 1.5, interval: TimeInterval = 0.3,
        sourceLocation: SourceLocation = #_sourceLocation, _ condition: () throws -> Bool
    ) throws {
        let deadline = Date(timeIntervalSinceNow: settle)
        while Date() < deadline {
            guard try condition() else {
                Issue.record("\(what) did not hold", sourceLocation: sourceLocation)
                return
            }
            Thread.sleep(forTimeInterval: interval)
        }
    }
}

enum Fixture {
    static let a = "com.chlee1001.BarNookFixture.A"
    static let b = "com.chlee1001.BarNookFixture.B"
    static let c = "com.chlee1001.BarNookFixture.C"
    static let all = [a, b, c]
    /// A regular app with seven menus: frontmost, it leaves about 240
    /// points for status items on the guest's display. Room for the icon,
    /// its own item and one fixture (176), not for three fixtures (247).
    static let wideName = "FixtureW"
    /// Nine menus, about 113 points: room for the icon and one fixture
    /// (106), not for the app's own item as well (176).
    static let widerName = "FixtureV"
    static let w = "com.chlee1001.BarNookFixture.W"
    static let v = "com.chlee1001.BarNookFixture.V"

    static func name(_ identifier: String) -> String {
        "Fixture" + identifier.split(separator: ".").last!
    }

    static func markerPath(_ identifier: String) -> String {
        "\(identifier).marked"
    }
}
