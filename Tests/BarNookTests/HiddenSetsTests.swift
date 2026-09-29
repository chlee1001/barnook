// Modified by Chaehyeon Lee (2026): ordered lists, normalization and the store contract.
import Foundation
import Testing
@testable import BarNook

@MainActor
struct HiddenSetsTests {
    private func makeStore() -> UserDefaults {
        let name = "HiddenSetsTests.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: name)!
        store.removePersistentDomain(forName: name)
        return store
    }

    @Test func hiddenStateHidesBothSets() {
        let sets = HiddenSets(store: makeStore())
        sets.update(HiddenLists(hidden: ["a"], alwaysHidden: ["b"]))
        sets.isHiddenSetShown = false
        #expect(sets.identifiersToHide(isAlwaysHiddenEnabled: true) == ["a", "b"])
    }

    @Test func shownStateHidesOnlyAlwaysHidden() {
        let sets = HiddenSets(store: makeStore())
        sets.update(HiddenLists(hidden: ["a"], alwaysHidden: ["b"]))
        sets.isHiddenSetShown = true
        #expect(sets.identifiersToHide(isAlwaysHiddenEnabled: true) == ["b"])
    }

    @Test func disabledAlwaysHiddenIsNeverHidden() {
        let sets = HiddenSets(store: makeStore())
        sets.update(HiddenLists(hidden: ["a"], alwaysHidden: ["b"]))
        sets.isHiddenSetShown = true
        #expect(sets.identifiersToHide(isAlwaysHiddenEnabled: false).isEmpty)
    }

    @Test func persistsAcrossInstances() {
        let store = makeStore()
        let first = HiddenSets(store: store)
        first.update(HiddenLists(hidden: ["b", "a"], alwaysHidden: ["c"]))
        first.isHiddenSetShown = true

        let second = HiddenSets(store: store)
        #expect(second.hidden == ["b", "a"])
        #expect(second.alwaysHidden == ["c"])
        #expect(second.isHiddenSetShown)
    }

    @Test func normalizedDropsDuplicatesAndAlwaysWins() {
        let lists = HiddenLists(hidden: ["a", "b", "a", "c"], alwaysHidden: ["c", "c"])
        #expect(lists.normalized == HiddenLists(hidden: ["a", "b"], alwaysHidden: ["c"]))
    }

    @Test func storesTheOrderUnsorted() {
        let store = makeStore()
        HiddenSets(store: store).update(HiddenLists(hidden: ["b", "a"], alwaysHidden: []))
        #expect(store.stringArray(forKey: HiddenSets.Key.hidden) == ["b", "a"])
    }

    @Test func loadWritesBackNormalizedOverlap() {
        let store = makeStore()
        store.set(["a", "b"], forKey: HiddenSets.Key.hidden)
        store.set(["b"], forKey: HiddenSets.Key.alwaysHidden)
        let sets = HiddenSets(store: store)
        #expect(sets.lists == HiddenLists(hidden: ["a"], alwaysHidden: ["b"]))
        #expect(store.stringArray(forKey: HiddenSets.Key.hidden) == ["a"])
        #expect(store.stringArray(forKey: HiddenSets.Key.alwaysHidden) == ["b"])
    }

    @Test func reloadWritesBackWithoutDuplicates() {
        let store = makeStore()
        let sets = HiddenSets(store: store)
        store.set(["c", "a", "c"], forKey: HiddenSets.Key.hidden)
        sets.reload()
        #expect(sets.hidden == ["c", "a"])
        #expect(store.stringArray(forKey: HiddenSets.Key.hidden) == ["c", "a"])
    }

    @Test func reloadReadsTheStoredOrder() {
        let store = makeStore()
        let sets = HiddenSets(store: store)
        store.set(["c", "a"], forKey: HiddenSets.Key.hidden)
        sets.reload()
        #expect(sets.hidden == ["c", "a"])
    }

    @Test func aCleanStoreStaysUnwritten() {
        let store = makeStore()
        _ = HiddenSets(store: store)
        #expect(store.object(forKey: HiddenSets.Key.hidden) == nil)
        #expect(store.object(forKey: HiddenSets.Key.alwaysHidden) == nil)
    }

    @Test func unchangedUpdateDoesNotWrite() {
        let store = makeStore()
        let sets = HiddenSets(store: store)
        sets.update(HiddenLists(hidden: ["a"], alwaysHidden: []))
        store.set(["sentinel"], forKey: HiddenSets.Key.hidden)
        sets.update(HiddenLists(hidden: ["a"], alwaysHidden: []))
        #expect(store.stringArray(forKey: HiddenSets.Key.hidden) == ["sentinel"])
    }

    @Test func updateNormalizes() {
        let sets = HiddenSets(store: makeStore())
        sets.update(HiddenLists(hidden: ["a", "b"], alwaysHidden: ["b"]))
        #expect(sets.hidden == ["a"])
        #expect(sets.alwaysHidden == ["b"])
    }
}

@MainActor
struct AlwaysHiddenShownTests {
    private func makeSets() -> HiddenSets {
        let name = "AlwaysHiddenShownTests.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: name)!
        store.removePersistentDomain(forName: name)
        let sets = HiddenSets(store: store)
        sets.update(HiddenLists(hidden: ["a"], alwaysHidden: ["b"]))
        return sets
    }

    @Test func showingAlwaysHiddenHidesNothing() {
        let sets = makeSets()
        sets.isHiddenSetShown = true
        sets.isAlwaysHiddenSetShown = true
        #expect(sets.identifiersToHide(isAlwaysHiddenEnabled: true).isEmpty)
    }

    @Test func barIdentifiersPutAlwaysHiddenFirstOnlyWhenShown() {
        let sets = makeSets()
        sets.update(HiddenLists(hidden: ["c", "a"], alwaysHidden: ["d", "b"]))
        sets.show(includingAlwaysHidden: false)
        #expect(sets.barIdentifiers().leading.isEmpty)
        #expect(sets.barIdentifiers().trailing == ["c", "a"])
        sets.show(includingAlwaysHidden: true)
        #expect(sets.barIdentifiers().leading == ["d", "b"])
        #expect(sets.barIdentifiers().trailing == ["c", "a"])
    }

    @Test func alwaysHiddenShownIsNotPersisted() {
        let name = "AlwaysHiddenShownTests.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: name)!
        store.removePersistentDomain(forName: name)
        HiddenSets(store: store).isAlwaysHiddenSetShown = true
        #expect(HiddenSets(store: store).isAlwaysHiddenSetShown == false)
    }
}
