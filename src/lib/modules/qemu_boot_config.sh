#!/bin/bash

if [[ -n "${_LIB_MODULE_QEMU_BOOT_CONFIG_LOADED:-}" ]]; then
    return
fi
readonly _LIB_MODULE_QEMU_BOOT_CONFIG_LOADED=1

qemu_boot_config::register() {
    steps::add "export_qemu_boot" "qemu_boot_config::export_boot_artifacts" "Export kernel and initramfs for QEMU direct boot"
    steps::add "finalize_qemu_artifacts" "qemu_boot_config::finalize_artifact_permissions" "Make QEMU artifacts readable by the invoking user"
}

qemu_boot_config::find_first_existing() {
    local candidate=""

    for candidate in "$@"; do
        if [[ -s "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

qemu_boot_config::export_boot_artifacts() {
    local kernel_source=""
    local initramfs_source=""

    log::assert_not_empty "$BUILD_MOUNT_BOOT" "QEMU boot source directory"
    log::assert_not_empty "$BUILD_QEMU_BOOT_DIR" "QEMU boot export directory"

    mkdir -p "$BUILD_QEMU_BOOT_DIR"

    kernel_source="$(
        qemu_boot_config::find_first_existing \
            "$BUILD_MOUNT_BOOT/Image" \
            "$BUILD_MOUNT_BOOT/vmlinuz-linux-aarch64" \
            "$BUILD_MOUNT_BOOT/vmlinuz-linux"
    )" || log::die "QEMU kernel was not found in $BUILD_MOUNT_BOOT"

    initramfs_source="$(
        qemu_boot_config::find_first_existing \
            "$BUILD_MOUNT_BOOT/initramfs-linux.img" \
            "$BUILD_MOUNT_BOOT/initramfs-linux-aarch64.img"
    )" || log::die "QEMU initramfs was not found in $BUILD_MOUNT_BOOT"

    cp "$kernel_source" "$BUILD_QEMU_BOOT_DIR/Image"
    cp "$initramfs_source" "$BUILD_QEMU_BOOT_DIR/initramfs-linux.img"
    printf '%s\n' "$BUILD_QEMU_KERNEL_CMDLINE" >"$BUILD_QEMU_BOOT_DIR/cmdline.txt"
}

qemu_boot_config::finalize_artifact_permissions() {
    chmod a+rw "$BUILD_IMAGE_PATH"
    chmod a+r "$BUILD_QEMU_BOOT_DIR/Image" "$BUILD_QEMU_BOOT_DIR/initramfs-linux.img" "$BUILD_QEMU_BOOT_DIR/cmdline.txt"
}
