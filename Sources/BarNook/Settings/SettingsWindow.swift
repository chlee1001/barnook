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
    private var screenObserver: NSObjectProtocol?

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
        self.tabs = tabs
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
        // Another screen, or a new resolution, has another height cap.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification, object: window, queue: .main
        ) { [weak tabs] _ in
            Task { @MainActor in tabs?.refit() }
        }
    }

    private let tabs: SettingsTabViewController

    isolated deinit {
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
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

/// Every pane has one width, so switching panes changes only the height.
let settingsPaneWidth: CGFloat = 500

/// The tallest a pane may be on the window's screen. A pane that wants more
/// takes this height and scrolls inside.
struct PaneHeightCapKey: EnvironmentKey {
    static let defaultValue: CGFloat = .infinity
}

extension EnvironmentValues {
    var paneHeightCap: CGFloat {
        get { self[PaneHeightCapKey.self] }
        set { self[PaneHeightCapKey.self] = newValue }
    }
}

extension View {
    /// A Form pane that wants `height`: it gets that, or the screen's cap and
    /// scrolls inside.
    func paneHeight(_ height: CGFloat) -> some View {
        modifier(PaneHeight(ideal: height))
    }
}

private struct PaneHeight: ViewModifier {
    @Environment(\.paneHeightCap) private var cap
    let ideal: CGFloat

    func body(content: Content) -> some View {
        content.frame(width: settingsPaneWidth, height: min(ideal, cap))
    }
}

/// Resizes the window to the selected pane, keeping it on the screen's
/// visible area. Each pane reports its own size; the window follows it. The
/// pane is told the screen's cap, so a tall one scrolls inside.
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

    func refit() { fit(animate: false) }

    private func fit(animate: Bool) {
        guard let window = view.window, let pane = selected else { return }
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? .infinite
        let chrome = window.frame.height - window.contentLayoutRect.height
        for case let other as PaneController in tabViewItems.map(\.viewController) {
            other.heightCap = SettingsWindowFrame.heightCap(visible: visible, chrome: chrome)
        }
        guard let frame = SettingsWindowFrame.fitted(
            current: window.frame, content: pane.contentSize, chrome: chrome, visible: visible
        ) else { return }
        window.setFrame(frame, display: true, animate: animate && window.isVisible && hasCentered)
        if !hasCentered {
            window.center()
            hasCentered = true
        }
    }
}

/// Where the Settings window goes for a pane of a given size. Pure, so the
/// screen cap and the edge rules can be tested without a window.
enum SettingsWindowFrame {
    /// The tallest a pane may be: the visible screen less the title bar and
    /// toolbar.
    static func heightCap(visible: NSRect, chrome: CGFloat) -> CGFloat {
        visible.height - chrome
    }

    /// The window frame for `content`: the height is capped at the screen, the
    /// top edge stays where it is, and a window that would reach below the
    /// visible area moves up instead. Nil before the pane has a size.
    static func fitted(current: NSRect, content: CGSize, chrome: CGFloat, visible: NSRect) -> NSRect? {
        guard content.width > 0, content.height > 0 else { return nil }
        let height = min(content.height, heightCap(visible: visible, chrome: chrome)) + chrome
        let y = max(current.maxY - height, visible.minY)
        return NSRect(x: current.minX, y: y, width: content.width, height: height)
    }
}

/// One pane: a SwiftUI view pinned to the top of the content area below the
/// toolbar. It reports the size the view wants, not the size it is given.
private final class PaneController: NSViewController {
    private(set) var contentSize: CGSize = .zero
    /// The screen's cap, passed to the pane so a tall one scrolls inside.
    var heightCap: CGFloat {
        get { cap.value }
        set { if cap.value != newValue { cap.value = newValue } }
    }
    private let cap = HeightCap()
    private let host: NSHostingView<AnyView>

    init(_ root: some View, onResize: @escaping @MainActor (PaneController) -> Void) {
        host = NSHostingView(rootView: AnyView(EmptyView()))
        super.init(nibName: nil, bundle: nil)
        host.sizingOptions = []
        host.rootView = AnyView(
            CappedPane(cap: cap) { root }
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

@MainActor
@Observable
private final class HeightCap {
    var value: CGFloat = .infinity
}

private struct CappedPane<Content: View>: View {
    let cap: HeightCap
    @ViewBuilder let content: Content

    var body: some View {
        content.environment(\.paneHeightCap, cap.value)
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
