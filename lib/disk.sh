#!/bin/bash

set -euo pipefail

# Защита от повторного импорта
if [[ -n "${_LIB_DISK_LOADED:-}" ]]; then
    return
fi
readonly _LIB_DISK_LOADED=1

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/log.sh"

CURRENT_LOOP_DEV=""
CURRENT_IMAGE_PATH=""
RESOLVED_PARTITION_PATH=""
declare -Ag PARTITION_LOOP_DEVS=()

disk::partition_device_path() {
    local loop_dev="$1"
    local partition_number="$2"

    log::assert_not_empty "$loop_dev" "loop device"
    log::assert_not_empty "$partition_number" "partition number"

    printf '%sp%s\n' "$loop_dev" "$partition_number"
}

disk::partition_layout() {
    local loop_dev="$1"
    local partition_number="$2"
    local partition_line=""
    local start_sector=""
    local size_sectors=""
    local sector_size=""

    log::assert_not_empty "$loop_dev" "loop device"
    log::assert_not_empty "$partition_number" "partition number"

    partition_line="$(sfdisk --dump "$loop_dev" | grep "^${loop_dev}p${partition_number}[[:space:]]*:")"
    if [[ -z "$partition_line" ]]; then
        log::die "Не удалось прочитать разметку для раздела ${partition_number} устройства $loop_dev"
    fi

    start_sector="$(sed -E 's/.*start=[[:space:]]*([0-9]+).*/\1/' <<<"$partition_line")"
    size_sectors="$(sed -E 's/.*size=[[:space:]]*([0-9]+).*/\1/' <<<"$partition_line")"
    sector_size="$(blockdev --getss "$loop_dev")"

    printf '%s %s %s\n' "$start_sector" "$size_sectors" "$sector_size"
}

disk::attach_partition_loop() {
    local partition_number="$1"
    local start_sector=""
    local size_sectors=""
    local sector_size=""
    local offset_bytes=""
    local size_bytes=""
    local partition_loop_dev=""
    local layout=""

    log::assert_not_empty "$CURRENT_LOOP_DEV" "current loop device"
    log::assert_not_empty "$CURRENT_IMAGE_PATH" "current image path"
    log::assert_not_empty "$partition_number" "partition number"

    if [[ -n "${PARTITION_LOOP_DEVS[$partition_number]:-}" ]]; then
        RESOLVED_PARTITION_PATH="${PARTITION_LOOP_DEVS[$partition_number]}"
        return 0
    fi

    layout="$(disk::partition_layout "$CURRENT_LOOP_DEV" "$partition_number")"
    read -r start_sector size_sectors sector_size <<<"$layout"

    offset_bytes=$((start_sector * sector_size))
    size_bytes=$((size_sectors * sector_size))

    partition_loop_dev="$(
        losetup --find --show \
            --offset "$offset_bytes" \
            --sizelimit "$size_bytes" \
            "$CURRENT_IMAGE_PATH"
    )"

    if [[ -z "$partition_loop_dev" ]]; then
        log::die "Не удалось создать loop-устройство для раздела ${partition_number}"
    fi

    PARTITION_LOOP_DEVS[$partition_number]="$partition_loop_dev"
    # shellcheck disable=SC2034
    RESOLVED_PARTITION_PATH="$partition_loop_dev"
    log::info "Создано loop-устройство раздела ${partition_number}: $partition_loop_dev"
}

disk::resolve_partition_path() {
    local loop_dev="$1"
    local partition_number="$2"
    local part_path=""

    log::assert_not_empty "$loop_dev" "loop device"
    log::assert_not_empty "$partition_number" "partition number"

    part_path="$(disk::partition_device_path "$loop_dev" "$partition_number")"
    if [[ -e "$part_path" ]]; then
        # shellcheck disable=SC2034
        RESOLVED_PARTITION_PATH="$part_path"
        return 0
    fi

    partprobe "$loop_dev"
    partx -u "$loop_dev"
    udevadm settle

    part_path="$(disk::partition_device_path "$loop_dev" "$partition_number")"
    if [[ -e "$part_path" ]]; then
        # shellcheck disable=SC2034
        RESOLVED_PARTITION_PATH="$part_path"
        return 0
    fi

    log::warn "Разделы не появились после partprobe, создаем отдельное loop-устройство для раздела ${partition_number}..."
    disk::attach_partition_loop "$partition_number"
}

disk::create_image() {
    local img_path="$1"
    local size="$2"

    log::assert_not_empty "$img_path" "путь к образу"
    log::assert_not_empty "$size" "размер образа"

    if test -f "$img_path"; then
        log::warn "$img_path уже присутствует в системе"
        if mv "$img_path" "$img_path.bak"; then
            log::info "Файл $img_path перемещен в $img_path.bak"
        else
            log::die "Не удалось переместить $img_path в $img_path.bak"

        fi
    fi

    # Используем sparse-файл, чтобы не тратить место хоста на пустые блоки.
    log::info "Создание образа $img_path размером $size..."
    truncate -s "$size" "$img_path"
}

disk::partition_simple() {
    local target="$1"
    log::assert_not_empty "$target" "целевое устройство/файл"

    log::info "Создание таблицы разделов GPT на $target..."

    {
        echo "label: gpt"
        # 1-й раздел: 512МБ, Тип: EFI System Partition
        echo "size=512M, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B"
        # 2-й раздел: все остальное, Тип: Linux Root (ARM-64)
        echo "type=B921B045-1DF0-41C3-AF44-4C6F280D3FAE"
    } | sfdisk --force --wipe always --wipe-partitions always --quiet "$target" &>/dev/null

    partprobe "$target"
}

disk::map_loop() {
    local img_path="$1"
    log::assert_not_empty "$img_path" "путь к образу"

    log::info "Подключение $img_path к loop-устройства..."
    # -P читает таблицу разделов и создает /dev/loopXp1
    CURRENT_LOOP_DEV=$(losetup --find -P --show "$img_path")
    CURRENT_IMAGE_PATH="$img_path"

    if [[ -z "$CURRENT_LOOP_DEV" ]]; then
        log::die "Не удалось создать loop-устройство."
    fi
    log::success "$img_path подключен к устройству: $CURRENT_LOOP_DEV"
}

disk::format_partition() {
    local part="$1"
    local fs_type="$2" # По умолчанию ext4

    log::assert_not_empty "$part" "раздел для форматирования"

    log::info "Форматирование $part в $fs_type..."
    if [[ "$fs_type" == "vfat" ]]; then
        if mkfs.vfat -F32 -n BOOT "$part" >/dev/null; then
            log::info "Раздел $part отформатирован в $fs_type"
        else
            log::die "Не удалось отформатировать раздел $part в $fs_type"
        fi
    elif [[ "$fs_type" == "ext4" ]] >/dev/null; then
        if mkfs.ext4 -q -L Archlinux "$part"; then
            log::info "Раздел $part отформатирован в $fs_type"
        else
            log::die "Не удалось отформатировать раздел $part в $fs_type"
        fi
    fi

    if udevadm settle; then
        log::info "Информация о новом разделе $part сохранена"
    else
        log::die "Не удалось сохранить информацию о разделе $part"
    fi

    if sync; then
        log::info "Запись данных на раздел $part заверешна"
    else
        log::die "Не удалось завершить запись на раздел $part"
    fi

    return 0
}

disk::mount_target() {
    local source="$1"
    local target="$2"

    log::assert_not_empty "$source" "источник монтирования"
    log::assert_not_empty "$target" "точка монтирования"

    if [[ ! -d "$target" ]]; then
        mkdir -p "$target"
    fi

    if mount "$source" "$target"; then
        log::info "Смонтирован раздел $source в $target"
    else
        log::die "Не удалось смонтировать раздел $source в $target"
    fi
}

disk::cleanup() {
    local mount_point="$1"
    local partition_loop_dev=""

    log::assert_not_empty "$mount_point" "источник монтирования"

    sync
    log::info "Запись данных на раздел $mount_point завершена"

    if [[ -n "$mount_point" ]] && mountpoint -q "$mount_point"; then
        log::info "Размонтирование $mount_point..."

        # -R размонтирует вложенные точки, включая boot-раздел.
        if ! umount -R "$mount_point" 2>/dev/null; then
            log::warn "Стандартное размонтирование не удалось, применяем силу..."
            # 2. Убиваем процессы, которые держат папку (требует psmisc / fuser)
            fuser -km "$mount_point" 2>/dev/null || true
            sleep 1

            # 3. Ленивое размонтирование (отключает ФС немедленно, очищает позже)
            umount -R -l "$mount_point" 2>/dev/null || true
        fi
    fi

    sync

    for partition_loop_dev in "${PARTITION_LOOP_DEVS[@]:-}"; do
        if [[ -n "$partition_loop_dev" ]]; then
            log::info "Отключение устройства раздела $partition_loop_dev..."
            losetup -d "$partition_loop_dev" 2>/dev/null ||
                log::warn "Не удалось освободить $partition_loop_dev"
        fi
    done
    PARTITION_LOOP_DEVS=()

    if [[ -n "$CURRENT_LOOP_DEV" ]]; then
        log::info "Отключение устройства $CURRENT_LOOP_DEV..."
        # Ждем секунду, чтобы ядро успело освободить дескрипторы
        sleep 1
        losetup -d "$CURRENT_LOOP_DEV" 2>/dev/null ||
            log::warn "Не удалось освободить $CURRENT_LOOP_DEV (возможно, занято ядром)"
        CURRENT_LOOP_DEV=""
    fi
}
