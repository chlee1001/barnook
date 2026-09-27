import Foundation

/// Where the floating bar goes: under the BarNook icon, just below the
/// menu bar, and always on screen. Cocoa coordinates. Pure, for tests.
enum FloatingBarPlacement {
    static let gap: CGFloat = 4

    /// `iconFrame` nil means the icon is collapsed or unknown; the bar then
    /// hangs from the right edge of the screen instead.
    static func frame(
        panelSize: NSSize,
        iconFrame: NSRect?,
        screen: NSRect,
        menuBarBottom: CGFloat
    ) -> NSRect {
        let top = menuBarBottom - gap
        var maxX = iconFrame?.maxX ?? screen.maxX - gap
        maxX = min(maxX, screen.maxX - gap)
        var minX = maxX - panelSize.width
        if minX < screen.minX + gap {
            minX = screen.minX + gap
        }
        return NSRect(x: minX, y: top - panelSize.height, width: panelSize.width, height: panelSize.height)
    }
}
