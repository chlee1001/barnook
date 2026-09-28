# Test checklist

Modified by Chaehyeon Lee (2026): added floating-bar pin and menu bar icon checks; settings window pane checks.

Numbers match the acceptance criteria in `docs/spec.md`. A row marked `vm` has a test in `Tests/BarNookVMTests` that `mise run vm-test` runs in a Tart guest (see `docs/development.md`). The other rows are manual: run `scripts/run.sh` first and set the sets in Settings › Apps. They stay manual because they need the permission onboarding (1 to 1c), the right-click menu (4a, 6c), the Settings window (2a, 5a, 8a, S1 to S10, W1 to W5, M1 to M6, A1 to A6) or the release scripts (10, 11). 8g, B8, B8h, B8p, F2a, F2b and F4a have no VM test yet.

| # | Steps | Expect | Result |
|---|---|---|---|
| 1 | Fresh install, launch | Icon shows a nook. "Welcome to BarNook" lists Accessibility and Screen Recording, both not granted; "Continue" is disabled. Hiding works. | |
| 1a | Close the window. Right-click the icon › "Settings…". Quit. Relaunch. | "Settings…" shows the onboarding again, not Settings. It shows again at launch. | |
| 1b | "Grant…" for Accessibility, turn BarNook on in System Settings. | The row turns "Granted" within a second, without a relaunch. | |
| 1c | "Grant…" for Screen Recording, turn BarNook on in System Settings. "Relaunch BarNook". | After the relaunch, no onboarding shows at launch. "Settings…" opens Settings; General › Permissions shows both "Granted". | |
| 2 | Put an app in the hidden set. Click the icon. Click again. | Items hide, show (`‹`), hide (nook). | vm |
| 2a | Settings › Menu Bar › Menu bar icon: pick a different icon for each state. Toggle the set in light and dark menu bars. Quit. Relaunch. | Each palette shows every icon with its image. The icon changes at once, matches the state, stays readable and clickable, and survives the relaunch. | Pass |
| 3 | Show the set. Quit. Relaunch. | Set is still shown. Sets are unchanged. | vm |
| 3a | Hide A. Quit the visible app B, relaunch B. | B reappears and stays. The `restriction` log shows `skip: unchanged` and no `activate` naming B. | vm; host pass with Clipy (4101e9a) |
| 3b | Hide A. Quit A, relaunch A. | A stays hidden. The `restriction` log shows `skip: unchanged` and no new `reason=fresh`. | vm |
| 4 | Put an app in the always-hidden set. Click. Option+click. | Normal click keeps it hidden. Option+click shows it. | vm |
| 4a | Right-click, "Show always-hidden items". | Both sets show. Menu item gets a checkmark. | |
| 4b | Settings › Apps: turn off "Always-hidden apps". | Always-hidden apps appear at once. | vm |
| 5 | Show the set. Wait for the timeout (default 15 s). | Set hides. | vm |
| 5a | Settings › Menu Bar: set the timeout to 3 s while the set is shown. | Set hides 3 s later. | Pass |
| 5b | Settings › Menu Bar: turn "After a timeout" off. Show the set. Wait. | Set stays. | vm |
| 6 | Show the set. Click the desktop. | Set hides. | vm |
| 6a | Show the set. Click another item in the menu bar. | Set stays. | vm |
| 6b | Settings › Menu Bar: turn "When the front app or Space changes" on. Show the set. Cmd+Tab to another app. | Set hides. | vm |
| 6c | Same setting on. Show the set. Right-click, "Settings…". | Set stays. BarNook coming to the front is not a focus change. | Pass |
| 7 | Show the set. Open the menu of a shown item. Wait past the timeout. | Set stays while the menu is open. Hides right after the menu closes. | vm |
| 7a | Show the set. Open the menu of a shown item. Pick a menu item. | Menu action runs. Set hides. | vm |
| 8 | Menu-bar mode. While the set is hidden, move the pointer to the clock. Click. Move away. | Hidden items show near the clock. Notification Center opens. Items hide again after 0.5 s. | vm |
| 8c | Menu-bar mode, 4 s timeout. Show the set, rest the pointer on the clock. | The set hides after 4 s but the items stay while the pointer is there; they hide once it leaves. | vm |
| 8g | Menu-bar mode. Rest on the clock, then move straight onto the Settings window. | The items hide within about 0.7 s. | |
| B8 | Bar mode, both permissions. Click the clock 10 times on each display (open, close). | Notification Center opens and closes each time. No hidden item appears in any menu bar, on any display. | Synthetic clicks: externals 0 hidden frames, NC 13/14 (docs/notification-center-clock.md); real clicks, a live panel with zero notifications (unit test only), latency gate, a refresh-rate recording (`screencapture -v` on this host averages about 17–43 fps) and panels opened outside BarNook (Fn+N, trackpad) not run |
| B8h | Bar mode. Sweep the pointer across the clock in under 60 ms; then rest on it for 5 s and leave. | The sweep does nothing. The rest covers the menu bars and lifts under the covers; no hidden item appears on screen, the strip is a still picture until the pointer leaves, then the restriction returns. | Host (95b2433): sweep no pre-lift; 5 s park, 0 hidden in the recording |
| B8p | Bar mode. Rest on the clock ~300 ms, click; leave. Then rest, leave, click another app within 1 s, rest again. | The click opens Notification Center within 700 ms (test gate; spec, "How it hides", records the measured spread); the second rest replays nothing. | Host (087ef3c+): stale-click case passes; open, then a clock click during the restore or after a rest closes it once with no reopen. Mouse-down to open: 25–400 ms after a 1 s rest (4e1f98a, built-in display off: 130 ms); about 500 ms after a 300 ms rest (087ef3c). With no rest, outside this row's gate: 317–587 ms (9708bd0), 410–717 ms (4e1f98a, built-in display off; the first click after idle was slowest). Not run: panels opened outside BarNook |
| 8a | Accessibility revoked after Settings opened: Menu Bar › Advanced, "Click the Clock…", click the left edge of the clock. | The width becomes the distance to the right edge plus 30. "Reset" returns 300. | Pass |
| 8b | With Accessibility: open Settings, then Menu Bar › Advanced. | "N points, measured". Hidden items show over the clock, not over Control Center. | vm |
| 9 | Quit from the right-click menu. | Every item returns. | vm |
| 9a | `kill -9` BarNook. | Every item returns. | vm |
| S1 | Settings › Apps: set an app to Hidden. | Its items hide at once. | |
| S2 | Set the same app to Always hidden. | It leaves the hidden set. Items stay hidden after a normal click. | |
| S3 | Set an app to Hidden, quit that app. | It stays in the list, marked "Not running". Set it to Shown. It leaves the list. | |
| S4 | Launch another app while Settings is open. | It appears in the Apps list. | |
| S5 | General: turn on "Launch at login". Open System Settings › Login Items. | BarNook is listed. Turn it off there. The switch in BarNook turns off when the window comes back to the front. | |
| S6 | General: "Quit BarNook". | Every item returns. | |
| S7 | General: "Export…", save. Open the file. | A plist with the sets and the rehide options. No `isHiddenSetShown`. | |
| S8 | Change a set. General: "Import…", pick the file from S7. | The set returns to the exported one at once. Items hide or show to match. | |
| S9 | "Import…", pick a plist that is not from BarNook. | An alert: "The file has no BarNook settings." Settings unchanged. | |
| S10 | "Import…", pick a plist with `rehideTimeout` 0. | An alert: "The value of “rehideTimeout” is outside 1-300." Every setting unchanged. | |
| W1 | Click the three panes, close, reopen. | The title follows the pane; minimize and zoom are dimmed; the height follows the pane; the window reopens on the last pane. | |
| W2 | Dark mode: every pane and the onboarding. | Every control, badge and glyph is readable. | |
| W3 | Keyboard only through every control; in each text field use Cmd-X/C/V/A. | Tab reaches every control; the four shortcuts work in every text field. | |
| W4 | VoiceOver over every pane and the onboarding. | Pane buttons and every control are read by name. | |
| W5 | Built-in 13-inch display at the default scale: open each pane. | The window stays on screen; a long pane scrolls inside. | |
| M1 | Reset the settings on a Mac without a notch and on a notch MacBook; open Menu Bar. | No notch: no Recommended, "In the menu bar" chosen. Notch: Recommended on the bar card only, the bar chosen. | |
| M2 | Pick the same icon for both states, then change one. | The warning shows and the choice is saved; the warning goes. | |
| M3 | Timeout field: 0, 999, abc, 42 and Return; the stepper to both ends; turn the switch off. | 1, 300, the previous value, 42; 1–300; the field and stepper disabled. | |
| M4 | Expand and collapse Advanced. With Accessibility off, "Click the Clock…". | Collapsed by default; the clock zone texts and buttons as before; width = distance + 30; Reset returns 300. | |
| M5 | Quit. `defaults write com.chlee1001.BarNookDev rehideTimeout -float 0`. Launch, show the set. | The field shows 1; the set hides after about 1 s, not at once. | |
| M6 | Turn "On a click outside the menu bar" off, show the set, click the desktop. | The set stays until the timeout. | |
| A1 | Set one app Shown, Hidden, Always hidden, then Shown. | After each step the app is in exactly one set or none; the counts follow. | |
| A2 | Turn "Always-hidden apps" off, then on. | Off: the always-hidden apps show, rows read "Always hidden · paused", the third segment is disabled. On: they hide again and the list is kept. | |
| A3 | Without Accessibility, open Apps. | "By position" cannot be chosen; the footer says position mode needs Accessibility. The rows stay editable. | |
| A4 | "By position": turn Always hidden on for an app left of the icon, then off. | On: a purple Always hidden capsule. Off: Shown until the next show or Cmd-drag, then Hidden by position. The list is never greyed out. | |
| A5 | Type part of an app name in the search field, then clear it. | Only matching apps show; the counts stay; no match shows "No apps with a menu bar item match." | |
| A6 | Quit a listed app. | "Not running"; it leaves the list once set to Shown. | |
| D1 | Settings › Apps: choose "By position" (needs Accessibility). | Apps already left of the icon hide. Rows show read-only Shown/Hidden capsules; the list stays readable. | vm |
| D2 | While the set is hidden, Cmd-drag the icon to the right of an item. | That app hides. | vm |
| D3 | Show the set. Cmd-drag the icon to the far left. | Every app leaves the hidden set and stays when the set hides again. | vm |
| D4 | Cmd-drag an app's item from right of the icon to left of it. | It hides. | vm |
| D5 | Settings › Apps: choose "From this list". | The rows are editable. The set is unchanged. | vm |
| F1 | A front app with a wide menu bar (or a notch). "In the menu bar" mode. Show the set. | macOS collapses what does not fit behind `«`. | vm |
| F2 | Same, "In a bar below the menu bar" mode. Click the icon. | A bar under the icon lists the hidden apps. Nothing in the menu bar moves. Icon shows `‹`. | vm |
| F3 | Option-click the icon in bar mode. | The bar adds the always-hidden apps. | vm |
| F4 | Bar mode. Each rehide condition. | The bar closes. A click in the bar does not close it. | vm |
| F2a | Bar mode. Show the set. Quit. Relaunch. Click the icon. | The bar opens at launch; the click hides the set. | Host pass |
| F2b | Bar mode. Pin an app, then unpin it from the reopened bar. | The icon reopens the bar and the set stays shown. | |
| F4a | Bar mode, 3 s timeout, focus rehide off. Show the set, rest the pointer on the bar for 5 s, then leave. | The set stays while the pointer is on the bar and hides once it leaves. | Host: stays 5 s; leave timing not checked |
| F5 | Bar mode, no Accessibility. Click an app in the bar. | The app is pinned: its item appears alone in the menu bar, every other app hides at once, and the bar closes. The icon brings the bar back, then hides everything. | Manual; VM grants Accessibility |
| F6 | Bar mode, with Accessibility. Click an app in the bar. | The app is pinned: its item appears in the menu bar, the bar closes, and its menu opens from a click on the item. Picking an item runs it; the set hides from the icon. | vm |
| F6a | Same, with a front app whose menus leave room for one item only. | A second pin that does not fit hides every other app; both pins are drawn. After the set hides, the front app's item returns. | vm |
| F6b | Three pins, with a menu bar item that animates (a timer, a meter). Leave the pointer alone. | The pins stay. No rehide condition and no fit-check escalation takes them away. | Pass |
| F6c | Pin an app that runs from outside `/Applications` (Synology Drive). | The bar marks it and says why. The other items stay: no escalation for an item macOS will not draw. | Pass |
| F7 | On the notch MacBook, first launch. | "Show hidden items" defaults to the bar. Settings › Menu Bar switches it. | Pass |
| 10 | Release build: `spctl --assess`, `stapler validate`. | Both pass. | Phase 5 |
| 11 | Clean checkout: `swift build`, every script. | No Xcode project needed. | Phase 5 |
