// Modified by Chaehyeon Lee (2026): BarNook status item key coverage.
import Foundation
import Testing
@testable import BarNook

struct SettingsFileTests {
    private func makeStore() -> UserDefaults {
        let name = "SettingsFileTests.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: name)!
        store.removePersistentDomain(forName: name)
        return store
    }

    @Test func roundTrip() throws {
        let source = makeStore()
        source.set(false, forKey: AppState.Key.rehideOnTimeout)
        source.set(42.0, forKey: AppState.Key.rehideTimeout)
        source.set(["a", "b"], forKey: HiddenSets.Key.hidden)
        source.set(true, forKey: HiddenSets.Key.isHiddenSetShown)

        let target = makeStore()
        try SettingsFile.import(SettingsFile.export(from: source), into: target)

        #expect(target.bool(forKey: AppState.Key.rehideOnTimeout) == false)
        #expect(target.double(forKey: AppState.Key.rehideTimeout) == 42)
        #expect(target.stringArray(forKey: HiddenSets.Key.hidden) == ["a", "b"])
        #expect(target.object(forKey: HiddenSets.Key.isHiddenSetShown) == nil)
    }

    @Test func exportSkipsUnsetAndForeignKeys() throws {
        let source = makeStore()
        source.set(["a"], forKey: HiddenSets.Key.hidden)
        source.set(123, forKey: "NSStatusItem Preferred Position barnook.icon")

        let data = try SettingsFile.export(from: source)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        #expect(plist?.keys.sorted() == [HiddenSets.Key.hidden])
    }

    @Test func importKeepsKeysTheFileLacks() throws {
        let target = makeStore()
        target.set(["kept"], forKey: HiddenSets.Key.alwaysHidden)
        let data = try plist([HiddenSets.Key.hidden: ["a"]])

        try SettingsFile.import(data, into: target)

        #expect(target.stringArray(forKey: HiddenSets.Key.hidden) == ["a"])
        #expect(target.stringArray(forKey: HiddenSets.Key.alwaysHidden) == ["kept"])
    }

    @Test func importIgnoresUnknownKeys() throws {
        let target = makeStore()
        let data = try plist([HiddenSets.Key.hidden: ["a"], "somethingElse": 1])

        try SettingsFile.import(data, into: target)

        #expect(target.object(forKey: "somethingElse") == nil)
    }

    @Test func importAcceptsAnIntegerTimeout() throws {
        let target = makeStore()
        try SettingsFile.import(try plist([AppState.Key.rehideTimeout: 30]), into: target)
        #expect(target.double(forKey: AppState.Key.rehideTimeout) == 30)
    }

    @Test func importRejectsAWrongTypeAndLeavesTheStoreAlone() throws {
        let target = makeStore()
        target.set(["kept"], forKey: HiddenSets.Key.hidden)
        let data = try plist([HiddenSets.Key.alwaysHidden: ["a"], AppState.Key.rehideTimeout: "soon"])

        #expect(throws: SettingsFile.ImportError.self) {
            try SettingsFile.import(data, into: target)
        }
        #expect(target.stringArray(forKey: HiddenSets.Key.hidden) == ["kept"])
        #expect(target.object(forKey: HiddenSets.Key.alwaysHidden) == nil)
    }

    @Test func importRejectsAFileWithNoKnownKeys() throws {
        let data = try plist(["somethingElse": 1])
        #expect(throws: SettingsFile.ImportError.self) {
            try SettingsFile.import(data, into: makeStore())
        }
    }

    @Test func importRejectsANonDictionary() {
        #expect(throws: SettingsFile.ImportError.self) {
            try SettingsFile.import(Data("not a plist".utf8), into: makeStore())
        }
    }

    private func plist(_ dictionary: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
    }
}
