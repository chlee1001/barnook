// Modified by Chaehyeon Lee (2026): BarNook status item key and icon choice coverage; the key list and the timeout range.
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
        source.set(MenuBarIcon.ellipsis.rawValue, forKey: AppState.Key.hiddenMenuBarIcon)
        source.set(MenuBarIcon.star.rawValue, forKey: AppState.Key.shownMenuBarIcon)
        source.set(["a", "b"], forKey: HiddenSets.Key.hidden)
        source.set(true, forKey: HiddenSets.Key.isHiddenSetShown)

        let target = makeStore()
        try SettingsFile.import(SettingsFile.export(from: source), into: target)

        #expect(target.bool(forKey: AppState.Key.rehideOnTimeout) == false)
        #expect(target.double(forKey: AppState.Key.rehideTimeout) == 42)
        #expect(target.string(forKey: AppState.Key.hiddenMenuBarIcon) == MenuBarIcon.ellipsis.rawValue)
        #expect(target.string(forKey: AppState.Key.shownMenuBarIcon) == MenuBarIcon.star.rawValue)
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

    @Test(arguments: [AppState.Key.hiddenMenuBarIcon, AppState.Key.shownMenuBarIcon, AppState.Key.hiddenItemsPlacement])
    func importRejectsAnUnknownChoice(key: String) throws {
        let target = makeStore()
        let data = try plist([HiddenSets.Key.hidden: ["a"], key: "unknown"])

        #expect(throws: SettingsFile.ImportError.self) {
            try SettingsFile.import(data, into: target)
        }
        #expect(target.object(forKey: HiddenSets.Key.hidden) == nil)
        #expect(target.object(forKey: key) == nil)
    }

    @Test @MainActor func iconChoiceFallsBackWhenUnrecognized() {
        let store = makeStore()
        store.set("unknown", forKey: AppState.Key.hiddenMenuBarIcon)
        let state = AppState(store: store)

        #expect(state.hiddenMenuBarIcon == .nook)
        #expect(state.shownMenuBarIcon == .chevronLeft)

        state.shownMenuBarIcon = .ellipsis
        #expect(store.string(forKey: AppState.Key.shownMenuBarIcon) == MenuBarIcon.ellipsis.rawValue)
        store.set(MenuBarIcon.dot.rawValue, forKey: AppState.Key.hiddenMenuBarIcon)
        state.reload()
        #expect(state.hiddenMenuBarIcon == .dot)
    }

    @Test @MainActor func allIconChoicesHaveTemplateImages() {
        for icon in MenuBarIcon.allCases {
            #expect(icon.image.isTemplate)
            #expect(icon.image.size.width > 0 && icon.image.size.height > 0)
        }
    }

    /// Written out by hand, not derived from `SettingsFile.keys`, so a key
    /// that disappears or changes kind fails here.
    @Test func settingsFileHasTheTwelveKeys() {
        let expected: [String: String] = [
            "isAlwaysHiddenEnabled": "bool", "rehideOnTimeout": "bool", "rehideOnClickOutside": "bool",
            "rehideOnFocusChange": "bool", "rehideTimeout": "number 1...300", "clockZoneWidth": "number",
            "hidesAppsLeftOfIcon": "bool", "hiddenItemsPlacement": "choice floatingBar,menuBar",
            "hiddenMenuBarIcon": "choice chevronLeft,chevronRight,dot,ellipsis,nook,star",
            "shownMenuBarIcon": "choice chevronLeft,chevronRight,dot,ellipsis,nook,star",
            "hiddenBundleIdentifiers": "stringArray", "alwaysHiddenBundleIdentifiers": "stringArray",
        ]
        #expect(SettingsFile.keys.mapValues(describe) == expected)
    }

    @Test func allTwelveKeysRoundTrip() throws {
        let values: [String: Any] = [
            "isAlwaysHiddenEnabled": false, "rehideOnTimeout": false, "rehideOnClickOutside": false,
            "rehideOnFocusChange": true, "rehideTimeout": 42.0, "clockZoneWidth": 180.0,
            "hidesAppsLeftOfIcon": true, "hiddenItemsPlacement": "floatingBar",
            "hiddenMenuBarIcon": "star", "shownMenuBarIcon": "dot",
            "hiddenBundleIdentifiers": ["a"], "alwaysHiddenBundleIdentifiers": ["b"],
        ]
        let source = makeStore()
        for (key, value) in values { source.set(value, forKey: key) }
        let target = makeStore()

        try SettingsFile.import(SettingsFile.export(from: source), into: target)

        for (key, value) in values {
            #expect(target.object(forKey: key) as? NSObject == value as? NSObject, "\(key)")
        }
    }

    @Test(arguments: [0.0, 301, -5, .nan])
    func importRefusesATimeoutOutOfRange(seconds: Double) throws {
        let target = makeStore()
        target.set(15.0, forKey: AppState.Key.rehideTimeout)
        target.set(["kept"], forKey: HiddenSets.Key.hidden)
        let data = try plist([HiddenSets.Key.hidden: ["a"], AppState.Key.rehideTimeout: seconds])

        #expect(throws: SettingsFile.ImportError.self) {
            try SettingsFile.import(data, into: target)
        }
        #expect(target.double(forKey: AppState.Key.rehideTimeout) == 15)
        #expect(target.stringArray(forKey: HiddenSets.Key.hidden) == ["kept"])
    }

    @Test(arguments: [1.0, 300, 42])
    func importAcceptsATimeoutInRange(seconds: Double) throws {
        let target = makeStore()
        try SettingsFile.import(try plist([AppState.Key.rehideTimeout: seconds]), into: target)
        #expect(target.double(forKey: AppState.Key.rehideTimeout) == seconds)
    }

    @Test func booleanAndNumberStayApart() throws {
        let target = makeStore()
        #expect(throws: SettingsFile.ImportError.self) {
            try SettingsFile.import(try plist([AppState.Key.rehideTimeout: true]), into: target)
        }
        #expect(throws: SettingsFile.ImportError.self) {
            try SettingsFile.import(try plist([AppState.Key.rehideOnTimeout: 1.0]), into: target)
        }
        #expect(target.object(forKey: AppState.Key.rehideTimeout) == nil)
        #expect(target.object(forKey: AppState.Key.rehideOnTimeout) == nil)
    }

    @Test @MainActor func placementDefaultFollowsTheNotch() {
        #expect(AppState.recommendedPlacement(hasNotch: true) == .floatingBar)
        #expect(AppState.recommendedPlacement(hasNotch: false) == .menuBar)

        let notch = makeStore()
        AppState.registerDefaults(in: notch, hasNotch: true)
        #expect(AppState(store: notch).hiddenItemsPlacement == .floatingBar)

        let chosen = makeStore()
        chosen.set(AppState.HiddenItemsPlacement.menuBar.rawValue, forKey: AppState.Key.hiddenItemsPlacement)
        AppState.registerDefaults(in: chosen, hasNotch: true)
        #expect(AppState(store: chosen).hiddenItemsPlacement == .menuBar)
    }

    @Test func outOfRangeErrorNamesTheRange() {
        let error = SettingsFile.ImportError.outOfRange(key: "rehideTimeout", range: 1...300)
        #expect(error.errorDescription == "The value of “rehideTimeout” is outside 1-300.")
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

    private func describe(_ kind: SettingsFile.ValueKind) -> String {
        switch kind {
        case .bool: "bool"
        case .stringArray: "stringArray"
        case .number(let range?): "number \(Int(range.lowerBound))...\(Int(range.upperBound))"
        case .number(nil): "number"
        case .choice(let values): "choice " + values.sorted().joined(separator: ",")
        }
    }

    private func plist(_ dictionary: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
    }
}
