// Modified by Chaehyeon Lee (2026): cover floating-bar pin interactions; the bar follows the stored order.
import BarNookCore
import Foundation
import Testing

/// Spec F8. A short status item region (the wide fixture frontmost, the
/// stand-in for a notch) collapses shown items behind macOS's own «. In
/// bar mode the restriction stays, nothing collapses, and a panel below
/// the menu bar lists the hidden apps.
@Suite(.serialized, .enabled(if: Guest.isConfigured))
struct FloatingBarTests {
    let guest = Guest()
    let bar: [String: Guest.Setting] = [
        "hiddenItemsPlacement": .string("floatingBar"),
        "hiddenBundleIdentifiers": .strings(Fixture.all),
    ]

    init() throws {
        try guest.startFixtures()
    }

    private func launchInBarMode(_ extra: [String: Guest.Setting] = [:]) throws {
        try guest.launchBarNook(bar.merging(extra) { $1 })
        try guest.waitUntil("A hides") { try !guest.appItems().contains(Fixture.a) }
    }

    private func showBar() throws {
        try guest.clickIcon()
        try guest.waitUntil("the bar opens") { try guest.barButtons() != nil }
    }

    /// `open` launches the app on the first call and activates it on the
    /// next, so it repeats until the app is frontmost.
    private func bringWideFixtureToFront(_ name: String = Fixture.wideName) throws {
        try guest.waitUntil("\(name) is frontmost", interval: 1) {
            try guest.launch(name)
            Thread.sleep(forTimeInterval: 0.5)
            return try guest.frontmostApp() == name
        }
        try guest.waitUntilSettled()
    }

    private func hasAccessibilityGrant() throws -> Bool {
        let value = try guest.run("sudo sqlite3 -bail \"/Library/Application Support/com.apple.TCC/TCC.db\" \"SELECT auth_value FROM access WHERE service = 'kTCCServiceAccessibility' AND client = 'com.chlee1001.BarNookDev' LIMIT 1;\"")
        return value == "2"
    }

    /// Pins A from the bar; returns once its item is in the menu bar and
    /// the bar has closed.
    private func pinAFromTheBar() throws {
        try showBar()
        let button = try #require(try guest.barButtons()?.first { $0.name == "FixtureA" })
        try guest.click(button.frame)
        try guest.waitUntil("the bar closes") { try guest.barButtons() == nil }
        try guest.waitUntil("A is pinned into the menu bar") { try guest.isDrawn(Fixture.a) }
    }

    /// Clicks the pinned item itself; returns once its menu is open.
    private func openAPinnedMenu() throws -> CGRect {
        let frame = try #require(try guest.frame(of: Fixture.a))
        try guest.click(frame)
        var menu: CGRect?
        try guest.waitUntil("A's menu opens") {
            menu = try guest.openMenus().first { $0.minY < 42 }
            return menu != nil
        }
        return try #require(menu)
    }

    /// The icon ends a pin in two clicks: the first brings the bar back,
    /// the second hides the set.
    private func hideViaIcon() throws {
        try guest.clickIcon()
        try guest.waitUntil("the bar reopens for another pin") { try guest.barButtons() != nil }
        try guest.clickIcon()
        try guest.waitUntil("the set hides") { try guest.setting("isHiddenSetShown") == "0" }
    }

    @Test func aShortRegionCollapsesItemsInMenuBarMode() throws {
        try guest.launchBarNook(["hiddenBundleIdentifiers": .strings(Fixture.all)])
        try guest.waitUntil("the set hides") { try guest.appItems().isDisjoint(with: Fixture.all) }
        try bringWideFixtureToFront()
        #expect(try !guest.hasOverflowButton())
        try guest.clickIcon()
        try guest.waitUntil("macOS collapses what does not fit") { try guest.hasOverflowButton() }
    }

    @Test func showOpensTheBarAndKeepsTheMenuBarHidden() throws {
        try launchInBarMode()
        try bringWideFixtureToFront()
        try showBar()
        #expect(try guest.barButtons()?.map(\.name) == ["FixtureA", "FixtureB", "FixtureC"])
        try guest.expectStable("the items stay hidden") { try guest.appItems().isDisjoint(with: Fixture.all) }
        #expect(try !guest.hasOverflowButton())
        #expect(try guest.setting("isHiddenSetShown") == "1")

        let icon = try #require(try guest.iconFrame())
        let frame = try #require(try guest.barFrame())
        #expect(abs(frame.maxX - icon.maxX) <= 4, "the bar hangs from the icon's right edge")
        #expect(frame.minY > icon.maxY && frame.minY < icon.maxY + 12, "the bar sits just below the menu bar")

        try guest.clickIcon()
        try guest.waitUntil("the bar closes") { try guest.barButtons() == nil }
    }

    @Test func optionShowAddsTheAlwaysHiddenSet() throws {
        try launchInBarMode([
            "hiddenBundleIdentifiers": .strings([Fixture.a]),
            "alwaysHiddenBundleIdentifiers": .strings([Fixture.b]),
        ])
        try guest.clickIcon()
        try guest.waitUntil("the bar shows A") { try guest.barButtons()?.map(\.name) == ["FixtureA"] }
        let before = try #require(try guest.barButtons()?.first { $0.name == "FixtureA" }).frame
        try guest.clickIcon()
        try guest.waitUntil("the bar closes") { try guest.barButtons() == nil }
        try guest.clickIcon(option: true)
        // The always-hidden app sits left of a separator; A keeps its place
        // under the icon once the bar has settled.
        try guest.waitUntil("the bar shows B, then A in its place") {
            guard let buttons = try guest.barButtons(), buttons.map(\.name) == ["FixtureB", "FixtureA"] else { return false }
            return abs(buttons[1].frame.midX - before.midX) <= 2
        }
    }

    @Test func barFollowsTheStoredOrder() throws {
        try launchInBarMode(["hiddenBundleIdentifiers": .strings([Fixture.c, Fixture.a, Fixture.b])])
        try showBar()
        #expect(try guest.barButtons()?.map(\.name) == ["FixtureC", "FixtureA", "FixtureB"])
    }

    @Test func rehideConditionsCloseTheBar() throws {
        try launchInBarMode(["rehideOnTimeout": .bool(true), "rehideTimeout": .double(2)])
        try showBar()
        try guest.waitUntil("the timeout closes the bar", timeout: 5) { try guest.barButtons() == nil }

        try launchInBarMode(["rehideOnClickOutside": .bool(true)])
        try showBar()
        let frame = try #require(try guest.barFrame())
        try guest.probe("click \(Int(frame.midX)) \(Int(frame.maxY + 40))")
        try guest.waitUntil("a click outside closes the bar") { try guest.barButtons() == nil }

        try launchInBarMode(["rehideOnFocusChange": .bool(true)])
        try showBar()
        try guest.run("open -a TextEdit")
        try guest.waitUntil("a focus change closes the bar") { try guest.barButtons() == nil }
        try guest.run("pkill -x TextEdit || true")
    }

    @Test func clickInTheBarIsNotOutside() throws {
        try launchInBarMode(["rehideOnClickOutside": .bool(true)])
        try showBar()
        let frame = try #require(try guest.barFrame())
        try guest.probe("click \(Int(frame.midX)) \(Int(frame.minY + 4))")  // the bar's top padding, no button
        try guest.expectStable("the bar stays") { try guest.barButtons() != nil }
    }

    /// Without the Accessibility permission nothing can be read, so a pin
    /// hides every other app at once: the one arrangement that always
    /// leaves the pinned item on screen. Runs only in a guest where the
    /// app has no grant (before scripts/vm-test.sh gave it one); the two
    /// tests after it need the grant.
    @Test func clickOnAnAppWithoutPermissionPinsIt() throws {
        try launchInBarMode()
        guard try !hasAccessibilityGrant() else { return }
        try bringWideFixtureToFront()
        try showBar()
        let button = try #require(try guest.barButtons()?.first { $0.name == "FixtureB" })
        try guest.click(button.frame)
        try guest.waitUntil("B appears") { try guest.appItems().contains(Fixture.b) }
        try guest.waitUntil("the bar closes") { try guest.barButtons() == nil }
        try guest.expectStable("A and C stay hidden and B stays") {
            let items = try guest.appItems()
            return items.contains(Fixture.b) && items.isDisjoint(with: [Fixture.a, Fixture.c])
        }
        #expect(try !guest.hasOverflowButton())
        try hideViaIcon()
        try guest.waitUntil("the icon hides B again") { try !guest.appItems().contains(Fixture.b) }
    }

    /// With the permission a click pins the app and closes the bar; the
    /// item stays in the menu bar, its menu opens from a click on the
    /// item, and the set hides from the icon.
    @Test func clickOnAnAppPinsItAndItsMenuOpens() throws {
        try launchInBarMode()
        guard try hasAccessibilityGrant() else {
            Issue.record("BarNook has no Accessibility grant in this guest; run scripts/vm-test.sh")
            return
        }
        try bringWideFixtureToFront()
        try guest.run("rm -f \(Fixture.markerPath(Fixture.a))")
        try pinAFromTheBar()
        // Room for one more item: the front app's own item stays.
        #expect(try guest.isDrawn(Fixture.w))
        let menuFrame = try openAPinnedMenu()
        try guest.click(CGRect(x: menuFrame.minX, y: menuFrame.minY + 6, width: menuFrame.width, height: 20))  // "Mark"
        try guest.waitUntil("Mark runs") { try !guest.run("ls \(Fixture.markerPath(Fixture.a)) 2>/dev/null || true").isEmpty }
        try guest.expectStable("A stays pinned after its menu closes") { try guest.isDrawn(Fixture.a) }
        try hideViaIcon()
        try guest.waitUntil("the set hides") {
            try guest.appItems().isDisjoint(with: Fixture.all) && guest.setting("isHiddenSetShown") == "0"
        }
    }

    /// A pin that does not fit hides every other app: the escalation from
    /// the fit check, not macOS's own collapse. One pin fits next to the
    /// icon with FixtureV frontmost; a second does not.
    @Test func pinsHideTheOthersOnlyWhenTheyMust() throws {
        try launchInBarMode()
        guard try hasAccessibilityGrant() else {
            Issue.record("BarNook has no Accessibility grant in this guest; run scripts/vm-test.sh")
            return
        }
        try bringWideFixtureToFront(Fixture.widerName)
        try pinAFromTheBar()
        // One pin fits next to the icon; V's own item does not.
        #expect(try guest.isDrawn(Fixture.a))
        #expect(try !guest.isDrawn(Fixture.v))
        // The second pin does not fit; the fit check hides every other app.
        try guest.clickIcon()
        try guest.waitUntil("the bar reopens") { try guest.barButtons() != nil }
        let button = try #require(try guest.barButtons()?.first { $0.name == "FixtureB" })
        try guest.click(button.frame)
        try guest.waitUntil("B is drawn once every other app hides") { try guest.isDrawn(Fixture.b) }
        #expect(try guest.isDrawn(Fixture.a))
        #expect(try !guest.isDrawn(Fixture.v))
        try hideViaIcon()
        try guest.waitUntil("V's item returns") { try guest.isDrawn(Fixture.v) }
    }
}
