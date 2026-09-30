#!/usr/bin/env bash
# Modified by Chaehyeon Lee (2026): fork identity and bundled licenses.
# Assemble the app bundle from the SwiftPM binary and sign it.
# A debug build is build/BarNookDev.app with the identifier
# kr.co.devch.BarNookDev, so it sits next to the release app in /Applications
# and in the Accessibility list, with its own settings. A release build is
# build/BarNook.app with kr.co.devch.BarNook; sign.sh signs it for release.
# The signature here uses the first Developer ID Application identity in the
# keychain, else the first Apple Development one, else ad hoc. An ad hoc
# signature changes with every build, and macOS ties the Accessibility grant
# to the signature, so an ad hoc debug build loses the permission at every
# rebuild. Any certificate keeps it.
# Usage: scripts/bundle.sh [debug|release]   (default: debug)
# VERSION and BUILD override CFBundleShortVersionString and CFBundleVersion.
# DEVELOPER_ID names the identity.
set -euo pipefail

config="${1:-debug}"
root="$(cd "$(dirname "$0")/.." && pwd)"
bin="$(swift build -c "$config" --package-path "$root" --show-bin-path)/BarNook"

name="BarNook"
[[ "$config" == "release" ]] || name="BarNookDev"
identifier="kr.co.devch.$name"
app="$root/build/$name.app"

swift build -c "$config" --package-path "$root" >&2

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/$name"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
cp "$root/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
cp "$root/LICENSE" "$app/Contents/Resources/LICENSE"
cp "$root/.build/artifacts/sparkle/Sparkle/LICENSE" "$app/Contents/Resources/Sparkle-LICENSE"
mkdir -p "$app/Contents/Frameworks"
ditto "$root/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" \
  "$app/Contents/Frameworks/Sparkle.framework"
echo -n "APPL????" > "$app/Contents/PkgInfo"

plist="$app/Contents/Info.plist"
plutil -replace CFBundleExecutable -string "$name" "$plist"
plutil -replace CFBundleName -string "$name" "$plist"
plutil -replace CFBundleIdentifier -string "$identifier" "$plist"
[[ -z "${VERSION:-}" ]] || plutil -replace CFBundleShortVersionString -string "$VERSION" "$plist"
[[ -z "${BUILD:-}" ]] || plutil -replace CFBundleVersion -string "$BUILD" "$plist"
# A debug build still offers "Check for Updates…" but never checks on its own,
# so it does not ask about automatic checks or replace itself with a release.
[[ "$config" == "release" ]] || plutil -replace SUEnableAutomaticChecks -bool false "$plist"

identity="${DEVELOPER_ID:-}"
for kind in "Developer ID Application" "Apple Development"; do
  [[ -z "$identity" ]] || break
  identity="$(security find-identity -v -p codesigning |
    sed -n "s/.*\"\($kind: [^\"]*\)\".*/\1/p" | head -1)"
done
codesign --force --sign "${identity:--}" --identifier "$identifier" "$app"
echo "$app"
