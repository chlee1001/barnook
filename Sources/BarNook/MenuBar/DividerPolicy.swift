import Foundation

/// The pure decision behind the icon as divider, kept apart from
/// `IconDivider` so tests can cover it.
enum DividerPolicy {
    /// The hidden set after a look at the menu bar. A visible app left of
    /// the icon joins. A visible app right of it leaves, but only while
    /// the set is shown: while it is hidden, a hidden app can still be on
    /// its way out and must not be read as "visible on the right". An app
    /// with an item on each side hides: hiding is per app. Apps that are
    /// not visible keep their membership, and the always-hidden set and
    /// BarNook itself are not touched.
    static func hiddenSet(
        current: Set<String>,
        alwaysHidden: Set<String>,
        own: String?,
        left: Set<String>,
        right: Set<String>,
        isShown: Bool
    ) -> Set<String> {
        var result = isShown ? current.subtracting(right) : current
        result.formUnion(left)
        result.subtract(alwaysHidden)
        if let own {
            result.remove(own)
        }
        return result
    }
}
