import AppKit
import SwiftUI

/// Whether the permission onboarding shows instead of Settings.
enum PermissionGate {
    enum Trigger { case launch, settings }

    /// At launch the onboarding shows until both permissions are granted,
    /// unless `skipsAtLaunch` (VM tests, which grant through the TCC
    /// database). Settings always routes through it while one is missing.
    static func showsOnboarding(granted: Bool, trigger: Trigger, skipsAtLaunch: Bool) -> Bool {
        guard !granted else { return false }
        return trigger == .settings || !skipsAtLaunch
    }

    static let skipAtLaunchKey = "skipsPermissionOnboarding"
}

/// The first window BarNook shows: both required permissions, their state,
/// and a way to grant each. Continue opens Settings once both are granted.
@MainActor
final class PermissionsOnboarding {
    private let window: NSWindow
    private let permissions: Permissions

    init(permissions: Permissions, openSettings: @escaping () -> Void) {
        self.permissions = permissions
        let view = PermissionsOnboardingView(openSettings: openSettings)
            .environment(permissions)
        let host = NSHostingController(rootView: view)
        host.sizingOptions = .preferredContentSize
        window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentViewController = host
        window.title = "Welcome to BarNook"
        window.isReleasedWhenClosed = false
        window.center()
    }

    var isVisible: Bool { window.isVisible }

    func show() {
        permissions.refresh()
        permissions.startPolling()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        permissions.stopPolling()
        window.orderOut(nil)
    }
}

private struct PermissionsOnboardingView: View {
    @Environment(Permissions.self) private var permissions
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("BarNook needs two permissions")
                .font(.title2.bold())
            Text("Grant both to open Settings. Hiding and showing work in the meantime.")
                .foregroundStyle(.secondary)
            row(
                .accessibility,
                title: "Accessibility",
                detail: "Reads where the clock and the menu bar items are, and clicks the clock for you in bar mode."
            )
            row(
                .screenRecording,
                title: "Screen Recording",
                detail: "Takes a picture of the menu bar that covers it while the clock opens Notification Center, so hidden items never show. The picture stays in memory and is thrown away at once."
            )
            if permissions.hasRequestedScreenRecording, !permissions.isScreenRecordingGranted {
                HStack {
                    Text("macOS applies Screen Recording after BarNook opens again.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Relaunch BarNook", action: permissions.relaunch)
                }
            }
            HStack {
                Spacer()
                Button("Continue", action: openSettings)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!permissions.areGranted)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func row(_ kind: Permissions.Kind, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: permissions.isGranted(kind) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(permissions.isGranted(kind) ? .green : .secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if permissions.isGranted(kind) {
                Text("Granted").foregroundStyle(.secondary)
            } else {
                Button("Grant…") { permissions.request(kind) }
            }
        }
    }
}
