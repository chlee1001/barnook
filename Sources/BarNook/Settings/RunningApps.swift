import AppKit
import Observation

/// The apps a picker can list: every running app with a regular or accessory
/// activation policy. With the Accessibility permission, only the apps that
/// have a menu bar item. An app in a set stays listed after it quits, so the
/// user can still uncheck it.
@MainActor
@Observable
final class RunningApps {
    struct Entry: Identifiable, Hashable {
        /// Bundle identifier.
        let id: String
        let name: String
        let icon: NSImage
        let isRunning: Bool
        let pid: pid_t

        static func == (lhs: Entry, rhs: Entry) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    private(set) var running: [Entry] = []
    /// Bundle identifiers of the running apps that have a menu bar item, or
    /// nil without the Accessibility permission.
    private(set) var withMenuBarItem: Set<String>?
    private let permission: AccessibilityPermission
    private var observer: Task<Void, Never>?
    private var scan: Task<Void, Never>?

    init(permission: AccessibilityPermission) {
        self.permission = permission
        refresh()
        observer = Task { [weak self] in
            for await _ in NSWorkspace.runningApplicationChanges() {
                self?.refresh()
            }
        }
    }

    /// Entries for a picker: the running apps plus the apps in `selected` that
    /// are not running, sorted by name.
    func entries(including selected: Set<String>) -> [Entry] {
        let runningIDs = Set(running.map(\.id))
        let quit = selected.subtracting(runningIDs).map(Self.lookUp)
        let listed = running.filter { withMenuBarItem?.contains($0.id) ?? true || selected.contains($0.id) }
        return (listed + quit).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func refresh() {
        let own = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        running = NSWorkspace.shared.runningApplications.compactMap { app in
            guard [.regular, .accessory].contains(app.activationPolicy),
                  let id = app.bundleIdentifier, id != own,
                  seen.insert(id).inserted
            else { return nil }
            return Entry(
                id: id,
                name: app.localizedName ?? id,
                icon: app.icon ?? Self.genericIcon,
                isRunning: true,
                pid: app.processIdentifier
            )
        }
        scanMenuBarItems()
    }

    /// Asks every running app over Accessibility whether it has a menu bar
    /// item. Off the main thread: each ask is an IPC with a timeout.
    private func scanMenuBarItems() {
        scan?.cancel()
        guard permission.isTrusted else {
            withMenuBarItem = nil
            return
        }
        let pids = running.map { ($0.id, $0.pid) }
        scan = Task.detached(priority: .userInitiated) { [weak self] in
            var found = Set<String>()
            for (id, pid) in pids {
                guard !Task.isCancelled else { return }
                if AccessibilityPermission.hasMenuBarItem(pid: pid) {
                    found.insert(id)
                }
            }
            let result = found
            await MainActor.run { self?.withMenuBarItem = result }
        }
    }

    private static let genericIcon = NSWorkspace.shared.icon(for: .applicationBundle)

    /// Name and icon of an app that is not running, from LaunchServices.
    private static func lookUp(_ id: String) -> Entry {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
            return Entry(id: id, name: id, icon: genericIcon, isRunning: false, pid: 0)
        }
        return Entry(
            id: id,
            name: FileManager.default.displayName(atPath: url.path),
            icon: NSWorkspace.shared.icon(forFile: url.path),
            isRunning: false,
            pid: 0
        )
    }
}
