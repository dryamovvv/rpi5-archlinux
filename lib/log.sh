#!/bin/bash
# lib/logger.sh

# Защита от повторного импорта
if [[ -n "${_LIB_LOGGER_LOADED:-}" ]]; then
    return
fi
readonly _LIB_LOGGER_LOADED=1

# Определяем папку, где лежит этот файл модуля
MODULE_DISK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly MODULE_DISK_DIR

# Импортируем цвета, используя путь относительно текущего модуля
# shellcheck disable=SC1091
source "$MODULE_DISK_DIR/colors.sh"

# Внутренняя функция для форматирования (не предназначена для вызова снаружи)
_log_base() {
    local level_color="$1"
    local level_name="$2"
    local message="$3"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    echo -e "${C_GRAY}[$timestamp]${C_RESET} ${level_color}${C_BOLD}[${level_name}]${C_RESET} $message"
}

# Публичные функции модуля
log::info() {
    _log_base "$C_BLUE" "INFO" "$1"
}

log::success() {
    _log_base "$C_GREEN" "OK  " "$1"
}

log::warn() {
    _log_base "$C_YELLOW" "WARN" "$1"
}

log::error() {
    # Ошибки выводим в stderr (поток 2)
    _log_base "$C_RED" "FAIL" "$1" >&2
}

# Завершить работу с ошибкой
log::die() {
    log::error "$1"
    exit 1
}

# Проверка: если переменная пуста, остановить скрипт
# Аргументы: $1 - значение, $2 - имя переменной для сообщения
log::assert_not_empty() {
    if [[ -z "$1" ]]; then
        log::die "Критическая ошибка: аргумент '$2' не указан в функции ${FUNCNAME[1]}"
    fi
}
