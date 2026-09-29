// Modified by Chaehyeon Lee (2026): the hidden list keeps its order; new apps join in menu bar order.
import Foundation

/// The pure decision behind the icon as divider, kept apart from
/// `IconDivider` so tests can cover it.
enum DividerPolicy {
    /// The hidden list after a look at the menu bar. A visible app left of
    /// the icon joins at the end, in menu bar order. A visible app right of
    /// it leaves, but only while the set is shown: while it is hidden, a
    /// hidden app can still be on its way out and must not be read as
    /// "visible on the right". An app with an item on each side hides:
    /// hiding is per app, and a member keeps its place. Apps that are not
    /// visible keep their membership and place, and the always-hidden list
    /// and BarNook itself are not touched. Applying the same split twice
    /// changes nothing.
    static func hiddenList(
        current: [String],
        alwaysHidden: [String],
        own: String?,
        left: [String],
        right: Set<String>,
        isShown: Bool
    ) -> [String] {
        let leftSet = Set(left)
        let excluded = Set(alwaysHidden).union(own.map { [$0] } ?? [])
        var result = current.filter { id in
            !excluded.contains(id) && !(isShown && right.contains(id) && !leftSet.contains(id))
        }
        var members = Set(result)
        for id in left where !excluded.contains(id) && members.insert(id).inserted {
            result.append(id)
        }
        return result
    }
}
