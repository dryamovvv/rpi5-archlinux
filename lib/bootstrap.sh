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

bootstrap::project_root() {
    cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

# Установка базовых пакетов
# Аргументы: $1 - точка монтирования
bootstrap::install_base() {
    local target="$1"
    log::assert_not_empty "$target" "точка монтирования"

    # Список базовых пакетов для первого запуска с донастройкой через first-boot.
    local pkgs=(
        "base"
        "archlinuxarm-keyring"
        "pacman-mirrorlist"
        "linux-rpi-16k"
        "raspberrypi-bootloader"
        "raspberrypi-utils"
        "firmware-raspberrypi"
        "wireless-regdb"
        "zram-generator"
        "sudo"
        "openssh"
    )

    log::info "Начало установки базовой системы (pacstrap)..."

    # -K сохраняет зеркала, -c предотвращает использование кеша хоста
    local project_root
    project_root="$(bootstrap::project_root)"

    if pacstrap -C "$project_root/conf/pacman-arm.conf" -M -K "$target" "${pkgs[@]}" --noconfirm; then
        log::success "Базовая система установлена."
    else
        log::die "Ошибка при работе pacstrap."
    fi
}

# Генерация таблицы разделов (fstab)
# Аргументы: $1 - точка монтирования
bootstrap::generate_fstab() {
    local target="$1"
    log::assert_not_empty "$target" "точка монтирования"

    log::info "Генерация /etc/fstab..."
    # -U использует UUID разделов (стандарт безопасности)
    genfstab -U "$target" >>"$target/etc/fstab"
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

bootstrap::fix_locale_conf() {
    local target="$1"
    log::assert_not_empty "$target" "точка монтирования"

    mkdir -p "$target/etc"
    if echo "LC_ALL=en_US.UTF-8" >"$target/etc/locale.conf" && echo "LANG=en_US.UTF-8" >> "$target/etc/locale.conf"; then
        cat  "$target/etc/locale.conf"
        log::success "Файл $target/etc/locale.conf"
    else
        log::die "Ошибка при обновлении $target/etc/locale.conf"
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

bootstrap::systemd_firstboot() {
    local target="$1"
    local timezone="$2"
    local root_password="$3"

    log::assert_not_empty "$target" "точка монтирования"
    log::assert_not_empty "$timezone" "часовой пояс"
    log::assert_not_empty "$root_password" "пароль root"

    log::info "Применяем systemd-firstboot..."
    systemd-firstboot \
        --root="$target" \
        --force \
        --locale=en_US.UTF-8 \
        --keymap=us \
        --timezone="$timezone" \
        --root-password="$root_password"
}

bootstrap::firstboot_service() {
    local target="$1"
    local user_name="$2"
    local user_password="$3"

    log::assert_not_empty "$target" "точка монтирования"
    log::assert_not_empty "$user_name" "имя пользователя"
    log::assert_not_empty "$user_password" "пароль пользователя"

    mkdir -p "$target/usr/local/lib/rpi5-archlinux" "$target/etc/systemd/system"
    cat <<EOF >"$target/usr/local/lib/rpi5-archlinux/firstboot.sh"
#!/bin/bash
set -euo pipefail

if ! id -u "$user_name" >/dev/null 2>&1; then
    useradd -m -G wheel "$user_name"
fi

echo "$user_name:$user_password" | chpasswd
chage -d 0 "$user_name"
locale-gen >/dev/null

systemctl disable rpi5-firstboot.service
rm -f /etc/systemd/system/multi-user.target.wants/rpi5-firstboot.service
EOF
    chmod 0755 "$target/usr/local/lib/rpi5-archlinux/firstboot.sh"

    cat <<'EOF' >"$target/etc/systemd/system/rpi5-firstboot.service"
[Unit]
Description=Complete first boot provisioning
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/lib/rpi5-archlinux/firstboot.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    bootstrap::systemd_enable_unit "$target" "rpi5-firstboot.service" "multi-user.target.wants"
}

# Настройка системных параметров внутри образа
# Аргументы: $1 - точка монтирования, $2 - имя хоста (hostname)
bootstrap::cmdline_txt() {
    local target="$1"
    log::assert_not_empty "$target" "точка монтирования"

    log::info "Создаем $target/cmdline.txt..."
    cat <<EOF >"$target/cmdline.txt"
root=/dev/mmcblk0p2 rw rootwait console=tty1 fsck.repair=yes nvme.max_host_mem_size_mb=128 cgroup_enable=memory swapaccount=1
EOF
    if test -f "$target/cmdline.txt"; then
        log::success "$target/cmdline.txt создан!"
    else
        log::die "$target/cmdline.txt не создан!"
    fi
}

bootstrap::config_txt() {
    local target="$1"
    log::assert_not_empty "$target" "точка монтирования"
    log::info "Создаем $target/config.txt..."
    cat <<EOF >"$target/config.txt"
# For more options and information see 
# http://rptl.io/configtxt 
# Some settings may impact device functionality. See link above for details 

[pi5] 
kernel=kernel8.img 
auto_initramfs=1 
initramfs initramfs-linux.img follow-kernel 
arm_64bit=1 
arm_boost=1 
device_tree_address=bcm2712-rpi-5-b.dtb 
overlay_prefix=overlays/ 
dtparam=pciex1_gen=3 
dtoverlay=disable-wifi 
dtoverlay=disable-bt 
disable_overscan=1 
disable_fw_kms_setup=1 
dtoverlay=vc4-kms-v3d 
max_framebuffers=2 
dtparam=audio=on 
camera_auto_detect=0 
display_auto_detect=0 

[all] 

EOF

    if test "$target/config.txt"; then
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
    sed -i 's/^HOOKS=(.*/HOOKS=(systemd autodetect sd-vconsole modconf keyboard block  filesystems fsck sd-shutdown)/' "$target/etc/mkinitcpio.conf"
    sed -i 's/^COMPRESSION="zstd"/#COMPRESSION="zstd"/' "$target/etc/mkinitcpio.conf"
    log::info "Обновлен $target/etc/mkinitcpio.conf..."
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

bootstrap::sshd() {
    local target="$1"
    local ssh_user="$2"
    log::assert_not_empty "$target" "точка монтирования"
    log::assert_not_empty "$ssh_user" "пользователь ssh"

    log::info "Настраиваем sshd"
    echo "AllowUsers $ssh_user" >>"$target/etc/ssh/sshd_config"
    bootstrap::systemd_enable_unit "$target" "sshd.service" "multi-user.target.wants"
}

bootstrap::swap() {
    local target="$1"
    log::assert_not_empty "$target" "точка монтирования"

    log::info "Создание и активация swap-файла (4GB)..."

    arch-chroot "$target" /bin/bash <<EOF
# Создаем директорию, если её нет
mkdir -p /swap

# Используем fallocate — это быстрее и современнее, чем dd
# Если файловая система (например, F2FS или BTRFS) не поддерживает fallocate, dd будет запасным вариантом
fallocate -l 4G /swap/swapfile || dd if=/dev/zero of=/swap/swapfile bs=1M count=4096 status=progress

# Устанавливаем критически важные права доступа
chmod 600 /swap/swapfile

# Инициализируем swap
mkswap /swap/swapfile

# Добавляем запись в /etc/fstab, если её там еще нет (проверка через grep)
if ! grep -q "/swap/swapfile" /etc/fstab; then
    echo "/swap/swapfile none swap defaults 0 0" >> /etc/fstab
fi
EOF
}

bootstrap::zram() {
    local target="$1"
    log::assert_not_empty "$target" "точка монтирования"

    log::info "Настраиваем zram (zram-generator.conf)..."
    mkdir -p "$target/etc/systemd"
    cat <<EOF >"$target/etc/systemd/zram-generator.conf"
[zram0]
zram-size = 8192
compression-algorithm = zstd
swap-priority = 100
EOF

    chmod 0644 "$target/etc/systemd/zram-generator.conf"
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


bootstrap::resize_root(){
    local target="$1"
    log::assert_not_empty "$target" "точка монтирования"
    log::info "Вызовем репарт при первой загрузке"
    mkdir -p "$target/etc/repart.d"
    cat <<EOF >"$target/etc/repart.d/50-root.conf"
[Partition]
Type=root-arm64
EOF
    bootstrap::systemd_enable_unit "$target" "systemd-growfs-root.service" "multi-user.target.wants"
} 
