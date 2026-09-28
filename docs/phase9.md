# Phase 9 record: the clock in bar mode

Status: **D0 failed on the host; stop before R0/S1/S2 under the approved spike gate.** The detector is diagnostic tooling, not a safe product signal. No winning trigger has been established.

## Question

In bar mode, the hidden items must never be drawn in the menu bar, and a click on the clock must open Notification Center (NC).

Two facts constrain the answer:

- NC does not open from a clock click while a restriction is active, and `MenuBarAgent` decides at mouse-down (`docs/spec.md`, "How it hides").
- Lifting the restriction for the clock draws every hidden item, so a lift is not allowed in bar mode.

So NC has to open through something that works while the restriction stays active.

## Setup

- **Host:**
  - The planned main-plus-LG stacked arrangement was not available for this run: `probe screens` reported one 1512×982 display. The running app was `/Applications/BarNook.app`, not a freshly installed `BarNookDev.app`; `hiddenItemsPlacement` was `floatingBar`.
  - The restarted Chostty had Accessibility (`AXIsProcessTrusted=true`, the clock's `AXPress` action was visible) and Screen Recording (`CGPreflightScreenCaptureAccess=true`).
  - For the MenuBarAgent log: `sudo log config --subsystem com.apple.menubar --mode persist:debug` before the run, and `--reset` after it.
- **Guest:** the Tart VM from Phase 7, with the fixtures hidden. `sshd` already holds Accessibility.
- **Probe:** `.build/debug/Probe`, or `probe` in the guest.
  - Points are Accessibility coordinates.
  - Take the clock's point from `probe layout` (the `com.apple.menuextra.clock` item's frame).

## Steps

### D0: the detector

1. Run `probe nc-windows` in each of four states:
   - NC closed.
   - NC open, from a clock click with no restriction.
   - A banner showing: `osascript -e 'display notification "x"'`.
   - Widgets shown on the desktop.
2. Record owner, layer and frame for each state.
3. Match the owner by process bundle identifier rather than the localized window-server owner. Set the layer and geometry to the observed backing window; verify whether the banner creates the same backing window.
4. **Pass:** `probe nc-state` agrees with the screen on 10 of 10 toggles, with no false positive in the banner or widget state.

If the panel cannot be told apart from those confounders, stop.

### R0: the baseline

With the restriction active, and at every grid point below:

- Run `probe click-press X Y --trigger none`.
- In parallel, run `probe watch-hidden <hidden IDs> --for 1500`.

**Expect:** NC stays closed, and `drawn` is empty.

Also record whether a native clock click closes an NC that is already open. That value becomes `nativeClickClosesNCWhenRestricted`.

### Timing grid

| Point | Options |
|---|---|
| 1 | `--at down --delay 0` |
| 2 | `--at down --delay 20` |
| 3 | `--at down --delay 80` |
| 4 | `--at up --delay 0` |
| 5 | `--at up --delay 80` |

Run 10 tries per point, starting once from NC closed and once from NC open.

The grid measures only how `MenuBarAgent` and NC answer at controlled timings. It does not validate the app's own path (global monitor, main-actor hop, AX read, press). VM rows B8/B8x/B8t and host row B8p cover that path.

### S1: AX press on the clock

- Run `probe press-system com.apple.menuextra.clock` ×10 with no click. Record `pressed`.
- Run the grid with `--trigger press`.

### S2: a trigger outside the menu bar

- **S2.1:** `--trigger key:45+fn` (globe+N).
- **S2.3:** `--trigger script`. System Events sends the same key; note any Automation prompt.
- **S2.4:** a documented URL, if one exists.

For each candidate, record the permission it needs: none, Accessibility, or Automation.

### Winner criteria

All five must hold at one grid point:

1. Closed → open on 10 of 10 tries, with exactly one transition each.
2. Open → closed on 10 of 10 tries, with exactly one transition each.
3. `watch-hidden` reports nothing drawn, and the MenuBarAgent log shows no assertion invalidation.
4. The median `ncOpenedAtMs` is at most 400.
5. On the host, both clocks pass.

S3 (release, press, reapply) is never a winner. Sampling cannot prove that the hidden items were never drawn. It may run once as a local diagnostic, never committed, to measure the flash window for the packet below.

## Result

Host D0 run on 2026-09-28, one 1512×982 display. A clock click with no banner toggled the window predicate 10/10 times (closed → open → closed, repeated). The open state exposed a `com.apple.notificationcenterui` window at layer 21 with full-display frame (0,0,1512,982). Desktop widgets from the same process were layer −2147483601 and 180×180. `NotificationCenterPanel` now matches the process bundle ID, layer 21 and a full-display frame instead of the original guessed English owner, popup-menu layer and side-panel frame.

**D0 fails the banner confounder.** With `nc-state` first reporting closed, `osascript -e 'display notification "Detector check" with title "BarNook"'` produced the *same* layer-21 full-display backing window and `nc-state` immediately reported open. The window subsequently disappeared without a clock click. This false positive was reproduced. The current window-list fields (process owner, layer and frame) cannot distinguish that banner state from the panel; the detector is unsafe for a click policy. The eight pure geometry cases pass but do not cover this observed ambiguity. No unobserved distinction is assumed.

Raw `probe nc-windows` JSON from the host (Cocoa coordinates; the probe reports the bundle ID as `owner`, not the localized process name):

| State | `nc-state` | `nc-windows` |
|---|---|---|
| Closed, desktop widgets visible | `{"open":false}` | `[{"frame":[[188,761],[180,180]],"layer":-2147483601,"owner":"com.apple.notificationcenterui"},{"frame":[[8,761],[180,180]],"layer":-2147483601,"owner":"com.apple.notificationcenterui"}]` |
| Clock-open (recorded during initial D0 toggles) | `{"open":true}` | `[{"frame":[[0,0],[1512,982]],"layer":21,"owner":"com.apple.notificationcenterui"},{"frame":[[188,761],[180,180]],"layer":-2147483601,"owner":"com.apple.notificationcenterui"},{"frame":[[8,761],[180,180]],"layer":-2147483601,"owner":"com.apple.notificationcenterui"}]` |
| Banner, after `nc-state` was false | `{"open":true}` (**false positive**) | `[{"frame":[[0,0],[1512,982]],"layer":21,"owner":"com.apple.notificationcenterui"},{"frame":[[188,761],[180,180]],"layer":-2147483601,"owner":"com.apple.notificationcenterui"},{"frame":[[8,761],[180,180]],"layer":-2147483601,"owner":"com.apple.notificationcenterui"}]` |

After the banner cleared, `nc-state` and `nc-windows` again reported the closed row. Subsequent synthetic clock clicks sometimes failed to reopen NC; the successful 10/10 D0 toggle sequence was earlier, before this banner run. This does not change the reproduced false positive. These three fields establish only an indistinguishable **signature**, not that the two states contain the identical window object.

An exploratory AX press away from the clock returned `pressed:false`; ten exploratory Fn+N key events while the pointer was away from the clock left `nc-state` false. These are **not** S1/S2 grid results, and they cannot establish a winner or a comprehensive negative verdict. No MenuBarAgent assertion log, hidden-item watch, two-display run, VM run, or timed grid was performed. The running app's existing clock hover lift also makes a plain native clock click unsuitable as R0 evidence.

| Step | Outcome |
|---|---|
| D0 | **Failed:** banner produces false positive with the same observed window signature. |
| R0 | Not run: D0 gate failed. |
| S1 | Not run: one exploratory AX press returned false. |
| S2.1 | Not run: ten exploratory Fn+N events away from clock did not change `nc-state`. |
| S2.3 | Not run. |
| S2.4 | Not run; no documented trigger established. |

**Winner:** none established; D0 gate failed.  
**Grid point:** none measured.  
**Without Accessibility:** not measured.

## If nothing wins

The work stops after this record. Nothing else lands and no pull request opens. These are the choices for the user:

- **N1:** keep bar mode strict: hidden items never appear, but the clock does not open NC. A BarNook right-click item or shortcut could open NC only if an independently verified trigger works while restricted. No such route has been established; the exploratory synthetic Fn+N negative had no unrestricted control, so it is not a trigger verdict. Otherwise that menu action would have to lift the restriction while NC is open, showing hidden items as a **user-approved exception** to the strict rule. This exception would also need a reliable NC-close signal: today's detector mistakes banners for an open panel and could leave the restriction lifted while a banner is visible.
- **N2:** allow the clock-zone lift in bar mode as before. Hidden items become visible; the user previously rejected this.
- **N3:** use menu-bar placement when the clock must open NC; approve S3 only after reviewing a display-refresh-rate recording and the MenuBarAgent log; or propose a different design, such as investigating richer window fields and testing Fn+N against an unrestricted control. Any NC-state-gated reapplication inherits the banner false positive until the detector is redesigned. N2 and menu-bar placement do not rely on this detector.

There is no verified basis yet to recommend N1's menu item as a strict no-flash route. The user's choice requires a ralplan revision before more implementation.
