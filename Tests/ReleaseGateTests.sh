#!/usr/bin/env bash
# Exercise the release preflight without using real signing keys or publishing.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/repo/scripts" "$work/repo/Resources" "$work/bin"
cp "$root/scripts/release.sh" "$work/repo/scripts/release.sh"
cp "$root/Resources/Info.plist" "$work/repo/Resources/Info.plist"
printf 'build/\n.release-env\n' > "$work/repo/.gitignore"
: > "$work/key"

printf '#!/bin/sh\nexit 0\n' > "$work/bin/swift"
printf '#!/bin/sh\necho REACHED_NOTARY_PREFLIGHT >&2\nexit 73\n' > "$work/bin/xcrun"
chmod +x "$work/bin/swift" "$work/bin/xcrun"

git init --bare -q "$work/remote.git"
git -C "$work/repo" init -b main -q
git -C "$work/repo" remote add origin "$work/remote.git"
git -C "$work/repo" add .
git -C "$work/repo" -c user.name=Test -c user.email=test@example.com commit -qm 'test fixture'
git -C "$work/repo" push -q -u origin main

run_release() {
  env PATH="$work/bin:$PATH" DEVELOPER_ID=fixture NOTARY_PROFILE=fixture \
    BARNOOK_SPARKLE_ED_KEY_FILE="$work/key" "$1/scripts/release.sh" 0.1.0
}

printf 'let unreviewed = true\n' > "$work/repo/scripts/untracked.swift"
if output="$(run_release "$work/repo" 2>&1)"; then
  echo 'Untracked source passed the release gate.' >&2; exit 1
fi
[[ "$output" == *'Release requires clean, current main.'* ]]
rm "$work/repo/scripts/untracked.swift"

mkdir -p "$work/repo/build"
: > "$work/repo/build/ignored-artifact"
if output="$(run_release "$work/repo" 2>&1)"; then
  echo 'Notary preflight fixture unexpectedly succeeded.' >&2; exit 1
fi
[[ "$output" == *REACHED_NOTARY_PREFLIGHT* ]] || { printf '%s\n' "$output" >&2; exit 1; }

git clone -q --depth 1 -b main "file://$work/remote.git" "$work/shallow"
if output="$(run_release "$work/shallow" 2>&1)"; then
  echo 'Shallow clone passed the release gate.' >&2; exit 1
fi
[[ "$output" == *'Release requires a non-shallow repository.'* ]]
[[ "$output" != *REACHED_NOTARY_PREFLIGHT* ]]
echo 'Release preflight rejects untracked source and shallow history; ignored artifacts pass.'
