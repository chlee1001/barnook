# Development

Modified by Chaehyeon Lee (2026): BarNook signing, branding and release instructions.

## Build from source

You need Xcode Command Line Tools with Swift 6.4. No Xcode project is necessary.

```sh
mise run build
mise run test
mise run run
```

`mise run run` bundles a debug build as `BarNookDev.app` with the identifier `kr.co.devch.BarNookDev`, signs it with a local certificate (ad hoc without one), copies it to `/Applications` and opens it. A stable certificate keeps its Accessibility grant across rebuilds. The debug build has its own settings and its own row in the Accessibility list, so it runs next to a release `BarNook.app`. `mise run install` does the same with a release build as `BarNook.app`, signed but not notarized. Without mise, use `swift build`, `swift test`, `scripts/run.sh` and `scripts/run.sh release`.

## VM tests

`Tests/BarNookVMTests` drives the app in a macOS guest, so a test run never touches your own menu bar or pointer. The guest is a [Tart](https://tart.run) VM cloned from `ghcr.io/cirruslabs/macos-golden-gate-base`, on which the image already grants Accessibility to `sshd`. The tests run on the host and reach the guest over `ssh`, through `scripts/vm.sh`. Every step is in `docs/plan.md`, Phase 7, and the spike in `docs/phase7.md`.

Once:

```sh
curl -sSL https://github.com/cirruslabs/tart/releases/latest/download/tart.tar.gz | tar xz -C ~/.local/opt
ln -s ~/.local/opt/tart.app/Contents/MacOS/tart ~/.local/bin/tart
tart pull ghcr.io/cirruslabs/macos-golden-gate-base:latest   # about 40 GB
scripts/vm.sh prepare                                          # barnook-golden, 20 seconds
```

Older `ellipsis-golden` guests authorize a different SSH key and are not reused by the new defaults. `prepare` creates `barnook-golden` with `~/.tart/barnook_ed25519`; it deletes the VM named by `BARNOOK_VM_GOLDEN` before cloning, so never point it at an existing guest you need to keep. Leave the old guest intact until the new one is verified.

The Homebrew formula for `tart` does not install on current Homebrew, hence the tarball.

To free the 40 GB the pulled image takes on the local disk, move `~/.tart/cache` to a NAS after `prepare`:

```sh
rsync -a ~/.tart/cache/ /path/on/nas/tart/cache/
rsync -a --checksum --itemize-changes ~/.tart/cache/ /path/on/nas/tart/cache/   # prints nothing when the copy is good
rm -r ~/.tart/cache
ln -s /path/on/nas/tart/cache ~/.tart/cache
```

Not `mv` or `cp`: `copyfile` spins on `lseek` for ever when it copies the sparse disk image to NFS.

Do this after `prepare`, not before: `tart pull` downloads into `~/.tart/tmp` and renames into `cache`, which fails across file systems. Keep `~/.tart/vms` local. `tart clone` is an APFS clone there, so a test run costs no space and no time; on NFS it would copy the whole image.

Then:

```sh
mise run vm-test                                # clone, install, test, delete: about two minutes
mise run vm-test -- --filter RehideTests        # one suite
```

`scripts/vm-test.sh` clones `BARNOOK_VM_GOLDEN` (default `barnook-golden`) as `BARNOOK_VM` (default `barnook-test`), copies `BarNookDev.app`, five fixture apps and the probe into it, grants the app Accessibility and Screen Recording in the guest's TCC database, runs `swift test --filter BarNookVMTests` (or the requested VM suite), copies `~/screenshots` from the guest to `build/vm-screenshots`, and deletes the VM. `BARNOOK_VM_KEEP=1` leaves the VM running after the run. `BARNOOK_VM_REUSE=1` runs against a VM that is already up, which is the loop while writing a test: `scripts/vm.sh clone` once, then `BARNOOK_VM_REUSE=1 scripts/vm-test.sh` as often as needed, then `scripts/vm.sh delete`. `scripts/vm.sh ssh` opens a shell in the guest, and `tart run barnook-test --vnc` after `scripts/vm.sh stop` shows its screen. `scripts/vm.sh` uses `~/.tart/barnook_ed25519` as its SSH key.

Without `BARNOOK_VM` the suites skip, so `mise run test` and CI stay unit tests. The rows of `docs/testing.md` marked `vm` have a test. The guest grants Accessibility and Screen Recording; the no-Accessibility case F5 remains manual. The guest has no notch.

## Make a release

1. Install your "Developer ID Application" identity in the login keychain. Do not use the original author's signing identity.
2. Create a notarytool profile for your Apple Developer team once, or reuse an existing profile for the same team:
   ```sh
   xcrun notarytool store-credentials barnook-chlee1001 \
     --apple-id you@example.com --team-id TEAMID --password app-specific-password
   ```
3. Keep BarNook's EdDSA private key at `~/.local/share/barnook/eddsa-private.key` (mode 600). Its public half is `SUPublicEDKey` in `Resources/Info.plist`; the release script verifies they match. Do not regenerate the key after shipping updates. Never commit or share the private key.
4. Put machine-local settings in the gitignored `.release-env` (or export them in the shell):
   ```sh
   DEVELOPER_ID='Developer ID Application: YOUR NAME (YOUR TEAM ID)'
   NOTARY_PROFILE=barnook-chlee1001  # or an existing profile for the same team
   # BARNOOK_SPARKLE_ED_KEY_FILE=/absolute/path/to/eddsa-private.key  # optional
   ```
5. Run `bash Tests/ReleaseGateTests.sh`, `shellcheck scripts/*.sh Tests/ReleaseGateTests.sh`, `swift build --build-tests`, and `swift test`. Make sure `gh auth status` shows your account. Merge reviewed changes into `main`, then run `mise run archive X.Y.Z` to prepare and inspect the signed ZIP and appcast. Run `mise run publish X.Y.Z` to tag and upload, or `mise run release X.Y.Z` for both. Release preparation requires a clean, non-shallow, current `main`. No tag is pushed until signed artifacts pass verification.

`scripts/release.sh X.Y.Z` does the build, sign, notarize, zip and appcast steps without the tag. `scripts/publish.sh X.Y.Z` (or `mise run publish X.Y.Z`) creates the GitHub release from the two files.

GitHub authorization checks before tagging are best-effort; network or upload failures can still leave a tag without a release. If the tag points to the same commit and no release exists, repair the credentials/network and retry `mise run publish X.Y.Z` with the same inspected artifacts. If a partial release exists, inspect and repair it manually rather than overwriting assets. Do not rerun `archive` for a tagged version.

`DEVELOPER_ID` and `NOTARY_PROFILE` are required for a release. The archive includes the original Apache 2.0 license and Sparkle's license. `build/BarNook-X.Y.Z.commit` binds the prepared artifacts to the reviewed commit; publication refuses a different head. The scripts are `bundle.sh`, `sign.sh`, `sign-sparkle.sh`, `notarize.sh`, `release.sh`, `publish.sh` and `make-icon.sh`.

## A second machine

Signing and notary credentials live in the keychain; the Sparkle private key lives in a local file. Move these securely to a second machine. `gh auth login` is separate.

On the release machine:

1. Certificates with their private keys: Xcode › Settings › Accounts › your Apple ID › ⚙ › "Export Apple ID and Code Signing Assets…" writes a `.developerprofile` with every certificate and key, the Developer ID Application identity among them. Keychain Access › My Certificates › right-click the identity › Export writes a `.p12` with only that one.
2. The file `~/.local/share/barnook/eddsa-private.key`; transfer it securely and set its permissions to 600.
3. The app-specific password for notarytool cannot be exported. Use the one you have, or make a new one at appleid.apple.com.

On the new machine:

1. Open the `.developerprofile` (Xcode imports it) or the `.p12`. `security find-identity -v -p codesigning` then lists "Developer ID Application".
2. Install the Sparkle key file at `~/.local/share/barnook/eddsa-private.key` with mode 600. The release script checks it against `SUPublicEDKey`; a different key strands installed copies (see "The update key").
3. `xcrun notarytool store-credentials barnook-chlee1001 --apple-id you@example.com --team-id TEAMID --password <app-specific-password>`.

Without the Developer ID identity, `scripts/bundle.sh` signs a debug build with an Apple Development identity if there is one, else ad hoc. Only a certificate keeps the Accessibility grant across rebuilds. A new Developer ID Application certificate can be made in Xcode › Settings › Accounts › Manage Certificates (account holder only, five per team) and signs future releases as well as the old one; only the Sparkle key has to be the original.

## Updates

BarNook uses [Sparkle 2](https://sparkle-project.org) from SwiftPM. `SUFeedURL` in `Resources/Info.plist` is `https://github.com/chlee1001/barnook/releases/latest/download/appcast.xml`. GitHub serves the `appcast.xml` asset of the newest release that is not a draft or a pre-release. Each release has an appcast with one item, itself, so the newest release is the only update that Sparkle sees.

`generate_appcast` signs the zip with BarNook's EdDSA private key file. `SUPublicEDKey` in `Resources/Info.plist` is the public half. An app can only install an update that this key signed.

### The update key

The fork uses its own Ed25519 private key file, not the original author's key or Sparkle's default keychain account. `generate_appcast --ed-key-file` signs each update. Back up the file securely; neither the private key nor `.release-env` belongs in Git.

If the key is lost, create a new Ed25519 key and put its public half in `Resources/Info.plist`. Apps with the old key cannot install the next release. Users must download it by hand.

## Website

The landing page lives in `site/` and is published to <https://devch.co.kr/barnook/>. It is static HTML with no build step: `site/index.html` (English) and `site/ko/index.html` (Korean) share `site/assets/site.css` and `site/assets/site.js`. The two pages are edited by hand and keep the same structure; the demo's strings for both languages are in the `STRINGS` table in `site.js`. The idle demo is pre-rendered in the HTML, so the page reads correctly without JavaScript.

Preview it under the same `/barnook/` path that Pages uses:

```
mkdir -p build/site-preview && ln -sfn ../../site build/site-preview/barnook
python3 -m http.server 8765 --bind 127.0.0.1 --directory build/site-preview
```

Then open <http://127.0.0.1:8765/barnook/> and <http://127.0.0.1:8765/barnook/ko/>.

- `scripts/make-site-assets.sh icons` rebuilds the site icons from `Resources/AppIcon.png`. Rerun it after `scripts/make-icon.sh`.
- `scripts/make-site-assets.sh og` renders `scripts/og-card.html` to `site/assets/og/og-{en,ko}.png` (1200×630) in headless Chrome. Set `CHROME` if Chrome is not in `/Applications`.
- `scripts/check-site.sh` checks en/ko parity, local links, third-party loads, page metadata, mockup leftovers, the font pins, and that both pages carry the demo elements `site.js` drives. `Tests/SiteCheckTests.sh` proves each check fails on a broken copy. CI runs both in the `site` job.
- `.github/workflows/pages.yml` deploys `site/` when a push to `main` touches it. GitHub Pages must be set once to Settings › Pages › Source: GitHub Actions; until then the deploy job fails.

The font is Pretendard Variable 1.3.9, shipped unmodified as `site/assets/fonts/PretendardVariable.woff2` with its OFL license in `site/assets/fonts/LICENSE.txt`. `check-site.sh` pins the size and sha256 of both. To upgrade, replace both files from the same upstream release, check them against the release archive, and update the four pins together. A subset or otherwise modified font must not keep the reserved name "Pretendard".

## Documentation

- `docs/spec.md`: what BarNook does.
- `docs/plan.md`: how it is built, phase by phase.
- `docs/phase0.md`: what was tried against `MenuBarAgent`, and what worked.
- `docs/phase7.md`: what was tried in a Tart guest, and what worked.
- `docs/notification-center-clock.md`: the clock in bar mode: the Notification Center detector, the trigger research, the cover-lift spike and the decision.
- `docs/testing.md`: the test checklist, VM and manual.

