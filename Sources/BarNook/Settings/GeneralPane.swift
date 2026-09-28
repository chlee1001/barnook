// Modified by Chaehyeon Lee (2026): BarNook settings labels, export name and menu bar icon pickers; panes for the toolbar settings window; menu bar options and app lists moved to their own panes; General leads with app and permission status.
import SwiftUI
import UniformTypeIdentifiers

/// The app itself: who it is, whether it can work, how it starts and
/// updates, and its settings file.
struct GeneralPane: View {
    @Environment(LaunchAtLogin.self) private var loginItem
    @Environment(Permissions.self) private var permission
    @Environment(Updater.self) private var updater

    var body: some View {
        @Bindable var updater = updater
        let status = permission.status
        VStack(spacing: 0) {
            Form {
                ForEach(status.missing, id: \.self) { kind in
                    PermissionBanner(kind: kind, step: status.step(kind))
                }
                Section {
                    AppHeader(missingCount: status.missing.count)
                }
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
                    ForEach(Permissions.Kind.allCases, id: \.self) { kind in
                        PermissionRow(kind: kind, step: status.step(kind))
                    }
                } header: {
                    Text("Permissions")
                } footer: {
                    Text("Both are required.")
                }
                Section("Updates") {
                    Toggle("Check for updates automatically", isOn: $updater.automaticallyChecksForUpdates)
                    LabeledContent("Check for a new version") {
                        Button("Check Now…", action: updater.checkForUpdates)
                            .disabled(!updater.canCheckForUpdates)
                    }
                }
                SettingsFileSection()
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Quit BarNook") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
        .paneHeight(idealHeight(missing: status.missing.count))
    }

    /// Tall enough for every row without scrolling; above the screen's cap
    /// the form scrolls.
    private func idealHeight(missing: Int) -> CGFloat {
        var height: CGFloat = 600 + CGFloat(missing) * 120
        if loginItem.needsApproval { height += 40 }
        if loginItem.error != nil { height += 30 }
        return height
    }
}

/// App icon, name, version and a one-line permission summary.
private struct AppHeader: View {
    let missingCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("BarNook").font(.headline)
                Text("Version \(Self.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(missingCount == 0 ? "Permissions OK"
                : missingCount == 1 ? "1 permission missing" : "\(missingCount) permissions missing")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .foregroundStyle(missingCount == 0 ? Color.green : .orange)
                .background((missingCount == 0 ? Color.green : .orange).opacity(0.15), in: Capsule())
        }
        .accessibilityElement(children: .combine)
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        guard let short = info?["CFBundleShortVersionString"] as? String else { return "development build" }
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }
}

/// Shown at the top of General while a permission is missing: what stops
/// working, and the one button that fixes it.
private struct PermissionBanner: View {
    @Environment(Permissions.self) private var permission
    let kind: Permissions.Kind
    let step: PermissionStatus.Step

    var body: some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(kind.title) is off").font(.headline)
                    Text(Self.effect(kind))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer()
                        if step == .needsRelaunch {
                            Button("Relaunch BarNook", action: permission.relaunch)
                                .buttonStyle(.borderedProminent)
                        } else {
                            Button("Open System Settings…") { permission.request(kind) }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private static func effect(_ kind: Permissions.Kind) -> String {
        switch kind {
        case .accessibility:
            "BarNook cannot read the menu bar: the Apps list shows every running app, position mode is paused, the clock zone is not measured, and in bar mode a click on the clock does not open Notification Center while items are hidden."
        case .screenRecording:
            "In bar mode a click on the clock does not open Notification Center while items are hidden."
        }
    }
}

/// One permission: its state and, when missing, the action that grants it.
private struct PermissionRow: View {
    @Environment(Permissions.self) private var permission
    let kind: Permissions.Kind
    let step: PermissionStatus.Step

    var body: some View {
        LabeledContent {
            switch step {
            case .allowed:
                Text("Allowed")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .foregroundStyle(.green)
                    .background(Color.green.opacity(0.15), in: Capsule())
            case .needsRelaunch:
                Button("Relaunch BarNook", action: permission.relaunch)
            case .waiting:
                Button("Allow…") { permission.request(kind) }
            }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(step == .allowed ? Color.green : .orange)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.title)
                    Text(Self.detail(kind))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private static func detail(_ kind: Permissions.Kind) -> String {
        switch kind {
        case .accessibility: "Reads the menu bar and clicks the clock in bar mode."
        case .screenRecording: "Takes the picture that covers the menu bar while the clock opens Notification Center."
        }
    }
}

/// "Export…" writes the settings to a property list. "Import…" reads one
/// back and the models reload from the store.
struct SettingsFileSection: View {
    @Environment(AppState.self) private var state
    @Environment(HiddenSets.self) private var sets

    var body: some View {
        Section {
            LabeledContent("Settings file") {
                Button("Export…") { Task { await exportSettings() } }
                Button("Import…") { Task { await importSettings() } }
            }
        } footer: {
            Text("Hidden apps and the Menu Bar and Apps options, as a property list.")
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
