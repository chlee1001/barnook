// Modified by Chaehyeon Lee (2026): BarNook launch alert.
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let sets: HiddenSets
    private let state: AppState
    private let permission = AccessibilityPermission()
    private let updater = Updater()
    private var settingsWindow: SettingsWindow?
    private var menuBar: MenuBarManager?
    private var clockZone: ClockZone?
    private var divider: IconDivider?

    override init() {
        AppState.registerDefaults(hasNotch: NSScreen.screens.contains { $0.safeAreaInsets.top > 0 })
        sets = HiddenSets()
        state = AppState()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        permission.askAtLaunchIfNeeded()
        clockZone = ClockZone(state: state, permission: permission)
        divider = IconDivider(state: state, sets: sets, permission: permission) { [weak menuBar] in
            menuBar?.iconFrame
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        divider?.release()
        menuBar?.release()
    }

    private func showSettings() {
        if settingsWindow == nil, let clockZone {
            settingsWindow = SettingsWindow(state: state, sets: sets, permission: permission, clockZone: clockZone, updater: updater)
        }
        settingsWindow?.show()
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
