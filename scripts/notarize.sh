#!/usr/bin/env bash
# Modified by Chaehyeon Lee (2026): explicit notary profile.
# Notarize a signed build/BarNook.app and staple the ticket.
# Usage: scripts/notarize.sh [path/to/BarNook.app]
# NOTARY_PROFILE names your notarytool keychain profile.
# Create it once:
#   xcrun notarytool store-credentials ellipsis \
#     --apple-id you@example.com --team-id TEAMID --password app-specific-password
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="${1:-$root/build/BarNook.app}"
profile="${NOTARY_PROFILE:?Set NOTARY_PROFILE to your notarytool keychain profile}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
ditto -c -k --keepParent "$app" "$work/BarNook.zip"

xcrun notarytool submit "$work/BarNook.zip" --keychain-profile "$profile" --wait
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type exec --verbose=2 "$app"
