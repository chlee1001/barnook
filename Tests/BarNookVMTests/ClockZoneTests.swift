import BarNookCore
import Foundation
import Testing

/// Row 8: the pointer over the clock lifts the restriction, so a click on
/// the clock opens Notification Center; the pointer leaving hides again.
@Suite(.serialized, .enabled(if: Guest.isConfigured))
struct ClockZoneTests {
    let guest = Guest()

    init() throws {
        try guest.startFixtures()
    }

    private func clock() throws -> CGRect {
        guard let clock = try guest.items().first(where: { $0.systemIdentifier == MenuBarLayout.clockIdentifier }) else {
            throw Guest.CommandFailure(command: "clock", status: 1, output: "no clock item")
        }
        return clock.frame
    }

    @Test func pointerOverTheClockShowsHiddenItems() throws {
        try guest.launchBarNook(["hiddenBundleIdentifiers": .strings([Fixture.a])])
        try guest.waitUntil("A hides") { try !guest.appItems().contains(Fixture.a) }
        let clock = try clock()
        try guest.probe("move \(Int(clock.midX)) \(Int(clock.midY))")
        try guest.waitUntil("A shows") { try guest.appItems().contains(Fixture.a) }
        try guest.probe("move 500 400")
        try guest.waitUntil("A hides again") { try !guest.appItems().contains(Fixture.a) }
    }

    @Test func measuredZoneStopsBeforeControlCenter() throws {
        try guest.launchBarNook(["hiddenBundleIdentifiers": .strings([Fixture.a])])
        try guest.waitUntil("A hides") { try !guest.appItems().contains(Fixture.a) }
        let width = Double(try guest.setting("clockZoneWidth")) ?? 0
        let clock = try clock()
        let bar = try #require(try guest.layout().displays.first?.frame)
        #expect(abs(width - (bar.maxX - clock.minX + 30)) < 0.01, "measured width is the clock offset plus the margin")
        try guest.probe("move \(Int(clock.minX - 40)) \(Int(clock.midY))")
        try guest.expectStable("A stays hidden left of the zone") { try !guest.appItems().contains(Fixture.a) }
    }
}
