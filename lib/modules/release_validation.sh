#!/bin/bash

if [[ -n "${_LIB_MODULE_RELEASE_VALIDATION_LOADED:-}" ]]; then
    return
fi
readonly _LIB_MODULE_RELEASE_VALIDATION_LOADED=1

release_validation::register() {
    steps::add "validate_boot_files" "release_validation::validate_boot_partition" "Validate required Raspberry Pi boot files"
}

release_validation::required_boot_files() {
    printf '%s\n' \
        "kernel8.img" \
        "initramfs-linux.img" \
        "bcm2712-rpi-5-b.dtb" \
        "config.txt" \
        "cmdline.txt"
}

release_validation::validate_boot_files() {
    local boot_dir="$1"
    local boot_file=""
    local boot_path=""

    log::assert_not_empty "$boot_dir" "boot directory"
    [[ -d "$boot_dir" ]] || log::die "Boot directory is missing: $boot_dir"

    while IFS= read -r boot_file; do
        boot_path="$boot_dir/$boot_file"

        [[ -e "$boot_path" ]] || log::die "Missing boot file: $boot_file"
        [[ -s "$boot_path" ]] || log::die "Empty boot file: $boot_file"
    done < <(release_validation::required_boot_files)
}

release_validation::validate_boot_partition() {
    release_validation::validate_boot_files "$BUILD_MOUNT_BOOT"
}
