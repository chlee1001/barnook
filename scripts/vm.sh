#!/usr/bin/env bash
# Tart guest for the BarNook VM tests. See docs/plan.md, Phase 7.
# Usage: scripts/vm.sh prepare          clone the base image as the golden VM and put the ssh key in it
#        scripts/vm.sh clone            clone the golden VM as $BARNOOK_VM and boot it headless
#        scripts/vm.sh ip               print the guest IP, waiting for it
#        scripts/vm.sh ssh [CMD...]     run a command in the guest, or open a shell
#        scripts/vm.sh scp SRC... DST   copy into the guest; DST is a guest path
#        scripts/vm.sh scp-from SRC DST copy a guest path out to DST on the host
#        scripts/vm.sh stop | delete    stop, or stop and delete, $BARNOOK_VM
set -euo pipefail

base="ghcr.io/cirruslabs/macos-golden-gate-base:latest"
golden="${BARNOOK_VM_GOLDEN:-barnook-golden}"
vm="${BARNOOK_VM:-barnook-test}"
user="admin"
key="$HOME/.tart/barnook_ed25519"
# The control socket keeps one connection open across the many short ssh
# calls of a test run, so each one costs milliseconds, not a handshake.
ssh_opts=(-i "$key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR
  -o ControlMaster=auto -o ControlPath="$HOME/.tart/ssh-%C" -o ControlPersist=120)

ip() { tart ip "$1" --wait 120; }

# Boots a VM in its own session, so it outlives the shell that started it.
boot() { perl -e 'use POSIX; POSIX::setsid(); exec @ARGV' -- tart run "$1" --no-graphics > /dev/null 2>&1 < /dev/null & }

case "${1:-}" in
  prepare)
    # The image grants Accessibility, Full Disk Access and Apple Events to
    # sshd, so the guest needs nothing but our key. See docs/phase7.md.
    if [[ ! -f "$key" ]]; then
      ssh-keygen -t ed25519 -N "" -C barnook-vm -f "$key" -q
    fi
    tart delete "$golden" 2>/dev/null || true
    tart clone "$base" "$golden"
    tart set "$golden" --cpu 4 --memory 8192
    boot "$golden"
    addr="$(ip "$golden")"
    expect -c "
      set timeout 120
      spawn ssh-copy-id -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $key.pub $user@$addr
      expect assword: { send $user\\r }
      expect eof
    " > /dev/null
    ssh "${ssh_opts[@]}" "$user@$addr" 'sudo shutdown -h now' >/dev/null 2>&1 || true
    while [[ "$(tart get "$golden" --format json | plutil -extract Running raw -)" == true ]]; do sleep 1; done
    echo "$golden is ready"
    ;;
  clone)
    tart delete "$vm" 2>/dev/null || true
    tart clone "$golden" "$vm"
    boot "$vm"
    addr="$(ip "$vm")"
    until ssh "${ssh_opts[@]}" -o ConnectTimeout=2 "$user@$addr" true 2>/dev/null; do sleep 1; done
    echo "$addr"
    ;;
  ip)
    ip "$vm"
    ;;
  ssh)
    shift
    exec ssh "${ssh_opts[@]}" "$user@$(ip "$vm")" "$@"
    ;;
  scp)
    shift
    dst="${*: -1}"
    exec scp "${ssh_opts[@]}" -r "${@:1:$#-1}" "$user@$(ip "$vm"):$dst"
    ;;
  scp-from)
    exec scp "${ssh_opts[@]}" -r "$user@$(ip "$vm"):$2" "$3"
    ;;
  stop)
    tart stop "$vm"
    ;;
  delete)
    tart stop "$vm" 2>/dev/null || true
    # A runner whose VM stopped under it keeps one of the two VM slots
    # macOS allows, and the next boot fails with "exceeds the system limit".
    pkill -f "tart run $vm " 2>/dev/null || true
    tart delete "$vm"
    ;;
  *)
    sed -n '2,8p' "$0" >&2
    exit 1
    ;;
esac
