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

	if pacstrap -C "$pacman_conf" -M "$target" "${pkgs[@]}" --noconfirm; then
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

	if [[ "${BUILD_FILESYSTEM:-ext4}" == "btrfs" ]]; then
		bootstrap::generate_btrfs_fstab "$target"
		return
	fi

	log::info "Генерация /etc/fstab..."
	genfstab -U "$target" >"$target/etc/fstab"
	bootstrap::add_nofail_to_boot "$target/etc/fstab"
	bootstrap::disable_swap "$target"
}

bootstrap::generate_btrfs_fstab() {
	local target="$1"
	log::assert_not_empty "$target" "точка монтирования"

	local root_uuid="${BUILD_ROOT_UUID:-}"
	log::assert_not_empty "$root_uuid" "BUILD_ROOT_UUID"

	local boot_part=""
	disk::resolve_partition_path "$CURRENT_LOOP_DEV" 1
	boot_part="$RESOLVED_PARTITION_PATH"
	local boot_uuid=""
	boot_uuid="$(blkid -s UUID -o value "$boot_part")"
	log::assert_not_empty "$boot_uuid" "ESP UUID"

	log::info "Генерация /etc/fstab для btrfs subvolume layout..."
	cat <<EOF >"$target/etc/fstab"
# /etc/fstab — btrfs subvolume layout
UUID=$root_uuid /          btrfs rw,noatime,compress=zstd,x-systemd.device-timeout=90 0 0
UUID=$root_uuid /home      btrfs rw,noatime,compress=zstd,subvol=@home    0 0
UUID=$root_uuid /.snapshots btrfs rw,noatime,subvol=@snapshots            0 0
UUID=$root_uuid /var/log   btrfs rw,noatime,compress=zstd,subvol=@var_log 0 0
UUID=$root_uuid /var/cache btrfs rw,noatime,nodatacow,subvol=@var_cache   0 0
UUID=$root_uuid /var/tmp   btrfs rw,noatime,nodatacow,subvol=@var_tmp     0 0
UUID=$root_uuid /swap      btrfs rw,noatime,nodatacow,subvol=@swap        0 0
UUID=$boot_uuid /boot      vfat defaults,noatime,nofail                    0 0
EOF
	log::success "/etc/fstab для btrfs создан"
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

	log::assert_not_empty "$target" "точка монтирования"

	log::info "Применяем systemd-firstboot..."
	local args=(
		--root="$target"
		--force
		--locale="${BUILD_LOCALE:-en_US.UTF-8}"
		--keymap="${BUILD_KEYMAP:-us}"
		--root-shell=/bin/bash
		--setup-machine-id
	)

	[[ -n "${BUILD_HOSTNAME:-}" ]] && args+=(--hostname="$BUILD_HOSTNAME")
	[[ -n "${BUILD_TIMEZONE:-}" ]] && args+=(--timezone="$BUILD_TIMEZONE")
	[[ -n "${BUILD_ROOT_PASSWORD:-}" ]] && args+=(--root-password="$BUILD_ROOT_PASSWORD")

	systemd-firstboot "${args[@]}"
}

bootstrap::firstboot_service() {
	local target="$1"

	log::assert_not_empty "$target" "точка монтирования"

	local identity_dir="$target/usr/local/lib/rpi5-archlinux"
	mkdir -p "$identity_dir"

	assets::write "systemd/firstboot.sh" "$identity_dir/firstboot.sh"
	sed -i "s/__SWAPFILE_SIZE__/${BUILD_SWAPFILE_SIZE:-}/g" "$identity_dir/firstboot.sh"
	chmod 0755 "$identity_dir/firstboot.sh"

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
		# LUKS keyboard mode: rd.luks.name only (no ip=dhcp)
		if [[ "${BUILD_ENABLE_ENCRYPTION:-0}" == "1" ]] && [[ -n "${LUKS_UUID:-}" ]]; then
			sed -i "1s/__ROOT_UUID__/$BUILD_ROOT_UUID/" "$target/cmdline.txt"
			if [[ "${BUILD_LUKS_UNLOCK_MODE:-keyboard}" == "ssh" ]] || [[ "${BUILD_LUKS_UNLOCK_MODE:-keyboard}" == "telegram" ]]; then
				sed -i "1s/^/rd.luks.name=$LUKS_UUID=cryptroot ip=dhcp /" "$target/cmdline.txt"
			else
				sed -i "1s/^/rd.luks.name=$LUKS_UUID=cryptroot /" "$target/cmdline.txt"
			fi
			log::info "cmdline.txt: rd.luks.name=$LUKS_UUID=cryptroot root=UUID=$BUILD_ROOT_UUID ($BUILD_LUKS_UNLOCK_MODE mode)"
		else
			sed -i "1s/__ROOT_UUID__/$BUILD_ROOT_UUID/" "$target/cmdline.txt"
			log::info "cmdline.txt: root=UUID=$BUILD_ROOT_UUID"
		fi
	else
		log::warn "BUILD_ROOT_UUID не задан — cmdline.txt содержит плейсхолдер __ROOT_UUID__"
	fi

	if [[ "${BUILD_FILESYSTEM:-ext4}" == "btrfs" ]]; then
		sed -i '1s/ fsck.repair=yes//' "$target/cmdline.txt"
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

	local modules="vfat"

	if [[ "${BUILD_FILESYSTEM:-ext4}" == "btrfs" ]]; then
		new_hooks="${new_hooks//fsck /}"
		new_hooks="${new_hooks// fsck)/)}"
		modules="vfat btrfs"
	fi

	# LUKS: sd-encrypt before filesystems
	#   keyboard: sd-encrypt only
	#   ssh:      sd-network + sd-tinyssh + sd-encrypt
	#   telegram: sd-network + telegram-unlock + sd-encrypt
	if [[ "${BUILD_ENABLE_ENCRYPTION:-0}" == "1" ]]; then
		modules="$modules dm_crypt"
		new_hooks="${new_hooks//filesystems /sd-encrypt filesystems }"
		if [[ "${BUILD_LUKS_UNLOCK_MODE:-keyboard}" == "ssh" ]]; then
			new_hooks="${new_hooks//sd-encrypt /sd-network sd-tinyssh sd-encrypt }"
			log::info "mkinitcpio: LUKS hooks (sd-network, sd-tinyssh, sd-encrypt, dm_crypt)"
		elif [[ "${BUILD_LUKS_UNLOCK_MODE:-keyboard}" == "telegram" ]]; then
			new_hooks="${new_hooks//sd-encrypt /sd-network telegram-unlock sd-encrypt }"
			log::info "mkinitcpio: LUKS hooks (sd-network, telegram-unlock, sd-encrypt, dm_crypt)"
		else
			log::info "mkinitcpio: LUKS hooks (sd-encrypt, dm_crypt) — keyboard mode"
		fi
	fi

	sed -i "s/^MODULES=(.*/MODULES=($modules)/" "$target/etc/mkinitcpio.conf"
	sed -i "s/^HOOKS=(.*/$new_hooks/" "$target/etc/mkinitcpio.conf"
	sed -i 's/^COMPRESSION="zstd"/#COMPRESSION="zstd"/' "$target/etc/mkinitcpio.conf"
	if [[ -n "${BUILD_MKINITCPIO_COMPRESSION:-}" ]]; then
		sed -i "s/^#COMPRESSION=.*/COMPRESSION=${BUILD_MKINITCPIO_COMPRESSION}/" "$target/etc/mkinitcpio.conf"
		log::info "mkinitcpio compression: $BUILD_MKINITCPIO_COMPRESSION"
	fi
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
MulticastDNS=yes
EOF
	mkdir -p "$target/etc/systemd"
	cat <<'EOF' >"$target/etc/systemd/resolved.conf"
[Resolve]
MulticastDNS=yes
EOF
	ln -sf /run/systemd/resolve/stub-resolv.conf "$target/etc/resolv.conf"
	bootstrap::systemd_enable_unit "$target" "systemd-networkd.service" "multi-user.target.wants"
	bootstrap::systemd_enable_unit "$target" "systemd-resolved.service" "multi-user.target.wants"
}

bootstrap::enable_wheel_sudo() {
	local target="$1"
	log::assert_not_empty "$target" "точка монтирования"

	log::info "Добавляем %wheel в /etc/sudoers.d/10-wheel..."
	assets::write "sudoers.d/10-wheel" "$target/etc/sudoers.d/10-wheel"
	chmod 440 "$target/etc/sudoers.d/10-wheel"
}

bootstrap::sshd() {
	local target="$1"
	local ssh_user="${2:-}"
	local extra_users="${3:-}"
	log::assert_not_empty "$target" "точка монтирования"

	log::info "Настраиваем sshd"

	if [[ -n "${BUILD_SSH_PORT:-}" ]]; then
		echo "Port ${BUILD_SSH_PORT}" >>"$target/etc/ssh/sshd_config"
		log::info "SSH port: ${BUILD_SSH_PORT}"
	fi

	echo "PermitRootLogin ${BUILD_SSH_PERMIT_ROOT_LOGIN:-yes}" >>"$target/etc/ssh/sshd_config"
	echo "KbdInteractiveAuthentication yes" >>"$target/etc/ssh/sshd_config"

	if [[ -f "$target/etc/ssh/sshd_config.d/99-archlinux.conf" ]]; then
		sed -i 's/KbdInteractiveAuthentication no/KbdInteractiveAuthentication yes/' \
			"$target/etc/ssh/sshd_config.d/99-archlinux.conf"
	fi

	local allow_users="root"
	[[ -n "$ssh_user" ]] && allow_users+=" $ssh_user"
	[[ -n "$extra_users" ]] && allow_users+=" $extra_users"
	echo "AllowUsers $allow_users" >>"$target/etc/ssh/sshd_config"

	if [[ -n "${BUILD_ROOT_SSH_KEY:-}" ]]; then
		mkdir -p "$target/root/.ssh"
		chmod 700 "$target/root/.ssh"
		echo "$BUILD_ROOT_SSH_KEY" >"$target/root/.ssh/authorized_keys"
		chmod 600 "$target/root/.ssh/authorized_keys"
		log::info "Root SSH key installed"
	fi

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

	log::info "Настраиваем CPU Boost и schedutil governor..."
	mkdir -p "$target/etc/tmpfiles.d"
	cat <<'EOF' >"$target/etc/tmpfiles.d/cpu-power.conf"
w /sys/devices/system/cpu/cpufreq/boost - - - - 1
w /sys/devices/system/cpu/cpufreq/policy0/scaling_governor - - - - schedutil
w /sys/devices/system/cpu/cpufreq/policy4/scaling_governor - - - - schedutil
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

	log::info "Создаем repart drop-in для расширения раздела при первой загрузке"
	mkdir -p "$target/etc/repart.d"
	cat <<EOF >"$target/etc/repart.d/50-root.conf"
[Partition]
Type=root-arm64
GrowFileSystem=yes
EOF

	bootstrap::systemd_enable_unit "$target" "systemd-repart.service" "sysinit.target.wants"
	bootstrap::systemd_enable_unit "$target" "systemd-growfs-root.service" "sysinit.target.wants"

	bootstrap::regenerate_initramfs "$target"
}

bootstrap::btrfs_setup_snapper() {
	local target="$1"
	log::assert_not_empty "$target" "точка монтирования"

	log::info "Настройка snapper для btrfs..."

	local snap_mount="$target/.snapshots"
	local root_part=""
	if [[ -n "${CRYPTROOT_DEVICE:-}" ]]; then
		root_part="/dev/mapper/cryptroot"
	else
		disk::resolve_partition_path "$CURRENT_LOOP_DEV" 2
		root_part="$RESOLVED_PARTITION_PATH"
	fi

	if mountpoint -q "$snap_mount" 2>/dev/null; then
		umount "$snap_mount"
	fi
	rmdir "$snap_mount" 2>/dev/null || true

	mkdir -p "$target/etc/snapper/configs"
	cat >"$target/etc/snapper/configs/root" <<'SNAPCONF'
SUBVOLUME="/"
FSTYPE="btrfs"
QGROUP=""
SPACE_LIMIT="0.5"
FREE_LIMIT="0.2"
ALLOW_USERS=""
ALLOW_GROUPS=""
SYNC_ACL="no"
BACKGROUND_COMPARISON="yes"
NUMBER_CLEANUP="yes"
NUMBER_MIN_AGE="1800"
NUMBER_LIMIT="50"
NUMBER_LIMIT_IMPORTANT="10"
TIMELINE_CREATE="yes"
TIMELINE_CLEANUP="yes"
TIMELINE_MIN_AGE="1800"
TIMELINE_LIMIT_HOURLY="5"
TIMELINE_LIMIT_DAILY="7"
TIMELINE_LIMIT_WEEKLY="4"
TIMELINE_LIMIT_MONTHLY="3"
TIMELINE_LIMIT_YEARLY="2"
EMPTY_PRE_POST_CLEANUP="yes"
EMPTY_PRE_POST_MIN_AGE="1800"
SNAPCONF

	cat >"$target/etc/snapper/configs/home" <<'SNAPCONF'
SUBVOLUME="/home"
FSTYPE="btrfs"
QGROUP=""
SPACE_LIMIT="0.5"
FREE_LIMIT="0.2"
ALLOW_USERS=""
ALLOW_GROUPS=""
SYNC_ACL="no"
BACKGROUND_COMPARISON="yes"
NUMBER_CLEANUP="yes"
NUMBER_MIN_AGE="1800"
NUMBER_LIMIT="50"
NUMBER_LIMIT_IMPORTANT="10"
TIMELINE_CREATE="yes"
TIMELINE_CLEANUP="yes"
TIMELINE_MIN_AGE="1800"
TIMELINE_LIMIT_HOURLY="3"
TIMELINE_LIMIT_DAILY="7"
TIMELINE_LIMIT_WEEKLY="4"
TIMELINE_LIMIT_MONTHLY="3"
TIMELINE_LIMIT_YEARLY="2"
EMPTY_PRE_POST_CLEANUP="yes"
EMPTY_PRE_POST_MIN_AGE="1800"
SNAPCONF

	# Register config in /etc/conf.d/snapper (snapper create-config does this)
	if [[ -f "$target/etc/conf.d/snapper" ]]; then
		sed -i 's/SNAPPER_CONFIGS=""/SNAPPER_CONFIGS="root home"/' "$target/etc/conf.d/snapper"
	fi

	if btrfs subvolume delete "$target/.snapshots" >/dev/null 2>&1; then
		log::info "Удален вложенный .snapshots subvolume внутри @"
	fi

	mkdir -p "$snap_mount"
	mount -o subvol=@snapshots,noatime "$root_part" "$snap_mount"
	chmod 750 "$snap_mount"

	bootstrap::systemd_enable_unit "$target" "snapper-timeline.timer" "timers.target.wants"
	bootstrap::systemd_enable_unit "$target" "snapper-cleanup.timer" "timers.target.wants"

	log::success "Snapper настроен"
}

# Native snapper rollback replaces custom rollback.sh (v0.10.0)
# btrfs subvolume set-default @ is done at image creation time
# Users can use: snapper -c root rollback <snap_num> && reboot

bootstrap::mcp_server() {
	local target="$1"
	log::assert_not_empty "$target" "точка монтирования"

	log::info "Installing arch-ops-server (MCP) in chroot..."
	if ! arch-chroot "$target" uv tool install --from "git+https://github.com/dryamovvv/arch-mcp" "arch-ops-server[http]" 2>&1; then
		log::warn "MCP server installation failed — skipping service enablement (no network?)"
		return 0
	fi

	local api_key
	api_key=$(python3 -c "import uuid; print(uuid.uuid4())")
	mkdir -p "$target/etc/arch-ops-mcp"
	cat >"$target/etc/arch-ops-mcp/env" <<EOF
ARCH_OPS_SERVER_BIND=127.0.0.1
ARCH_OPS_SERVER_API_KEY=$api_key
EOF
	chmod 600 "$target/etc/arch-ops-mcp/env"

	printf '%s' "$api_key" >"${BUILD_IMAGE_PATH}.mcp-key"
	chmod 600 "${BUILD_IMAGE_PATH}.mcp-key"
	log::info "MCP API key saved to ${BUILD_IMAGE_PATH}.mcp-key"

	assets::write "systemd/arch-ops-mcp.service" "$target/etc/systemd/system/arch-ops-mcp.service"
	bootstrap::systemd_enable_custom_unit "$target" "arch-ops-mcp.service" "multi-user.target.wants"

	log::info "arch-ops-server (MCP) configured"
}

bootstrap::luks_initramfs() {
	local target="$1"
	log::assert_not_empty "$target" "точка монтирования"

	local unlock_mode="${BUILD_LUKS_UNLOCK_MODE:-keyboard}"

	if [[ "$unlock_mode" == "keyboard" ]]; then
		log::info "LUKS: keyboard mode — skipping initramfs extras"
		return 0
	fi

	if [[ "$unlock_mode" == "telegram" ]]; then
		log::info "Настройка LUKS Telegram unlock..."
		mkdir -p "$target/etc/initcpio/install" "$target/etc/initcpio/hooks"
		assets::write "initcpio/install/telegram-unlock" "$target/etc/initcpio/install/telegram-unlock"
		chmod 0644 "$target/etc/initcpio/install/telegram-unlock"
		assets::write "initcpio/hooks/telegram-unlock" "$target/etc/initcpio/hooks/telegram-unlock"
		chmod 0644 "$target/etc/initcpio/hooks/telegram-unlock"
		sed -i "s|__BOT_TOKEN__|${BUILD_TELEGRAM_BOT_TOKEN}|g" "$target/etc/initcpio/hooks/telegram-unlock"
		sed -i "s|__CHAT_ID__|${BUILD_TELEGRAM_CHAT_ID}|g" "$target/etc/initcpio/hooks/telegram-unlock"
		sed -i "s|__LUKS_UUID__|${LUKS_UUID}|g" "$target/etc/initcpio/hooks/telegram-unlock"
		log::info "Telegram unlock hook installed"
		return 0
	fi

	log::info "Настройка LUKS remote SSH unlock (sd-tinyssh)..."

	arch-chroot "$target" pacman -Sy --noconfirm tinyssh 2>&1 || true

	mkdir -p "$target/etc/tinyssh"
	if [[ -z "$(ls -A "$target/etc/tinyssh" 2>/dev/null)" ]]; then
		arch-chroot "$target" tinysshd-makekey "$target/etc/tinyssh/sshkeydir" 2>&1 || true
	fi

	if [[ -d "$target/root/.ssh" ]]; then
		cp "$target/root/.ssh/authorized_keys" "$target/etc/tinyssh/root_key" 2>/dev/null || true
	fi

	local aur_pkg_url="${BUILD_AUR_PKG_URL:-}"
	if [[ -n "$aur_pkg_url" ]]; then
		log::info "Downloading pre-built mkinitcpio-systemd-extras..."
		arch-chroot "$target" bash -c "curl -fL $aur_pkg_url -o /tmp/mkinitcpio-systemd-extras.pkg.tar.zst && pacman -U --noconfirm /tmp/mkinitcpio-systemd-extras.pkg.tar.zst" 2>&1 ||
			log::warn "mkinitcpio-systemd-extras installation failed — remote SSH unlock may not work"
	fi

	log::info "LUKS remote unlock configured"
}
