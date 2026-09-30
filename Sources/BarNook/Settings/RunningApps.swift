// Modified by Chaehyeon Lee (2026): rescan when the Accessibility permission changes;
// check every process of an app for its menu bar item.
import AppKit
import Observation

/// The apps the Apps list can show: every running app with a regular or accessory
/// activation policy. With the Accessibility permission, only the apps that
/// have a menu bar item. An app in a set stays listed after it quits, so the
/// user can still set it to Shown.
@MainActor
@Observable
final class RunningApps {
    struct Entry: Identifiable, Hashable {
        /// Bundle identifier.
        let id: String
        let name: String
        let icon: NSImage
        let isRunning: Bool
        /// Every process with this bundle identifier. An app such as espanso
        /// runs several, and only one of them may own the menu bar item.
        let pids: [pid_t]

        static func == (lhs: Entry, rhs: Entry) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    private(set) var running: [Entry] = []
    /// Bundle identifiers of the running apps that have a menu bar item, or
    /// nil without the Accessibility permission.
    private(set) var withMenuBarItem: Set<String>?
    private let permission: Permissions
    private var observer: Task<Void, Never>?
    private var scan: Task<Void, Never>?

    init(permission: Permissions) {
        self.permission = permission
        refresh()
        observer = Task { [weak self] in
            for await _ in NSWorkspace.runningApplicationChanges() {
                self?.refresh()
            }
        }
        observePermission()
    }

    /// Entries for the Apps list: the running apps plus the apps in `selected` that
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
        let apps = NSWorkspace.shared.runningApplications.filter {
            [.regular, .accessory].contains($0.activationPolicy) && $0.bundleIdentifier != own
        }
        let groups = Self.group(apps.map { ($0.bundleIdentifier, $0.processIdentifier) })
        running = groups.compactMap { group in
            guard let app = apps.first(where: { $0.processIdentifier == group.pids[0] }) else { return nil }
            return Entry(
                id: group.id,
                name: app.localizedName ?? group.id,
                icon: app.icon ?? Self.genericIcon,
                isRunning: true,
                pids: group.pids
            )
        }
        scanMenuBarItems()
    }

    /// The processes grouped by bundle identifier, in first-seen order.
    /// Processes without an identifier are left out.
    nonisolated static func group(_ processes: [(id: String?, pid: pid_t)]) -> [(id: String, pids: [pid_t])] {
        var order: [String] = []
        var pids: [String: [pid_t]] = [:]
        for (id, pid) in processes {
            guard let id else { continue }
            if pids[id] == nil { order.append(id) }
            pids[id, default: []].append(pid)
        }
        return order.map { ($0, pids[$0]!) }
    }

    /// Asks every running app over Accessibility whether it has a menu bar
    /// item. Off the main thread: each ask is an IPC with a timeout.
    private func scanMenuBarItems() {
        scan?.cancel()
        guard permission.isTrusted else {
            withMenuBarItem = nil
            return
        }
        let pids = running.map { ($0.id, $0.pids) }
        scan = Task.detached(priority: .userInitiated) { [weak self] in
            var found = Set<String>()
            for (id, appPIDs) in pids {
                for pid in appPIDs {
                    guard !Task.isCancelled else { return }
                    if Permissions.hasMenuBarItem(pid: pid) {
                        found.insert(id)
                        break
                    }
                }
            }
            let result = found
            await MainActor.run { self?.withMenuBarItem = result }
        }
    }

    /// The Accessibility permission decides which apps are listed, so a
    /// change rescans while Settings stays open.
    private func observePermission() {
        withObservationTracking {
            _ = permission.isTrusted
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.refresh()
                self.observePermission()
            }
        }
    }

    private static let genericIcon = NSWorkspace.shared.icon(for: .applicationBundle)

    /// Name and icon of an app that is not running, from LaunchServices.
    private static func lookUp(_ id: String) -> Entry {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
            return Entry(id: id, name: id, icon: genericIcon, isRunning: false, pids: [])
        }
        return Entry(
            id: id,
            name: FileManager.default.displayName(atPath: url.path),
            icon: NSWorkspace.shared.icon(forFile: url.path),
            isRunning: false,
            pids: []
        )
    }
}
