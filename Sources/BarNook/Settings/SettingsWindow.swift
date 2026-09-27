// Modified by Chaehyeon Lee (2026): BarNook window title.
import AppKit
import SwiftUI

/// The one Settings window. Closing it hides it; `show()` brings it back.
@MainActor
final class SettingsWindow {
    private let window: NSWindow
    private let apps: RunningApps
    private let loginItem = LaunchAtLogin()

    init(state: AppState, sets: HiddenSets, permission: AccessibilityPermission, clockZone: ClockZone, updater: Updater) {
        apps = RunningApps(permission: permission)
        let content = SettingsView()
            .environment(state)
            .environment(sets)
            .environment(apps)
            .environment(loginItem)
            .environment(permission)
            .environment(clockZone)
            .environment(updater)
        let host = NSHostingController(rootView: content)
        host.sizingOptions = .preferredContentSize
        window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = host
        window.title = "BarNook Settings"
        window.isReleasedWhenClosed = false
        window.center()
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
