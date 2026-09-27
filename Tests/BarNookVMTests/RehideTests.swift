import BarNookCore
import Foundation
import Testing

/// Acceptance criteria 5 to 7a: the shown set hides again after a timeout,
/// a click outside, or a focus change, and never while a menu is open.
@Suite(.serialized, .enabled(if: Guest.isConfigured))
struct RehideTests {
    let guest = Guest()
    let hidden: [String: Guest.Setting] = ["hiddenBundleIdentifiers": .strings([Fixture.a])]

    init() throws {
        try guest.startFixtures()
        try guest.run("pkill -x TextEdit || true")
    }

    private func showA() throws {
        try guest.waitUntil("A hides") { try !guest.appItems().contains(Fixture.a) }
        try guest.clickIcon()
        try guest.waitUntil("A shows") { try guest.appItems().contains(Fixture.a) }
    }

    /// Opens the fixture's menu by clicking its item and returns the menu's frame.
    private func openMenu(of fixture: String) throws -> CGRect {
        guard let item = try guest.frame(of: fixture) else { throw Guest.CommandFailure(command: "menu", status: 1, output: "\(fixture) is not visible") }
        try guest.click(item)
        var menu: CGRect?
        try guest.waitUntil("the menu opens") {
            menu = try guest.openMenus().first { $0.minY >= item.maxY - 12 && $0.minY <= item.maxY + 12 }
            return menu != nil
        }
        return menu ?? .zero
    }

    @Test func timeoutHides() throws {
        try guest.launchBarNook(hidden.merging(["rehideOnTimeout": .bool(true), "rehideTimeout": .double(2)]) { $1 })
        try showA()
        try guest.waitUntil("A hides on its own", timeout: 5) { try !guest.appItems().contains(Fixture.a) }
    }

    @Test func noTimeoutKeepsTheSetShown() throws {
        try guest.launchBarNook(hidden.merging(["rehideOnTimeout": .bool(false), "rehideTimeout": .double(1)]) { $1 })
        try showA()
        try guest.expectStable("A stays shown", for: 3) { try guest.appItems().contains(Fixture.a) }
    }

    @Test func clickOutsideHides() throws {
        try guest.launchBarNook(hidden.merging(["rehideOnClickOutside": .bool(true)]) { $1 })
        try showA()
        try guest.probe("click 500 400")
        try guest.waitUntil("A hides") { try !guest.appItems().contains(Fixture.a) }
    }

    @Test func clickOnAnotherItemKeepsTheSetShown() throws {
        try guest.launchBarNook(hidden.merging(["rehideOnClickOutside": .bool(true)]) { $1 })
        try showA()
        let menu = try openMenu(of: Fixture.c)
        try guest.expectStable("A stays shown with C's menu open") { try guest.appItems().contains(Fixture.a) }
        try guest.click(menu.offsetBy(dx: 0, dy: -menu.height))  // the item above the menu closes it
        try guest.waitUntil("the menu closes") { try guest.openMenus().isEmpty }
        try guest.expectStable("A stays shown after the menu closes") { try guest.appItems().contains(Fixture.a) }
    }

    @Test func focusChangeHides() throws {
        try guest.launchBarNook(hidden.merging(["rehideOnFocusChange": .bool(true)]) { $1 })
        try showA()
        try guest.run("open -a TextEdit")
        try guest.waitUntil("A hides") { try !guest.appItems().contains(Fixture.a) }
        try guest.run("pkill -x TextEdit || true")
    }

    @Test func openMenuDefersTheTimeout() throws {
        try guest.launchBarNook(hidden.merging(["rehideOnTimeout": .bool(true), "rehideTimeout": .double(2)]) { $1 })
        try showA()
        let menu = try openMenu(of: Fixture.a)
        try guest.expectStable("A stays shown while its menu is open", for: 4) { try guest.appItems().contains(Fixture.a) }
        try guest.click(menu.offsetBy(dx: 0, dy: -menu.height))
        try guest.waitUntil("A hides once the menu closes", timeout: 3) { try !guest.appItems().contains(Fixture.a) }
    }

    @Test func menuActionRunsThenTheSetHides() throws {
        try guest.launchBarNook(hidden.merging(["rehideOnTimeout": .bool(true), "rehideTimeout": .double(2)]) { $1 })
        try guest.run("rm -f \(Fixture.markerPath(Fixture.a))")
        try showA()
        let menu = try openMenu(of: Fixture.a)
        try guest.click(CGRect(x: menu.minX, y: menu.minY + 6, width: menu.width, height: 20))  // "Mark", the first item
        try guest.waitUntil("Mark runs") { try guest.run("ls \(Fixture.markerPath(Fixture.a)) 2>/dev/null || true").isEmpty == false }
        try guest.waitUntil("A hides", timeout: 5) { try !guest.appItems().contains(Fixture.a) }
    }
}
