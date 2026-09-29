import Foundation

/// What BarNook does with one app's menu bar items: the app is in the hidden
/// list, the always-hidden list, or neither.
enum AppVisibility: CaseIterable, Hashable {
    case shown, hidden, alwaysHidden

    /// A line under the app's name.
    enum Note: Equatable { case notRunning, alwaysHiddenPaused }

    /// An app in both lists counts as always hidden, the same rule as
    /// `HiddenLists.normalized`.
    static func of(_ id: String, in lists: HiddenLists) -> AppVisibility {
        if lists.alwaysHidden.contains(id) { return .alwaysHidden }
        if lists.hidden.contains(id) { return .hidden }
        return .shown
    }

    /// The lists after `id` takes `visibility`: an app that changes joins
    /// the end of its new list and leaves the others; an app already there
    /// keeps its place. Other ids keep their order.
    static func apply(_ visibility: AppVisibility, to id: String, in lists: HiddenLists) -> HiddenLists {
        guard of(id, in: lists) != visibility else { return lists }
        var result = lists
        result.hidden.removeAll { $0 == id }
        result.alwaysHidden.removeAll { $0 == id }
        switch visibility {
        case .shown: break
        case .hidden: result.hidden.append(id)
        case .alwaysHidden: result.alwaysHidden.append(id)
        }
        return result
    }

    /// The listed apps in three groups. The hidden groups keep the lists'
    /// order and skip ids that are not listed; shown keeps `listed` order.
    static func groups(listed: [String], in lists: HiddenLists)
        -> (hidden: [String], alwaysHidden: [String], shown: [String])
    {
        let listedSet = Set(listed)
        let always = lists.alwaysHidden.filter { listedSet.contains($0) }
        let alwaysSet = Set(always)
        let hidden = lists.hidden.filter { listedSet.contains($0) && !alwaysSet.contains($0) }
        let hiddenSet = Set(hidden)
        let shown = listed.filter { !hiddenSet.contains($0) && !alwaysSet.contains($0) }
        return (hidden, always, shown)
    }

    /// The choices a row offers when the user picks from the list.
    static func listSelectable(alwaysHiddenEnabled: Bool) -> Set<AppVisibility> {
        alwaysHiddenEnabled ? [.shown, .hidden, .alwaysHidden] : [.shown, .hidden]
    }

    /// When the icon's position decides hidden or shown, a row can still
    /// move an app in or out of the always-hidden set. Leaving it shows the
    /// app until the divider files it again. While the set is off an app
    /// can still leave it, as in the list, but none can join: nil.
    static func alwaysHiddenToggleTarget(current: AppVisibility, alwaysHiddenEnabled: Bool) -> AppVisibility? {
        if current == .alwaysHidden { return .shown }
        return alwaysHiddenEnabled ? .alwaysHidden : nil
    }

    static func note(isRunning: Bool, visibility: AppVisibility, alwaysHiddenEnabled: Bool) -> Note? {
        if !isRunning { return .notRunning }
        if visibility == .alwaysHidden, !alwaysHiddenEnabled { return .alwaysHiddenPaused }
        return nil
    }

    /// Search ignores case and accents; an empty query matches every app.
    static func matches(name: String, query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
