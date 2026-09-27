import Foundation

/// The pure decision behind the pins, kept apart from `MenuBarManager` so
/// tests can cover it. A click in the floating bar pins an app: the
/// restriction lets its item through and the user clicks the item itself.
/// Spec F8.
enum PinPolicy {
    /// How many items are let through at once. Three fit beside the front
    /// app's menus on a narrow display; past that macOS collapses them
    /// behind its own `«` and a pin buys the user nothing.
    static let limit = 3

    /// The pins after a click on `identifier`, oldest first. A click on a
    /// pinned app unpins it. A click past the limit drops the oldest pin,
    /// so the newest click always lands.
    static func toggling(_ identifier: String, in pins: [String]) -> [String] {
        if let index = pins.firstIndex(of: identifier) {
            var result = pins
            result.remove(at: index)
            return result
        }
        return Array((pins + [identifier]).suffix(limit))
    }
}
