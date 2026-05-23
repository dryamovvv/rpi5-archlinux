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
mount_point="$tmpdir/mnt"
mkdir -p "$mount_point"

CURRENT_LOOP_DEV="/dev/loop-main"
PARTITION_LOOP_DEVS=([1]="/dev/loop-boot" [2]="/dev/loop-root")

sync() {
    printf 'sync\n' >>"$calls_file"
}

mountpoint() {
    [[ "$1" == "-q" && "$2" == "$mount_point" ]]
}

umount() {
    printf 'umount %s\n' "$*" >>"$calls_file"
}

losetup() {
    printf 'losetup %s\n' "$*" >>"$calls_file"
}

sleep() {
    :
}

disk::cleanup "$mount_point"

grep -q '^sync$' "$calls_file" || {
    printf 'FAIL: cleanup must sync image data\n' >&2
    exit 1
}

grep -q "umount -R $mount_point" "$calls_file" || {
    printf 'FAIL: cleanup must recursively unmount target\n' >&2
    exit 1
}

grep -q 'losetup -d /dev/loop-boot' "$calls_file" || {
    printf 'FAIL: cleanup must detach boot partition loop\n' >&2
    exit 1
}

grep -q 'losetup -d /dev/loop-root' "$calls_file" || {
    printf 'FAIL: cleanup must detach root partition loop\n' >&2
    exit 1
}

grep -q 'losetup -d /dev/loop-main' "$calls_file" || {
    printf 'FAIL: cleanup must detach main loop\n' >&2
    exit 1
}
