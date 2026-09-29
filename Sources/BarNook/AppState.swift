// Modified by Chaehyeon Lee (2026): persisted menu bar icon choices; the recommended placement for a display.
import Foundation
import Observation

/// Settings other than the hidden sets. Every property reads and writes one
/// `UserDefaults` key so a Settings view and the menu bar code see the same value.
@MainActor
@Observable
final class AppState {
    enum Key {
        static let isAlwaysHiddenEnabled = "isAlwaysHiddenEnabled"
        static let rehideOnTimeout = "rehideOnTimeout"
        static let rehideOnClickOutside = "rehideOnClickOutside"
        static let rehideOnFocusChange = "rehideOnFocusChange"
        static let rehideTimeout = "rehideTimeout"
        static let clockZoneWidth = "clockZoneWidth"
        static let hidesAppsLeftOfIcon = "hidesAppsLeftOfIcon"
        static let hiddenItemsPlacement = "hiddenItemsPlacement"
        static let hiddenMenuBarIcon = "hiddenMenuBarIcon"
        static let shownMenuBarIcon = "shownMenuBarIcon"
    }

    /// Where a shown set goes. See spec F8.
    enum HiddenItemsPlacement: String, CaseIterable {
        /// The restriction lifts and the items return to the menu bar.
        case menuBar
        /// The restriction stays and a panel below the menu bar lists the apps.
        case floatingBar
    }

    static let defaults: [String: Any] = [
        Key.isAlwaysHiddenEnabled: true,
        Key.rehideOnTimeout: true,
        Key.rehideOnClickOutside: true,
        Key.rehideOnFocusChange: false,
        Key.rehideTimeout: 15.0,
        Key.clockZoneWidth: 300.0,
        Key.hidesAppsLeftOfIcon: false,
        Key.hiddenItemsPlacement: HiddenItemsPlacement.menuBar.rawValue,
        Key.hiddenMenuBarIcon: MenuBarIcon.nook.rawValue,
        Key.shownMenuBarIcon: MenuBarIcon.chevronLeft.rawValue,
    ]

    /// The placement default is `recommendedPlacement(hasNotch:)`. Registered,
    /// not written, so a user who never chose follows the display at each launch.
    static func registerDefaults(hasNotch: Bool) {
        UserDefaults.standard.register(defaults: registeredDefaults(hasNotch: hasNotch))
    }

    /// The values `registerDefaults` registers. Registration is process-wide,
    /// so tests read this instead.
    static func registeredDefaults(hasNotch: Bool) -> [String: Any] {
        var defaults = defaults
        defaults[Key.hiddenItemsPlacement] = recommendedPlacement(hasNotch: hasNotch).rawValue
        return defaults
    }

    /// A notch collapses shown items that do not fit, so the bar suits it;
    /// without one the items can return to the menu bar.
    static func recommendedPlacement(hasNotch: Bool) -> HiddenItemsPlacement {
        hasNotch ? .floatingBar : .menuBar
    }

    private let store: UserDefaults

    init(store: UserDefaults = .standard) {
        self.store = store
        isAlwaysHiddenEnabled = store.bool(forKey: Key.isAlwaysHiddenEnabled)
        rehideOnTimeout = store.bool(forKey: Key.rehideOnTimeout)
        rehideOnClickOutside = store.bool(forKey: Key.rehideOnClickOutside)
        rehideOnFocusChange = store.bool(forKey: Key.rehideOnFocusChange)
        rehideTimeout = store.double(forKey: Key.rehideTimeout)
        clockZoneWidth = store.double(forKey: Key.clockZoneWidth)
        hidesAppsLeftOfIcon = store.bool(forKey: Key.hidesAppsLeftOfIcon)
        hiddenItemsPlacement = Self.placement(in: store)
        hiddenMenuBarIcon = Self.icon(in: store, forKey: Key.hiddenMenuBarIcon, default: .nook)
        shownMenuBarIcon = Self.icon(in: store, forKey: Key.shownMenuBarIcon, default: .chevronLeft)
    }

    private static func placement(in store: UserDefaults) -> HiddenItemsPlacement {
        store.string(forKey: Key.hiddenItemsPlacement).flatMap(HiddenItemsPlacement.init) ?? .menuBar
    }

    private static func icon(in store: UserDefaults, forKey key: String, default fallback: MenuBarIcon) -> MenuBarIcon {
        store.string(forKey: key).flatMap(MenuBarIcon.init) ?? fallback
    }

    /// Reads every value from the store again, after an import wrote to it.
    func reload() {
        isAlwaysHiddenEnabled = store.bool(forKey: Key.isAlwaysHiddenEnabled)
        rehideOnTimeout = store.bool(forKey: Key.rehideOnTimeout)
        rehideOnClickOutside = store.bool(forKey: Key.rehideOnClickOutside)
        rehideOnFocusChange = store.bool(forKey: Key.rehideOnFocusChange)
        rehideTimeout = store.double(forKey: Key.rehideTimeout)
        clockZoneWidth = store.double(forKey: Key.clockZoneWidth)
        hidesAppsLeftOfIcon = store.bool(forKey: Key.hidesAppsLeftOfIcon)
        hiddenItemsPlacement = Self.placement(in: store)
        hiddenMenuBarIcon = Self.icon(in: store, forKey: Key.hiddenMenuBarIcon, default: .nook)
        shownMenuBarIcon = Self.icon(in: store, forKey: Key.shownMenuBarIcon, default: .chevronLeft)
    }

    var isAlwaysHiddenEnabled: Bool {
        didSet { store.set(isAlwaysHiddenEnabled, forKey: Key.isAlwaysHiddenEnabled) }
    }
    var rehideOnTimeout: Bool {
        didSet { store.set(rehideOnTimeout, forKey: Key.rehideOnTimeout) }
    }
    var rehideOnClickOutside: Bool {
        didSet { store.set(rehideOnClickOutside, forKey: Key.rehideOnClickOutside) }
    }
    var rehideOnFocusChange: Bool {
        didSet { store.set(rehideOnFocusChange, forKey: Key.rehideOnFocusChange) }
    }
    /// Seconds. 1–300.
    var rehideTimeout: Double {
        didSet { store.set(rehideTimeout, forKey: Key.rehideTimeout) }
    }
    /// Points from the right edge of the menu bar. The restriction lifts
    /// while the pointer is in this zone, so that a clock click opens
    /// Notification Center. See `ClockZone`.
    var clockZoneWidth: Double {
        didSet { store.set(clockZoneWidth, forKey: Key.clockZoneWidth) }
    }
    /// The BarNook icon is the divider: apps left of it are the hidden set.
    /// Needs the Accessibility permission. See `IconDivider`.
    var hidesAppsLeftOfIcon: Bool {
        didSet { store.set(hidesAppsLeftOfIcon, forKey: Key.hidesAppsLeftOfIcon) }
    }
    var hiddenItemsPlacement: HiddenItemsPlacement {
        didSet { store.set(hiddenItemsPlacement.rawValue, forKey: Key.hiddenItemsPlacement) }
    }
    var hiddenMenuBarIcon: MenuBarIcon {
        didSet { store.set(hiddenMenuBarIcon.rawValue, forKey: Key.hiddenMenuBarIcon) }
    }
    var shownMenuBarIcon: MenuBarIcon {
        didSet { store.set(shownMenuBarIcon.rawValue, forKey: Key.shownMenuBarIcon) }
    }
}
