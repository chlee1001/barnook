import SwiftUI
import UniformTypeIdentifiers

/// Which apps hide: the apps in Hidden, Always hidden and Shown groups, and
/// a choice between picking them here or by the icon's position.
struct AppsPane: View {
    @Environment(AppState.self) private var state
    @Environment(HiddenSets.self) private var sets
    @Environment(RunningApps.self) private var apps
    @Environment(Permissions.self) private var permission
    @State private var query = ""
    @State private var isShownExpanded = true
    /// The app that just moved, marked for a moment.
    @State private var moved: String?
    @State private var clearMoved: Task<Void, Never>?
    /// Where a dragged row would land, while it is over one.
    @State private var dropSpot: DropSpot?

    var body: some View {
        @Bindable var state = state
        let listed = listedApps
        // RunningApps lists each id once; a repeat would keep the first
        // rather than stop the app.
        let byID = Dictionary(listed.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let groups = AppVisibility.groups(listed: listed.map(\.id), in: sets.lists)
        let isSearching = !query.trimmingCharacters(in: .whitespaces).isEmpty
        let matching = listed.filter { AppVisibility.matches(name: $0.name, query: query) }
        Form {
            Section {
                Picker("Choose hidden apps", selection: $state.hidesAppsLeftOfIcon) {
                    Text("From this list").tag(false)
                    Text("By position").tag(true)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .disabled(!permission.isTrusted)
                .help("By position: apps left of the BarNook icon in the menu bar are hidden")
                Toggle(isOn: $state.isAlwaysHiddenEnabled) {
                    Text("Always-hidden apps")
                    Text("Stay hidden until you Option-click the icon")
                }
            } footer: {
                Text(modeFooter)
            }
            Section {
                if listed.isEmpty {
                    Text("No apps with a menu bar item are running.")
                        .foregroundStyle(.secondary)
                } else if isSearching {
                    if matching.isEmpty {
                        Text("No apps with a menu bar item match.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(matching) { app in
                        row(app, badge: true)
                    }
                }
            } header: {
                HStack(spacing: 8) {
                    TextField("Search apps", text: $query, prompt: Text("Search apps"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                    CountBadge(text: "\(groups.hidden.count) hidden", color: .accentColor)
                    CountBadge(text: "\(groups.alwaysHidden.count) always", color: .purple)
                        .opacity(state.isAlwaysHiddenEnabled ? 1 : 0.5)
                }
            } footer: {
                if isSearching, !listed.isEmpty {
                    Text("Clear the search to reorder.")
                }
            }
            if !listed.isEmpty, !isSearching {
                group(.hidden, groups.hidden.compactMap { byID[$0] }, ordered: canReorder)
                group(.alwaysHidden, groups.alwaysHidden.compactMap { byID[$0] }, ordered: canReorder)
                group(.shown, groups.shown.compactMap { byID[$0] }, ordered: false, footer: listFooter)
            }
            Section {
                KeyCap(key: "Click", text: "Show or hide the hidden apps")
                KeyCap(key: "⌥ Click", text: "Also show the always-hidden apps")
                KeyCap(key: "⌘ Drag", text: isDividerActive
                    ? "Move an item across the BarNook icon to hide or show it"
                    : "Move menu bar items")
            }
        }
        .formStyle(.grouped)
        .paneHeight(620)
    }

    /// One group: a header with its count and what its order means, then
    /// its apps. Shown folds away. An empty group says where to drop.
    @ViewBuilder
    private func group(_ visibility: AppVisibility, _ entries: [RunningApps.Entry], ordered: Bool, footer: String? = nil) -> some View {
        let isOpen = visibility != .shown || isShownExpanded
        Section {
            if entries.isEmpty || !isOpen {
                dropRow(visibility, text: entries.isEmpty
                    ? (acceptsDrops(visibility) ? "Drag an app here" : "No apps")
                    : "Drop an app here to show it")
            }
            ForEach(isOpen ? entries : []) { app in
                let spot = DropSpot(group: visibility, before: app.id)
                row(app, badge: false, reorder: ordered ? entries.map(\.id) : nil)
                    .draggable(AppRowDrag(id: app.id)) {
                        Label {
                            Text(app.name)
                        } icon: {
                            Image(nsImage: app.icon)
                        }
                    }
                    .overlay(alignment: .top) {
                        // Marks where the app would land, only where the
                        // order counts.
                        if dropSpot == spot, ordered {
                            Capsule()
                                .fill(AppLabel.tint(visibility))
                                .frame(height: 2)
                                .offset(y: -4)
                                .allowsHitTesting(false)
                        }
                    }
                    .accepting(spot, in: $dropSpot) { drop($0, into: visibility, before: app.id) }
            }
        } header: {
            HStack(spacing: 6) {
                if visibility == .shown {
                    Button {
                        withAnimation { isShownExpanded.toggle() }
                    } label: {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(isShownExpanded ? 90 : 0))
                            .frame(width: 12)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isShownExpanded ? "Collapse Shown" : "Expand Shown")
                }
                Text(AppLabel.title(visibility))
                CountBadge(text: "\(entries.count)", color: AppLabel.tint(visibility))
                    .accessibilityLabel("\(entries.count) apps")
                Spacer()
                if let hint = hint(visibility, ordered: ordered) {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .background(targetMark(visibility, ordered: ordered), in: RoundedRectangle(cornerRadius: 6))
            .accepting(DropSpot(group: visibility, before: nil), in: $dropSpot) { drop($0, into: visibility, before: nil) }
        } footer: {
            if let footer {
                Text(footer)
            }
        }
    }

    /// A row with no app: an empty group or a folded Shown. A drop on it,
    /// like one on the group's header, goes to the end of the group.
    private func dropRow(_ visibility: AppVisibility, text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .background(targetMark(visibility, ordered: false), in: RoundedRectangle(cornerRadius: 6))
            .accepting(DropSpot(group: visibility, before: nil), in: $dropSpot) { drop($0, into: visibility, before: nil) }
    }

    /// The group's tint while a row is over its header or empty row, or
    /// over any of its apps when its order does not count and no line marks
    /// the spot.
    private func targetMark(_ visibility: AppVisibility, ordered: Bool) -> Color {
        guard let dropSpot, dropSpot.group == visibility, dropSpot.before == nil || !ordered,
              acceptsDrops(visibility) else { return .clear }
        return AppLabel.tint(visibility).opacity(0.15)
    }

    /// Whether any app from another group may be dropped into `visibility`.
    private func acceptsDrops(_ visibility: AppVisibility) -> Bool {
        AppVisibility.allCases.contains { from in
            from != visibility && AppVisibility.canMove(
                from: from, to: visibility, isDividerActive: isDividerActive,
                isAlwaysHiddenEnabled: state.isAlwaysHiddenEnabled, canReorder: false
            )
        }
    }

    private func row(_ app: RunningApps.Entry, badge: Bool, reorder ids: [String]? = nil) -> some View {
        AppRow(
            app: app,
            visibility: visibility(of: app.id),
            isDividerActive: isDividerActive,
            isAlwaysHiddenEnabled: state.isAlwaysHiddenEnabled,
            showsBadge: badge,
            isMoved: moved == app.id
        )
        .accessibilityActions {
            if let ids, let index = ids.firstIndex(of: app.id) {
                if index > 0 {
                    Button("Move up") { step(app.id, by: -1) }
                }
                if index < ids.count - 1 {
                    Button("Move down") { step(app.id, by: 1) }
                }
            }
        }
    }

    private var isDividerActive: Bool { state.hidesAppsLeftOfIcon && permission.isTrusted }

    private var listedApps: [RunningApps.Entry] {
        apps.entries(including: Set(sets.hidden).union(sets.alwaysHidden))
    }

    /// The order within a group means something only in the floating bar.
    private var canReorder: Bool { state.hiddenItemsPlacement == .floatingBar }

    /// Only the floating bar follows the order, so without it the hidden
    /// groups have no hint.
    private func hint(_ visibility: AppVisibility, ordered: Bool) -> String? {
        switch visibility {
        case .shown: "By name"
        case .hidden: ordered ? "Left to right in the bar" : nil
        case .alwaysHidden: ordered ? "After an Option-click" : nil
        }
    }

    private var listFooter: String {
        let change = isDividerActive
            ? "Drag an app into or out of Always hidden to change it."
            : "Drag an app into another group to change it."
        return canReorder
            ? "Drag to reorder the bar. \(change)"
            : "macOS sets the order in the menu bar; Cmd-drag items there. \(change)"
    }

    private var modeFooter: String {
        if !permission.isTrusted {
            return state.hidesAppsLeftOfIcon
                ? "Position mode needs \(Permissions.Kind.accessibility.title). It resumes once it is allowed."
                : "Position mode needs \(Permissions.Kind.accessibility.title)."
        }
        return isDividerActive
            ? "Apps left of the BarNook icon are hidden. Cmd-drag an item across the icon to change it. Always hidden and the order in the bar are set here."
            : "Pick a state for each app below, or drag it into a group."
    }

    /// A drop of dragged rows into a group. Only rows of this list that may
    /// go there move.
    private func drop(_ items: [AppRowDrag], into target: AppVisibility, before anchor: String?) {
        guard let (lists, id) = AppVisibility.drop(
            items.map(\.id), into: target, before: anchor,
            listed: Set(listedApps.map(\.id)), in: sets.lists,
            allowed: { from in
                AppVisibility.canMove(
                    from: from, to: target, isDividerActive: isDividerActive,
                    isAlwaysHiddenEnabled: state.isAlwaysHiddenEnabled, canReorder: canReorder
                )
            }
        ) else { return }
        commit(lists, moved: id)
    }

    /// VoiceOver's Move up and Move down, which say where the app is now.
    private func step(_ id: String, by offset: Int) {
        commit(AppVisibility.step(id, by: offset, in: sets.lists), moved: id)
    }

    /// Stores a change, marks the app that moved and tells VoiceOver where
    /// it is now: "Hidden, 3 of 5", or "Shown".
    private func commit(_ lists: HiddenLists, moved id: String) {
        guard lists != sets.lists else { return }
        withAnimation { sets.update(lists) }
        mark(id)
        let title = AppLabel.title(AppVisibility.of(id, in: lists))
        let text = if let place = AppVisibility.place(of: id, in: lists) {
            "\(title), \(place.index) of \(place.count)"
        } else {
            title
        }
        AccessibilityNotification.Announcement(text).post()
    }

    private func mark(_ id: String) {
        moved = id
        clearMoved?.cancel()
        clearMoved = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            withAnimation { moved = nil }
        }
    }

    private func visibility(of id: String) -> Binding<AppVisibility> {
        Binding(
            get: { AppVisibility.of(id, in: sets.lists) },
            set: { commit(AppVisibility.apply($0, to: id, in: sets.lists), moved: id) }
        )
    }
}

/// One app: icon, name, a note, and its visibility.
private struct AppRow: View {
    let app: RunningApps.Entry
    @Binding var visibility: AppVisibility
    let isDividerActive: Bool
    let isAlwaysHiddenEnabled: Bool
    /// In a search the groups are gone, so each row says its state.
    let showsBadge: Bool
    let isMoved: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .lineLimit(1)
                    .foregroundStyle(app.isRunning ? .primary : .secondary)
                if let note = AppVisibility.note(isRunning: app.isRunning, visibility: visibility, alwaysHiddenEnabled: isAlwaysHiddenEnabled) {
                    Text(Self.text(note, visibility: visibility))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if showsBadge {
                CountBadge(text: AppLabel.title(visibility), color: AppLabel.tint(visibility))
            }
            if isDividerActive {
                dividerControls
            } else {
                listControls
            }
        }
        .padding(.vertical, 2)
        .background(
            AppLabel.tint(visibility).opacity(isMoved ? 0.15 : 0),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(app.name)
    }

    /// A hidden app that quit stays in its list, and so in its place.
    private static func text(_ note: AppVisibility.Note, visibility: AppVisibility) -> String {
        switch note {
        case .notRunning: visibility == .shown ? "Not running" : "Not running · keeps its place"
        case .alwaysHiddenPaused: "Always hidden · paused"
        }
    }

    /// Three icon buttons in one segmented control.
    private var listControls: some View {
        let selectable = AppVisibility.listSelectable(alwaysHiddenEnabled: isAlwaysHiddenEnabled)
        return HStack(spacing: 0) {
            ForEach(AppVisibility.allCases, id: \.self) { option in
                let isSelected = option == visibility
                Button {
                    visibility = option
                } label: {
                    Image(systemName: Self.symbol(option))
                        .frame(width: 30, height: 20)
                        .foregroundStyle(isSelected ? AppLabel.tint(option) : .secondary)
                        .background(isSelected ? AnyShapeStyle(.background) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!selectable.contains(option))
                .help(AppLabel.title(option))
                .accessibilityLabel(AppLabel.title(option))
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(2)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
    }

    /// The icon's position decides hidden or shown; only always hidden is
    /// set here.
    private var dividerControls: some View {
        let target = AppVisibility.alwaysHiddenToggleTarget(current: visibility, alwaysHiddenEnabled: isAlwaysHiddenEnabled)
        return HStack(spacing: 6) {
            Label(AppLabel.title(visibility), systemImage: visibility == .alwaysHidden ? "eye.slash.fill" : "lock.fill")
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .foregroundStyle(AppLabel.tint(visibility))
                .background(AppLabel.tint(visibility).opacity(0.15), in: Capsule())
                .help(visibility == .alwaysHidden ? "Always hidden" : "Set by the icon's position")
            Button {
                if let target { visibility = target }
            } label: {
                Image(systemName: "eye.slash.fill")
                    .frame(width: 26, height: 20)
                    .foregroundStyle(visibility == .alwaysHidden ? Color.purple : .secondary)
            }
            .buttonStyle(.borderless)
            .disabled(target == nil)
            .help(visibility == .alwaysHidden ? "Stop always hiding" : "Always hide")
            .accessibilityLabel(visibility == .alwaysHidden ? "Stop always hiding" : "Always hide")
        }
    }

    private static func symbol(_ visibility: AppVisibility) -> String {
        switch visibility {
        case .shown: "eye"
        case .hidden: "eye.slash"
        case .alwaysHidden: "eye.slash.fill"
        }
    }
}

/// The name and color of each state, shared by headers, badges and rows.
private enum AppLabel {
    static func title(_ visibility: AppVisibility) -> String {
        switch visibility {
        case .shown: "Shown"
        case .hidden: "Hidden"
        case .alwaysHidden: "Always hidden"
        }
    }

    static func tint(_ visibility: AppVisibility) -> Color {
        switch visibility {
        case .shown: .secondary
        case .hidden: .accentColor
        case .alwaysHidden: .purple
        }
    }
}

private struct CountBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
            .fixedSize()
    }
}

/// A shortcut on the BarNook icon and what it does.
private struct KeyCap: View {
    let key: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Text(key)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                .frame(minWidth: 64, alignment: .leading)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Where a dragged row lands: before an app of a group, or at its end.
private struct DropSpot: Equatable {
    let group: AppVisibility
    let before: String?
}

private extension UTType {
    /// A row of the Apps list being dragged. Declared in Info.plist; only
    /// BarNook makes it, so text dragged from another app never matches.
    static let barNookAppRow = UTType(exportedAs: "kr.co.devch.BarNook.app-row")
}

/// The app a dragged row stands for, and the process that made the drag:
/// BarNook and BarNookDev share the type, and a row from one must not
/// change the other.
private struct AppRowDrag: Codable, Transferable {
    let id: String
    var process = ProcessInfo.processInfo.processIdentifier

    var isFromThisProcess: Bool { process == ProcessInfo.processInfo.processIdentifier }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .barNookAppRow)
    }
}

private extension View {
    /// Takes dragged rows at `spot`, and marks `spot` while one is over it.
    func accepting(_ spot: DropSpot, in current: Binding<DropSpot?>, perform: @escaping ([AppRowDrag]) -> Void) -> some View {
        dropDestination(for: AppRowDrag.self) { items, _ in
            current.wrappedValue = nil
            perform(items.filter(\.isFromThisProcess))
        }
        .onDropSessionUpdated { session in
            switch session.phase {
            case .entering, .active:
                if current.wrappedValue != spot { current.wrappedValue = spot }
            case .exiting, .ended, .dataTransferCompleted:
                if current.wrappedValue == spot { current.wrappedValue = nil }
            @unknown default:
                break
            }
        }
    }
}
