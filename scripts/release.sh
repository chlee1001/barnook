#!/usr/bin/env bash
# Modified by Chaehyeon Lee (2026): own signing key, release gate and feed.
# Build, sign, notarize and prepare a release; publishing is separate.
# Usage: scripts/release.sh X.Y.Z
set -euo pipefail

version="${1:?usage: scripts/release.sh X.Y.Z}"
root="$(cd "$(dirname "$0")/.." && pwd)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid version: $version" >&2; exit 2; }

# Per-machine paths and credential names. Never commit this file.
if [[ -f "$root/.release-env" ]]; then
  # shellcheck disable=SC1091
  source "$root/.release-env"
fi
: "${DEVELOPER_ID:?Set DEVELOPER_ID to your Developer ID Application identity}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to your notarytool keychain profile}"
export DEVELOPER_ID NOTARY_PROFILE
key="${BARNOOK_SPARKLE_ED_KEY_FILE:-$HOME/.local/share/barnook/eddsa-private.key}"
[[ -f "$key" ]] || { echo "Missing Sparkle private key: $key" >&2; exit 1; }

# Refuse to sign an app that cannot verify its own updates. Never print the key.
BARNOOK_KEY_FILE="$key" BARNOOK_PLIST="$root/Resources/Info.plist" swift -e '
import CryptoKit
import Foundation
let env = ProcessInfo.processInfo.environment
let encoded = try String(contentsOfFile: env["BARNOOK_KEY_FILE"]!, encoding: .utf8)
    .trimmingCharacters(in: .whitespacesAndNewlines)
guard let data = Data(base64Encoded: encoded) else { fatalError("Invalid Sparkle private key") }
let publicKey = try Curve25519.Signing.PrivateKey(rawRepresentation: data)
    .publicKey.rawRepresentation.base64EncodedString()
let plist = NSDictionary(contentsOfFile: env["BARNOOK_PLIST"]!)!
precondition(plist["SUPublicEDKey"] as? String == publicKey, "Sparkle key does not match SUPublicEDKey")
'

# A release must come from the reviewed tip of main. Check before any signing.
git -C "$root" fetch --quiet origin main --tags
[[ "$(git -C "$root" branch --show-current)" == main &&
   "$(git -C "$root" rev-parse HEAD)" == "$(git -C "$root" rev-parse origin/main)" &&
   -z "$(git -C "$root" status --porcelain)" ]] || {
  echo "Release requires clean, current main." >&2; exit 1;
}
[[ "$(git -C "$root" rev-parse --is-shallow-repository)" == false ]] || {
  echo "Release requires a non-shallow repository." >&2; exit 1;
}
git -C "$root" check-ref-format "refs/tags/v$version"
if git -C "$root" ls-remote --exit-code --tags origin "refs/tags/v$version" >/dev/null; then
  echo "Tag v$version already exists on origin." >&2; exit 1
fi
latest="$(git -C "$root" tag --list 'v[0-9]*' --sort=-version:refname | awk 'NR == 1 { print; exit }')"
if [[ -n "$latest" ]]; then
  [[ "$latest" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Unexpected release tag: $latest" >&2; exit 1; }
  IFS=. read -r major minor patch <<< "$version"
  IFS=. read -r old_major old_minor old_patch <<< "${latest#v}"
  (( 10#$major > 10#$old_major ||
     (10#$major == 10#$old_major && 10#$minor > 10#$old_minor) ||
     (10#$major == 10#$old_major && 10#$minor == 10#$old_minor && 10#$patch > 10#$old_patch) )) || {
    echo "$version must be newer than $latest." >&2; exit 1;
  }
  git -C "$root" merge-base --is-ancestor "$latest" HEAD || {
    echo "Latest release $latest is not an ancestor of main." >&2; exit 1;
  }
fi
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" --output-format json >/dev/null

# Use Git's monotonically increasing commit count as CFBundleVersion.
build="$(git -C "$root" rev-list --count HEAD)"
app="$(VERSION="$version" BUILD="$build" "$root/scripts/bundle.sh" release)"
"$root/scripts/sign.sh" "$app"
"$root/scripts/notarize.sh" "$app"

zip="$root/build/BarNook-$version.zip"
ditto -c -k --keepParent "$app" "$zip"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp "$zip" "$work/"
# generate_appcast merges an existing output feed; each release publishes only its new archive.
"$root/.build/artifacts/sparkle/Sparkle/bin/generate_appcast" \
  --ed-key-file "$key" \
  --download-url-prefix "https://github.com/chlee1001/barnook/releases/download/v$version/" \
  --link "https://github.com/chlee1001/barnook/releases" \
  -o "$work/appcast.xml" "$work"
[[ -s "$work/appcast.xml" ]] || { echo "Missing signed appcast" >&2; exit 1; }
swift "$root/scripts/verify-appcast.swift" "$work/appcast.xml" "$zip" "$app/Contents/Info.plist" "$version"
mv "$work/appcast.xml" "$root/build/appcast.xml"
git -C "$root" rev-parse HEAD > "$root/build/BarNook-$version.commit"
echo "$zip"
echo "$root/build/appcast.xml"
