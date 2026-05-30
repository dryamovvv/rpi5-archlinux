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

config::load_default() {
	local config_path="$1"

	log::assert_not_empty "$config_path" "config path"

	if declare -F config::load_embedded_default >/dev/null; then
		config::load_embedded_default
		return 0
	fi

	config::load "$config_path"
}

config::select_qemu() {
	BUILD_IMAGE_PATH="${BUILD_QEMU_IMAGE_PATH:-$BUILD_PROJECT_ROOT/dist/images/archlinux-qemu-aarch64.img}"
	BUILD_MOUNT_ROOT="${BUILD_QEMU_MOUNT_ROOT:-/mnt/arch_qemu_build}"
	BUILD_MOUNT_BOOT="$BUILD_MOUNT_ROOT/boot"
	BUILD_MKINITCPIO_HOOKS="${BUILD_QEMU_MKINITCPIO_HOOKS:-$BUILD_MKINITCPIO_HOOKS}"
	BUILD_QEMU_BOOT_DIR="${BUILD_QEMU_BOOT_DIR:-$BUILD_PROJECT_ROOT/dist/images/qemu-boot}"
	BUILD_QEMU_CPU="${BUILD_QEMU_CPU:-cortex-a72}"
	BUILD_QEMU_SMP="${BUILD_QEMU_SMP:-4}"
	BUILD_QEMU_MEMORY="${BUILD_QEMU_MEMORY:-2048}"
	BUILD_QEMU_SSH_HOST_PORT="${BUILD_QEMU_SSH_HOST_PORT:-2222}"
	BUILD_QEMU_KERNEL_CMDLINE="${BUILD_QEMU_KERNEL_CMDLINE:-root=/dev/vda2 rw rootwait console=ttyAMA0}"
	BUILD_QEMU_ROOTFLAGS="${BUILD_QEMU_ROOTFLAGS:-}"

	if [[ "${BUILD_FILESYSTEM:-ext4}" == "btrfs" ]] && [[ -z "$BUILD_QEMU_ROOTFLAGS" ]]; then
		BUILD_QEMU_ROOTFLAGS="subvol=@"
	fi

	if declare -p BUILD_QEMU_MODULES >/dev/null 2>&1; then
		BUILD_MODULES=("${BUILD_QEMU_MODULES[@]}")
	else
		BUILD_MODULES=(
			"disk_image"
			"base_system"
			"qemu_boot_config"
			"services"
		)
	fi

	if declare -p BUILD_QEMU_PACKAGES >/dev/null 2>&1; then
		BUILD_PACKAGES=("${BUILD_QEMU_PACKAGES[@]}")
	else
		BUILD_PACKAGES=(
			"base"
			"archlinuxarm-keyring"
			"pacman-mirrorlist"
			"linux-aarch64"
			"sudo"
			"openssh"
		)
	fi

	if [[ "${BUILD_FILESYSTEM:-ext4}" == "btrfs" ]]; then
		BUILD_PACKAGES+=("btrfs-progs" "snapper" "snap-pac")
	fi
}

config::validate() {
	BUILD_FILESYSTEM="${BUILD_FILESYSTEM:-ext4}"
	BUILD_IMAGE_SHRINK_MARGIN="${BUILD_IMAGE_SHRINK_MARGIN:-256M}"

	if [[ "$BUILD_FILESYSTEM" != "ext4" && "$BUILD_FILESYSTEM" != "btrfs" ]]; then
		log::die "BUILD_FILESYSTEM must be 'ext4' or 'btrfs', got: '$BUILD_FILESYSTEM'"
	fi

	local required_values=(
		"${BUILD_IMAGE_PATH:-}"
		"${BUILD_IMAGE_SIZE:-}"
		"${BUILD_IMAGE_SHRINK_MARGIN:-}"
		"${BUILD_MOUNT_ROOT:-}"
		"${BUILD_MOUNT_BOOT:-}"
		"${BUILD_MKINITCPIO_HOOKS:-}"
		"${BUILD_SSH_USER:-}"
	)
	local value=""

	for value in "${required_values[@]}"; do
		[[ -n "$value" ]] || log::die "Required build config value is empty"
	done

	if [[ ! -f "${BUILD_PACMAN_CONF:-}" ]] && ! assets::has_embedded "pacman/pacman-arm.conf"; then
		log::die "Required pacman config is missing"
	fi

	((${#BUILD_MODULES[@]} > 0)) || log::die "BUILD_MODULES must not be empty"
	((${#BUILD_PACKAGES[@]} > 0)) || log::die "BUILD_PACKAGES must not be empty"

	if [[ "${BUILD_ENABLE_ZRAM:-0}" == "1" ]] && [[ -z "${BUILD_ZRAM_SIZE:-}" ]]; then
		log::warn "BUILD_ZRAM_SIZE is empty, zram-generator will use default"
	fi

	if [[ -n "${BUILD_SWAPFILE_SIZE:-}" ]] && ! [[ "$BUILD_SWAPFILE_SIZE" =~ ^[0-9]+[gGmMkK]?$ ]]; then
		log::die "BUILD_SWAPFILE_SIZE must be a valid size (e.g. 16g, 2g, 512m)"
	fi
}
