// Modified by Chaehyeon Lee (2026): BarNook settings labels, export name and menu bar icon pickers.
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(HiddenSets.self) private var sets
    @Environment(RunningApps.self) private var apps
    @Environment(Permissions.self) private var permission

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettings()
            }
            Tab("Hidden", systemImage: "eye.slash") {
                @Bindable var state = state
                Form {
                    Section {
                        Toggle("Hide apps left of the BarNook icon", isOn: $state.hidesAppsLeftOfIcon)
                            .disabled(!permission.isTrusted)
                    } footer: {
                        Text("Cmd-drag items across the icon. Apps left of it join the hidden set. Apps right of it leave it when the set is shown. The always-hidden set is not affected.")
                    }
                    Section {
                        AppPicker(
                            apps: apps.entries(including: sets.hidden),
                            selection: hiddenSelection,
                            otherSet: sets.alwaysHidden,
                            otherSetName: "Always hidden"
                        )
                    } header: {
                        Text("Hidden apps")
                    } footer: {
                        Text(isDividerActive
                            ? "The icon's position manages this list. Cmd-drag an item to change it."
                            : "These apps hide until you click the BarNook icon.")
                    }
                    .disabled(isDividerActive)
                }
                .formStyle(.grouped)
            }
            Tab("Always Hidden", systemImage: "eye.slash.fill") {
                @Bindable var state = state
                Form {
                    Section {
                        Toggle("Keep an always-hidden set", isOn: $state.isAlwaysHiddenEnabled)
                    } footer: {
                        Text("Option-click the BarNook icon to show these apps.")
                    }
                    Section("Always-hidden apps") {
                        AppPicker(
                            apps: apps.entries(including: sets.alwaysHidden),
                            selection: alwaysHiddenSelection,
                            otherSet: sets.hidden,
                            otherSetName: "Hidden"
                        )
                    }
                    .disabled(!state.isAlwaysHiddenEnabled)
                }
                .formStyle(.grouped)
            }
        }
        .frame(width: 480, height: 460)
        .onAppear {
            permission.refresh()
            apps.refresh()
        }
        .onChange(of: permission.isTrusted) { apps.refresh() }
    }

    private var isDividerActive: Bool { state.hidesAppsLeftOfIcon && permission.isTrusted }

    /// An app can be in one set only, so a check here removes it from the other set.
    private var hiddenSelection: Binding<Set<String>> {
        Binding(
            get: { sets.hidden },
            set: { new in
                sets.alwaysHidden.subtract(new)
                sets.hidden = new
            }
        )
    }

    private var alwaysHiddenSelection: Binding<Set<String>> {
        Binding(
            get: { sets.alwaysHidden },
            set: { new in
                sets.hidden.subtract(new)
                sets.alwaysHidden = new
            }
        )
    }
}

private struct GeneralSettings: View {
    @Environment(AppState.self) private var state
    @Environment(LaunchAtLogin.self) private var loginItem
    @Environment(Permissions.self) private var permission
    @Environment(Updater.self) private var updater

    var body: some View {
        @Bindable var state = state
        @Bindable var updater = updater
        Form {
            Section {
                Toggle(
                    "Launch at login",
                    isOn: Binding(get: { loginItem.isEnabled }, set: loginItem.set)
                )
                if loginItem.needsApproval {
                    LabeledContent("Waiting for approval in System Settings") {
                        Button("Open Login Items", action: loginItem.openSystemSettings)
                    }
                }
                if let error = loginItem.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Section {
                Picker("Show hidden items", selection: $state.hiddenItemsPlacement) {
                    Text("In the menu bar").tag(AppState.HiddenItemsPlacement.menuBar)
                    Text("In a bar below the menu bar").tag(AppState.HiddenItemsPlacement.floatingBar)
                }
            } footer: {
                Text("A notch, or a long app menu, leaves no room for every item. The bar shows the hidden apps below the menu bar instead, and a click on one opens its menu bar item.")
            }
            Section {
                Picker("When items are hidden", selection: $state.hiddenMenuBarIcon) {
                    iconOptions
                }
                Picker("When items are shown", selection: $state.shownMenuBarIcon) {
                    iconOptions
                }
            } header: {
                Text("Menu bar icon")
            } footer: {
                Text("Choose the icon shown in the menu bar for each state. Changes take effect immediately.")
            }
            Section("Hide again") {
                Toggle("After a timeout", isOn: $state.rehideOnTimeout)
                Stepper(value: $state.rehideTimeout, in: 1...300, step: 1) {
                    Text("\(Int(state.rehideTimeout)) seconds")
                }
                .disabled(!state.rehideOnTimeout)
                Toggle("On a click outside the menu bar", isOn: $state.rehideOnClickOutside)
                Toggle("When the front app or Space changes", isOn: $state.rehideOnFocusChange)
            }
            Section {
                ForEach(Permissions.Kind.allCases, id: \.self) { kind in
                    LabeledContent(kind.title) {
                        if permission.isGranted(kind) {
                            Text("Granted")
                                .foregroundStyle(.secondary)
                        } else {
                            Button("Open System Settings…") { permission.request(kind) }
                        }
                    }
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("Both are required. Accessibility reads the menu bar and clicks the clock in bar mode; Screen Recording takes the picture that covers the menu bar while the clock opens Notification Center.")
            }
            ClockZoneSection()
            SettingsFileSection()
            Section("About") {
                LabeledContent("Version", value: Self.version)
                Toggle("Check for updates automatically", isOn: $updater.automaticallyChecksForUpdates)
                Button("Check for Updates…", action: updater.checkForUpdates)
                    .disabled(!updater.canCheckForUpdates)
                Button("Quit BarNook") {
                    NSApp.terminate(nil)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loginItem.refresh)
    }

    private var iconOptions: some View {
        ForEach(MenuBarIcon.allCases, id: \.self) { icon in
            Label {
                Text(icon.title)
            } icon: {
                Image(nsImage: icon.image)
            }
            .tag(icon)
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        guard let short = info?["CFBundleShortVersionString"] as? String else { return "development build" }
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }
}

/// "Export…" writes the settings to a property list. "Import…" reads one
/// back and the models reload from the store.
private struct SettingsFileSection: View {
    @Environment(AppState.self) private var state
    @Environment(HiddenSets.self) private var sets

    var body: some View {
        Section {
            LabeledContent("Settings file") {
                Button("Export…") { Task { await exportSettings() } }
                Button("Import…") { Task { await importSettings() } }
            }
        } footer: {
            Text("The hidden sets and the options above, as a property list.")
        }
    }

    private func exportSettings() async {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.propertyList]
        panel.nameFieldStringValue = "BarNook Settings.plist"
        guard await panel.begin() == .OK, let url = panel.url else { return }
        do {
            try SettingsFile.export(from: .standard).write(to: url)
        } catch {
            Self.report(error, title: "The settings were not exported")
        }
    }

    private func importSettings() async {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.propertyList]
        guard await panel.begin() == .OK, let url = panel.url else { return }
        do {
            try SettingsFile.import(try Data(contentsOf: url), into: .standard)
            state.reload()
            sets.reload()
        } catch {
            Self.report(error, title: "The settings were not imported")
        }
    }

    private static func report(_ error: Error, title: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}

/// The trailing zone of the menu bar around the clock. In menu-bar mode
/// hidden items show while the pointer is in it, so that a clock click opens
/// Notification Center; in bar mode it only pre-filters clock clicks for the
/// covered lift. Measured from the clock item, or from one click on the clock.
private struct ClockZoneSection: View {
    @Environment(AppState.self) private var state
    @Environment(ClockZone.self) private var clockZone

    var body: some View {
        Section {
            LabeledContent("Clock zone") {
                if clockZone.isWaitingForClick {
                    Text("Click the left edge of the clock")
                        .foregroundStyle(.secondary)
                    Button("Cancel", action: clockZone.cancelClick)
                } else {
                    Text(clockZone.isMeasured ? "\(width) points, measured" : "\(width) points")
                        .foregroundStyle(.secondary)
                    if !clockZone.isMeasured {
                        Button("Click the Clock…", action: clockZone.waitForClick)
                    }
                    if !clockZone.isMeasured, state.clockZoneWidth != ClockZone.defaultWidth {
                        Button("Reset", action: clockZone.reset)
                    }
                }
            }
        } footer: {
            Text(state.hiddenItemsPlacement == .floatingBar
                ? "In bar mode a click on the clock opens Notification Center under a picture of the menu bar, so hidden items stay covered."
                : clockZone.isMeasured
                    ? "Hidden items show while the pointer is over the clock, so that a click opens Notification Center."
                    : "Hidden items show while the pointer is in the trailing \(width) points of the menu bar, so that a clock click opens Notification Center. Click the clock once to fit the zone to it.")
        }
        .onAppear(perform: clockZone.measureIfTrusted)
    }

    private var width: Int { Int(state.clockZoneWidth) }
}
