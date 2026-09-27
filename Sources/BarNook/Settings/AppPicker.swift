import SwiftUI

/// Rows for a `Form` section: one checkbox per app. Checking an app in one
/// set removes it from the other; the caller's binding does that.
struct AppPicker: View {
    let apps: [RunningApps.Entry]
    @Binding var selection: Set<String>
    /// The other set. An app in it shows a note so the user knows why it is
    /// not checked here.
    let otherSet: Set<String>
    let otherSetName: String

    var body: some View {
        if apps.isEmpty {
            Text("No apps with a menu bar item are running.")
                .foregroundStyle(.secondary)
        }
        ForEach(apps) { app in
            Toggle(isOn: binding(for: app.id)) {
                HStack {
                    Image(nsImage: app.icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                    Text(app.name)
                        .foregroundStyle(app.isRunning ? .primary : .secondary)
                    Spacer()
                    if !app.isRunning {
                        Text("Not running")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else if otherSet.contains(app.id) {
                        Text(otherSetName)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .toggleStyle(.checkbox)
            .accessibilityLabel(app.name)
        }
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selection.contains(id) },
            set: { checked in
                if checked {
                    selection.insert(id)
                } else {
                    selection.remove(id)
                }
            }
        )
    }
}
