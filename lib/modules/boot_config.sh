#!/bin/bash

if [[ -n "${_LIB_MODULE_BOOT_CONFIG_LOADED:-}" ]]; then
    return
fi
readonly _LIB_MODULE_BOOT_CONFIG_LOADED=1

boot_config::register() {
    steps::add "configure_boot" "boot_config::configure" "Write Raspberry Pi boot configuration"
}

boot_config::configure() {
    bootstrap::cmdline_txt "$BUILD_MOUNT_BOOT"
    bootstrap::config_txt "$BUILD_MOUNT_BOOT"
    bootstrap::mkinitcpio_conf "$BUILD_MOUNT_ROOT" "$BUILD_MKINITCPIO_HOOKS"
}
