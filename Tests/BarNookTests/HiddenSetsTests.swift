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
        sets.hidden = ["a"]
        sets.alwaysHidden = ["b"]
        sets.isHiddenSetShown = false
        #expect(sets.identifiersToHide(isAlwaysHiddenEnabled: true) == ["a", "b"])
    }

    @Test func shownStateHidesOnlyAlwaysHidden() {
        let sets = HiddenSets(store: makeStore())
        sets.hidden = ["a"]
        sets.alwaysHidden = ["b"]
        sets.isHiddenSetShown = true
        #expect(sets.identifiersToHide(isAlwaysHiddenEnabled: true) == ["b"])
    }

    @Test func disabledAlwaysHiddenIsNeverHidden() {
        let sets = HiddenSets(store: makeStore())
        sets.hidden = ["a"]
        sets.alwaysHidden = ["b"]
        sets.isHiddenSetShown = true
        #expect(sets.identifiersToHide(isAlwaysHiddenEnabled: false).isEmpty)
    }

    @Test func persistsAcrossInstances() {
        let store = makeStore()
        let first = HiddenSets(store: store)
        first.hidden = ["a", "b"]
        first.alwaysHidden = ["c"]
        first.isHiddenSetShown = true

        let second = HiddenSets(store: store)
        #expect(second.hidden == ["a", "b"])
        #expect(second.alwaysHidden == ["c"])
        #expect(second.isHiddenSetShown)
    }
}

@MainActor
struct AlwaysHiddenShownTests {
    private func makeSets() -> HiddenSets {
        let name = "AlwaysHiddenShownTests.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: name)!
        store.removePersistentDomain(forName: name)
        let sets = HiddenSets(store: store)
        sets.hidden = ["a"]
        sets.alwaysHidden = ["b"]
        return sets
    }

    @Test func showingAlwaysHiddenHidesNothing() {
        let sets = makeSets()
        sets.isHiddenSetShown = true
        sets.isAlwaysHiddenSetShown = true
        #expect(sets.identifiersToHide(isAlwaysHiddenEnabled: true).isEmpty)
    }

    @Test func alwaysHiddenShownIsNotPersisted() {
        let name = "AlwaysHiddenShownTests.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: name)!
        store.removePersistentDomain(forName: name)
        HiddenSets(store: store).isAlwaysHiddenSetShown = true
        #expect(HiddenSets(store: store).isAlwaysHiddenSetShown == false)
    }
}
