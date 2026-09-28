#!/usr/bin/env bash
# Modified by Chaehyeon Lee (2026): fork accessibility identity.
# Run the BarNook VM tests: build, clone the golden VM, install the app, the
# fixtures and the probe in the guest, run BarNookVMTests against it,
# fetch the screenshots, delete the VM. See docs/plan.md, Phase 7.
# Usage: scripts/vm-test.sh [swift test args...]
#   BARNOOK_VM       the clone's name (default barnook-test)
#   BARNOOK_VM_KEEP  set to keep the VM running after the run, for a look
#                    over VNC (tart run BARNOOK_VM --vnc after tart stop)
#   BARNOOK_VM_REUSE set to run against a BARNOOK_VM that is already up,
#                     with the bundles copied again; implies KEEP
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
export BARNOOK_VM="${BARNOOK_VM:-barnook-test}"
vm="$root/scripts/vm.sh"
filter=BarNookVMTests
if [[ "${1:-}" == --filter ]]; then
  [[ $# -ge 2 && -n "$2" ]] || { echo 'Expected a VM suite after --filter.' >&2; exit 2; }
  filter="BarNookVMTests.$2"
  shift 2
fi
for argument in "$@"; do
  [[ "$argument" != --filter ]] || { echo 'Specify only one VM suite filter.' >&2; exit 2; }
done

app="$("$root/scripts/bundle.sh" debug)"
fixtures=()
for n in A B C; do
  fixtures+=("$("$root/scripts/bundle-fixture.sh" "$n")")
done
fixtures+=("$("$root/scripts/bundle-fixture.sh" W 7)")
fixtures+=("$("$root/scripts/bundle-fixture.sh" V 9)")
swift build --package-path "$root" --product Probe >&2
probe="$(swift build --package-path "$root" --product Probe --show-bin-path)/Probe"

if [[ "$filter" != BarNookVMTests ]]; then
  listed="$(swift test --package-path "$root" list)"
  [[ "$listed" == *"$filter/"* ]] || { echo "No VM tests match $filter." >&2; exit 2; }
fi

cloned=0
cleanup_vm() {
  local result=${1:-$?}
  trap - EXIT
  if [[ "$cloned" == 1 && -z "${BARNOOK_VM_KEEP:-}" ]]; then
    "$vm" delete || { [[ "$result" != 0 ]] || result=1; }
  fi
  exit "$result"
}
trap cleanup_vm EXIT
if [[ -z "${BARNOOK_VM_REUSE:-}" ]]; then
  cloned=1
  "$vm" clone >&2
fi

"$vm" ssh 'pkill -x BarNookDev; pkill -x FixtureA; pkill -x FixtureB; pkill -x FixtureC; pkill -x FixtureW; pkill -x FixtureV; rm -rf screenshots; true'
"$vm" scp "$app" "${fixtures[@]}" /Applications/
"$vm" scp "$probe" /Users/admin/probe

# The image grants Accessibility to sshd, not to apps it launches. BarNook
# requires Accessibility and Screen Recording. SIP is off in the guest, so
# the rows go straight into the TCC database, as the image's own rows did;
# tccd restarts to read them.
"$vm" ssh 'sh -s' <<'GUEST'
set -e
result="$(sudo sqlite3 -bail "/Library/Application Support/com.apple.TCC/TCC.db" \
  "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, indirect_object_identifier, flags)
   VALUES ('kTCCServiceAccessibility', 'com.chlee1001.BarNookDev', 0, 2, 0, 1, 'UNUSED', 0),
          ('kTCCServiceScreenCapture', 'com.chlee1001.BarNookDev', 0, 2, 0, 1, 'UNUSED', 0);
   SELECT COUNT(*) = 2 FROM access
   WHERE service IN ('kTCCServiceAccessibility', 'kTCCServiceScreenCapture') AND client = 'com.chlee1001.BarNookDev'
     AND client_type = 0 AND auth_value = 2 AND auth_reason = 0 AND auth_version = 1
     AND indirect_object_identifier = 'UNUSED' AND flags = 0;
  ")"
[ "$result" = 1 ]
sudo pkill tccd
GUEST

status=0
# One menu bar in the guest: suites must not run at the same time.
swift test --package-path "$root" --no-parallel --filter "$filter" "$@" || status=$?

mkdir -p "$root/build/vm-screenshots"
"$vm" scp-from screenshots "$root/build/vm-screenshots/" 2>/dev/null || true

if [[ -n "${BARNOOK_VM_KEEP:-}${BARNOOK_VM_REUSE:-}" ]]; then
  echo "$BARNOOK_VM is still running: scripts/vm.sh ssh, or scripts/vm.sh delete" >&2
fi
cleanup_vm "$status"
