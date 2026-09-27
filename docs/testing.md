# Test checklist

Modified by Chaehyeon Lee (2026): added floating-bar pin checks.

Numbers match the acceptance criteria in `docs/spec.md`. A row marked `vm` has a test in `Tests/EllipsisVMTests` that `mise run vm-test` runs in a Tart guest (see `docs/development.md`). The other rows are manual: run `scripts/run.sh` first and set the sets in Settings › Hidden and Settings › Always Hidden. They stay manual because they need the permission dialog (1 to 1b), the right-click menu (4a, 6c), the Settings window (5a, 8a, S1 to S9) or the release scripts (10, 11).

| # | Steps | Expect | Result |
|---|---|---|---|
| 1 | Fresh install, launch | Icon shows `…`. One BarNook dialog offers Accessibility. No macOS prompt. | |
| 1a | Dialog: "Not Now". Quit. Relaunch. | No dialog. Settings › General shows "Grant Permission…". | |
| 1b | Settings: "Grant Permission…", then turn BarNook on in System Settings › Accessibility. | Settings shows "Granted" without a relaunch. Hidden tab lists only apps with a menu bar item. | |
| 2 | Put an app in the hidden set. Click the icon. Click again. | Items hide, show (`‹`), hide (`…`). | vm |
| 3 | Show the set. Quit. Relaunch. | Set is still shown. Sets are unchanged. | vm |
| 4 | Put an app in the always-hidden set. Click. Option+click. | Normal click keeps it hidden. Option+click shows it. | vm |
| 4a | Right-click, "Show always-hidden items". | Both sets show. Menu item gets a checkmark. | |
| 4b | Settings: turn off "Keep an always-hidden set". | Always-hidden apps appear at once. | vm |
| 5 | Show the set. Wait for the timeout (default 15 s). | Set hides. | vm |
| 5a | Settings: set the timeout to 3 s while the set is shown. | Set hides 3 s later. | Pass |
| 5b | Settings: turn "After a timeout" off. Show the set. Wait. | Set stays. | vm |
| 6 | Show the set. Click the desktop. | Set hides. | vm |
| 6a | Show the set. Click another item in the menu bar. | Set stays. | vm |
| 6b | Settings: turn "When the front app or Space changes" on. Show the set. Cmd+Tab to another app. | Set hides. | vm |
| 6c | Same setting on. Show the set. Right-click, "Settings…". | Set stays. BarNook coming to the front is not a focus change. | Pass |
| 7 | Show the set. Open the menu of a shown item. Wait past the timeout. | Set stays while the menu is open. Hides right after the menu closes. | vm |
| 7a | Show the set. Open the menu of a shown item. Pick a menu item. | Menu action runs. Set hides. | vm |
| 8 | While the set is hidden, move the pointer to the clock. Click. Move away. | Hidden items show near the clock. Notification Center opens. Items hide again after 0.5 s. | vm |
| 8a | Without Accessibility: General, "Click the Clock…", click the left edge of the clock. | The width becomes the distance to the right edge plus 30. "Reset" returns 300. | Pass |
| 8b | With Accessibility: open General. | "N points, measured". Hidden items show over the clock, not over Control Center. | vm |
| 9 | Quit from the right-click menu. | Every item returns. | vm |
| 9a | `kill -9` BarNook. | Every item returns. | vm |
| S1 | Settings › Hidden: check an app. | Its items hide at once. | Pass |
| S2 | Check the same app under Always Hidden. | It leaves the Hidden list. Items stay hidden after a normal click. | Pass |
| S3 | Check an app, quit that app. | It stays in the list, marked "Not running". Uncheck it. It leaves the list. | |
| S4 | Launch another app while Settings is open. | It appears in both lists. | |
| S5 | General: turn on "Launch at login". Open System Settings › Login Items. | BarNook is listed. Turn it off there. The switch in BarNook turns off when the window reopens. | |
| S6 | General: "Quit BarNook". | Every item returns. | |
| S7 | General: "Export…", save. Open the file. | A plist with the sets and the rehide options. No `isHiddenSetShown`. | |
| S8 | Change a set. General: "Import…", pick the file from S7. | The set returns to the exported one at once. Items hide or show to match. | |
| S9 | "Import…", pick a plist that is not from BarNook. | An alert: "The file has no BarNook settings." Settings unchanged. | |
| D1 | Settings › Hidden: turn on "Hide apps left of the BarNook icon" (needs Accessibility). | Apps already left of the icon hide. The Hidden picker greys out. | vm |
| D2 | While the set is hidden, Cmd-drag the icon to the right of an item. | That app hides. | vm |
| D3 | Show the set. Cmd-drag the icon to the far left. | Every app leaves the hidden set and stays when the set hides again. | vm |
| D4 | Cmd-drag an app's item from right of the icon to left of it. | It hides. | vm |
| D5 | Settings › Hidden: turn the switch off. | The picker is editable. The set is unchanged. | vm |
| F1 | A front app with a wide menu bar (or a notch). "In the menu bar" mode. Show the set. | macOS collapses what does not fit behind `«`. | vm |
| F2 | Same, "In a bar below the menu bar" mode. Click the icon. | A bar under the icon lists the hidden apps. Nothing in the menu bar moves. Icon shows `‹`. | vm |
| F3 | Option-click the icon in bar mode. | The bar adds the always-hidden apps. | vm |
| F4 | Bar mode. Each rehide condition. | The bar closes. A click in the bar does not close it. | vm |
| F5 | Bar mode, no Accessibility. Click an app in the bar. | The app is pinned: its item appears alone in the menu bar, every other app hides at once, and the bar closes. The icon brings the bar back, then hides everything. | Manual; VM grants Accessibility |
| F6 | Bar mode, with Accessibility. Click an app in the bar. | The app is pinned: its item appears in the menu bar, the bar closes, and its menu opens from a click on the item. Picking an item runs it; the set hides from the icon. | vm |
| F6a | Same, with a front app whose menus leave room for one item only. | A second pin that does not fit hides every other app; both pins are drawn. After the set hides, the front app's item returns. | vm |
| F6b | Three pins, with a menu bar item that animates (a timer, a meter). Leave the pointer alone. | The pins stay. No rehide condition and no fit-check escalation takes them away. | Pass |
| F6c | Pin an app that runs from outside `/Applications` (Synology Drive). | The bar marks it and says why. The other items stay: no escalation for an item macOS will not draw. | Pass |
| F7 | On the notch MacBook, first launch. | "Show hidden items" defaults to the bar. Settings › General switches it. | Pass |
| 10 | Release build: `spctl --assess`, `stapler validate`. | Both pass. | Phase 5 |
| 11 | Clean checkout: `swift build`, every script. | No Xcode project needed. | Phase 5 |
