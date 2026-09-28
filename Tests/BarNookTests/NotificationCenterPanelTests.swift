import AppKit
import BarNookCore
import Testing

/// Main and stacked-display geometry from the reported setup; the host
/// spike presently sees only one 1512-point display.
@Suite struct NotificationCenterPanelTests {
    let main = NotificationCenterPanel.Display(
        frame: NSRect(x: 0, y: 0, width: 2048, height: 1280),
        visibleFrame: NSRect(x: 0, y: 0, width: 2048, height: 1249)
    )
    let wide = NotificationCenterPanel.Display(
        frame: NSRect(x: -479, y: 1280, width: 3440, height: 1440),
        visibleFrame: NSRect(x: -479, y: 1280, width: 3440, height: 1409)
    )
    var displays: [NotificationCenterPanel.Display] { [main, wide] }
    let owner = "com.apple.notificationcenterui"
    let layer = NotificationCenterPanel.panelLayer

    func window(_ frame: NSRect, owner: String? = nil, layer: Int? = nil) -> NotificationCenterPanel.Window {
        NotificationCenterPanel.Window(owner: owner ?? self.owner, layer: layer ?? self.layer, frame: frame)
    }

    @Test func thePanelOnTheMainDisplayIsOpen() {
        let panel = window(main.frame)
        #expect(NotificationCenterPanel.isOpen([panel], displays: displays))
    }

    @Test func thePanelOnTheDisplayAboveIsOpen() {
        let panel = window(wide.frame)
        #expect(NotificationCenterPanel.isOpen([panel], displays: displays))
    }

    // A small synthetic banner frame is excluded. The observed banner also
    // creates a full-display backing window and *does* fool this predicate.
    @Test func aSmallBannerWindowIsNotThePanel() {
        let banner = window(NSRect(x: 1680, y: 1161, width: 360, height: 80))
        #expect(!NotificationCenterPanel.isOpen([banner], displays: displays))
    }

    @Test func aWidgetOnAnotherLayerIsNotThePanel() {
        let widget = window(main.frame, layer: Int(CGWindowLevelForKey(.desktopWindow)))
        #expect(!NotificationCenterPanel.isOpen([widget], displays: displays))
    }

    @Test func anotherOwnerIsNotThePanel() {
        let other = window(main.frame, owner: "com.apple.controlcenter")
        #expect(!NotificationCenterPanel.isOpen([other], displays: displays))
    }

    @Test func aWindowAtTheLeftEdgeIsNotThePanel() {
        let left = window(NSRect(x: 0, y: 0, width: 400, height: 1280))
        #expect(!NotificationCenterPanel.isOpen([left], displays: displays))
    }

    @Test func noWindowsMeansClosed() {
        #expect(!NotificationCenterPanel.isOpen([], displays: displays))
    }

    @Test func aBannerBesideThePanelStillReadsOpen() {
        let banner = window(NSRect(x: 1680, y: 1161, width: 360, height: 80))
        let panel = window(main.frame)
        #expect(NotificationCenterPanel.isOpen([banner, panel], displays: displays))
    }
}
