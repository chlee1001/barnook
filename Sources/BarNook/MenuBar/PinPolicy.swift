// Modified by Chaehyeon Lee (2026): room for a pin that does not fit comes from the fewest apps, leftmost first.
import BarNookCore
import CoreGraphics
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

    /// The apps to hide so that every collapsed pin in `layout` is drawn,
    /// drawn from `hideable` only: as few as can make the room. Empty when
    /// the pins are drawn or no app in `hideable` has an item left.
    ///
    /// Every app item, drawn or collapsed, needs its width once nothing is
    /// collapsed; item frames are slots that touch, so a frame's width is
    /// that need. The region runs from the collapsed stack, which sits at or
    /// right of its left edge, to the end of the last drawn app item, so the
    /// room is never overestimated. Hiding an app gives back every one of
    /// its items. The leftmost single app that covers the shortfall goes;
    /// if none does, apps go from the left, the side macOS collapses, until
    /// they do. The caller reads the layout again and asks once more if a
    /// pin is still collapsed.
    static func room(for pins: [String], in layout: MenuBarLayout, hideable: Set<String>) -> Set<String> {
        var room = Set<String>()
        for display in layout.displays {
            let appItems = display.items.filter { $0.bundleIdentifier != nil }
            let collapsed = appItems.filter { !display.isDrawn($0) }
            guard collapsed.contains(where: { pins.contains($0.bundleIdentifier!) }),
                  let regionStart = collapsed.map(\.frame.minX).min(),
                  let regionEnd = appItems.filter(display.isDrawn).map(\.frame.maxX).max()
            else { continue }

            let demand = appItems.reduce(0) { $0 + $1.frame.width }
            let shortfall = demand - (regionEnd - regionStart)
            guard shortfall > 0 else { continue }

            var freed: [String: CGFloat] = [:]
            var leftEdge: [String: CGFloat] = [:]
            for item in appItems {
                let id = item.bundleIdentifier!
                guard hideable.contains(id), !pins.contains(id) else { continue }
                freed[id, default: 0] += item.frame.width
                leftEdge[id] = min(leftEdge[id] ?? .infinity, item.frame.minX)
            }
            let leftFirst = freed.keys.sorted { (leftEdge[$0]!, $0) < (leftEdge[$1]!, $1) }
            if let one = leftFirst.first(where: { freed[$0]! >= shortfall }) {
                room.insert(one)
                continue
            }
            var remaining = shortfall
            for id in leftFirst where remaining > 0 {
                room.insert(id)
                remaining -= freed[id]!
            }
        }
        return room
    }
}
