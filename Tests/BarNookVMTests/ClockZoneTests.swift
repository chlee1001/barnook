import BarNookCore
import Foundation
import Testing

/// Rows 8, 8b and 8c: the pointer over the clock lifts the restriction, so a
/// click on the clock opens Notification Center; the pointer leaving hides again.
@Suite(.serialized, .enabled(if: Guest.isConfigured))
struct ClockZoneTests {
    let guest = Guest()

    init() throws {
        try guest.startFixtures()
    }

    @Test func pointerOverTheClockShowsHiddenItems() throws {
        try guest.launchBarNook(["hiddenBundleIdentifiers": .strings([Fixture.a])])
        try guest.waitUntil("A hides") { try !guest.appItems().contains(Fixture.a) }
        let clock = try guest.clockFrame()
        try guest.probe("move \(Int(clock.midX)) \(Int(clock.midY))")
        try guest.waitUntil("A shows") { try guest.appItems().contains(Fixture.a) }
        try guest.probe("move 500 400")
        try guest.waitUntil("A hides again") { try !guest.appItems().contains(Fixture.a) }
    }

    /// Row 8c: a rehide while the pointer rests on the clock hides the set on
    /// time, but the restriction waits until the pointer leaves, so the
    /// hidden items stay under the pointer.
    @Test func theClockHoverHoldsThroughARehide() throws {
        let clock = try guest.clockFrame()
        try guest.launchBarNook([
            "hiddenBundleIdentifiers": .strings([Fixture.a]),
            "rehideOnTimeout": .bool(true),
            "rehideTimeout": .double(4),
        ])
        try guest.clickIcon()
        try guest.waitUntil("A shows") { try guest.appItems().contains(Fixture.a) }
        try guest.probe("move \(Int(clock.midX)) \(Int(clock.midY))")
        try guest.waitUntil("the set hides after the timeout") { try guest.setting("isHiddenSetShown") == "0" }
        try guest.expectStable("A stays under the pointer", for: 3) { try guest.appItems().contains(Fixture.a) }
        try guest.probe("move 500 400")
        try guest.waitUntil("A hides once the pointer leaves") { try !guest.appItems().contains(Fixture.a) }
    }

    @Test func measuredZoneStopsBeforeControlCenter() throws {
        try guest.launchBarNook(["hiddenBundleIdentifiers": .strings([Fixture.a])])
        try guest.waitUntil("A hides") { try !guest.appItems().contains(Fixture.a) }
        let width = Double(try guest.setting("clockZoneWidth")) ?? 0
        let clock = try guest.clockFrame()
        let bar = try #require(try guest.layout().displays.first?.frame)
        #expect(abs(width - (bar.maxX - clock.minX + 30)) < 0.01, "measured width is the clock offset plus the margin")
        try guest.probe("move \(Int(clock.minX - 40)) \(Int(clock.midY))")
        try guest.expectStable("A stays hidden left of the zone") { try !guest.appItems().contains(Fixture.a) }
    }
}
