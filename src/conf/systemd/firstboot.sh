#!/bin/bash
set -euo pipefail

USER_NAME="__USER_NAME__"
SWAPFILE_SIZE="__SWAPFILE_SIZE__"

if ! id -u "$USER_NAME" >/dev/null 2>&1; then
    useradd -m -G wheel "$USER_NAME"
    chage -d 0 "$USER_NAME"
fi

if [[ -n "$SWAPFILE_SIZE" ]] && command -v btrfs >/dev/null 2>&1 \
    && [[ "$(findmnt -n -o FSTYPE /)" == "btrfs" ]] \
    && ! swapon --show | grep -q /swap/swapfile; then
    if ! mountpoint -q /swap 2>/dev/null; then
        mkdir -p /swap
        mount -t btrfs -o subvol=@swap,noatime,nodatacow "$(findmnt -n -o SOURCE /)" /swap 2>/dev/null || true
    fi
    btrfs filesystem mkswapfile --size "$SWAPFILE_SIZE" --uuid clear /swap/swapfile
    grep -q "/swap/swapfile" /etc/fstab 2>/dev/null || \
        echo "/swap/swapfile none swap defaults,pri=1 0 0" >>/etc/fstab
    swapon --fixpgsz /swap/swapfile
fi
