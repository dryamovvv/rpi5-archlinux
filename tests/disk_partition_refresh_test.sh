#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

source "$repo_root/lib/disk.sh"

log::info() { :; }
log::success() { :; }
log::warn() { :; }
log::error() { printf '%s\n' "$*" >&2; }
log::die() { printf '%s\n' "$*" >&2; exit 1; }
log::assert_not_empty() {
    if [[ -z "${1:-}" ]]; then
        log::die "empty arg: ${2:-unknown}"
    fi
}

calls_file="$tmpdir/calls.log"
initial_loop="$tmpdir/loop0"
remapped_loop="$tmpdir/loop1"
image_path="$tmpdir/arch_root.img"

touch "$image_path"
CURRENT_LOOP_DEV="$initial_loop"
CURRENT_IMAGE_PATH="$image_path"

partprobe() {
    printf 'partprobe %s\n' "$*" >>"$calls_file"
}

partx() {
    printf 'partx %s\n' "$*" >>"$calls_file"
}

udevadm() {
    printf 'udevadm %s\n' "$*" >>"$calls_file"
}

sleep() {
    :
}

losetup() {
    printf 'losetup %s\n' "$*" >>"$calls_file"
    if [[ "$1" == "--find" ]]; then
        touch "${remapped_loop}p1" "${remapped_loop}p2"
        printf '%s\n' "$remapped_loop"
        return 0
    fi

    return 0
}

disk::resolve_partition_path "$CURRENT_LOOP_DEV" 1
resolved_path="$RESOLVED_PARTITION_PATH"

[[ "$resolved_path" == "${remapped_loop}p1" ]] || {
    printf 'FAIL: expected remapped partition path, got %s\n' "$resolved_path" >&2
    exit 1
}

[[ "$CURRENT_LOOP_DEV" == "$remapped_loop" ]] || {
    printf 'FAIL: expected CURRENT_LOOP_DEV to be updated, got %s\n' "$CURRENT_LOOP_DEV" >&2
    exit 1
}

grep -q 'losetup -d' "$calls_file" || {
    printf 'FAIL: expected losetup detach during refresh\n' >&2
    exit 1
}

grep -q 'losetup --find -P --show' "$calls_file" || {
    printf 'FAIL: expected losetup remap during refresh\n' >&2
    exit 1
}
