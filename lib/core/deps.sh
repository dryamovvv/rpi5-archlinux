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
    deps::require_commands \
        blockdev \
        genfstab \
        losetup \
        mkfs.ext4 \
        mkfs.vfat \
        mount \
        pacstrap \
        partprobe \
        partx \
        sfdisk \
        systemd-firstboot \
        udevadm \
        umount
}
