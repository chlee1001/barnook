// Modified by Chaehyeon Lee (2026): BarNook launch alert; required-permission onboarding.
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
