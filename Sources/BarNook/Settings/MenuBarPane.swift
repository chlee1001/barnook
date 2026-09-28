import AppKit
import SwiftUI

/// Where shown items go, the icon for each state, when items hide again, and
/// the clock zone under Advanced.
struct MenuBarPane: View {
    @Environment(AppState.self) private var state
    @State private var showsAdvanced = false

    var body: some View {
        @Bindable var state = state
        Form {
            Section {
                PlacementCards(selection: $state.hiddenItemsPlacement)
            } header: {
                Text("Show hidden items")
            } footer: {
                Text(state.hiddenItemsPlacement == .floatingBar
                    ? "The hidden apps show in a bar below the menu bar. A click on one pins its item in the menu bar for you to click."
                    : "Hidden items return to the menu bar while shown. A notch or a long app menu can leave no room for them.")
            }
            Section {
                IconPreview(hidden: state.hiddenMenuBarIcon, shown: state.shownMenuBarIcon)
                IconPalette(title: "When items are hidden", selection: $state.hiddenMenuBarIcon)
                IconPalette(title: "When items are shown", selection: $state.shownMenuBarIcon)
            } header: {
                Text("Menu bar icon")
            } footer: {
                if state.hiddenMenuBarIcon == state.shownMenuBarIcon {
                    Text("Both states use the same icon, so you cannot tell whether items are shown.")
                        .foregroundStyle(.orange)
                }
            }
            Section {
                TimeoutRow(seconds: $state.rehideTimeout, isOn: $state.rehideOnTimeout)
                Toggle("On a click outside the menu bar", isOn: $state.rehideOnClickOutside)
                Toggle("When the front app or Space changes", isOn: $state.rehideOnFocusChange)
            } header: {
                Text("Hide again")
            } footer: {
                Text("Items stay while one of their menus is open or the pointer rests on the bar.")
            }
            Section {
                DisclosureGroup("Advanced", isExpanded: $showsAdvanced) {
                    ClockZoneRow()
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: settingsPaneWidth, height: showsAdvanced ? 830 : 720)
    }
}

/// Two cards that show what each placement does, selected like radio buttons.
private struct PlacementCards: View {
    @Binding var selection: AppState.HiddenItemsPlacement
    private let recommended = AppState.recommendedPlacement(hasNotch: NSScreen.anyHasNotch)

    var body: some View {
        HStack(spacing: 12) {
            card(.menuBar, title: "In the menu bar")
            card(.floatingBar, title: "In a bar below the menu bar")
        }
        .padding(.vertical, 4)
    }

    private func card(_ placement: AppState.HiddenItemsPlacement, title: String) -> some View {
        let isSelected = selection == placement
        return Button {
            selection = placement
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                PlacementIllustration(placement: placement)
                HStack(spacing: 6) {
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    Text(title)
                        .font(.callout.weight(.medium))
                        .lineLimit(2)
                }
                if placement == recommended, NSScreen.anyHasNotch {
                    Text("Recommended")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A menu bar strip with the hidden items either in it or in a bar below it.
private struct PlacementIllustration: View {
    let placement: AppState.HiddenItemsPlacement

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [.blue.opacity(0.45), .purple.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing))
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 3) {
                    Spacer()
                    if placement == .menuBar {
                        item(.accentColor)
                        item(.accentColor)
                    }
                    item(.primary)
                    item(.primary)
                    item(.primary)
                }
                .padding(.horizontal, 6)
                .frame(height: 10)
                .background(.white.opacity(0.5))
                if placement == .floatingBar {
                    HStack(spacing: 3) {
                        item(.accentColor)
                        item(.accentColor)
                        item(.accentColor)
                    }
                    .padding(3)
                    .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 3))
                    .padding(.trailing, 6)
                }
            }
        }
        .frame(height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true)
    }

    private func item(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 1.5).fill(color.opacity(0.8)).frame(width: 6, height: 6)
    }
}

/// The menu bar icon as it looks while items are hidden and while shown.
private struct IconPreview: View {
    let hidden: MenuBarIcon
    let shown: MenuBarIcon

    var body: some View {
        HStack(spacing: 10) {
            strip(hidden, label: "Hidden")
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            strip(shown, label: "Shown")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview: \(hidden.title) while hidden, \(shown.title) while shown")
    }

    private func strip(_ icon: MenuBarIcon, label: String) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Image(nsImage: icon.image)
                .renderingMode(.template)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .frame(maxWidth: .infinity)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }
}

/// One button per icon; the chosen one is filled with the accent color.
private struct IconPalette: View {
    let title: String
    @Binding var selection: MenuBarIcon

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                ForEach(MenuBarIcon.allCases, id: \.self) { icon in
                    let isSelected = icon == selection
                    Button {
                        selection = icon
                    } label: {
                        Image(nsImage: icon.image)
                            .renderingMode(.template)
                            .frame(width: 28, height: 24)
                            .foregroundStyle(isSelected ? Color.white : .primary)
                            .background(isSelected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help(icon.title)
                    .accessibilityLabel(icon.title)
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
    }
}

/// "After [n] seconds" with a switch. The value is typed or stepped and
/// always stays a whole number within the timeout range.
private struct TimeoutRow: View {
    @Binding var seconds: Double
    @Binding var isOn: Bool

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                TextField("Seconds", value: clamped, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 48)
                    .accessibilityLabel("Hide again after seconds")
                Stepper("Seconds", value: clamped, in: RehidePolicy.timeoutRange, step: 1)
                    .labelsHidden()
                Text("seconds").foregroundStyle(.secondary)
            }
            .disabled(!isOn)
            Toggle("After a timeout", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        } label: {
            Text("After a timeout")
        }
    }

    private var clamped: Binding<Double> {
        Binding(
            get: { RehidePolicy.clampedTimeout(seconds) },
            set: { seconds = RehidePolicy.clampedTimeout($0) }
        )
    }
}
