import SwiftUI

/// Which apps hide: one list where each app is shown, hidden or always
/// hidden, and a choice between picking them here or by the icon's position.
struct AppsPane: View {
    @Environment(AppState.self) private var state
    @Environment(HiddenSets.self) private var sets
    @Environment(RunningApps.self) private var apps
    @Environment(Permissions.self) private var permission
    @State private var query = ""

    var body: some View {
        @Bindable var state = state
        let listed = apps.entries(including: sets.hidden.union(sets.alwaysHidden))
        let counts = AppVisibility.counts(ids: listed.map(\.id), hidden: sets.hidden, alwaysHidden: sets.alwaysHidden)
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
                } else if matching.isEmpty {
                    Text("No apps with a menu bar item match.")
                        .foregroundStyle(.secondary)
                }
                ForEach(matching) { app in
                    AppRow(
                        app: app,
                        visibility: visibility(of: app.id),
                        isDividerActive: isDividerActive,
                        isAlwaysHiddenEnabled: state.isAlwaysHiddenEnabled
                    )
                }
            } header: {
                HStack(spacing: 8) {
                    TextField("Search apps", text: $query, prompt: Text("Search apps"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                    CountBadge(text: "\(counts.hidden) hidden", color: .accentColor)
                    CountBadge(text: "\(counts.always) always", color: .purple)
                        .opacity(state.isAlwaysHiddenEnabled ? 1 : 0.5)
                }
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

    private var isDividerActive: Bool { state.hidesAppsLeftOfIcon && permission.isTrusted }

    private var modeFooter: String {
        if !permission.isTrusted {
            return state.hidesAppsLeftOfIcon
                ? "Position mode needs \(Permissions.Kind.accessibility.title). It resumes once it is allowed."
                : "Position mode needs \(Permissions.Kind.accessibility.title)."
        }
        return isDividerActive
            ? "Apps left of the BarNook icon are hidden. Cmd-drag an item across the icon to change it. Always hidden is set here."
            : "Pick a state for each app below."
    }

    private func visibility(of id: String) -> Binding<AppVisibility> {
        Binding(
            get: { AppVisibility.of(id, hidden: sets.hidden, alwaysHidden: sets.alwaysHidden) },
            set: { new in
                let result = AppVisibility.apply(new, to: id, hidden: sets.hidden, alwaysHidden: sets.alwaysHidden)
                // Each assignment writes the defaults, so only a set that
                // changed is assigned. An app moves between the sets in one
                // main-actor turn; the menu bar code sees the final state.
                if result.hidden != sets.hidden { sets.hidden = result.hidden }
                if result.alwaysHidden != sets.alwaysHidden { sets.alwaysHidden = result.alwaysHidden }
            }
        )
    }
}

/// One app: icon, name, a note, and its visibility.
private struct AppRow: View {
    let app: RunningApps.Entry
    @Binding var visibility: AppVisibility
    let isDividerActive: Bool
    let isAlwaysHiddenEnabled: Bool

    init(app: RunningApps.Entry, visibility: Binding<AppVisibility>, isDividerActive: Bool, isAlwaysHiddenEnabled: Bool) {
        self.app = app
        _visibility = visibility
        self.isDividerActive = isDividerActive
        self.isAlwaysHiddenEnabled = isAlwaysHiddenEnabled
    }

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
                    Text(note == .notRunning ? "Not running" : "Always hidden · paused")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if isDividerActive {
                dividerControls
            } else {
                listControls
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(app.name)
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
                        .foregroundStyle(isSelected ? Self.tint(option) : .secondary)
                        .background(isSelected ? AnyShapeStyle(.background) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!selectable.contains(option))
                .help(Self.title(option))
                .accessibilityLabel(Self.title(option))
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
            Label(Self.title(visibility), systemImage: visibility == .alwaysHidden ? "eye.slash.fill" : "lock.fill")
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .foregroundStyle(Self.tint(visibility))
                .background(Self.tint(visibility).opacity(0.15), in: Capsule())
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

    private static func title(_ visibility: AppVisibility) -> String {
        switch visibility {
        case .shown: "Shown"
        case .hidden: "Hidden"
        case .alwaysHidden: "Always hidden"
        }
    }

    private static func tint(_ visibility: AppVisibility) -> Color {
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
