# Repository Guidelines

## Project Overview

BarNook is a macOS 27 menu-bar item manager and an independent Apache 2.0 derivative of ronny/ellipsis. It hides and reveals menu-bar app groups, with a floating app-icon bar for notched displays. Accessibility improves item detection and interaction but is optional; macOS/private MenuBarClientCore behavior limits per-item control. Preserve the original license, copyright, attribution, and bundled Sparkle licenses; mark modifications to inherited files.

## Architecture & Data Flow

- `Sources/Ellipsis/EllipsisApp.swift` starts the AppKit application. `AppDelegate.swift` registers defaults, wires `AppState`, hidden sets, menu-bar restriction, divider, clock zone, and `MenuBarManager`, and opens settings lazily.
- `AppState.swift` is `@MainActor @Observable`: properties mirror `UserDefaults`; hidden-set state is separate. The manager coordinates status items, reveal/rehide, pinning, and `FloatingBar`. Settings UI lives under `Sources/Ellipsis/Settings/`.
- `Sources/EllipsisCore/MenuBarLayout.swift` reads Accessibility menu-bar windows into item/display snapshots and settles asynchronous samples. `MenuBarGeometry.swift` computes screen/menu bounds. Layout frames use AX top-left coordinates; geometry uses Cocoa coordinates—convert deliberately at the boundary.
- `Sources/Probe/` and `Sources/Fixture/` provide guest-test instrumentation and menu-bar fixtures, not app UI.

## Key Directories

- `Sources/Ellipsis/MenuBar/`: status-item control, hidden sets, rehide, floating bar, placement and policies.
- `Sources/Ellipsis/Accessibility/`: Accessibility permission handling; `Sources/Ellipsis/Settings/`: persisted settings and UI.
- `Sources/EllipsisCore/`: reusable layout/geometry logic; `Tests/EllipsisTests/`: in-process tests; `Tests/EllipsisVMTests/`: Tart guest tests.
- `Resources/`: app metadata, icon, entitlements; `scripts/`: bundling, development installation, VM, signing and release; `docs/`: specification, development and QA checklists.

## Development Commands

- `swift build` or `mise run build`; `swift test` or `mise run test`; `swift build --build-tests` checks test compilation.
- `mise run run` installs/launches a separate debug `BarNookDev.app` in `/Applications`; `scripts/run.sh [debug|release]` replaces the corresponding installed app and launches it. These are mutating commands, not read-only runs.
- `shellcheck scripts/*.sh` checks shell scripts. See `mise.toml` and `docs/development.md` for bundling, installation and VM setup.

## Code Conventions & Common Patterns

- Swift 6 language mode; follow existing type/file names and Swift Testing conventions. Keep pure layout/policy decisions in `EllipsisCore` or small menu-bar policy types rather than embedding them in AppKit event handlers.
- UI and observable settings are main-actor isolated; AX reads use bounded IPC and settled async sampling. Handle unavailable AX data and permission denial explicitly. For settings imports, validate all known values before changing `UserDefaults`; unknown keys are ignored.
- Wire shared state explicitly at launch rather than creating independent settings stores. Respect AX-versus-Cocoa coordinate systems and the distinction between a whole-app hidden set and an individual status item.

## Important Files

`Package.swift` defines targets and Sparkle dependency; `Resources/Info.plist` sets the agent app identity, minimum OS, update feed and Sparkle public key. `Sources/Ellipsis/AppDelegate.swift`, `AppState.swift`, `MenuBar/MenuBarManager.swift`, and `EllipsisCore/MenuBarLayout.swift` are primary entry points for behavioral changes. Consult `docs/spec.md`, `docs/development.md`, and `docs/testing.md` for product limits and procedures.

## Runtime/Tooling Preferences

Use macOS 27, Xcode Command Line Tools with Swift 6.4, SwiftPM, and optional mise task aliases (`mise.toml` does not pin a toolchain). There is no Xcode project. `scripts/bundle.sh` assembles the app and embeds `Sparkle.framework`; normal `swift build` is not an installed app. Do not commit credentials, `.release-env`, or Sparkle private keys.

## Testing & QA

- Unit tests use Swift Testing (`@Test`, `#expect`) and isolated fixtures/UserDefaults suites. Run `swift test` and `swift build --build-tests`; hosted CI runs both on `xcode-27` and ShellCheck on Ubuntu.
- VM tests require Tart, a prepared macOS guest, installed fixture/probe and `ELLIPSIS_VM`; run `mise run vm-test` (focused example: `mise run vm-test -- --filter RehideTests`). Bare `swift test` skips VM behavior. Report VM and manual permission/UI/release checks separately; use `docs/testing.md` for the checklist. No blanket coverage percentage is defined.
- For release-script changes, perform a dry preflight, shell syntax checks and artifact inspection before publishing. Never claim unrun checks.

## Changes, Reviews & Releases

Branch from `main`; make one logical change per commit with a conventional-commit subject, short why-focused body, and only applicable lore trailers (`Lore-id`, `Constraint`, `Rejected`, `Confidence`, `Scope-risk`, `Reversibility`, `Tested`, `Not-tested`). This is a solo-maintained repository: accept only maintainer-authored PRs against `main`, describing changes, rationale, actual verification, limitations and honest risk; do not require external reviewers. For high-risk feature, signing, updater and release changes, record a maintainer self-review of the exact head commit, findings or remaining risks, focused checks and release impact before merging. AI feedback is advisory, not independent approval; never imply an external review happened.

Publish only from clean `main` at `origin/main` after merge, CI checks and the recorded maintainer review. `scripts/release.sh X.Y.Z` prepares a signed/notarized ZIP and signed Sparkle appcast for inspection; `scripts/publish.sh X.Y.Z` tags and uploads after verifying artifacts. `mise run release X.Y.Z` combines them. Never tag or publish before signing/build checks succeed. Keep Developer ID, notarytool and EdDSA secrets outside Git; `SUPublicEDKey` must match the appcast signing key.
