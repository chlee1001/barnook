// Modified by Chaehyeon Lee (2026): BarNook window title; toolbar panes that fit the window to the selected pane.
import AppKit
import SwiftUI

/// The one Settings window. Closing it hides it; `show()` brings it back.
/// Each pane is a toolbar item; the window title follows the selected pane.
@MainActor
final class SettingsWindow {
    private let window: NSWindow
    private let apps: RunningApps
    private let loginItem = LaunchAtLogin()
    private let permission: Permissions
    private let clockZone: ClockZone
    private var keyObserver: NSObjectProtocol?

    init(state: AppState, sets: HiddenSets, permission: Permissions, clockZone: ClockZone, updater: Updater) {
        self.permission = permission
        self.clockZone = clockZone
        apps = RunningApps(permission: permission)
        let environment = SettingsEnvironment(
            state: state, sets: sets, apps: apps, loginItem: loginItem,
            permission: permission, clockZone: clockZone, updater: updater
        )
        let tabs = SettingsTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addPane("General", symbol: "gearshape", GeneralPane().modifier(environment))
        tabs.addPane("Menu Bar", symbol: "menubar.rectangle", MenuBarPane().modifier(environment))
        tabs.addPane("Apps", symbol: "square.grid.2x2", AppsPane().modifier(environment))
        window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.toolbarStyle = .preference
        window.contentViewController = tabs
        window.isReleasedWhenClosed = false
        // A pane can only show what it last read; read again whenever the
        // window comes to the front, not only when it opens.
        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshModels() }
        }
    }

    isolated deinit {
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
    }

    func show() {
        refreshModels()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func refreshModels() {
        permission.refresh()
        apps.refresh()
        loginItem.refresh()
        clockZone.measureIfTrusted()
    }
}

/// Resizes the window to the selected pane, keeping its top edge, and caps
/// the height at the screen so a tall pane scrolls inside instead. Each pane
/// reports its own size; the window follows it.
private final class SettingsTabViewController: NSTabViewController {
    private var hasCentered = false

    func addPane(_ title: String, symbol: String, _ root: some View) {
        let pane = PaneController(root) { [weak self] pane in
            guard let self, self.selected === pane else { return }
            self.fit(animate: true)
        }
        pane.title = title
        let item = NSTabViewItem(viewController: pane)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        addTabViewItem(item)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        updateTitle()
        fit(animate: false)
    }

    override func tabView(_ tabView: NSTabView, didSelect item: NSTabViewItem?) {
        super.tabView(tabView, didSelect: item)
        updateTitle()
        fit(animate: true)
    }

    private var selected: PaneController? {
        guard tabViewItems.indices.contains(selectedTabViewItemIndex) else { return nil }
        return tabViewItems[selectedTabViewItemIndex].viewController as? PaneController
    }

    private func updateTitle() {
        guard let selected else { return }
        view.window?.title = selected.title ?? ""
    }

    private func fit(animate: Bool) {
        guard let window = view.window, var size = selected?.contentSize,
              size.width > 0, size.height > 0
        else { return }
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? .infinite
        let chrome = window.frame.height - window.contentLayoutRect.height
        size.height = min(size.height, visible.height - chrome)
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.setFrame(frame, display: true, animate: animate && window.isVisible)
        if !hasCentered {
            window.center()
            hasCentered = true
        }
    }
}

/// One pane: a SwiftUI view pinned to the top of the content area below the
/// toolbar. It reports the size the view wants, not the size it is given.
private final class PaneController: NSViewController {
    private(set) var contentSize: CGSize = .zero
    private let host: NSHostingView<AnyView>

    init(_ root: some View, onResize: @escaping @MainActor (PaneController) -> Void) {
        host = NSHostingView(rootView: AnyView(EmptyView()))
        super.init(nibName: nil, bundle: nil)
        host.sizingOptions = []
        host.rootView = AnyView(
            root
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGSize.self, of: \.size) { [weak self] size in
                    guard let self, size != self.contentSize else { return }
                    self.contentSize = size
                    // Not inside SwiftUI's layout pass: resizing the window
                    // there feeds the new height back into the same pass.
                    DispatchQueue.main.async { onResize(self) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let container = NSView()
        host.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor),
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        view = container
    }
}

/// The models every pane reads, injected into each pane's hosting controller.
struct SettingsEnvironment: ViewModifier {
    let state: AppState
    let sets: HiddenSets
    let apps: RunningApps
    let loginItem: LaunchAtLogin
    let permission: Permissions
    let clockZone: ClockZone
    let updater: Updater

    func body(content: Content) -> some View {
        content
            .environment(state)
            .environment(sets)
            .environment(apps)
            .environment(loginItem)
            .environment(permission)
            .environment(clockZone)
            .environment(updater)
    }
}
