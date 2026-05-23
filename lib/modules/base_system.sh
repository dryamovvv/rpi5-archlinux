#!/bin/bash

if [[ -n "${_LIB_MODULE_BASE_SYSTEM_LOADED:-}" ]]; then
    return
fi
readonly _LIB_MODULE_BASE_SYSTEM_LOADED=1

base_system::register() {
    steps::add "prepare_base_config" "base_system::prepare_config" "Write early target configuration"
    steps::add "install_base" "base_system::install" "Install Arch Linux ARM packages"
}

base_system::prepare_config() {
    bootstrap::fix_vconsole "$BUILD_MOUNT_ROOT"
}

base_system::install() {
    bootstrap::install_base "$BUILD_MOUNT_ROOT"
    bootstrap::generate_fstab "$BUILD_MOUNT_ROOT"
}
