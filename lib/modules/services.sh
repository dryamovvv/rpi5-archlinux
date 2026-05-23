#!/bin/bash

if [[ -n "${_LIB_MODULE_SERVICES_LOADED:-}" ]]; then
    return
fi
readonly _LIB_MODULE_SERVICES_LOADED=1

services::register() {
    steps::add "configure_system" "services::configure_system" "Configure users, locale, and first boot"
    steps::add "configure_services" "services::configure_services" "Configure enabled services and runtime settings"
}

services::configure_system() {
    bootstrap::fix_locale_conf "$BUILD_MOUNT_ROOT"
    bootstrap::locale_gen_file "$BUILD_MOUNT_ROOT"
    bootstrap::systemd_firstboot "$BUILD_MOUNT_ROOT" "$BUILD_TIMEZONE" "$BUILD_ROOT_PASSWORD"
    bootstrap::firstboot_service "$BUILD_MOUNT_ROOT" "$BUILD_USER_NAME" "$BUILD_USER_PASSWORD"
}

services::configure_services() {
    bootstrap::network "$BUILD_MOUNT_ROOT"
    bootstrap::sshd "$BUILD_MOUNT_ROOT" "$BUILD_SSH_USER"
    bootstrap::zram "$BUILD_MOUNT_ROOT"
    bootstrap::cpu_boost "$BUILD_MOUNT_ROOT"
    bootstrap::wifi_regdom "$BUILD_MOUNT_ROOT"
    bootstrap::resize_root "$BUILD_MOUNT_ROOT"
}
