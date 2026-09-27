#!/usr/bin/env bash
# Modified by Chaehyeon Lee (2026): verify artifacts before tagging and publishing.
# Publish locally prepared, notarized artifacts from current main.
# Usage: scripts/publish.sh X.Y.Z
set -euo pipefail

version="${1:?usage: scripts/publish.sh X.Y.Z}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid version: $version" >&2; exit 2; }
root="$(cd "$(dirname "$0")/.." && pwd)"
tag="v$version"
app="$root/build/BarNook.app"
zip="$root/build/BarNook-$version.zip"
appcast="$root/build/appcast.xml"
commit_file="$root/build/BarNook-$version.commit"

for file in "$zip" "$appcast" "$commit_file" "$app/Contents/Resources/LICENSE" "$app/Contents/Resources/Sparkle-LICENSE"; do
  [[ -s "$file" ]] || { echo "Missing release artifact: $file" >&2; exit 1; }
done
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" == "$version" &&
   "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == com.chlee1001.BarNook &&
   "$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$app/Contents/Info.plist")" == https://github.com/chlee1001/barnook/releases/latest/download/appcast.xml ]] || {
  echo "Bundle version, identifier or feed does not match this release." >&2; exit 1;
}
swift "$root/scripts/verify-appcast.swift" "$appcast" "$zip" "$app/Contents/Info.plist" "$version"
codesign --verify --deep --strict "$app"
xcrun stapler validate "$app"
spctl --assess --type exec "$app"
# The archive must contain the app just inspected, not an older build.
extracted="$(mktemp -d)"
trap 'rm -rf "$extracted"' EXIT
ditto -x -k "$zip" "$extracted"
diff -qr "$app" "$extracted/BarNook.app" || {
  echo "The zip does not match the notarized app." >&2; exit 1;
}

git -C "$root" fetch --quiet origin main --tags
[[ "$(git -C "$root" branch --show-current)" == main &&
   "$(git -C "$root" rev-parse HEAD)" == "$(git -C "$root" rev-parse origin/main)" &&
   "$(<"$commit_file")" == "$(git -C "$root" rev-parse HEAD)" &&
   -z "$(git -C "$root" status --porcelain --untracked-files=all)" ]] || {
  echo "Publish requires clean, current main and artifacts built from that commit." >&2; exit 1;
}
gh auth status --hostname github.com || {
  echo "GitHub CLI authentication is required to publish a release." >&2; exit 1;
}
[[ "$(gh api repos/chlee1001/barnook --jq '.permissions.push')" == true ]] || {
  echo "GitHub CLI account lacks repository push permission." >&2; exit 1;
}
if git -C "$root" rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  [[ "$(git -C "$root" rev-parse "$tag^{commit}")" == "$(git -C "$root" rev-parse HEAD)" ]] || {
    echo "Tag $tag points to a different commit." >&2; exit 1;
  }
else
  git -C "$root" tag -a "$tag" -m "BarNook $version"
fi
if git -C "$root" ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null; then
  remote_commit="$(git -C "$root" ls-remote --tags origin "refs/tags/$tag^{}")"
  [[ -n "$remote_commit" ]] || remote_commit="$(git -C "$root" ls-remote --tags origin "refs/tags/$tag")"
  [[ "${remote_commit%%[[:space:]]*}" == "$(git -C "$root" rev-parse HEAD)" ]] || {
    echo "Remote tag $tag does not point to this release commit." >&2; exit 1;
  }
else
  git -C "$root" push origin "refs/tags/$tag"
fi
# --verify-tag refuses a release if the tag did not reach origin.
gh release create "$tag" --repo chlee1001/barnook --verify-tag \
  --title "BarNook $version" --generate-notes "$zip" "$appcast"
