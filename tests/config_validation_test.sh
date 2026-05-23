#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$repo_root/lib/log.sh"
source "$repo_root/lib/core/config.sh"

log::info() { :; }
log::success() { :; }
log::warn() { :; }
log::error() { printf '%s\n' "$*" >&2; }
log::die() { printf '%s\n' "$*" >&2; exit 1; }

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

set_valid_config() {
    BUILD_PACMAN_CONF="$repo_root/conf/pacman-arm.conf"
    BUILD_IMAGE_PATH="$repo_root/arch_root.img"
    BUILD_IMAGE_SIZE="4g"
    BUILD_MOUNT_ROOT="/mnt/arch_build"
    BUILD_MOUNT_BOOT="$BUILD_MOUNT_ROOT/boot"
    BUILD_USER_NAME="dryam"
    BUILD_USER_PASSWORD="dryam"
    BUILD_SSH_USER="$BUILD_USER_NAME"
    BUILD_ROOT_PASSWORD="root"
    BUILD_TIMEZONE="Europe/Moscow"
    BUILD_MKINITCPIO_HOOKS="HOOKS=(base systemd filesystems fsck)"
    BUILD_MODULES=("disk_image")
    BUILD_PACKAGES=("base")
}

expect_config_failure() {
    local message="$1"

    if (config::validate) >/tmp/rpi5-config-validation.out 2>&1; then
        fail "$message"
    fi

    grep -q "Required build config value is empty" /tmp/rpi5-config-validation.out ||
        fail "$message must explain missing required value"
}

set_valid_config
config::validate

set_valid_config
BUILD_ROOT_PASSWORD=""
expect_config_failure "config validation must reject empty root password"

set_valid_config
BUILD_USER_PASSWORD=""
expect_config_failure "config validation must reject empty user password"

set_valid_config
BUILD_MKINITCPIO_HOOKS=""
expect_config_failure "config validation must reject empty mkinitcpio hooks"
