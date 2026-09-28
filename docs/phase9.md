# Phase 9 record: the clock in bar mode

Status: **decided and shipped (2026-09-28).** The maintainer chose A1: in bar mode, a clock click always uses the cover-lift. Accessibility and Screen Recording are required, and a first-launch onboarding window keeps Settings closed until both are granted.

What shipped:

- `901704f` the covered lift;
- `40da177` covering every menu bar;
- `5f42bef` the onboarding.

The D0, R0, S1 and S2 sections below are the historical spike record.

- **Detector.** `901704f` replaced the window-list Notification Center detector with the Accessibility one described under "N3(c) follow-up". It removed `probe nc-windows` and made `probe nc-state` read Accessibility. Where this record mentions `nc-windows`, or `nc-state` reporting a banner as open, it describes the old detector.
- **Not measured.** The revised latency gate (median ≤ 600 ms, p90 ≤ 1 s on the product path) and a recording at the display's refresh rate have not been run. Both remain Not-tested.

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


## N3(c) follow-up (2026-09-28)

### No trigger works under an assertion

A `/tmp` harness held its own assertion with the pointer away from the clock. Under it, none of these opened NC in any try:

- Fn+N, as a flag and as a real fn key-down;
- AXPress and AXShowMenu on the clock;
- a synthetic clock click;
- System Events Fn+N;
- distributed notifications.

In the repeated runs (Fn+N and AXPress, 5 each, with the hidden set and with a restriction that hides nothing) NC opened 0 of 20 times. The block comes from the assertion itself, not from the allow-list.

With no assertion, Fn+N opened NC in 135–183 ms, AXPress in about 500 ms and a click in 177 ms. In the log, MenuBarAgent forwards the click to ControlCenter, but under an assertion ControlCenter never logs `Sending mouse down event to Notification Center`.

The same limit is reported for Hidden Bar (#437), Ice (PR #995) and Barline (PR #46).

### An accessibility detector tells a banner from the panel

With a banner only, the NC window's AX tree holds only `AXGroup` subrole `AXNotificationCenterBanner`. When the panel is open, it also holds `AXGroup` id `AXNotificationListItems`. On the host:

- 10/10 clock toggles were classified correctly;
- 3/3 banners were classified as a banner, while `nc-state` reported open;
- the panel with a banner over it was classified as the panel.

This needs Accessibility.

### A stale assertion

At 11:09:38, two overlapping activations left one assertion behind. From then on, hover lifts showed nothing and the clock stayed inert until BarNook relaunched. The MenuBarAgent activate/invalidate balance shows it. Commit `616addb` fixes this (the plan's commits 1 and 1b).

### Cover-lift spike

The harness is `/tmp/ncx/cover.swift` and is not committed. BarNook was not running.

For each try, the harness:

1. captures the status-item strip left of the clock with ScreenCaptureKit;
2. shows that image in a borderless window at level `mainMenu + 2` that ignores the mouse;
3. lifts the assertion and, 80 ms later, posts a click on the clock (or AXPresses it);
4. waits 150 ms and reapplies;
5. waits until no hidden app owns a slot in the AX layout, then removes the cover 150 ms later.

Menu-bar frames were sampled throughout. The flash metric counts changed columns left of the baseline's leftmost icon, where hidden items appear.

| Run | Tries | Frames with hidden items | NC opened |
|---|---|---|---|
| No cover, click (control) | 3 | 12 of 12 sampled frames per try | 3/3 |
| No cover, AXPress (control) | 5 | 5–7 per try | 5/5 |
| Cover, fixed 150 ms hold after reapply | 5 | 1 try with a fading ghost | 5/5 |
| Cover, click, fixed 400 ms hold (display 0) | 5 | 3 tries with the MenuBarAgent crossfade | 5/5 |
| **Cover, click, wait for layout + 150 ms, 3 displays** | **30** | **0** | **30/30** |
| Cover, AXPress, 3 displays, fixed 400 ms hold | 15 | 2 tries with 1 frame | 14/15 |

For the final row:

- NC appeared a median 461 ms after the lift, 90th percentile 825 ms, maximum 1097 ms.
- The cover stays up a median 1343 ms, maximum 1581 ms. Uncovering must wait for the layout, not a timer: MenuBarAgent redraws and crossfades for 640–920 ms after the assertion reports active.
- NC stayed open after the reapply.
- Escape closed it with no lift.

The displays were the built-in 1512×982 and two externals, 1920×1200 and 2560×1440.

### Limits

- **Frame sampling.** Sampling runs at about 20 frames per second, not at the display's refresh rate. A single-frame flash between samples cannot be excluded. The final row shows no hidden item in any sample.
- **What the cover hides.** Under the cover, the real bar still draws the hidden items; only the screen shows the old image. Anything that changes the strip during those 1.3 s is frozen too: an icon's own update, or the clock's highlight left of the cover.
- **Permissions.** The cover needs Screen Recording for the capture, and BarNook does not ask for it today. Posting the click needs Accessibility.
- **Hover.** The bar-mode hover lift is still in the product. The spike ran with BarNook quit, so it says nothing about the product path.
- **Not measured.** A real mouse click, a banner arriving during the cover, and fullscreen spaces.


## Proposed revision after the spike (approved as A1 with required permissions; B(a)/(b) replaced by the onboarding)

The approved plan has two rules for bar mode: the restriction is never lifted on a hover or click, and the hidden items are never drawn. The cover-lift breaks both on purpose. The restriction is lifted for about 0.4–0.9 s, and MenuBarAgent draws the hidden items under the cover. The spike shows only that no hidden item appeared in the frames it sampled, about 20 per second. The user asked for items to be "never shown, even briefly". The cover meets that only on screen, as far as sampling can tell, and only when BarNook has Screen Recording.

### What to approve

**A. The contract for bar mode.**

1. **Cover-lift (recommended).** A click on the clock opens NC. No hidden item is visible on screen, within the sampling limit above. What is gained and what it costs:
   - NC appears about 0.46 s after the click, median; the native click takes about 0.18 s. This is above the plan's 400 ms gate, so the gate becomes "median ≤ 600 ms and p90 ≤ 1 s, measured on the product path."
   - The status strip is frozen for about 1.3 s after the click.
   - Two permissions are needed: Screen Recording (new) and Accessibility.
2. **Strict.** In bar mode the clock does nothing. The Settings footer points to the trackpad edge swipe and to menu-bar placement.
3. **Cover-lift, then strict.** Use the cover-lift when both permissions are granted, and strict otherwise.

**B. Screen Recording.** Pick one:

- (a) Ask for it the first time the clock is clicked in bar mode, with a one-line reason.
- (b) Put it behind a Settings toggle, "Clock opens Notification Center (needs Screen Recording)", which is off by default.

Recommended: (b), since it is the only new permission and turning it on is the user's choice.

### Revised commits

- **Commits 1 and 1b.** Landed as `616addb`.
- **Commit 2** (monotonic allow-list). Unchanged and still gated by its four conditions. On this host the running-app churn comes from background agents, such as `AXVisualSupportAgent` flapping. So commit 2 is the likely fix for the repeated reassertions, if the gate holds.
- **Commit 3** (menu-bar-mode hover hold and watch). Unchanged. It does not depend on the cover.
- **Commit 4, rewritten** as `fix(floating-bar): open Notification Center from the clock behind a cover`:
  - Remove the bar-mode hover lift, as before.
  - A global `leftMouseDown` monitor, filtered to the clock (`clockZone` plus the AX clock frame), starts one `ClockCover` action at a time, with a 300 ms debounce. The action:
    1. captures the status strip with ScreenCaptureKit;
    2. shows a `mainMenu + 2` window that ignores the mouse;
    3. calls `restriction.release()`;
    4. waits 80 ms and replays the click at the clock;
    5. waits 150 ms and calls `applyCurrentState()`;
    6. waits for a layout with no hidden owner, capped at 3 s, then 150 ms;
    7. removes the cover.
  - A click that lands while NC is already open is not intercepted. Escape and the dismissing click close NC with no lift. The AX detector reports NC's state: it looks for `AXNotificationListItems`, not the window list.
  - Pure policy in `ClockCoverPolicy`: the timings, when to intercept, and debounce. The whole commit touches only `MenuBarManager`, a new `ClockCover` class and Settings.
- **Commit 5** (rehide waits while the pointer is on the bar; `IconClickPolicy`). Unchanged.
- **Commit 6** (reopen the bar at relaunch). Unchanged.

### Verification of the revised commit 4

- Unit tests for `ClockCoverPolicy`.
- Host rows. Run each on the 1512, 1920 and 2560 displays, 10 times each, with the product installed:
  - a real mouse click opens NC;
  - 0 frames in which a hidden item is visible, using the sampled metric from the spike;
  - a banner arriving under the cover;
  - a fullscreen space;
  - NC's latency against the new gate.
- A 120 Hz screen recording of at least 3 clicks, reviewed frame by frame.
- VM rows B8 and B8c, adapted, if Tart is available.
- In the VM, Screen Recording has to be granted to BarNookDev.

This packet goes into a new ralplan run for consensus review. The current run has used all 5 of its iterations.


### Product path on the host (BarNookDev, commits `901704f` and `40da177`)

- **Setup.** Both permissions were granted and bar mode was on, with the user's 14 hidden apps. A separate process sampled the status strip of every menu bar, about 13 frames per second per display. It counted icon edges that were not there at rest, within 700 points left of the resting items.
- **Control.** In menu-bar mode, a hover lift over the clock drew hidden items in 13–15 of 33 frames on each display.
- **Covered lift, 9 clicks spread over the 1512, 1920 and 2560 displays.** On the two externals, no frame out of 533 showed a new icon. On the built-in display the metric counted the front app's menus and RunCat's running animation. The frames were stacked and checked by eye: the status strip stays at its resting items (a second run of 5 clicks with Finder in front showed the same).
- **Notification Center.** It opened 8/9 in the three-display run and 5/5 in the Finder run. It closed every time.
- **The one open that failed.** A click came about 1.5 s after the previous lift and was ignored. The layout was probably still settling.
- **The first fix.** The first product build skipped displays whose menu bar hides itself: `visibleFrame` reports no menu bar there. `40da177` takes the strips from the Accessibility layout instead.
- **Not tested.** Real mouse clicks, fullscreen spaces, a banner during the cover, and a screen recording at display refresh rate.


### The twitch and the slowness (2026-09-28, maintainer report)

- **Twitch.** The maintainer's screen recording showed the status icons jumping about 15 points left and sliding back. `screencapture -v` recordings traced it to the cover windows' default window animation: the windows zoomed in from a smaller frame and faded out while shrinking, so the picture itself scaled. The recordings are variable-frame-rate. They were requested at 120 fps, but reached an average of about 28–43 fps. A 10 ms window-list watcher confirmed the cover frames scaling. `56cb91e` makes the covers appear and go at once. Recordings on all three displays then showed no icon shift. The `56cb91e` commit message calls these "120 Hz recordings"; that overstates the achieved rate. A refresh-rate recording has not been run.
- **Missed opens.** The same traces showed MenuBarAgent handling the replayed click up to 450 ms late. A reapply before then swallowed it, most often after an Escape close, where 1 of 9 opened. The reapply now waits for the panel, capped at 900 ms, and 8 of 8 opened.
- **Slowness.** Click to panel took 577–620 ms, against about 170 ms natively. Most of it was MenuBarAgent laying out the lift before handling the replay.
  - `d34e088` captures and reads in parallel, keeps the display list, and replays 10 ms after the lift. That brought click to panel to 409–500 ms.
  - It also covers and lifts once the pointer has rested 60 ms on the clock, and the maintainer reported it smoother. The gain depends on how busy MenuBarAgent still is with the lift, and the host measurements vary. After a rest of about 1 s, mouse-down to panel ranged from 22 to about 400 ms. After a 300 ms rest or none, it was about 330–500 ms. MenuBarAgent's own click log leaves out its input queue, so figures measured from it (27–36 ms at 95b2433) are lower. The cause of the spread is not established.
- **Closing.** A clock click that closes the panel closes it natively. Replaying that click, or reading the panel after it, reopened the panel, so BarNook now remembers that a lift opened it and never lifts for, or replays, a click while the panel is believed open.
- **Trade-off.** While the pointer rests on the clock, every menu bar left of the clock is a still picture.
- **Not tested.**
  - A Notification Center panel opened outside BarNook (Fn+N, the trackpad edge swipe). BarNook's belief that the panel is open covers only panels a lift opened, and the Accessibility read is best effort for the rest.
  - Real mouse clicks.
  - Fullscreen spaces.
  - A banner during the cover.
  - VM runs: Tart is not installed.


### Commit-message corrections (2026-09-28)

Two commit messages on `fix/menu-bar-stability` are left as they are and corrected here. The branch history is not rewritten: the review snapshots are pinned to these commits.

- **`56cb91e`.** The message says "120 Hz recordings". The recordings were `screencapture -v` captures, variable-frame-rate with an average of about 28–43 fps. They were not refresh-rate recordings. See "The twitch and the slowness" above.
- **`e4b4172`.** The message has no `Not-tested:` line. It documents `23c83f0`, whose message lists what was not tested: the hide timing after the pointer leaves, and VM rows F2a, F2b and F4a.

Before a pull request, these two messages can be amended instead, if the maintainer asks.
