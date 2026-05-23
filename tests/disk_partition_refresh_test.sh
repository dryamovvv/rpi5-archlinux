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
partition_loop="$tmpdir/loop-part1"
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
    if [[ "$1" == "--find" && "$2" == "--show" && "$3" == "--offset" ]]; then
        printf '%s\n' "$partition_loop"
        return 0
    fi

    return 0
}

sfdisk() {
    cat <<EOF
label: gpt
${initial_loop}p1 : start=        2048, size=     1048576, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B
EOF
}

blockdev() {
    printf '512\n'
}

disk::resolve_partition_path "$CURRENT_LOOP_DEV" 1
resolved_path="$RESOLVED_PARTITION_PATH"

[[ "$resolved_path" == "$partition_loop" ]] || {
    printf 'FAIL: expected dedicated partition loop path, got %s\n' "$resolved_path" >&2
    exit 1
}

grep -q 'losetup --find --show --offset' "$calls_file" || {
    printf 'FAIL: expected losetup with offset during partition fallback\n' >&2
    exit 1
}
