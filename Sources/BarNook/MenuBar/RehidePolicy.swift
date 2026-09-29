// Modified by Chaehyeon Lee (2026): the rehide waits while the pointer rests on the floating bar; the timeout stays within 1-300 seconds.
import BarNookCore
import Foundation

/// Pure decisions for auto-rehide, kept apart from the monitors so tests
/// can cover them.
enum RehidePolicy {
    /// Seconds the rehide timeout may take (spec F3).
    static let timeoutRange: ClosedRange<Double> = 1...300

    /// A whole number of seconds in `timeoutRange`, for a value nothing has
    /// bounded yet: a hand-edited default, or a number typed in Settings.
    static func clampedTimeout(_ seconds: Double) -> Double {
        guard !seconds.isNaN else { return timeoutRange.lowerBound }
        return min(max(seconds.rounded(), timeoutRange.lowerBound), timeoutRange.upperBound)
    }

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

    /// A hide waits while a menu from a shown item is open, and while the
    /// pointer rests on the floating bar: the user is about to click an app.
    static func shouldWait(menus: [NSRect], menuBar: MenuBarGeometry, panel: NSRect?, pointer: NSPoint) -> Bool {
        isMenuOpen(menus, menuBar: menuBar) || panel?.contains(pointer) == true
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
