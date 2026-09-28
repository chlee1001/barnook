import BarNookCore
import Testing

/// Trees shaped like the ones read on the host (docs/phase9.md).
@Suite struct NotificationCenterPanelTests {
    typealias Node = NotificationCenterPanel.Node

    func window(_ content: [Node]) -> (title: String?, root: Node) {
        ("Notification Center", Node(children: [Node(children: [Node(children: [Node(children: content)])])]))
    }

    let banner = Node(identifier: "F1E82E30-DD6F-48F1-AF93-AA7A24CFF663", children: [Node(identifier: "title"), Node(identifier: "body")])
    let list = Node(identifier: "AXNotificationListItems")
    let widget: (title: String?, root: Node) = ("Calendar", Node(children: [Node(identifier: "widget-local:com.apple.iCal")]))

    @Test func noWindowIsClosed() {
        #expect(!NotificationCenterPanel.isOpen(windows: []))
    }

    @Test func desktopWidgetsAreClosed() {
        #expect(!NotificationCenterPanel.isOpen(windows: [widget]))
    }

    /// D0: the banner's window has the panel's owner, layer and frame.
    @Test func aBannerAloneIsClosed() {
        #expect(!NotificationCenterPanel.isOpen(windows: [window([banner]), widget]))
    }

    @Test func theListIsOpen() {
        #expect(NotificationCenterPanel.isOpen(windows: [window([list]), widget]))
    }

    @Test func theListUnderABannerIsOpen() {
        #expect(NotificationCenterPanel.isOpen(windows: [window([list, banner])]))
    }

    /// A panel with every notification cleared has no list, only widgets
    /// and the widget editor button.
    @Test func aPanelWithNoNotificationsIsOpen() {
        let editor = Node(identifier: "widget-editor-button")
        #expect(NotificationCenterPanel.isOpen(windows: [window([editor]), widget]))
    }

    @Test func theListInAnotherWindowIsClosed() {
        let other: (title: String?, root: Node) = ("Other", Node(children: [list]))
        #expect(!NotificationCenterPanel.isOpen(windows: [other]))
    }
}
