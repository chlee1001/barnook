// Modified by Chaehyeon Lee (2026): ordered lists kept in the store as shown; one write path.
import Foundation
import Observation

/// The two app lists in their order: the floating bar shows them left to right.
struct HiddenLists: Equatable, Sendable {
    var hidden: [String] = []
    var alwaysHidden: [String] = []

    /// Each id once, at its first place; an id in both lists stays in
    /// `alwaysHidden` only, since that set wins when both are hidden.
    var normalized: HiddenLists {
        let alwaysHidden = Self.unique(alwaysHidden)
        let always = Set(alwaysHidden)
        return HiddenLists(hidden: Self.unique(hidden).filter { !always.contains($0) }, alwaysHidden: alwaysHidden)
    }

    private static func unique(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }
}

/// The two lists of bundle identifiers BarNook hides, and which of them are
/// currently shown. The lists and `isHiddenSetShown` persist in
/// `UserDefaults`; the lists are stored in their order, which the floating
/// bar and the Apps list show. Memory is always normalized and the store
/// always matches it.
@MainActor
@Observable
final class HiddenSets {
    enum Key {
        static let hidden = "hiddenBundleIdentifiers"
        static let alwaysHidden = "alwaysHiddenBundleIdentifiers"
        static let isHiddenSetShown = "isHiddenSetShown"
    }

    private let store: UserDefaults

    private(set) var hidden: [String]
    private(set) var alwaysHidden: [String]

    var lists: HiddenLists { HiddenLists(hidden: hidden, alwaysHidden: alwaysHidden) }

    init(store: UserDefaults = .standard) {
        self.store = store
        let stored = Self.read(from: store)
        let lists = stored.normalized
        hidden = lists.hidden
        alwaysHidden = lists.alwaysHidden
        isHiddenSetShown = store.bool(forKey: Key.isHiddenSetShown)
        Self.persist(lists, over: stored, in: store)
    }

    /// Reads both lists from the store again, after an import wrote to it.
    /// A list the import left overlapping or with duplicates is written
    /// back normalized.
    func reload() {
        let stored = Self.read(from: store)
        let lists = stored.normalized
        Self.persist(lists, over: stored, in: store)
        if lists.hidden != hidden { hidden = lists.hidden }
        if lists.alwaysHidden != alwaysHidden { alwaysHidden = lists.alwaysHidden }
    }

    /// The only way to change the lists. Both change in one call, so an app
    /// moving between them is never in both or neither; only a list that
    /// changed is written.
    func update(_ new: HiddenLists) {
        let new = new.normalized
        let old = lists
        guard new != old else { return }
        Self.persist(new, over: old, in: store)
        if new.hidden != hidden { hidden = new.hidden }
        if new.alwaysHidden != alwaysHidden { alwaysHidden = new.alwaysHidden }
    }

    var isHiddenSetShown: Bool {
        didSet { store.set(isHiddenSetShown, forKey: Key.isHiddenSetShown) }
    }

    /// Not persisted: the always-hidden set hides again at every launch.
    var isAlwaysHiddenSetShown = false

    func show(includingAlwaysHidden: Bool) {
        isHiddenSetShown = true
        isAlwaysHiddenSetShown = includingAlwaysHidden
    }

    func hide() {
        isHiddenSetShown = false
        isAlwaysHiddenSetShown = false
    }

    /// The floating bar's apps, left to right: the always-hidden list first
    /// while an Option-click shows it, then the hidden list.
    func barIdentifiers() -> (leading: [String], trailing: [String]) {
        (isAlwaysHiddenSetShown ? alwaysHidden : [], hidden)
    }

    /// The bundle identifiers a restriction must hide right now.
    /// Empty means no restriction is necessary.
    func identifiersToHide(isAlwaysHiddenEnabled: Bool) -> Set<String> {
        var result = isHiddenSetShown ? [] : Set(hidden)
        if isAlwaysHiddenEnabled, !isAlwaysHiddenSetShown {
            result.formUnion(alwaysHidden)
        }
        return result
    }

    private static func read(from store: UserDefaults) -> HiddenLists {
        HiddenLists(
            hidden: store.stringArray(forKey: Key.hidden) ?? [],
            alwaysHidden: store.stringArray(forKey: Key.alwaysHidden) ?? []
        )
    }

    /// A key is written only when its list differs, so a clean or empty
    /// store stays unwritten.
    private static func persist(_ new: HiddenLists, over old: HiddenLists, in store: UserDefaults) {
        if new.hidden != old.hidden { store.set(new.hidden, forKey: Key.hidden) }
        if new.alwaysHidden != old.alwaysHidden { store.set(new.alwaysHidden, forKey: Key.alwaysHidden) }
    }
}
