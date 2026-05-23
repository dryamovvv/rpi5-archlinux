#!/bin/bash
# lib/template.sh

# 1. Инициализация окружения
set -e          # Остановить выполнение при любой ошибке
set -o pipefail # Считать ошибкой сбой в любой части пайпа (A | B)

# Защита от повторного импорта
if [[ -n "${_LIB_DISK_LOADED:-}" ]]; then
    return
fi
readonly _LIB_DISK_LOADED=1

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/log.sh"

CURRENT_LOOP_DEV=""
CURRENT_IMAGE_PATH=""
# shellcheck disable=SC2034
RESOLVED_PARTITION_PATH=""

disk::partition_device_path() {
    local loop_dev="$1"
    local partition_number="$2"

    log::assert_not_empty "$loop_dev" "loop device"
    log::assert_not_empty "$partition_number" "partition number"

    printf '%sp%s\n' "$loop_dev" "$partition_number"
}

disk::refresh_loop_partitions() {
    log::assert_not_empty "$CURRENT_LOOP_DEV" "current loop device"
    log::assert_not_empty "$CURRENT_IMAGE_PATH" "current image path"

    log::warn "Разделы не появились после partprobe, переподключаем loop-устройство..."

    losetup -d "$CURRENT_LOOP_DEV"
    CURRENT_LOOP_DEV=$(losetup --find -P --show "$CURRENT_IMAGE_PATH")

    if [[ -z "$CURRENT_LOOP_DEV" ]]; then
        log::die "Не удалось переподключить loop-устройство."
    fi

    udevadm settle
    log::info "Loop-устройство переподключено: $CURRENT_LOOP_DEV"
}

disk::resolve_partition_path() {
    local loop_dev="$1"
    local partition_number="$2"
    local part_path=""
    local attempt

    log::assert_not_empty "$loop_dev" "loop device"
    log::assert_not_empty "$partition_number" "partition number"

    for attempt in 1 2; do
        part_path="$(disk::partition_device_path "$CURRENT_LOOP_DEV" "$partition_number")"
        if [[ -e "$part_path" ]]; then
            # shellcheck disable=SC2034
            RESOLVED_PARTITION_PATH="$part_path"
            return 0
        fi

        partprobe "$CURRENT_LOOP_DEV"
        partx -u "$CURRENT_LOOP_DEV"
        udevadm settle

        part_path="$(disk::partition_device_path "$CURRENT_LOOP_DEV" "$partition_number")"
        if [[ -e "$part_path" ]]; then
            # shellcheck disable=SC2034
            RESOLVED_PARTITION_PATH="$part_path"
            return 0
        fi

        if [[ $attempt -eq 1 ]]; then
            disk::refresh_loop_partitions
        fi
    done

    log::die "Не удалось обнаружить раздел ${partition_number} для $CURRENT_LOOP_DEV"
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

    # Логика создания пустого файла и разметки (через dd, parted)
    log::info "Создание образа $img_path размером $size..."
    fallocate -l "$size" "$img_path"
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
        log::die "Не удалось смонтироваться раздел $part в $target"
    fi
}

disk::cleanup() {
    local mount_point="$1"

    log::assert_not_empty "$mount_point" "источник монтирования"

    if sync; then
        log::info "Запись данных на раздел $mount_point заверешна"
    else
        log::die "Не удалось завершить запись на раздел $mount_point"
    fi

    if [[ -n "$mount_point" ]] && mountpoint -q "$mount_point"; then
        log::info "Размонтирование $mount_point..."

        # 1. Пытаемся размонтировать рекурсивно
        # -R размонтирует все вложенные системы (proc, sys, dev)
        if ! umount -R "$mount_point" 2>/dev/null; then
            log::warn "Стандартное размонтирование не удалось, применяем силу..."
            # 2. Убиваем процессы, которые держат папку (требует psmisc / fuser)
            PID=$(fuser -m "$mount_point" 2>/dev/null)
            kill "$PID"
            sleep 1

            # 3. Ленивое размонтирование (отключает ФС немедленно, очищает позже)
            umount -R "$mount_point" 2>/dev/null || true
        fi
    fi

    if [[ -n "$CURRENT_LOOP_DEV" ]]; then
        log::info "Отключение устройства $CURRENT_LOOP_DEV..."
        # Ждем секунду, чтобы ядро успело освободить дескрипторы
        sleep 1
        losetup -d "$CURRENT_LOOP_DEV" 2>/dev/null ||
            log::warn "Не удалось освободить $CURRENT_LOOP_DEV (возможно, занято ядром)"
        CURRENT_LOOP_DEV=""
    fi
}
