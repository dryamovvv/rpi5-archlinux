#!/bin/bash

if [[ -n "${_LIB_CORE_CONFIG_LOADED:-}" ]]; then
    return
fi
readonly _LIB_CORE_CONFIG_LOADED=1

config::load() {
    local config_path="$1"

    log::assert_not_empty "$config_path" "config path"
    [[ -f "$config_path" ]] || log::die "Config file not found: $config_path"

    # shellcheck disable=SC1090
    source "$config_path"
}

config::validate() {
    local required_files=(
        "$BUILD_PACMAN_CONF"
    )
    local required_values=(
        "$BUILD_IMAGE_PATH"
        "$BUILD_IMAGE_SIZE"
        "$BUILD_MOUNT_ROOT"
        "$BUILD_MOUNT_BOOT"
        "$BUILD_USER_NAME"
        "$BUILD_USER_PASSWORD"
        "$BUILD_SSH_USER"
        "$BUILD_ROOT_PASSWORD"
        "$BUILD_TIMEZONE"
        "$BUILD_MKINITCPIO_HOOKS"
    )
    local value=""
    local file_path=""

    for value in "${required_values[@]}"; do
        [[ -n "$value" ]] || log::die "Required build config value is empty"
    done

    for file_path in "${required_files[@]}"; do
        [[ -f "$file_path" ]] || log::die "Required build file is missing: $file_path"
    done

    ((${#BUILD_MODULES[@]} > 0)) || log::die "BUILD_MODULES must not be empty"
    ((${#BUILD_PACKAGES[@]} > 0)) || log::die "BUILD_PACKAGES must not be empty"
}
