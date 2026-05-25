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

bootstrap::systemd_enable_custom_unit() {
  local target="$1"
  local unit="$2"
  local wants_dir="$3"
  mkdir -p "$target/etc/systemd/system/$wants_dir"
  ln -sf "/etc/systemd/system/$unit" "$target/etc/systemd/system/$wants_dir/$unit"
}

bootstrap::systemd_enable_custom_unit "$TMPDIR" "test.service" "multi-user.target.wants"

SYMLINK="$TMPDIR/etc/systemd/system/multi-user.target.wants/test.service"
if [[ ! -L "$SYMLINK" ]]; then
  fail "Symlink was not created at $SYMLINK"
fi

TARGET="$(readlink "$SYMLINK")"
if [[ "$TARGET" != "/etc/systemd/system/test.service" ]]; then
  fail "Symlink points to $TARGET, expected /etc/systemd/system/test.service"
fi

echo "PASS: custom unit symlink points to /etc/systemd/system/"
