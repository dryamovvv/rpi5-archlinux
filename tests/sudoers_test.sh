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

echo '# %wheel ALL=(ALL:ALL) ALL' >"$TMPDIR/sudoers"
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' "$TMPDIR/sudoers"

if grep -q '# %wheel' "$TMPDIR/sudoers"; then
  fail "%wheel line is still commented"
fi

if ! grep -q '%wheel ALL=(ALL:ALL) ALL' "$TMPDIR/sudoers"; then
  fail "%wheel line not uncommented (got: $(cat "$TMPDIR/sudoers"))"
fi

echo "PASS: sudoers wheel uncommented"
