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

    disk::resolve_partition_path "$CURRENT_LOOP_DEV" 1
    part_boot="$RESOLVED_PARTITION_PATH"
    disk::resolve_partition_path "$CURRENT_LOOP_DEV" 2
    part_root="$RESOLVED_PARTITION_PATH"

    disk::format_partition "$part_boot" "vfat"
    disk::format_partition "$part_root" "ext4"
}

disk_image::mount_filesystems() {
    local part_boot=""
    local part_root=""

    disk::resolve_partition_path "$CURRENT_LOOP_DEV" 1
    part_boot="$RESOLVED_PARTITION_PATH"
    disk::resolve_partition_path "$CURRENT_LOOP_DEV" 2
    part_root="$RESOLVED_PARTITION_PATH"

    disk::mount_target "$part_root" "$BUILD_MOUNT_ROOT"
    disk::mount_target "$part_boot" "$BUILD_MOUNT_BOOT"
}
