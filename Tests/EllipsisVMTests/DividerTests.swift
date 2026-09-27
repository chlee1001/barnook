// Modified by Chaehyeon Lee (2026): BarNook VM diagnostics.
import EllipsisCore
import Foundation
import Testing

/// Rows D1 to D5: the icon as the divider. Apps left of it join the hidden
/// set, apps dragged right of it leave. Needs the Accessibility grant that
/// scripts/vm-test.sh gives the app.
@Suite(.serialized, .enabled(if: Guest.isConfigured))
struct DividerTests {
    let guest = Guest()
    let divider: [String: Guest.Setting] = ["hidesAppsLeftOfIcon": .bool(true)]

    init() throws {
        try guest.startFixtures()
    }

    /// Cmd-drags the icon so that its left edge lands at `x`.
    private func cmdDragIcon(leftEdgeTo x: CGFloat) throws {
        guard let icon = try guest.iconFrame() else { throw Guest.CommandFailure(command: "icon", status: 1, output: "no BarNook icon") }
        try guest.probe("drag \(Int(icon.midX)) \(Int(icon.midY)) \(Int(x + icon.width / 2)) \(Int(icon.midY)) --command")
    }

    @Test func switchOnHidesAppsLeftOfTheIcon() throws {
        try guest.quit(Fixture.name(Fixture.a))
        try guest.launchEllipsis(divider)
        try guest.placeFixture(Fixture.a, pointsFromRight: Guest.iconPosition + 100)
        try guest.launch(Fixture.name(Fixture.a))
        try guest.waitUntil("A appears left of the icon and joins the set") {
            (try? guest.setting("hiddenBundleIdentifiers"))?.contains(Fixture.a) == true
        }
        try guest.waitUntil("A hides") { try !guest.appItems().contains(Fixture.a) }
        try guest.expectStable("B and C stay") { try guest.appItems().isSuperset(of: [Fixture.b, Fixture.c]) }
    }

    @Test func draggingTheIconRightOfAnItemHidesIt() throws {
        try guest.launchEllipsis(divider)
        let fixtures = try guest.items().filter { Fixture.all.contains($0.bundleIdentifier ?? "") }
        guard let icon = try guest.iconFrame(), let first = fixtures.first(where: { $0.frame.minX >= icon.maxX }) else {
            Issue.record("expected a fixture right of the icon")
            return
        }
        try cmdDragIcon(leftEdgeTo: first.frame.maxX + 8)
        try guest.waitUntil("\(first.bundleIdentifier!) hides") { try !guest.appItems().contains(first.bundleIdentifier!) }
        #expect(try guest.setting("hiddenBundleIdentifiers").contains(first.bundleIdentifier!))
    }

    @Test func draggingTheIconFarLeftWhileShownEmptiesTheSet() throws {
        try guest.launchEllipsis(divider.merging(["hiddenBundleIdentifiers": .strings([Fixture.a, Fixture.b])]) { $1 })
        try guest.waitUntil("A and B hide") { try guest.appItems().isDisjoint(with: [Fixture.a, Fixture.b]) }
        try guest.clickIcon()
        try guest.waitUntil("A and B show") { try guest.appItems().isSuperset(of: [Fixture.a, Fixture.b]) }
        try cmdDragIcon(leftEdgeTo: 400)
        try guest.waitUntil("the set empties") { try guest.setting("hiddenBundleIdentifiers") == "(\n)" }
        try guest.clickIcon()
        try guest.expectStable("every fixture stays") { try guest.appItems().isSuperset(of: Fixture.all) }
    }

    @Test func draggingAnItemLeftOfTheIconHidesIt() throws {
        try guest.launchEllipsis(divider)
        guard let icon = try guest.iconFrame(), let c = try guest.frame(of: Fixture.c) else {
            Issue.record("expected the icon and C")
            return
        }
        try guest.probe("drag \(Int(c.midX)) \(Int(c.midY)) \(Int(icon.minX - 4)) \(Int(icon.midY)) --command")
        try guest.waitUntil("C hides") { try !guest.appItems().contains(Fixture.c) }
    }

    @Test func switchOffKeepsTheSet() throws {
        try guest.launchEllipsis(divider.merging(["hiddenBundleIdentifiers": .strings([Fixture.a])]) { $1 })
        try guest.waitUntil("A hides") { try !guest.appItems().contains(Fixture.a) }
        try guest.launchEllipsis(["hiddenBundleIdentifiers": .strings([Fixture.a]), "hidesAppsLeftOfIcon": .bool(false)])
        try guest.waitUntil("A hides") { try !guest.appItems().contains(Fixture.a) }
        try guest.expectStable("A stays hidden") { try !guest.appItems().contains(Fixture.a) }
        #expect(try guest.setting("hiddenBundleIdentifiers").contains(Fixture.a))
    }
}
