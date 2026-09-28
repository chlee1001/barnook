import Foundation

/// What BarNook does with one app's menu bar items. An app is in the hidden
/// set, the always-hidden set, or neither; this names the three cases so a
/// Settings row picks one instead of two checkboxes in two lists.
enum AppVisibility: CaseIterable, Hashable {
    case shown, hidden, alwaysHidden

    /// A line under the app's name.
    enum Note: Equatable { case notRunning, alwaysHiddenPaused }

    /// An app in both sets (possible from an older imported file) counts as
    /// always hidden, since that set wins when both are hidden.
    static func of(_ id: String, hidden: Set<String>, alwaysHidden: Set<String>) -> AppVisibility {
        if alwaysHidden.contains(id) { return .alwaysHidden }
        if hidden.contains(id) { return .hidden }
        return .shown
    }

    /// The two sets after `id` takes `visibility`: it is in the matching set
    /// only. Other ids are untouched.
    static func apply(
        _ visibility: AppVisibility, to id: String, hidden: Set<String>, alwaysHidden: Set<String>
    ) -> (hidden: Set<String>, alwaysHidden: Set<String>) {
        var hidden = hidden
        var alwaysHidden = alwaysHidden
        hidden.remove(id)
        alwaysHidden.remove(id)
        switch visibility {
        case .shown: break
        case .hidden: hidden.insert(id)
        case .alwaysHidden: alwaysHidden.insert(id)
        }
        return (hidden, alwaysHidden)
    }

    /// The choices a row offers when the user picks from the list.
    static func listSelectable(alwaysHiddenEnabled: Bool) -> Set<AppVisibility> {
        alwaysHiddenEnabled ? [.shown, .hidden, .alwaysHidden] : [.shown, .hidden]
    }

    /// When the icon's position decides hidden or shown, a row can still
    /// move an app in or out of the always-hidden set. Nil while that set is
    /// off. Leaving it shows the app until the divider files it again.
    static func alwaysHiddenToggleTarget(current: AppVisibility, alwaysHiddenEnabled: Bool) -> AppVisibility? {
        guard alwaysHiddenEnabled else { return nil }
        return current == .alwaysHidden ? .shown : .alwaysHidden
    }

    static func note(isRunning: Bool, visibility: AppVisibility, alwaysHiddenEnabled: Bool) -> Note? {
        if !isRunning { return .notRunning }
        if visibility == .alwaysHidden, !alwaysHiddenEnabled { return .alwaysHiddenPaused }
        return nil
    }

    /// Counts over the listed apps only.
    static func counts(ids: [String], hidden: Set<String>, alwaysHidden: Set<String>) -> (hidden: Int, always: Int) {
        ids.reduce(into: (hidden: 0, always: 0)) { counts, id in
            switch of(id, hidden: hidden, alwaysHidden: alwaysHidden) {
            case .shown: break
            case .hidden: counts.hidden += 1
            case .alwaysHidden: counts.always += 1
            }
        }
    }

    /// Search ignores case and accents; an empty query matches every app.
    static func matches(name: String, query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
