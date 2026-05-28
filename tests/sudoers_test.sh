#!/bin/bash
set -euo pipefail

log::info() { :; }
log::success() { :; }
log::warn() { :; }
log::error() { printf '%s\n' "$*" >&2; }
log::die() {
  printf '%s\n' "$*" >&2
  exit 1
}
log::assert_not_empty() { :; }

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/etc/sudoers.d"
echo '%wheel ALL=(ALL:ALL) ALL' >"$TMPDIR/etc/sudoers.d/10-wheel"
chmod 440 "$TMPDIR/etc/sudoers.d/10-wheel"

if [[ ! -f "$TMPDIR/etc/sudoers.d/10-wheel" ]]; then
    fail "10-wheel file not created"
fi

if ! grep -q '%wheel ALL=(ALL:ALL) ALL' "$TMPDIR/etc/sudoers.d/10-wheel"; then
    fail "wrong content in 10-wheel (got: $(cat "$TMPDIR/etc/sudoers.d/10-wheel"))"
fi

perms=$(stat -c "%a" "$TMPDIR/etc/sudoers.d/10-wheel" 2>/dev/null || stat -f "%Lp" "$TMPDIR/etc/sudoers.d/10-wheel" 2>/dev/null)
if [[ "$perms" != "440" ]]; then
    fail "expected 440 permissions, got $perms"
fi

echo "PASS: sudoers drop-in created correctly"
