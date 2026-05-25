#!/bin/bash
# lib/bootstrap.sh — Установка и настройка базовой системы Arch Linux

# Защита от повторного импорта
if [[ -n "${_LIB_BOOTSTRAP_LOADED:-}" ]]; then
    return
fi
readonly _LIB_BOOTSTRAP_LOADED=1

# Импорт зависимостей
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/log.sh"

# Установка базовых пакетов
# Аргументы: $1 - точка монтирования
bootstrap::install_base() {
    local target="$1"
    local pkgs=()
    log::assert_not_empty "$target" "точка монтирования"

    if declare -p BUILD_PACKAGES >/dev/null 2>&1; then
      pkgs=("${BUILD_PACKAGES[@]}")
    else
      pkgs=(
        "base"
        "archlinuxarm-keyring"
        "pacman-mirrorlist"
        "linux-rpi-16k"
        "raspberrypi-bootloader"
        "raspberrypi-utils"
        "firmware-raspberrypi"
        "linux-firmware"
        "wireless-regdb"
        "sudo"
        "openssh"
        "git"
        "vim"
        "htop"
        "tmux"
        "bash-completion"
        "man-db"
        "man-pages"
        "logrotate"
        "i2c-tools"
        "cpupower"
        "rng-tools"
        "iptables-nft"
        "fail2ban"
        "wpa_supplicant"
        "avahi"
      )
    fi

    log::info "Начало установки базовой системы (pacstrap)..."

    local pacman_conf=""

    if [[ -n "${BUILD_PACMAN_CONF:-}" && -f "$BUILD_PACMAN_CONF" ]]; then
      pacman_conf="$BUILD_PACMAN_CONF"
    else
      pacman_conf="$(assets::materialize "pacman/pacman-arm.conf")"
    fi

    if pacstrap -C "$pacman_conf" -M -K "$target" "${pkgs[@]}" --noconfirm; then
      log::success "Базовая система установлена."
    else
      log::die "Ошибка при работе pacstrap."
    fi
}

# Добавляет nofail в опции монтирования /boot в fstab
# Аргументы: $1 - путь к fstab
bootstrap::add_nofail_to_boot() {
    local fstab_path="$1"
    log::assert_not_empty "$fstab_path" "путь к fstab"

    if [[ ! -f "$fstab_path" ]]; then
      return
    fi
    if grep -qP '^[^#]+\s+/boot\s+' "$fstab_path" 2>/dev/null; then
      sed -i '/^[^#]\+\s\+\/boot\s\+/ s/\([[:space:]]\+[^[:space:]]\+\)\{2\}$/,nofail&/' "$fstab_path"
    fi
}

# Генерация таблицы разделов (fstab)
# Аргументы: $1 - точка монтирования
bootstrap::generate_fstab() {
    local target="$1"
    log::assert_not_empty "$target" "точка монтирования"

    log::info "Генерация /etc/fstab..."
    # -U использует UUID разделов (стандарт безопасности)
    # Добавляем nofail для /boot, чтобы отсутствие boot-раздела не блокировало загрузку
    genfstab -U "$target" >"$target/etc/fstab"
    bootstrap::add_nofail_to_boot "$target/etc/fstab"
    bootstrap::disable_swap "$target"
}

bootstrap::fix_vconsole() {
    local target="$1"
    log::assert_not_empty "$target" "точка монтирования"

    mkdir -p "$target/etc"
    if echo "XKBLAYOUT=us" >"$target/etc/vconsole.conf"; then
      log::success "Файл $target/etc/vconsole.conf обновлен"
    else
      log::die "Ошибка при обновлении $target/etc/vconsole.conf"
    fi
}

bootstrap::locale_gen_file() {
    local target="$1"
    log::assert_not_empty "$target" "точка монтирования"

    mkdir -p "$target/etc"
    if ! grep -q '^en_US.UTF-8 UTF-8$' "$target/etc/locale.gen" 2>/dev/null; then
      echo "en_US.UTF-8 UTF-8" >>"$target/etc/locale.gen"
    fi
}

bootstrap::systemd_enable_unit() {
    local target="$1"
    local unit="$2"
    local wants_dir="$3"

    log::assert_not_empty "$target" "точка монтирования"
    log::assert_not_empty "$unit" "systemd unit"
    log::assert_not_empty "$wants_dir" "wants dir"

    mkdir -p "$target/etc/systemd/system/$wants_dir"
    ln -sf "/usr/lib/systemd/system/$unit" "$target/etc/systemd/system/$wants_dir/$unit"
}

# Enable a custom unit stored in /etc/systemd/system/ (not /usr/lib/systemd/system/)
bootstrap::systemd_enable_custom_unit() {
    local target="$1"
    local unit="$2"
    local wants_dir="$3"

    log::assert_not_empty "$target" "точка монтирования"
    log::assert_not_empty "$unit" "systemd unit"
    log::assert_not_empty "$wants_dir" "wants dir"

    mkdir -p "$target/etc/systemd/system/$wants_dir"
    ln -sf "/etc/systemd/system/$unit" "$target/etc/systemd/system/$wants_dir/$unit"
}

bootstrap::systemd_firstboot() {
    local target="$1"
    local timezone="$2"
    local root_password="$3"
    local hostname="$4"

    log::assert_not_empty "$target" "точка монтирования"
    log::assert_not_empty "$timezone" "часовой пояс"
    log::assert_not_empty "$root_password" "пароль root"
    log::assert_not_empty "$hostname" "hostname"

    log::info "Применяем systemd-firstboot..."
    systemd-firstboot \
      --root="$target" \
      --force \
      --locale=en_US.UTF-8 \
      --keymap=us \
      --timezone="$timezone" \
      --hostname="$hostname" \
      --root-password="$root_password" \
      --root-shell=/bin/bash \
      --setup-machine-id
}

bootstrap::firstboot_service() {
    local target="$1"
    local user_name="$2"

    log::assert_not_empty "$target" "точка монтирования"
    log::assert_not_empty "$user_name" "имя пользователя"

    mkdir -p "$target/usr/local/lib/rpi5-archlinux" "$target/etc/systemd/system"
    cat <<FIRSTBOOTSCRIPT >"$target/usr/local/lib/rpi5-archlinux/firstboot.sh"
#!/bin/bash
set -euo pipefail

if ! id -u "$user_name" >/dev/null 2>&1; then
      useradd -m -G wheel "$user_name"
      # No preset password — user must change on first login
      chage -d 0 "$user_name"
fi

locale-gen >/dev/null

if command -v systemd-repart >/dev/null 2>&1; then
      systemd-repart --dry-run=no
fi
systemctl restart systemd-growfs-root.service || true
FIRSTBOOTSCRIPT
    chmod 0755 "$target/usr/local/lib/rpi5-archlinux/firstboot.sh"

    assets::write "systemd/rpi5-firstboot.service" "$target/etc/systemd/system/rpi5-firstboot.service"

    bootstrap::systemd_enable_custom_unit "$target" "rpi5-firstboot.service" "multi-user.target.wants"
}

# Настройка системных параметров внутри образа
# Аргументы: $1 - точка монтирования, $2 - имя хоста (hostname)
bootstrap::cmdline_txt() {
    local target="$1"
    log::assert_not_empty "$target" "точка монтирования"

    log::info "Создаем $target/cmdline.txt..."
    assets::write "boot/cmdline.txt" "$target/cmdline.txt"

    if [[ -n "${BUILD_ROOT_UUID:-}" ]]; then
      sed -i "s/__ROOT_UUID__/$BUILD_ROOT_UUID/" "$target/cmdline.txt"
      log::info "cmdline.txt: root=UUID=$BUILD_ROOT_UUID"
    else
      log::warn "BUILD_ROOT_UUID не задан — cmdline.txt содержит плейсхолдер __ROOT_UUID__"
    fi

    if [[ -s "$target/cmdline.txt" ]]; then
      log::success "$target/cmdline.txt создан!"
    else
      log::die "$target/cmdline.txt не создан!"
    fi
}

bootstrap::config_txt() {
    local target="$1"
    log::assert_not_empty "$target" "точка монтирования"
    log::info "Создаем $target/config.txt..."
    assets::write "boot/config.txt" "$target/config.txt"

    if [[ -s "$target/config.txt" ]]; then
      log::success "$target/config.txt создан!"
    else
      log::die "$target/config.txt не создан!"
    fi

}

bootstrap::mkinitcpio_conf() {
    local target="$1"
    local new_hooks="$2"
    log::assert_not_empty "$target" "точка монтирования"
    log::assert_not_empty "$new_hooks" "новая строка HOOKS"
    log::info "Обновляем $target/etc/mkinitcpio.conf..."
    sed -i "s/^HOOKS=(.*/$new_hooks/" "$target/etc/mkinitcpio.conf"
    sed -i 's/^MODULES=(.*/MODULES=(vfat)/' "$target/etc/mkinitcpio.conf"
    sed -i 's/^COMPRESSION="zstd"/#COMPRESSION="zstd"/' "$target/etc/mkinitcpio.conf"
    log::info "Обновлен $target/etc/mkinitcpio.conf..."
}

bootstrap::regenerate_initramfs() {
    local target="$1"
    log::assert_not_empty "$target" "точка монтирования"

    log::info "Регенерируем initramfs в chroot..."
    arch-chroot "$target" mkinitcpio -P 2>&1 || log::warn "initramfs regeneration encountered issues"
    log::success "initramfs обновлён"
}

bootstrap::network() {
    local target="$1"
    log::assert_not_empty "$target" "точка монтирования"
    log::info "Настраиваем systemd-networkd и resolved..."
    mkdir -p "$target/etc/systemd/network"
    cat <<'EOF' >"$target/etc/systemd/network/20-wired.network"
[Match]
Name=en*

[Network]
DHCP=yes
EOF
    ln -sf /run/systemd/resolve/stub-resolv.conf "$target/etc/resolv.conf"
    bootstrap::systemd_enable_unit "$target" "systemd-networkd.service" "multi-user.target.wants"
    bootstrap::systemd_enable_unit "$target" "systemd-resolved.service" "multi-user.target.wants"
}

bootstrap::enable_wheel_sudo() {
    local target="$1"
    log::assert_not_empty "$target" "точка монтирования"

    log::info "Раскомментируем %wheel в /etc/sudoers..."
    sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' "$target/etc/sudoers"
}

bootstrap::sshd() {
    local target="$1"
    local ssh_user="$2"
    log::assert_not_empty "$target" "точка монтирования"
    log::assert_not_empty "$ssh_user" "пользователь ssh"

    log::info "Настраиваем sshd"
    echo "AllowUsers $ssh_user" >>"$target/etc/ssh/sshd_config"
    bootstrap::systemd_enable_unit "$target" "sshd.service" "multi-user.target.wants"
}

bootstrap::disable_swap() {
    local target="$1"
    log::assert_not_empty "$target" "точка монтирования"

    log::info "Отключаем swap-файл и zram в образе..."
    rm -f "$target/etc/systemd/zram-generator.conf"
    rm -rf "$target/swap"
    if [[ -f "$target/etc/fstab" ]]; then
      sed -i -E '/[[:space:]]swap[[:space:]]/d' "$target/etc/fstab"
    fi
}

bootstrap::cpu_boost() {
    local target="$1"
    log::assert_not_empty "$target" "точка монтирования"

    log::info "Настраиваем активацию CPU Boost при загрузке..."
    mkdir -p "$target/etc/tmpfiles.d"
    cat <<'EOF' >"$target/etc/tmpfiles.d/cpu-boost.conf"
w /sys/devices/system/cpu/cpufreq/boost - - - - 1
EOF
}

bootstrap::wifi_regdom() {
    local target="$1"
    log::assert_not_empty "$target" "точка монтирования"

    log::info "Устанавливаем WIRELESS_REGDOM=RU..."

    mkdir -p "$target/etc/conf.d"
    cat <<'EOF' >"$target/etc/conf.d/wireless-regdom"
WIRELESS_REGDOM="RU"
EOF
}

bootstrap::resize_root() {
    local target="$1"
    log::assert_not_empty "$target" "точка монтирования"
    log::info "Вызовем репарт при первой загрузке"
    mkdir -p "$target/etc/repart.d"
    cat <<EOF >"$target/etc/repart.d/50-root.conf"
[Partition]
Type=root-arm64
GrowFileSystem=yes
EOF
    bootstrap::systemd_enable_unit "$target" "systemd-growfs-root.service" "multi-user.target.wants"
}
