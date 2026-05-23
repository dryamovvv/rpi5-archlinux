#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

source "$repo_root/lib/log.sh"
source "$repo_root/lib/core/steps.sh"
source "$repo_root/lib/modules/release_validation.sh"

log::info() { :; }
log::success() { :; }
log::warn() { :; }
log::error() { printf '%s\n' "$*" >&2; }
log::die() { printf '%s\n' "$*" >&2; exit 1; }

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

boot_dir="$tmpdir/boot"
mkdir -p "$boot_dir"

for path in kernel8.img initramfs-linux.img bcm2712-rpi-5-b.dtb config.txt cmdline.txt; do
    printf 'content\n' >"$boot_dir/$path"
done

release_validation::validate_boot_files "$boot_dir"

rm -f "$boot_dir/cmdline.txt"
if (release_validation::validate_boot_files "$boot_dir") >/tmp/rpi5-boot-missing.out 2>&1; then
    fail "boot validation must reject missing boot files"
fi
grep -q "Missing boot file" /tmp/rpi5-boot-missing.out ||
    fail "missing boot file failure must explain the problem"

printf 'content\n' >"$boot_dir/cmdline.txt"
: >"$boot_dir/config.txt"
if (release_validation::validate_boot_files "$boot_dir") >/tmp/rpi5-boot-empty.out 2>&1; then
    fail "boot validation must reject zero-size boot files"
fi
grep -q "Empty boot file" /tmp/rpi5-boot-empty.out ||
    fail "empty boot file failure must explain the problem"

steps::reset
release_validation::register
steps::exists "validate_boot_files" || fail "release_validation must register validate_boot_files step"
