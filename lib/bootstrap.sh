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

bootstrap::add_qemu() {
    local target="$1"
    log::assert_not_empty "$target" "точка монтирования"
    log::assert_not_empty "$QEMU_BIN" "qemu static"
    log::info "Копирую $QEMU_BIN в $target/usr/bin"
    if cp "$QEMU_BIN" "$target/usr/bin"; then
        log::success "Успешно скопирован QEMU_BIN в $target/usr/bin"
    else
        log::die "Ошибка при копировании QEMU_BIN $target/usr/bin"
    fi
}

# Установка базовых пакетов
# Аргументы: $1 - точка монтирования
bootstrap::install_base() {
    local target="$1"
    log::assert_not_empty "$target" "точка монтирования"

    # Список базовых пакетов (минимальный набор 2026)
    local pkgs=(
        "base"
        "archlinuxarm-keyring"
        "pacman-mirrorlist"
        "linux-rpi-16k"
        "linux-rpi-16k-headers"
        "raspberrypi-bootloader"
        "raspberrypi-utils"
        "firmware-raspberrypi"
        "wireless-regdb"
        "lm_sensors"
        "bash-completion"
        "nano"
        "tmux"
        "htop"
        "nvme-cli"
        "zram-generator"
        "sudo"
        "stress-ng"
        "zram-generator"
        "openssh"
        "git"
        "dosfstools"
        "polkit"
        "less"
	"lsof"
	"strace"
	"man"
	"python-setuptools"
	"python-pip"
	"python-pipx"
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

# Настройка системных параметров внутри образа
# Аргументы: $1 - точка монтирования, $2 - имя хоста (hostname)
bootstrap::locale_gen() {
    local target="$1"
    log::assert_not_empty "$target" "точка монтирования"

    log::info "Генерация локали..."
    arch-chroot "$target" /bin/bash <<EOF
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
    locale-gen > /dev/null
EOF

    log::success "Система настроена."
}

bootstrap::root_passwd() {
    local target="$1"
    log::assert_not_empty "$target" "точка монтирования"

    log::info "Установка пароля root..."
    arch-chroot "$target" /bin/bash <<EOF

        # Установка пароля root (по умолчанию 'root')
        echo "root:root" | chpasswd
EOF
    log::success "Пароль root сменен."
}

bootstrap::sudo_user() {
    local target="$1"
    local user_name="$2"
    log::assert_not_empty "$target" "точка монтирования"
    log::assert_not_empty "$target" "имя пользователя"

    log::info "Создаем  /etc/sudoers.d/10-wheel..."
    arch-chroot "$target" /bin/bash -c "cat <<EOF > /etc/sudoers.d/10-wheel
%wheel ALL=(ALL:ALL) ALL
EOF
    chmod 0440 /etc/sudoers.d/10-wheel"

    #     arch-chroot "$target" /bin/bash <<EOF
    #         chmod 0440 /etc/sudoers.d/10-wheel
    # EOF

    log::info "Создание пользователя sudo"
    arch-chroot "$target" /bin/bash <<EOF
        useradd -m -G wheel "$user_name"
        echo "$user_name:$user_name" |  chpasswd
        chage -d 0 "$user_name"
EOF
    log::success "Пользователь $user_name создан с временным паролем $user_name"
}

bootstrap::time() {
    local target="$1"
    local timezone="$2"
    log::assert_not_empty "$target" "точка монтирования"
    log::assert_not_empty "$timezone" "часовой пояс"
    arch-chroot "$target" /bin/bash <<EOF
    # Установка временного пояса
    ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
    hwclock --systohc
EOF
}

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
    arch-chroot "$target" /bin/bash <<EOF
    # Заменяем строку HOOKS
    sed -i 's/^HOOKS=(.*/HOOKS=(systemd autodetect sd-vconsole modconf keyboard block  filesystems fsck sd-shutdown)/' /etc/mkinitcpio.conf
    sed -i 's/^COMPRESSION="zstd"/#COMPRESSION="zstd"/' /etc/mkinitcpio.conf
    # После изменения HOOKS всегда нужно пересобрать образ!
    mkinitcpio -P
EOF
    log::info "Обновлен $target/etc/mkinitcpio.conf..."
}

bootstrap::network() {
    local target="$1"
    log::assert_not_empty "$target" "точка монтирования"
    log::info "Настраиваем systemd-networkd и resolved..."
    arch-chroot "$target" /bin/bash <<EOF
echo "[Match]" > /etc/systemd/network/20-wired.network
echo "Name=en*" >> /etc/systemd/network/20-wired.network
echo "[Network]" >> /etc/systemd/network/20-wired.network
echo "DHCP=yes" >> /etc/systemd/network/20-wired.network
echo "nameserver 8.8.8.8" >> /etc/resolv.conf
systemctl enable systemd-networkd systemd-resolved
EOF
}

bootstrap::sshd() {
    local target="$1"
    local ssh_user="$2"
    log::assert_not_empty "$target" "точка монтирования"
    log::assert_not_empty "$ssh_user" "пользователь ssh"

    log::info "Настраиваем sshd"
    arch-chroot "$target" /bin/bash <<EOF
echo "AllowUsers $ssh_user" | tee -a /etc/ssh/sshd_config > /dev/null
systemctl enable sshd.service systemd-resolved
EOF
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

    arch-chroot "$target" tee /etc/systemd/zram-generator.conf >/dev/null <<EOF
[zram0]
zram-size = 8192
compression-algorithm = zstd
swap-priority = 100
EOF

    # Установка правильных прав доступа — важный шаг для надежности
    arch-chroot "$target" chmod 0644 /etc/systemd/zram-generator.conf
}

bootstrap::cpu_boost() {
    local target="$1"
    log::assert_not_empty "$target" "точка монтирования"

    log::info "Настраиваем активацию CPU Boost при загрузке..."
    arch-chroot "$target" /bin/bash <<EOF
cat <<boostEOF > /etc/tmpfiles.d/cpu-boost.conf
w /sys/devices/system/cpu/cpufreq/boost - - - - 1
boostEOF
EOF
}

bootstrap::wifi_regdom() {
    local target="$1"
    log::assert_not_empty "$target" "точка монтирования"

    log::info "Устанавливаем WIRELESS_REGDOM=RU..."

    # Используем sed для раскомментирования строки с RU
    # s/^#// — убирает символ решетки в начале строки
    # Ищем конкретно WIRELESS_REGDOM="RU"
    arch-chroot "$target" sed -i 's/^#WIRELESS_REGDOM="RU"/WIRELESS_REGDOM="RU"/' /etc/conf.d/wireless-regdom
}


bootstrap::resize_root(){
    local target="$1"
    log::assert_not_empty "$target" "точка монтирования"
    log::info "Вызовем репарт при первой загрузке"
    arch-chroot "$target" mkdir -p /etc/repart.d
    arch-chroot "$target" tee /etc/repart.d/50-root.conf > /dev/null <<EOF
[Partition]
Type=root-arm64
EOF
    arch-chroot "$target" systemctl enable systemd-growfs-root.service
} 
