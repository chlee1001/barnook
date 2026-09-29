// Modified by Chaehyeon Lee (2026): BarNook launch alert; required-permission onboarding; an Edit menu for text-field shortcuts; a shared notch check.
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let sets: HiddenSets
    private let state: AppState
    private let permission = Permissions()
    private let updater = Updater()
    private var settingsWindow: SettingsWindow?
    private var onboarding: PermissionsOnboarding?
    private var menuBar: MenuBarManager?
    private var clockZone: ClockZone?
    private var divider: IconDivider?

    override init() {
        AppState.registerDefaults(hasNotch: NSScreen.anyHasNotch)
        sets = HiddenSets()
        state = AppState()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.editMenu()
        let restriction: MenuBarRestriction
        do {
            restriction = try MenuBarRestriction()
        } catch {
            Self.quit(with: error)
            return
        }
        menuBar = MenuBarManager(restriction: restriction, sets: sets, state: state, permission: permission, updater: updater) { [unowned self] in
            showSettings()
        }
        if PermissionGate.showsOnboarding(
            granted: permission.areGranted, trigger: .launch,
            skipsAtLaunch: UserDefaults.standard.bool(forKey: PermissionGate.skipAtLaunchKey)
        ) {
            showOnboarding()
        }
        clockZone = ClockZone(state: state, permission: permission)
        divider = IconDivider(state: state, sets: sets, permission: permission) { [weak menuBar] in
            menuBar?.iconFrame
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        divider?.release()
        menuBar?.release()
    }

    /// Settings opens only once both permissions are granted; until then the
    /// onboarding shows instead.
    private func showSettings() {
        permission.refresh()
        if PermissionGate.showsOnboarding(granted: permission.areGranted, trigger: .settings, skipsAtLaunch: false) {
            showOnboarding()
            return
        }
        onboarding?.close()
        if settingsWindow == nil, let clockZone {
            settingsWindow = SettingsWindow(state: state, sets: sets, permission: permission, clockZone: clockZone, updater: updater)
        }
        settingsWindow?.show()
    }

    private func showOnboarding() {
        if onboarding == nil {
            onboarding = PermissionsOnboarding(permissions: permission) { [unowned self] in
                showSettings()
            }
        }
        onboarding?.show()
    }

    /// An agent app shows no menu bar, but text fields find Cut, Copy, Paste
    /// and Select All through the main menu's key equivalents. Without one
    /// the Settings fields ignore Cmd-X/C/V/A.
    private static func editMenu() -> NSMenu {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        // The first item is always the application menu; Edit follows it.
        let main = NSMenu()
        let app = NSMenuItem()
        app.submenu = NSMenu()
        main.addItem(app)
        let item = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        item.submenu = edit
        main.addItem(item)
        return main
    }

    private static func quit(with error: Error) {
        let alert = NSAlert()
        alert.messageText = "BarNook cannot run on this version of macOS"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Quit")
        NSApp.activate()
        alert.runModal()
        NSApp.terminate(nil)
    }
}

extension NSScreen {
    /// A screen with a camera housing reports a top safe-area inset.
    static var anyHasNotch: Bool { screens.contains { $0.safeAreaInsets.top > 0 } }
}
