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

/// The window shown while a required permission is missing: both
/// permissions, their state, and a way to grant each. Continue opens
/// Settings once both are granted.
@MainActor
final class PermissionsOnboarding {
    private let window: NSWindow
    private let permissions: Permissions
    private var closeObserver: NSObjectProtocol?

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
        // The close button hides the window; the permission poll stops with it.
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak permissions] _ in
            Task { @MainActor in permissions?.stopPolling() }
        }
    }

    isolated deinit {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
    }

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
        let status = permissions.status
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Set up BarNook")
                        .font(.title2.bold())
                    Text("Allow both to open Settings. Hiding and showing work in the meantime.")
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                ProgressView(value: Double(status.allowedCount), total: Double(Permissions.Kind.allCases.count))
                Text("\(status.allowedCount) of \(Permissions.Kind.allCases.count) allowed")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ForEach(Array(Permissions.Kind.allCases.enumerated()), id: \.element) { index, kind in
                stepCard(kind, number: index + 1, step: status.step(kind))
            }
            DisclosureGroup("What does BarNook capture?") {
                Text("Only a picture of the menu bar, taken in bar mode while the pointer is on the clock or clicks it. It stays in memory and is discarded when the cover comes off. Nothing is saved or sent.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
            Divider()
            HStack(spacing: 12) {
                Text(Self.hint(status.hint))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Continue", action: openSettings)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!permissions.areGranted)
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    private func stepCard(_ kind: Permissions.Kind, number: Int, step: PermissionStatus.Step) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Self.color(step))
                switch step {
                case .waiting: Text("\(number)").font(.callout.bold()).foregroundStyle(.secondary)
                case .needsRelaunch: Image(systemName: "arrow.clockwise").font(.callout.bold()).foregroundStyle(.white)
                case .allowed: Image(systemName: "checkmark").font(.callout.bold()).foregroundStyle(.white)
                }
            }
            .frame(width: 26, height: 26)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(kind.title).font(.headline)
                Text(Self.detail(kind)).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                switch step {
                case .allowed:
                    Text("Allowed")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .foregroundStyle(.green)
                        .background(Color.green.opacity(0.15), in: Capsule())
                case .needsRelaunch:
                    Text("Needs relaunch")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    Button("Relaunch BarNook", action: permissions.relaunch)
                        .buttonStyle(.borderedProminent)
                    Button("Allow…") { permissions.request(kind) }
                        .buttonStyle(.borderless)
                        .font(.caption)
                case .waiting:
                    Button("Allow…") { permissions.request(kind) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(kind.title), \(Self.stepName(step))")
    }

    private static func detail(_ kind: Permissions.Kind) -> String {
        switch kind {
        case .accessibility:
            "Reads where the clock and the menu bar items are, and clicks the clock for you in bar mode."
        case .screenRecording:
            "Takes a picture of the menu bar and shows it over the bar while the clock opens Notification Center, so hidden items stay covered."
        }
    }

    private static func hint(_ hint: PermissionStatus.Hint) -> String {
        switch hint {
        case .ready:
            "All set. Settings opens next."
        case .relaunch:
            "macOS applies \(Permissions.Kind.screenRecording.title) after BarNook opens again."
        case .allow(let kinds) where kinds.count == 1:
            "Allow \(kinds[0].title) to continue."
        case .allow:
            "Allow both permissions to continue."
        }
    }

    private static func color(_ step: PermissionStatus.Step) -> Color {
        switch step {
        case .waiting: Color.secondary.opacity(0.2)
        case .needsRelaunch: .orange
        case .allowed: .green
        }
    }

    private static func stepName(_ step: PermissionStatus.Step) -> String {
        switch step {
        case .waiting: "not allowed"
        case .needsRelaunch: "needs relaunch"
        case .allowed: "allowed"
        }
    }
}
