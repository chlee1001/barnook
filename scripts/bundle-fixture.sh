#!/usr/bin/env bash
# Modified by Chaehyeon Lee (2026): fork fixture identity.
# Bundle the fixture app for the VM tests as build/FixtureN.app with the
# identifier com.chlee1001.BarNookFixture.N. The status item's title is FixtureN.
# With a menu count the app is a regular app with that many menus, so it
# takes most of the menu bar while it is frontmost: the stand-in for a notch.
# Each menu is about 55 points wide on the guest's 1024-point display.
# Usage: scripts/bundle-fixture.sh N [MENUS]   (N is one letter or word, e.g. A)
set -euo pipefail

suffix="${1:?usage: bundle-fixture.sh N [MENUS]}"
root="$(cd "$(dirname "$0")/.." && pwd)"
bin="$(swift build --package-path "$root" --product Fixture --show-bin-path)/Fixture"
name="Fixture$suffix"
identifier="com.chlee1001.BarNookFixture.$suffix"
app="$root/build/$name.app"

swift build --package-path "$root" --product Fixture >&2

rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin" "$app/Contents/MacOS/$name"
cp "$root/Resources/Fixture-Info.plist" "$app/Contents/Info.plist"
echo -n "APPL????" > "$app/Contents/PkgInfo"
plist="$app/Contents/Info.plist"
plutil -replace CFBundleExecutable -string "$name" "$plist"
plutil -replace CFBundleName -string "$name" "$plist"
plutil -replace CFBundleIdentifier -string "$identifier" "$plist"
[[ -z "${2:-}" ]] || { plutil -replace EllipsisFixtureMenuCount -integer "$2" "$plist"; plutil -remove LSUIElement "$plist"; }
codesign --force --sign - --identifier "$identifier" "$app"
echo "$app"
