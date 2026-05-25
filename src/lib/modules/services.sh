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
    bootstrap::locale_gen_file "$BUILD_MOUNT_ROOT"
    bootstrap::systemd_firstboot "$BUILD_MOUNT_ROOT" "$BUILD_TIMEZONE" "$BUILD_ROOT_PASSWORD" "$BUILD_HOSTNAME"
    bootstrap::firstboot_service "$BUILD_MOUNT_ROOT" "$BUILD_USER_NAME"
}

services::configure_services() {
    bootstrap::network "$BUILD_MOUNT_ROOT"
    bootstrap::sshd "$BUILD_MOUNT_ROOT" "$BUILD_SSH_USER"
    bootstrap::enable_wheel_sudo "$BUILD_MOUNT_ROOT"

    # ZRAM
    if [[ "${BUILD_ENABLE_ZRAM:-0}" == "1" ]]; then
        cat > "$BUILD_MOUNT_ROOT/etc/systemd/zram-generator.conf" <<'EOF'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOF
        log::info "ZRAM enabled (zram-generator configured)"
    else
        bootstrap::disable_swap "$BUILD_MOUNT_ROOT"
    fi

    bootstrap::cpu_boost "$BUILD_MOUNT_ROOT"
    bootstrap::wifi_regdom "$BUILD_MOUNT_ROOT"
    bootstrap::resize_root "$BUILD_MOUNT_ROOT"

    # fail2ban
    mkdir -p "$BUILD_MOUNT_ROOT/etc/fail2ban/jail.d"
    assets::write "fail2ban/sshd.conf" "$BUILD_MOUNT_ROOT/etc/fail2ban/jail.d/sshd.conf"
    bootstrap::systemd_enable_unit "$BUILD_MOUNT_ROOT" "fail2ban.service" "multi-user.target.wants"

    # Wi-Fi (optional)
    if [[ "${BUILD_ENABLE_WIFI:-0}" == "1" ]]; then
        log::info "Wi-Fi enabled"
        mkdir -p "$BUILD_MOUNT_ROOT/etc/wpa_supplicant"
        cat > "$BUILD_MOUNT_ROOT/etc/wpa_supplicant/wpa_supplicant-wlan0.conf" <<'EOF'
# Add your Wi-Fi network here:
# network={
#     ssid="YourNetwork"
#     psk="YourPassword"
# }
EOF
    fi
}
