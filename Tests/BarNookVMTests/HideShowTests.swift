import BarNookCore
import Foundation
import Testing

/// Acceptance criteria 2, 3, 4, 4b, 9 and 9a: hide, show, the always-hidden
/// set, and every item returning when BarNook stops. Numbers are the rows
/// of docs/testing.md.
@Suite(.serialized, .enabled(if: Guest.isConfigured))
struct HideShowTests {
    let guest = Guest()

    init() throws {
        try guest.startFixtures()
    }

    @Test func hiddenSetHidesAtLaunch() throws {
        try guest.launchBarNook(["hiddenBundleIdentifiers": .strings([Fixture.a])])
        try guest.waitUntil("A hides") { try !guest.appItems().contains(Fixture.a) }
        #expect(try guest.appItems().isSuperset(of: [Fixture.b, Fixture.c]))
    }

    @Test func clickTogglesTheHiddenSet() throws {
        try guest.launchBarNook(["hiddenBundleIdentifiers": .strings([Fixture.a, Fixture.b])])
        try guest.waitUntil("A and B hide") { try guest.appItems().isDisjoint(with: [Fixture.a, Fixture.b]) }

        try guest.clickIcon()
        try guest.waitUntil("A and B show") { try guest.appItems().isSuperset(of: [Fixture.a, Fixture.b]) }
        #expect(try guest.setting("isHiddenSetShown") == "1")

        try guest.clickIcon()
        try guest.waitUntil("A and B hide again") { try guest.appItems().isDisjoint(with: [Fixture.a, Fixture.b]) }
        #expect(try guest.setting("isHiddenSetShown") == "0")
    }

    @Test func shownStateSurvivesARelaunch() throws {
        try guest.launchBarNook(["hiddenBundleIdentifiers": .strings([Fixture.a])])
        try guest.waitUntil("A hides") { try !guest.appItems().contains(Fixture.a) }
        try guest.clickIcon()
        try guest.waitUntil("A shows") { try guest.appItems().contains(Fixture.a) }

        try guest.quit(Guest.appName)
        try guest.launch(Guest.appName)
        try guest.waitUntil("the icon returns") { try guest.iconFrame() != nil }
        try guest.expectStable("A stays shown") { try guest.appItems().contains(Fixture.a) }
        #expect(try guest.setting("hiddenBundleIdentifiers").contains(Fixture.a))
    }

    @Test func alwaysHiddenNeedsOption() throws {
        try guest.launchBarNook([
            "hiddenBundleIdentifiers": .strings([Fixture.a]),
            "alwaysHiddenBundleIdentifiers": .strings([Fixture.b]),
        ])
        try guest.waitUntil("A and B hide") { try guest.appItems().isDisjoint(with: [Fixture.a, Fixture.b]) }

        try guest.clickIcon()
        try guest.waitUntil("A shows") { try guest.appItems().contains(Fixture.a) }
        try guest.expectStable("B stays hidden") { try !guest.appItems().contains(Fixture.b) }

        try guest.clickIcon()
        try guest.waitUntil("A hides") { try !guest.appItems().contains(Fixture.a) }

        try guest.clickIcon(option: true)
        try guest.waitUntil("A and B show") { try guest.appItems().isSuperset(of: [Fixture.a, Fixture.b]) }
    }

    @Test func disablingTheAlwaysHiddenSetShowsIt() throws {
        try guest.launchBarNook([
            "alwaysHiddenBundleIdentifiers": .strings([Fixture.b]),
            "isAlwaysHiddenEnabled": .bool(false),
        ])
        try guest.expectStable("B stays visible") { try guest.appItems().contains(Fixture.b) }
    }

    /// The restriction is an allow-list of the running apps, so an app that
    /// launches later needs a new one.
    @Test func appLaunchedWhileHiddenStaysVisible() throws {
        try guest.quit(Fixture.name(Fixture.c))
        try guest.launchBarNook(["hiddenBundleIdentifiers": .strings([Fixture.a])])
        try guest.waitUntil("A hides") { try !guest.appItems().contains(Fixture.a) }
        try guest.launch(Fixture.name(Fixture.c))
        try guest.waitUntil("C appears") { try guest.appItems().contains(Fixture.c) }
        try guest.expectStable("C stays") { try guest.appItems().contains(Fixture.c) }
    }

    @Test func quitReturnsEveryItem() throws {
        try guest.launchBarNook(["hiddenBundleIdentifiers": .strings([Fixture.a])])
        try guest.waitUntil("A hides") { try !guest.appItems().contains(Fixture.a) }
        try guest.quit(Guest.appName)
        try guest.waitUntil("A returns") { try guest.appItems().contains(Fixture.a) }
    }

    @Test func killReturnsEveryItem() throws {
        try guest.launchBarNook(["hiddenBundleIdentifiers": .strings([Fixture.a])])
        try guest.waitUntil("A hides") { try !guest.appItems().contains(Fixture.a) }
        try guest.kill(Guest.appName)
        try guest.waitUntil("A returns") { try guest.appItems().contains(Fixture.a) }
    }
}
