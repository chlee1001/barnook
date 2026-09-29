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

    /// The lists after `id` is dragged into `target`, before `anchor`: at
    /// the end when the anchor is not in that list, unchanged when the
    /// anchor is the app itself. Into Shown the app only leaves its list.
    /// Other ids keep their order.
    static func move(_ id: String, to target: AppVisibility, before anchor: String?, in lists: HiddenLists) -> HiddenLists {
        guard anchor != id else { return lists }
        var result = lists
        result.hidden.removeAll { $0 == id }
        result.alwaysHidden.removeAll { $0 == id }
        func insert(into list: inout [String]) {
            if let anchor, let index = list.firstIndex(of: anchor) {
                list.insert(id, at: index)
            } else {
                list.append(id)
            }
        }
        switch target {
        case .shown: break
        case .hidden: insert(into: &result.hidden)
        case .alwaysHidden: insert(into: &result.alwaysHidden)
        }
        return result
    }

    /// The lists after `id` moves `offset` places within its own list.
    /// Unchanged past either end, and for a shown app.
    static func step(_ id: String, by offset: Int, in lists: HiddenLists) -> HiddenLists {
        func stepped(_ list: [String]) -> [String]? {
            guard let index = list.firstIndex(of: id) else { return nil }
            let target = index + offset
            guard list.indices.contains(target) else { return list }
            var list = list
            list.remove(at: index)
            list.insert(id, at: target)
            return list
        }
        var result = lists
        if let list = stepped(lists.alwaysHidden) {
            result.alwaysHidden = list
        } else if let list = stepped(lists.hidden) {
            result.hidden = list
        }
        return result
    }

    /// Whether a drag from one group into another (or within one) is taken.
    /// Within a group only a reorder, never in Shown. Across groups the
    /// same rules as the row's buttons: the divider's always-hidden toggle
    /// by position, the list's choices otherwise.
    static func canMove(
        from: AppVisibility, to: AppVisibility, isDividerActive: Bool,
        isAlwaysHiddenEnabled: Bool, canReorder: Bool
    ) -> Bool {
        if from == to { return to != .shown && canReorder }
        if isDividerActive {
            return to == alwaysHiddenToggleTarget(current: from, alwaysHiddenEnabled: isAlwaysHiddenEnabled)
        }
        return listSelectable(alwaysHiddenEnabled: isAlwaysHiddenEnabled).contains(to)
    }

    /// The lists after `ids` are dropped into `target` before `anchor`, in
    /// drag order, and the last app that moved. An id not in `listed`, or
    /// one `allowed` refuses, stays where it was; nil when none moved.
    static func drop(
        _ ids: [String], into target: AppVisibility, before anchor: String?, listed: Set<String>,
        in lists: HiddenLists, allowed: (_ from: AppVisibility) -> Bool
    ) -> (lists: HiddenLists, moved: String)? {
        var result = lists
        var moved: String?
        for id in ids where listed.contains(id) && allowed(of(id, in: result)) {
            result = move(id, to: target, before: anchor, in: result)
            moved = id
        }
        guard let moved, result != lists else { return nil }
        return (result, moved)
    }

    /// The app's place in its list, counted from 1, or nil for a shown app.
    static func place(of id: String, in lists: HiddenLists) -> (index: Int, count: Int)? {
        let list = switch of(id, in: lists) {
        case .shown: [String]()
        case .hidden: lists.hidden
        case .alwaysHidden: lists.alwaysHidden
        }
        guard let index = list.firstIndex(of: id) else { return nil }
        return (index + 1, list.count)
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
