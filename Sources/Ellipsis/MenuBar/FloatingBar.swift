// Modified by Chaehyeon Lee (2026): added pin indicators and reachability hints.
import AppKit
import SwiftUI

/// The panel below the menu bar that lists the hidden apps while the set is
/// shown in bar mode. Spec F8. Non-activating, on every Space, next to
/// full-screen apps; the frontmost app keeps the focus. One app icon per
/// app: macOS 27 has no window per item to capture.
@MainActor
final class FloatingBar {
    struct App: Identifiable {
        let id: String
        let name: String
        let icon: NSImage
    }

    private let panel: NSPanel
    private let onClick: (String) -> Void

    init(onClick: @escaping (String) -> Void) {
        self.onClick = onClick
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.animationBehavior = .utilityWindow
    }

    var isVisible: Bool { panel.isVisible }

    /// The panel's frame in screen coordinates while it is visible.
    var frame: NSRect? { panel.isVisible ? panel.frame : nil }

    /// Shows `apps` under `iconFrame` (Cocoa coordinates), or at the right
    /// edge of `screen` when the icon has no frame. `pinned` marks the apps
    /// already pinned, so a click on them unpins. `unreachable` marks the
    /// apps macOS keeps hidden whatever the allow-list says, so a pin
    /// cannot draw them. `hint` is added to every tooltip, for the state
    /// without the Accessibility permission.
    func show(
        apps: [App], pinned: Set<String> = [], unreachable: Set<String> = [],
        hint: String?, iconFrame: NSRect?, screen: NSScreen
    ) {
        let view = NSHostingView(
            rootView: BarView(apps: apps, pinned: pinned, unreachable: unreachable, hint: hint, onClick: onClick)
        )
        view.sizingOptions = [.intrinsicContentSize]
        panel.contentView = view
        place(iconFrame: iconFrame, screen: screen)
        panel.orderFrontRegardless()
    }

    /// Moves the visible panel under `iconFrame`, for after the icon settles.
    func place(iconFrame: NSRect?, screen: NSScreen) {
        guard let view = panel.contentView else { return }
        let frame = FloatingBarPlacement.frame(
            panelSize: view.fittingSize,
            iconFrame: iconFrame,
            screen: screen.frame,
            menuBarBottom: screen.visibleFrame.maxY
        )
        panel.setFrame(frame, display: true)
    }

    func hide() {
        panel.orderOut(nil)
    }

    /// The running apps among `identifiers`, in name order. An app that is
    /// not running has no item to show.
    static func apps(for identifiers: Set<String>) -> [App] {
        identifiers.compactMap { id -> App? in
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first else { return nil }
            return App(id: id, name: app.localizedName ?? id, icon: app.icon ?? NSWorkspace.shared.icon(for: .applicationBundle))
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

private struct BarView: View {
    let apps: [FloatingBar.App]
    let pinned: Set<String>
    let unreachable: Set<String>
    let hint: String?
    let onClick: (String) -> Void

    var body: some View {
        HStack(spacing: 2) {
            if apps.isEmpty {
                Text("No hidden apps are running")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
            ForEach(apps) { app in
                AppButton(
                    app: app,
                    isPinned: pinned.contains(app.id),
                    isUnreachable: unreachable.contains(app.id),
                    hint: hint,
                    onClick: onClick
                )
            }
        }
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(2)
        .fixedSize()
    }
}

private struct AppButton: View {
    let app: FloatingBar.App
    let isPinned: Bool
    let isUnreachable: Bool
    let hint: String?
    let onClick: (String) -> Void
    @State private var isHovered = false

    var body: some View {
        Button {
            onClick(app.id)
        } label: {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 18, height: 18)
                .opacity(isUnreachable ? 0.4 : 1)
                .padding(6)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.12) : .clear)
        )
        .overlay {
            if isPinned {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
            }
        }
        .onHover { isHovered = $0 }
        .help(helpText)
        .accessibilityLabel(app.name)
        .accessibilityValue(isPinned ? "pinned" : "")
    }

    private var helpText: String {
        if isUnreachable {
            return "\(app.name) — runs outside /Applications, so macOS hides it whenever BarNook hides anything"
        }
        let pin = isPinned ? "pinned — click to unpin" : "click to pin"
        return hint.map { "\(app.name) — \(pin); \($0)" } ?? "\(app.name) — \(pin)"
    }
}
