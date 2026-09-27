import BarNookCore
import Foundation

/// Pure decisions for auto-rehide, kept apart from the monitors so tests
/// can cover them.
enum RehidePolicy {
    /// A menu that hangs from the menu bar has its top edge at, or a few
    /// points below, the bar's bottom edge. Pop-up buttons and context
    /// menus elsewhere on screen do not count.
    static let menuGap: CGFloat = 12

    static func menuBarMenus(_ menus: [NSRect], menuBar: MenuBarGeometry) -> [NSRect] {
        menus.filter { menu in
            menuBar.frames.contains { bar in
                menu.maxY >= bar.minY - menuGap && menu.maxY <= bar.maxY
                    && menu.maxX > bar.minX && menu.minX < bar.maxX
            }
        }
    }

    static func isMenuOpen(_ menus: [NSRect], menuBar: MenuBarGeometry) -> Bool {
        !menuBarMenus(menus, menuBar: menuBar).isEmpty
    }

    /// A click in the menu bar, inside an open menu, or inside the floating
    /// bar (`panel`) is not "outside".
    static func shouldHide(
        afterClickAt point: NSPoint, menuBar: MenuBarGeometry, menus: [NSRect], panel: NSRect? = nil
    ) -> Bool {
        if menuBar.contains(point) { return false }
        if let panel, panel.contains(point) { return false }
        if menuBarMenus(menus, menuBar: menuBar).contains(where: { $0.contains(point) }) { return false }
        return true
    }
}
