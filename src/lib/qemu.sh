#!/bin/bash

if [[ -n "${_LIB_QEMU_LOADED:-}" ]]; then
    return
fi
readonly _LIB_QEMU_LOADED=1

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/log.sh"

qemu::kernel_path() {
    printf '%s/Image\n' "$BUILD_QEMU_BOOT_DIR"
}

qemu::initramfs_path() {
    printf '%s/initramfs-linux.img\n' "$BUILD_QEMU_BOOT_DIR"
}

qemu::validate_artifacts() {
    [[ -f "$BUILD_IMAGE_PATH" ]] || log::die "QEMU image is missing: $BUILD_IMAGE_PATH"
    [[ -s "$BUILD_IMAGE_PATH" ]] || log::die "QEMU image is empty: $BUILD_IMAGE_PATH"
    [[ -s "$(qemu::kernel_path)" ]] || log::die "QEMU kernel is missing: $(qemu::kernel_path)"
    [[ -s "$(qemu::initramfs_path)" ]] || log::die "QEMU initramfs is missing: $(qemu::initramfs_path)"
}

qemu::command() {
    local qemu_cmdline="$BUILD_QEMU_KERNEL_CMDLINE"
    if [[ -n "${BUILD_QEMU_ROOTFLAGS:-}" ]]; then
        qemu_cmdline="$qemu_cmdline rootflags=$BUILD_QEMU_ROOTFLAGS"
    fi
    printf 'qemu-system-aarch64'
    printf ' %q' \
        -M virt \
        -cpu "$BUILD_QEMU_CPU" \
        -smp "$BUILD_QEMU_SMP" \
        -m "$BUILD_QEMU_MEMORY" \
        -nographic \
        -kernel "$(qemu::kernel_path)" \
        -initrd "$(qemu::initramfs_path)" \
        -append "$qemu_cmdline" \
        -drive "file=$BUILD_IMAGE_PATH,format=raw,if=virtio" \
        -netdev "user,id=net0,hostfwd=tcp::$BUILD_QEMU_SSH_HOST_PORT-:22" \
        -device "virtio-net-pci,netdev=net0"
    printf '\n'
}

qemu::run() {
    local command_line=""

    if ((RUNNER_DRY_RUN)); then
        qemu::command
        return 0
    fi

    deps::validate_qemu_commands

    qemu::validate_artifacts
    command_line="$(qemu::command)"
    log::info "Starting QEMU. SSH will be forwarded from localhost:$BUILD_QEMU_SSH_HOST_PORT to guest port 22."
    eval "$command_line"
}
