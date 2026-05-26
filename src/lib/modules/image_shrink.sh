#!/bin/bash

if [[ -n "${_LIB_MODULE_IMAGE_SHRINK_LOADED:-}" ]]; then
    return
fi
readonly _LIB_MODULE_IMAGE_SHRINK_LOADED=1

image_shrink::register() {
    steps::add "shrink_image" "image_shrink::shrink" "Shrink image to the minimum useful size"
}

image_shrink::shrink() {
    if [[ "${BUILD_FILESYSTEM:-ext4}" == "btrfs" ]]; then
        log::info "Btrfs: пропускаем shrink (не поддерживается)"
        return 0
    fi
    disk::shrink_image "$BUILD_IMAGE_PATH" "$CURRENT_LOOP_DEV" 2 "$BUILD_IMAGE_SHRINK_MARGIN"
}
