#!/bin/bash
# scripts/main.sh
# Основной скрипт для сборки Arch Linux образа для Raspberry Pi 5
# shdoc
# @summary Основной скрипт для сборки Arch Linux образа для Raspberry Pi 5
# @description
# Этот скрипт автоматизирует процесс создания загрузочного образа Arch Linux
# для Raspberry Pi 5, включая создание образа, разметку, форматирование
# и монтирование.
# @author
# @version 1.0
# @license MIT
#
# @usage
# ./scripts/main.sh
#
# @requires
# - root права для выполнения операций с дисками
# - утилиты: losetup, parted, mkfs.ext4, mount
# @provides
# - arch_root.img - готовый образ Arch Linux
# @exitcode 0 Успешное завершение
# @exitcode 1 Ошибка при выполнении
# @exitcode 2 Прервано пользователем
# shdoc
# 1. Инициализация окружения
set -e          # Остановить выполнение при любой ошибке
set -o pipefail # Считать ошибкой сбой в любой части пайпа (A | B)
# Определяем корень проекта
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly PROJECT_ROOT
readonly LIB_DIR="$PROJECT_ROOT/lib"
# Импортируем логгер
# shellcheck disable=SC1091
source "$LIB_DIR/log.sh"
# Импортируем disk.sh
# shellcheck disable=SC1091
source "$LIB_DIR/disk.sh"
# Импортируем bootstrap.sh
# shellcheck disable=SC1091
source "$LIB_DIR/bootstrap.sh"
# Конфигурация образа
readonly IMG="$PROJECT_ROOT/arch_root.img" # Имя выходного файла образа
readonly IMG_SIZE="4g"               # Размер образа (4 гигабайта)
readonly MNT_ROOT="/mnt/arch_build"       # Точка монтирования для работы с образом
readonly MNT_BOOT="$MNT_ROOT/boot"
readonly SUDO_USER="dryam"
readonly SSH_USER="$SUDO_USER"
readonly TIME_ZONE="Europe/Moscow"
readonly NEW_HOOKS="HOOKS=(base systemd autodetect  modconf kms keyboard keymap sd-vconsole block filesystems fsck)"
# 2. Перехват прерывания (Ctrl+C) или ошибки
# Функция cleanup::run должна быть описана в lib/cleanup.sh
#trap 'cleanup::run' EXIT SIGINT SIGTERM
# Устанавливаем обработчик сигналов для очистки ресурсов при завершении
# Это гарантирует, что точка монтирования будет очищена даже при ошибке или прерывании
# trap 'disk::cleanup "$MNT"' EXIT SIGINT SIGTERM
# @function step_prepare
# @summary Подготовка - создание пустого файла образа
# @description
# Создает пустой файл образа заданного размера, который будет использоваться
# для установки Arch Linux.
# @exitcode 0 Успешное создание образа
# @exitcode 1 Ошибка при создании образа
step_prepare() {
    disk::create_image "$IMG" "$IMG_SIZE"
}
# @function step_mount
# @summary Монтирование - форматирование и монтирование раздела
# @description
# Создает loop устройство, форматирует раздел в ext4 и монтирует его
# в указанную точку монтирования для дальнейшей работы.
# @exitcode 0 Успешное монтирование
# @exitcode 1 Ошибка при монтировании
step_map_loop() {
    # Создаем loop устройство для работы с образом как с блочным устройством
    disk::map_loop "$IMG"
}
# @function step_partition
# @summary Разметка - создание раздела на образе
# @description
# Выполняет разметку диска, создавая один основной раздел, занимающий
# все доступное пространство.
# @exitcode 0 Успешная разметка
# @exitcode 1 Ошибка при разметке
step_partition() {
    # Теперь CURRENT_LOOP_DEV установлена внутри модуля disk.sh
    disk::partition_simple "${CURRENT_LOOP_DEV}"
}
step_create_fs(){
    local part_boot
    local part_root
    disk::resolve_partition_path "$CURRENT_LOOP_DEV" 1
    part_boot="$RESOLVED_PARTITION_PATH"
    disk::resolve_partition_path "$CURRENT_LOOP_DEV" 2
    part_root="$RESOLVED_PARTITION_PATH"
    disk::format_partition "$part_boot" "vfat"
    disk::format_partition "$part_root" "ext4"
}
step_mount_fs(){
    local part_boot
    local part_root
    disk::resolve_partition_path "$CURRENT_LOOP_DEV" 1
    part_boot="$RESOLVED_PARTITION_PATH"
    disk::resolve_partition_path "$CURRENT_LOOP_DEV" 2
    part_root="$RESOLVED_PARTITION_PATH"
    disk::mount_target "$part_root"  "$MNT_ROOT"
    disk::mount_target "$part_boot"  "$MNT_BOOT"
}

step_before_pacstrap(){
    bootstrap::fix_vconsole "$MNT_ROOT"
}

step_pacstrap() {
    bootstrap::install_base "$MNT_ROOT"
    bootstrap::generate_fstab "$MNT_ROOT"
}

step_setup(){
    bootstrap::fix_locale_conf "$MNT_ROOT"
    bootstrap::locale_gen_file "$MNT_ROOT"
    bootstrap::systemd_firstboot "$MNT_ROOT" "$TIME_ZONE" "root"
    bootstrap::firstboot_service "$MNT_ROOT" "$SUDO_USER" "$SUDO_USER"
    bootstrap::cmdline_txt "$MNT_BOOT"
    bootstrap::config_txt "$MNT_BOOT"
    bootstrap::mkinitcpio_conf "$MNT_ROOT" "$NEW_HOOKS"
    bootstrap::network "$MNT_ROOT"
    bootstrap::sshd "$MNT_ROOT" "$SSH_USER"
    bootstrap::zram "$MNT_ROOT"
    bootstrap::cpu_boost "$MNT_ROOT"
    bootstrap::wifi_regdom "$MNT_ROOT"
    bootstrap::resize_root "$MNT_ROOT"
}


# 3. Список этапов сборки
# Массив позволяет легко добавлять/удалять шаги и управлять порядком выполнения
readonly STEPS=(
    "step_prepare"
    "step_map_loop"
    "step_partition"
    "step_create_fs"
    "step_mount_fs"
    "step_before_pacstrap"
    "step_pacstrap"
    "step_setup"
)
# Проверка прав доступа - скрипт должен запускаться с правами root
    if [[ $EUID -ne 0 ]]; then
        log::warn "Скрипту требуются права root. Пытаюсь повысить привилегии..."
        exec sudo -E "$0" "$@"
    fi
# @function main
# @summary Основная функция скрипта
# @description
# Оркестрирует процесс сборки образа, выполняя все этапы последовательно
# и обрабатывая ошибки.
# @arg $@ Все аргументы командной строки
# @exitcode 0 Успешное завершение сборки
# @exitcode 1 Ошибка на одном из этапов
# @exitcode 2 Прервано пользователем
main() {
    log::info "Начало сборки Arch Linux образа..."
    # Выполняем все этапы сборки последовательно
    for step in "${STEPS[@]}"; do
        log::info "Выполнение этапа: $step"
        # Вызываем функцию из соответствующего модуля
        if $step; then
            log::success "Этап $step завершен успешно."
        else
            log::error "Критическая ошибка на этапе $step"
            exit 1
        fi
    done
    log::success "Сборка образа завершена успешно!"
}
# Запуск основной функции с передачей всех аргументов
main "$@"
