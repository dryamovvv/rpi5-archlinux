#!/bin/bash

if [[ -n "${_LIB_CORE_DEPS_LOADED:-}" ]]; then
    return
fi
readonly _LIB_CORE_DEPS_LOADED=1

deps::require_commands() {
    local command_name=""
    local missing=0

    for command_name in "$@"; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            log::error "Missing required command: $command_name"
            missing=1
        fi
    done

    ((missing == 0)) || return 1
}

deps::validate_build_commands() {
    local required=( \
        aria2c \
        blockdev \
        dumpe2fs \
        e2fsck \
        fuser \
        genfstab \
        losetup \
        mkfs.ext4 \
        mkfs.vfat \
        mount \
        arch-chroot \
        pacstrap \
        partprobe \
        partx \
        resize2fs \
        sgdisk \
        sfdisk \
        systemd-firstboot \
        udevadm \
        umount \
    )

    if [[ "${BUILD_FILESYSTEM:-ext4}" == "btrfs" ]]; then
        required+=(mkfs.btrfs btrfs)
    fi

    deps::require_commands "${required[@]}"
}

deps::validate_qemu_commands() {
    deps::require_commands qemu-system-aarch64
}
