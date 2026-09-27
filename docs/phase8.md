# Phase 8 record — a menu bar that is too short

Date: 2026-09-18. Guest: the Phase 7 Tart VM, macOS 27.0 (26A5416b), one 1024×768 display, no notch. The short region comes from `FixtureW`, a regular app with five menus (`scripts/bundle-fixture.sh W 5`): while it is frontmost, about 217 points remain between its menus and the Spotlight item. The notch itself is untested until the host check at the end of this phase.

## Result

macOS 27 has its own overflow. `MenuBarAgent` fills the region from the right, collapses the items that do not fit at the region's left edge, and draws a system button, `«`, "Show Hidden Menu Bar Items", in their place. Nothing is pushed off-screen and nothing is lost from the layout. The BarNook icon is the first item to collapse when the set shows, because it is the leftmost.

## What we tested

| Question | Answer |
|---|---|
| What `MenuBarAgent` does with an item that does not fit | It collapses the leftmost items. Their frames stack at the region's left edge (W at 580, C at 583, the icon at 618 in a 217-point region), they are not drawn, and `«` appears where the drawn items start (637, 17×27). With ten menus and no room at all, every app item collapses, the BarNook icon too, and only `«`, Control Center and the clock are drawn. |
| Whether `MenuBarLayout` reports a frame for a collapsed item | Yes, with the stacked frame. So a collapsed item is one whose frame lies left of the `«` button, or overlaps another item's. The button is a childless `AXButton` in the `MenuBarAgent` window, which `MenuBarLayout` skips today. |
| Whether a restriction that allows one app makes its item fit | Yes, as long as the region holds the icon and that item. With every other app hidden, 217 points hold W (74), the icon (36) and one fixture (70). |
| Whether a collapsed item takes a click | Yes. A click at the collapsed icon's reported frame toggled the set, with nothing drawn there. A user cannot find it. |
| Whether `«` opens anything | Not from a synthetic click, a hover, a long press or `AXPress` on the button. Untested with a real mouse; try it over VNC. |

## Also found

- `com.apple.campo` is macOS 27's Spotlight service; its item is the magnifying glass at the right end of the app items. It is an app item to `MenuBarLayout` (it has an owner pid), not a system item, so `appItems(splitAt:)` and the divider count it.
- A regular app launched with `open` from `ssh` is not always frontmost at once; a second `open` activates it.
- `tart run` started from a shell that then exits leaves a runner that holds one of the two VM slots macOS allows. `scripts/vm.sh` boots in its own session and kills the runner on `delete`.

## What this means for F8

The spec says a shown item that does not fit "is not drawn at all". Closer: it is collapsed behind a system `«`, and the BarNook icon goes first. Three ways to go:

1. The floating bar as specified. The restriction stays, nothing collapses, the bar shows the hidden apps. The icon stays drawn because nothing else is added to the bar.
2. Show only what fits. Read the layout after a show; if anything is collapsed, hide again from the left until nothing is, or until only the icon is left. Partial shows, no new UI, but `MenuBarAgent` decides the order and the icon is the first casualty.
3. Rely on macOS's `«`. Only if it opens with a real mouse, and even then the icon is behind it.

The VM stands for the notch on every point above except one: whether the notch region behaves as the app-menu region does. That is the host check.
