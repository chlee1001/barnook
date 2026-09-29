# BarNook

Modified by Chaehyeon Lee (2026): floating-bar pins, BarNook branding, an independent update channel, the settings panes and the hidden app order.
Original project: [ronny/ellipsis](https://github.com/ronny/ellipsis).
Website: [chlee1001.github.io/barnook](https://chlee1001.github.io/barnook/) ([한국어](https://chlee1001.github.io/barnook/ko/)).

BarNook hides selected menu bar items on macOS 27. Click its icon to show them. Click again, or wait, to hide them again.

## Requirements

- macOS 27.0 or later.
- BarNook must run from `/Applications`. `MenuBarAgent` matches the allow-list against apps in that folder only. A copy in any other folder hides its own icon.
- BarNook requires Accessibility and Screen Recording. The first window asks for both, and Settings opens once they are allowed. Hiding and showing work in the meantime. See Limits.

## Install a release

1. Download `BarNook-X.Y.Z.zip` from [GitHub Releases](../../releases).
2. Open the zip. Move `BarNook.app` to `/Applications`.
3. Open BarNook. Its small nook icon appears in the menu bar. Settings › Menu Bar › "Menu bar icon" picks a different icon for the hidden and shown states.
4. Right-click the icon. Select "Settings…". In Settings › Apps, set apps to Hidden. Or, with the Accessibility permission, choose "By position" and Cmd-drag items to the left of the icon. Drag the apps in the Hidden group to set their order in the bar below the menu bar.

On a MacBook with a notch, a shown set may not fit in the menu bar. macOS then collapses the items that do not fit behind a `«` button, the BarNook icon first. So on a notch display, BarNook shows the hidden apps in a bar below the menu bar instead, one app icon per app, and the menu bar stays as it is. A click on an app in the bar pins its item for you to click in the menu bar. Settings › Menu Bar › "Show hidden items" switches between the bar and the menu bar on any display.

This fork checks its own GitHub Releases for updates with [Sparkle](https://sparkle-project.org). At the second launch, it asks whether it can check on its own. "Check for Updates…" in the icon menu checks now. The original app uses a different signing and update key; it cannot update itself into this fork. Install this fork manually once and reconfigure its separate settings.

## Limits

- Private API. BarNook loads `MenuBarClientCore.framework` and uses its `MBAssessmentMode` classes. A macOS update can rename or remove them. BarNook checks for the classes at launch and shows an alert if they are missing.
- Focus and the camera/microphone indicator are hidden while any set is hidden. No setting brings them back. This is a limit of the API.
- The hidden sets hold whole apps, not single items. An app with two menu bar items hides both.
- The bar below the menu bar shows app icons, not the items. An item that changes (a timer, a meter) shows only its app icon there. A click on an app in the bar pins its item in the menu bar for you to click, up to three at once; without the Accessibility permission the other items give way while a pin is up.
- An app that runs from outside `/Applications` cannot be pinned into view. `MenuBarAgent` matches its allow-list against `/Applications` only, so macOS hides that item whenever BarNook hides anything. The bar marks such an app. Synology Drive, which runs from `~/Library/Application Support`, is one. Keep it out of the hidden set, or switch "Show hidden items" to "In the menu bar", which lifts the restriction while the set is shown.
- With the Accessibility permission, the Apps list in Settings shows only apps with a menu bar item, the icon can work as a divider (Cmd-drag items to its left to hide them), and the clock zone fits the clock. If the permission is revoked later, the list shows every running app.

## Alternatives

- [Ice](https://github.com/jordanbaird/Ice), doesn't work in macOS 27 at the time of writing.
- [Thaw](https://github.com/thaw-app/Thaw), doesn't work in macOS 27 at the time of writing.
- [Bartender 7](https://www.macbartender.com/bartender7)

## Development

See [docs/development.md](docs/development.md) for how to build, test and release.

## License

Based on [ronny/ellipsis](https://github.com/ronny/ellipsis) by Ronny Haryanto.
Chaehyeon Lee modified the floating bar to pin menu bar items in 2026.
These changes are noted in the modified files. The original copyright notice
is retained; BarNook remains under the Apache License 2.0. See [LICENSE](LICENSE)
and [CREDITS.md](CREDITS.md).
