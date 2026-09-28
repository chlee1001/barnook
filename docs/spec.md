# BarNook — specification

Modified by Chaehyeon Lee (2026): specified temporary floating-bar pins and selectable menu bar icons.

BarNook is a macOS menu bar item manager based on [ronny/ellipsis](https://github.com/ronny/ellipsis). It hides and shows menu bar items of other apps on macOS 27 (Golden Gate).

## Goals

- Hide and show menu bar items with one click.
- Keep an "always hidden" set of apps that you never want to see.
- Rehide the items automatically after a timeout or after a click outside the menu bar.
- Hiding and showing need no permission. BarNook requires Accessibility and Screen Recording, for the menu bar layout and for the covered clock click in bar mode (F6). No Full Disk Access.
- Build with SwiftPM and shell scripts only. No `.xcodeproj`, no Xcode GUI.
- Ship a Developer ID signed and notarized `.app`.

## Non-goals

- Menu bar appearance changes (tint, shadow, border, shape).
- Menu bar item search or spotlight.
- User-supplied icons or profiles.
- Per-display rules.
- Global hotkeys (not in v1).
- Item rearrangement. BarNook never moves an item.
- Hiding one item of an app while another item of the same app stays visible. macOS 27 cannot do this (see "How it hides").
- macOS 26 or earlier.

## Definitions

| Term | Meaning |
|---|---|
| Item | One menu bar item from any app. |
| App | The owner of one or more items, identified by its bundle identifier. |
| Hidden set | Apps that BarNook hides until you click the BarNook icon. |
| Always-hidden set | Apps that BarNook hides until you Option+click the BarNook icon. |
| Restriction | The macOS 27 assessment-mode allow-list that BarNook holds while it hides apps. |
| BarNook icon | The clickable `NSStatusItem` that BarNook owns. Its glyph can be chosen separately for hidden and shown items. |

## How it hides

macOS 27 moved menu bar layout into a system process, `MenuBarAgent`. The old method, a status item with a length of 10,000 points, no longer works. `MenuBarAgent` places a wide item only while it fits. It draws items that do not fit on top of the wide item. It never pushes an item off-screen. The Phase 0 spike proved this on a display without a notch. See `docs/phase0.md`.

BarNook uses the menu bar half of macOS assessment mode instead. This is the mechanism behind `AEAssessmentConfiguration.allowedMenuBarItems` (public, macOS 27). The public API needs an Apple-approved entitlement and locks the whole machine. The private framework `MenuBarClientCore` exposes only the menu bar part:

```
MBAssessmentModeConfiguration(allowedSystemItems: [NSNumber], allowedBundleIdentifiers: [String])
MBAssessmentModeAssertion.activate(withConfiguration:completionHandler:)
MBAssessmentModeAssertion.invalidate()
```

While an assertion is active, `MenuBarAgent` shows only the apps and system items in the allow-list. BarNook puts every app except the hidden ones in the allow-list. BarNook puts every system item code (integers 0 to 40) in the allow-list. No permission is necessary. Thaw 3 uses the same mechanism.

Known limits of this mechanism:

- Granularity is one app, not one item. If an app has two items, both hide together.
- Focus and the camera/microphone indicator are hidden while a restriction is active. No system item code brings them back.
- The framework is private. BarNook loads it with `dlopen` and checks that the classes exist at launch. If they do not exist, BarNook shows an alert and quits.
- The `allowedSystemItems` codes are undocumented. Code 2 is the clock, code 6 is Wi-Fi, code 8 is Control Center.
- Notification Center does not open from a clock click while a restriction is active. Control Center and Wi-Fi menus do open. No system item code changes this (tested 0 to 2000). `MenuBarAgent` decides at mouse-down, so a release on mouse-down is too late. In menu-bar mode BarNook releases the restriction while the pointer is in the trailing zone of the menu bar, and applies it again 0.5 seconds after the pointer leaves; hidden items show while the pointer is there. In bar mode, when the pointer rests on the clock for 60 ms, BarNook covers every menu bar left of its clock (status items and app menu titles) with a picture of itself and lifts the restriction under the covers, so a click reaches MenuBarAgent as it is instead of waiting for a lift. How fast Notification Center then opens depends on how long MenuBarAgent is still busy with the lift; on the host, mouse-down to panel ranged from about 25 ms to about 400 ms after a 1 s rest, about 320–600 ms after a 300 ms rest, and about 320–720 ms with no rest, where the first click after idle is the slowest. The test gate (testing.md B8p, after a rest) is 700 ms. While the pointer rests there, that part of every menu bar is a still picture. The restriction returns and the covers come off once the pointer leaves the clock, the displays change or the placement does. A click that comes before the covers are up is replayed once they are: BarNook covers every status strip, lifts the restriction, replays the click 10 ms later, reapplies it once Notification Center opens (at most 900 ms), and removes the covers once the layout has no hidden app again (about 1.3 s; at the latest after 1 s for MenuBarAgent's reply plus 3 s for the layout, and an unreadable layout counts as not yet settled). A menu bar without a strip to cover (no clock, no matching screen) stops the lift before it starts. The lift draws the hidden items under the covers; the covers keep them off screen. Needs Accessibility and Screen Recording (F6). A click while Notification Center is open closes it with no lift. The zone is 300 points by default, the clock plus 30 points when measured (F6), or set by one click on the clock (F4).
- Item frames are not readable without the Accessibility permission. `MenuBarAgent` has a utilities service (`listMenuBarItemsForSpaceID:`, `getPreferredTrailingItemPositions:`) but it needs the private entitlement `com.apple.private.menubar.utilities`. The window server exposes no window per item. With the permission, the windows of `MenuBarAgent` expose one slot per item with its frame and owner.
- Activation is asynchronous. The newest assertion wins while several are alive, and an `invalidate` of an older one leaves the newer one intact. BarNook keeps older assertions until a newer one reports success, or every item flashes for a moment. A failed activation leaves the previous assertion live and is retried after 250 ms, 1 s and 4 s. An allow-list MenuBarAgent already holds (same apps, same MenuBarAgent pid) is not asked for again. A release also invalidates any assertion still on its way, so none outlives it; one that did (seen on 27.0 when two activations overlapped) kept the bar restricted through every later release. Hidden items can show only when no assertion is live: after MenuBarAgent restarts, until the next running-apps change reasserts, and after an activation fails with none live before it, until a retry succeeds; once three retries have failed, the next running-apps change tries again. Both are logged under the `restriction` category. An allowed app that quits stays on the list until the next release, so a background agent that restarts does not change the assertion.
- `MenuBarAgent` matches the allow-list only against apps that run from `/Applications`. An app that runs from another folder is always hidden while a restriction is active. This includes BarNook itself. The BarNook icon disappears if BarNook runs from a build folder.

BarNook releases the restriction when it shows the hidden set. BarNook holds a restriction that hides only the always-hidden set when it shows the hidden set with a normal click.

## Features

### F1: Hide and show the hidden set

- The BarNook icon defaults to a nook when the hidden set is hidden and `‹` when the set is shown. Each state has an independent choice of bundled template glyphs: nook, ellipsis, left or right chevron, dot, or star.
- Click the icon to toggle the hidden set.
- The state persists across restarts.

### F2: Always-hidden set

- Apps in the always-hidden set stay hidden after a normal click.
- Option+click on the BarNook icon shows both sets.
- The Settings window has a switch to enable or disable this set. Default: enabled.

### F3: Auto-rehide

BarNook rehides the hidden set when one of these conditions is true and the related setting is on:

- Timeout. A timer starts when the set is shown. Default: 15 seconds. Range: 1–300 seconds. Off is permitted.
- Click outside. The user clicks anywhere that is not the menu bar.
- Focus change. The frontmost app changes or the active Space changes.

Each condition has its own switch in Settings. Defaults: timeout on, click outside on, focus change off.

BarNook does not rehide while a menu from a shown item is open, or while the pointer rests on the floating bar (F8).

### F4: Settings window

A SwiftUI window with these controls:

- Launch at login (`SMAppService`).
- Menu bar icon: separate pickers for the hidden and shown states; changes take effect immediately and are included in settings export/import.
- Hidden set: a list of running apps with a checkbox per app. BarNook lists apps with a `.regular` or `.accessory` activation policy.
- Always-hidden set: the same list, and a switch to enable the set.
- "Hide apps left of the BarNook icon": a switch (F7). Off without the Accessibility permission.
- Auto-rehide: three switches and the timeout value.
- Clock zone: the width, and without the Accessibility permission a "Click the Clock…" button that takes the width from the next click in the menu bar.
- Export and import: the sets and the options above as a property list file. Import ignores unknown keys and refuses a value of the wrong type.
- Version number and a quit button.

Open the window from a right-click menu on the BarNook icon. The same menu has "Show always-hidden items", "Settings…", and "Quit".

### F5: App shape

- Menu bar only. `LSUIElement` is true. No Dock icon.
- Minimum macOS: 27.0.
- Swift 6 language mode, strict concurrency.
- Persist settings in `UserDefaults`.

### F6: Required permissions and onboarding

BarNook requires two permissions:

- **Accessibility.** BarNook asks each app over Accessibility (`AXExtrasMenuBar`) whether it has a menu bar item, so the pickers (F4) list only those apps. It reads the menu bar layout from `MenuBarAgent`, fits the clock zone to the clock, and clicks the clock in bar mode (F8).
- **Screen Recording.** In bar mode a clock click lifts the restriction for a moment. BarNook covers the status-item strip with a picture of itself during that time, so hidden items do not appear on screen (`docs/phase9.md`). The picture stays in memory.

Hiding and showing work without either permission.

- **Launch.** While one is missing, a "Welcome to BarNook" window shows at launch. It lists both permissions with their state and a "Grant…" button each. The button shows the system prompt and opens the permission's list in System Settings. The window re-reads the state every second.
- **Screen Recording takes effect after a relaunch.** Once it was requested, the window offers "Relaunch BarNook".
- **Settings.** "Continue" opens Settings once both are granted. Until then, the icon menu's "Settings…" opens the onboarding window instead. Settings › General shows both permissions' state.
- **Changes.** BarNook notices an Accessibility change at once, through the `com.apple.accessibility.api` distributed notification. Screen Recording is read when a window shows and before each covered clock click.
- **VM tests.** `skipsPermissionOnboarding` in the defaults keeps the window from showing at launch. The guest grants both permissions through the TCC database.

### F7: The icon as divider

Off by default. When on, the BarNook icon divides the menu bar like the Bartender and Ice icons do: Cmd-drag items across it. Needs the Accessibility permission: with it, the windows of `MenuBarAgent` expose every visible item with its frame and owner, and the icon's own window frame gives the split point.

- A visible app left of the icon joins the hidden set. A visible app right of it leaves the set, but only while the set is shown: while it is hidden, a hidden app can still be on its way out.
- An app with an item on each side hides. Hiding is per app.
- Apps that are not visible keep their membership. The always-hidden set is never touched.
- BarNook reads the menu bar when the switch turns on, when the set is shown, after a Cmd-drag ends, and after an app launches. Turning the switch on hides whatever already sits left of the icon.
- While the switch is on, the Hidden picker in Settings is read-only.

### F8: The floating bar

A notch splits the menu bar. `MenuBarAgent` never pushes an item off-screen: it fills the status item region from the right, collapses the leftmost items that do not fit, and draws a system `«` button in their place (`docs/phase8.md`). The BarNook icon is the leftmost, so it collapses first. On a display with a notch, "show" loses items and the icon. The floating bar shows the hidden apps in a panel below the menu bar instead. The restriction stays active and nothing in the menu bar moves.

No image of an item is available. On macOS 27 the window server has no window per item, so the ScreenCaptureKit method of Ice (capture each item window) does not work. A capture of the menu bar region needs the Screen Recording permission, and it cannot capture an item that is not drawn. So the bar shows the app icon (`NSRunningApplication.icon`) of each hidden app. Hiding is per app, so one icon per app is the same granularity.

- Settings › General has "Show hidden items": "In the menu bar" or "In a bar below the menu bar". Until the user picks one, the default is the bar when a screen has a notch at launch (`NSScreen.safeAreaInsets.top` is more than zero), and the menu bar otherwise.
- In bar mode, a click on the icon shows the panel with one icon per app in the hidden set. An Option click adds the always-hidden set. The icon changes to the chevron as it does today.
- The panel is a non-activating `NSPanel` at the status bar level, on every Space and next to full-screen apps. Its right edge is under the BarNook icon. Its top is at the bottom edge of the menu bar. The frontmost app keeps the focus.
- Each icon has a tooltip with the app name. A hover highlights it.
- The rehide conditions of F3 close the panel: timeout, a click outside the panel and the menu bar, and a focus change.
- A click on an icon pins that app. The restriction lets its item through, the panel closes, and the user clicks the item itself in the menu bar, as they would any other item. Nothing is pressed on the user's behalf: the press raced the layout and lost the item its menu. Up to three apps are pinned at once (`PinPolicy`); a click past the limit drops the oldest pin, and a click on a pinned app unpins it. With the Accessibility permission the pins are checked against the layout once it settles: a pin that does not fit (macOS put it behind `«`) hides every other app, so every pin is drawn whenever the region holds the icon and the pins. Without the permission nothing can be read, so every other app hides at once, the one arrangement that always leaves the pin on screen.
- Whenever the set is shown in bar mode and the bar is closed — a pin closed it, the last pin went, or BarNook relaunched — the icon brings the bar back on the first click and hides the set, the pins and the bar on the second. A relaunch with the set shown opens the bar. No rehide condition takes a pin away: a pin is an item the user put in the menu bar to click, and a timeout or a focus change that pulled it back would be the click-through race again, one step removed. The conditions resume once the last pin is gone.
- An app that runs from outside `/Applications` is marked in the bar and cannot be pinned into view: `MenuBarAgent` matches the allow-list against `/Applications` only, so the item stays hidden whatever the allow-list says (see "How it hides"). Such an app is left out of the fit check too — hiding every other app would empty the menu bar and still not draw it.
- An app with an item that changes (a timer, a meter) shows only its app icon in the bar. The README lists this limit.

## Build and distribution

- `Package.swift` with a SwiftPM executable target and Sparkle for updates.
- `scripts/bundle.sh` assembles `build/BarNook.app` from the SwiftPM binary, `Info.plist`, entitlements, licenses and the icon.
- `scripts/sign.sh` signs with the Developer ID Application certificate and hardened runtime.
- `scripts/notarize.sh` submits the app with `notarytool`, waits, and staples the ticket.
- `scripts/release.sh` runs the three scripts above and produces a `.zip` or `.dmg`.
- Signing identity and Apple ID come from environment variables. Never commit them.

## Acceptance criteria

1. A fresh install on macOS 27 shows the BarNook icon and the "Welcome to BarNook" window with both permissions. Settings opens only after both are granted; Screen Recording applies after the offered relaunch.
2. Add an app to the hidden set. Its items disappear. Click the icon. The items return. Click again. The items disappear.
3. Quit and relaunch. The hidden state and the sets are unchanged.
4. Add an app to the always-hidden set. It stays hidden after a normal click. Option+click shows it.
5. Show the set, wait for the timeout. The set hides itself.
6. Show the set, click on the desktop. The set hides itself.
7. Show the set, open the menu of a shown item. The set does not hide while the menu is open.
8. While the hidden set is hidden, move the pointer to the clock and click. Notification Center opens.
9. Quit BarNook. Every item returns.
10. `spctl --assess` and `stapler validate` pass on the release build.
11. `swift build` and all scripts run from a terminal with no Xcode project.

## Open risks

- Private API. A macOS 27 point release can rename or remove the `MBAssessmentMode*` classes. BarNook checks for them at launch.
- The `/Applications` rule comes from a test on one machine. Other folders that LaunchServices registers, such as `~/Applications`, are not tested.
- If BarNook crashes, `MenuBarAgent` drops the restriction when the XPC connection closes. This needs a test.
- Global mouse monitors (`NSEvent.addGlobalMonitorForEvents`) deliver mouse-move and mouse-down events with no Accessibility permission on macOS 27.0. BarNook depends on this for the clock hover and for F3 "click outside".
- Open menus of other apps come from `CGWindowListCopyWindowInfo`, deprecated since macOS 14. Its replacement, `SCShareableContent`, needs Screen Recording. If the window list stops reporting pop-up menu windows, the menu-open guard for F3 stops working and a rehide can close a shown item's menu.
- The default clock zone is 300 points, so hidden items show whenever the pointer is near the right end of the menu bar. The measured or clicked zone fixes that, but a clock that grows (a longer date format) can outgrow a clicked zone. The measured zone follows: it is read again when Settings opens.
- The floating bar (F8) is built on displays without a notch. The behavior of `MenuBarAgent` with a notch on macOS 27 comes from one spike on one laptop (`docs/phase8.md`). The escalation that hides every other app for the pins makes the visible items disappear for a moment; with the permission it is used only when a pin does not fit.
