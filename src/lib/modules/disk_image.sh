#!/bin/bash

if [[ -n "${_LIB_MODULE_DISK_IMAGE_LOADED:-}" ]]; then
    return
fi
readonly _LIB_MODULE_DISK_IMAGE_LOADED=1

disk_image::register() {
    steps::add "prepare_image" "disk_image::prepare" "Create sparse image file"
    steps::add "map_loop" "disk_image::map_loop" "Attach image to a loop device"
    steps::add "partition_image" "disk_image::partition" "Create image partition table"
    steps::add "create_filesystems" "disk_image::create_filesystems" "Format boot and root filesystems"
    steps::add "mount_filesystems" "disk_image::mount_filesystems" "Mount image filesystems"
}

disk_image::prepare() {
    disk::create_image "$BUILD_IMAGE_PATH" "$BUILD_IMAGE_SIZE"
}

disk_image::map_loop() {
    disk::map_loop "$BUILD_IMAGE_PATH"
}

disk_image::partition() {
    disk::partition_simple "$CURRENT_LOOP_DEV"
}

disk_image::create_filesystems() {
    local part_boot=""
    local part_root=""
    local root_fs="${BUILD_FILESYSTEM:-ext4}"
    local temp_mount="/tmp/btrfs_temp_subvol"

    disk::resolve_partition_path "$CURRENT_LOOP_DEV" 1
    part_boot="$RESOLVED_PARTITION_PATH"
    disk::resolve_partition_path "$CURRENT_LOOP_DEV" 2
    part_root="$RESOLVED_PARTITION_PATH"

    disk::format_partition "$part_boot" "vfat"
    disk::format_partition "$part_root" "$root_fs"

    BUILD_ROOT_UUID="$(blkid -s UUID -o value "$part_root")"
    readonly BUILD_ROOT_UUID
    log::info "Root partition UUID: $BUILD_ROOT_UUID"

    if [[ "$root_fs" == "btrfs" ]]; then
        mkdir -p "$temp_mount"
        if mount "$part_root" "$temp_mount"; then
            disk::btrfs_subvol_create_all "$temp_mount"
            umount "$temp_mount"
        else
            log::die "Не удалось примонтировать btrfs для создания subvolumes"
        fi
    fi
}

disk_image::mount_filesystems() {
    local part_boot=""
    local part_root=""
    local root_fs="${BUILD_FILESYSTEM:-ext4}"

    disk::resolve_partition_path "$CURRENT_LOOP_DEV" 1
    part_boot="$RESOLVED_PARTITION_PATH"
    disk::resolve_partition_path "$CURRENT_LOOP_DEV" 2
    part_root="$RESOLVED_PARTITION_PATH"

    if [[ "$root_fs" == "btrfs" ]]; then
        disk::btrfs_mount_subvol_root "$part_root" "$BUILD_MOUNT_ROOT"
        mkdir -p "$BUILD_MOUNT_ROOT"/{home,.snapshots,swap,var/{log,cache,tmp,lib}}
        disk::btrfs_mount_subvol "$part_root" "@home" "$BUILD_MOUNT_ROOT/home" "compress=zstd,noatime"
        disk::btrfs_mount_subvol "$part_root" "@snapshots" "$BUILD_MOUNT_ROOT/.snapshots" "noatime"
        disk::btrfs_mount_subvol "$part_root" "@swap" "$BUILD_MOUNT_ROOT/swap" "noatime,nodatacow"
        disk::btrfs_mount_subvol "$part_root" "@var_log" "$BUILD_MOUNT_ROOT/var/log" "compress=zstd,noatime"
        disk::btrfs_mount_subvol "$part_root" "@var_cache" "$BUILD_MOUNT_ROOT/var/cache" "noatime,nodatacow"
        disk::btrfs_mount_subvol "$part_root" "@var_tmp" "$BUILD_MOUNT_ROOT/var/tmp" "noatime,nodatacow"
        disk::btrfs_mount_subvol "$part_root" "@var_lib" "$BUILD_MOUNT_ROOT/var/lib" "noatime,nodatacow"
    else
        disk::mount_target "$part_root" "$BUILD_MOUNT_ROOT"
    fi

    disk::mount_target "$part_boot" "$BUILD_MOUNT_BOOT"
}
