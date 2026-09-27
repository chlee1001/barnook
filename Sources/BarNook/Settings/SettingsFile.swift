// Modified by Chaehyeon Lee (2026): BarNook import diagnostics and menu bar icon choices.
import Foundation

/// The settings as a property list, for "Export…" and "Import…" in General.
/// Only the settings keys travel: not the shown state, not the Accessibility
/// opt-out, and none of AppKit's own keys in the defaults domain.
enum SettingsFile {
    enum ValueKind {
        case bool, number, stringArray
        /// A string from a fixed set, such as an enum's raw values.
        case choice(Set<String>)
    }

    private static let placements = Set(AppState.HiddenItemsPlacement.allCases.map(\.rawValue))
    private static let icons = Set(MenuBarIcon.allCases.map(\.rawValue))

    static let keys: [String: ValueKind] = [
        AppState.Key.isAlwaysHiddenEnabled: .bool,
        AppState.Key.rehideOnTimeout: .bool,
        AppState.Key.rehideOnClickOutside: .bool,
        AppState.Key.rehideOnFocusChange: .bool,
        AppState.Key.rehideTimeout: .number,
        AppState.Key.clockZoneWidth: .number,
        AppState.Key.hidesAppsLeftOfIcon: .bool,
        AppState.Key.hiddenItemsPlacement: .choice(placements),
        AppState.Key.hiddenMenuBarIcon: .choice(icons),
        AppState.Key.shownMenuBarIcon: .choice(icons),
        HiddenSets.Key.hidden: .stringArray,
        HiddenSets.Key.alwaysHidden: .stringArray,
    ]

    enum ImportError: LocalizedError {
        case notADictionary
        case noKnownKeys
        case wrongType(key: String)

        var errorDescription: String? {
            switch self {
            case .notADictionary: "The file is not a property list of settings."
            case .noKnownKeys: "The file has no BarNook settings."
            case .wrongType(let key): "The value of “\(key)” has the wrong type or an unknown value."
            }
        }
    }

    static func export(from store: UserDefaults) throws -> Data {
        var plist: [String: Any] = [:]
        for key in keys.keys {
            if let value = store.object(forKey: key) {
                plist[key] = value
            }
        }
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    /// Writes the known keys of `data` into `store`. Unknown keys are ignored.
    /// Known keys that the file lacks keep their current value. The store is
    /// untouched if any value has the wrong type.
    static func `import`(_ data: Data, into store: UserDefaults) throws {
        let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
        guard let plist = plist as? [String: Any] else { throw ImportError.notADictionary }
        var values: [String: Any] = [:]
        for (key, kind) in keys {
            guard let value = plist[key] else { continue }
            guard kind.matches(value) else { throw ImportError.wrongType(key: key) }
            values[key] = value
        }
        guard !values.isEmpty else { throw ImportError.noKnownKeys }
        for (key, value) in values {
            store.set(value, forKey: key)
        }
    }
}

extension SettingsFile.ValueKind {
    func matches(_ value: Any) -> Bool {
        switch self {
        case .bool: value is Bool
        case .number: value is NSNumber && !(value is Bool)
        case .stringArray: value is [String]
        case .choice(let allowed): (value as? String).map(allowed.contains) ?? false
        }
    }
}
