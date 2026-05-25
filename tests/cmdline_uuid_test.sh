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

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Mock assets::write to capture output
assets::write() { echo "root=UUID=__ROOT_UUID__ rw rootwait" >"$2"; }

# shellcheck disable=SC2034
BUILD_ROOT_UUID="test-uuid-1234"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

source "$repo_root/src/lib/log.sh" 2>/dev/null || true
export BUILD_PROJECT_ROOT="$repo_root"
source "$repo_root/src/lib/core/assets.sh" 2>/dev/null || true
source "$repo_root/src/lib/bootstrap.sh" 2>/dev/null || true
bootstrap::cmdline_txt "$TMPDIR"

if grep -q '__ROOT_UUID__' "$TMPDIR/cmdline.txt"; then
  fail "UUID placeholder was NOT substituted"
fi

if ! grep -q 'root=UUID=test-uuid-1234' "$TMPDIR/cmdline.txt"; then
  fail "UUID was not found in cmdline.txt (got: $(cat "$TMPDIR/cmdline.txt"))"
fi

echo "PASS: cmdline UUID substitution works"
