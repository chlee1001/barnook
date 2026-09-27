# Phase 0 record — hide method on macOS 27

Date: 2026-09-17. Machine: macOS 27.0 (26A428), two 3008×1692 displays and one 1920×1080 display, no notch.

## Result

The large-length divider method fails. The assessment-mode restriction works with no permission. The spec now uses the restriction. See `docs/spec.md`, "How it hides".

## What we tested

### Divider length

A spike app with one icon item and one divider item. A script set the divider length and read the divider window frame after one second. A third-party item sat left of the divider.

| Length | Divider frame | Item left of the divider |
|---|---|---|
| 100 to 1449 | Right edge on the icon, width as requested | Pushed left, still visible |
| 1489 (largest that fits) | Right edge on the icon | Drawn on top of the divider, next to the icon |
| 1500 and more | Left edge on the icon, extends off-screen to the right | Not moved |
| 10,000 | Same as 1500, width clamped to 5016 | Not moved |

`MenuBarAgent` places a wide item only while it fits between the app menus and the items to its right. Items that do not fit stay visible on top of the wide item. Nothing goes off-screen. Nothing goes into an overflow menu on these displays.

The fit limit depends on the width of the frontmost app menu. Ice PR 994 and the PWB97 fork size the divider to fit the region. This only pushes items on this machine.

### Status item windows

`CGWindowListCopyWindowInfo` lists no window per status item. Each display has one full-width `MenuBarAgent` window. The `NSStatusItem` window in the app is a proxy.

### Layout table

`MenuBarAgent` stores item order in `~/Library/Group Containers/com.apple.MenuBar/Library/Preferences/com.apple.MenuBar.plist`, key `TrailingItemPreferredPositions`. Keys look like `status:<bundle id>::<autosave name>` and `module:<name>`. The value is the distance from the right edge. A Cmd+drag updates the file.

An app without Full Disk Access cannot read the file. Thaw 3 asks the user to select the file once in a file panel.

### Assessment-mode restriction

`MenuBarAgent` runs an XPC server, `com.apple.MenuBarAgent.VisibilityRestrictionServer`. The private framework `MenuBarClientCore` wraps it in `MBAssessmentModeConfiguration` and `MBAssessmentModeAssertion`. This framework can be loaded with `dlopen`. Its entitlements are all public, so no private entitlement is necessary.

A test tool activated an assertion from a plain process. Results:

- Apps outside `allowedBundleIdentifiers` disappear at once. They return on `invalidate()`.
- `allowedSystemItems` takes integers, not strings. The strings from `AEMenuBarItem` (`battery`, `clock`, ...) do nothing.
- Codes 0 to 6 match the seven public `AEMenuBarItem` constants in order. Code 8 is Control Center. Code 6 is Wi-Fi.
- With codes 0 to 300, every system item stays visible except Focus and the camera/microphone indicator.
- The test process got no permission prompt.
- The spike app ran from `build/`. Its own icon disappeared under every allow-list, with the bundle ID, the process name, an ad-hoc signature, a Developer ID signature, and after `lsregister`. A copy in `/Applications` matched at once, with an ad-hoc signature. Bartender documents the same rule.
- A `kill -9` of the spike released the restriction. Every item returned.

## Tools

The scripts and `Sources/Ellipsis/main.swift` from this spike are no longer in the repository; `build/Ellipsis.app` was the historical bundle name. The current app builds from `Sources/BarNook/` as `BarNook.app` (see `docs/development.md`).

## Sources

- Ice `ControlItem.swift`: the 10,000-point method.
- Ice PR 994 and issue 980: the fitted-spacer attempt for macOS 27.
- Thaw 3.0.0 alpha release notes: the layout table and the per-app hiding limit.
- The Golden Gate assessment mode driver.
- `AutomaticAssessmentConfiguration.framework` headers: `allowsMenuBar`, `allowedMenuBarItems`, `AEMenuBarItem`.
