# TODO — План работ по улучшению rpi5-archlinux-image

> Версия: 2026-05-26, на основе `IMPROVEMENTS.md` и обсуждения

---

## Этап 1: Безопасность (Issue #4 + #1)

### 1.1 Убрать пароли из heredoc

**Сейчас:** пароль пользователя зашит в теле `firstboot.sh` открытым текстом, виден в `ps aux`.

**Решение:**
- Root-пароль уже задается через `systemd-firstboot --root-password="$BUILD_ROOT_PASSWORD"`
- Пользователь создается через `useradd`, пароль **не задается** — вместо этого `chage -d 0` обязывает сменить при первом логине
- `build.conf.example`: убрать `BUILD_USER_PASSWORD`, добавить комментарий

**Файлы:** `src/lib/bootstrap.sh` (функция `firstboot_service`), `build.conf.example`

### 1.2 SigLevel + HTTPS-зеркала

**Сейчас:** `SigLevel = Never`, зеркала HTTP.

**Решение:**
1. Заменить `http://` → `https://` в `src/conf/pacman/pacman-arm.conf`
2. `SigLevel = Required DatabaseOptional`
3. Перед `pacstrap` выполнить:
   ```bash
   pacman-key --init --root "$target"
   pacman-key --populate archlinuxarm --root "$target"
   ```

**Файлы:** `src/conf/pacman/pacman-arm.conf`, `src/lib/bootstrap.sh`

---

## Этап 2: Пакеты

### 2.1 Добавить в `BUILD_PACKAGES`

| Пакет | Зачем |
|-------|-------|
| `i2c-tools` | Отладка I2C (GPIO, HAT-ы) |
| `cpupower` | Управление CPU governor |
| `rng-tools` | Питание entropy-пула от HW RNG |
| `iptables-nft` | Базовый фаервол |
| `git` | Нужен всем |
| `man-db` `man-pages` | Man-страницы |
| `vim` | Редактор |
| `htop` | Мониторинг |
| `logrotate` | Ротация логов |
| `bash-completion` | Автодополнение |
| `tmux` | Терминальный мультиплексор |
| `wpa_supplicant` | Wi-Fi (на будущее) |
| `fail2ban` | Защита SSH |
| `avahi` | mDNS (.local-доступ) |

**Файлы:** `build.conf.example`

---

## Этап 3: Конфигурация системы

### 3.1 CPU Governor — `schedutil`

RPi5 big.LITTLE (4×A76 + 4×A55). `schedutil` — EAS-aware, экономит энергию без потери производительности.

```bash
# /etc/tmpfiles.d/cpu-governor.conf
w /sys/devices/system/cpu/cpufreq/policy0/scaling_governor - - - - schedutil
w /sys/devices/system/cpu/cpufreq/policy4/scaling_governor - - - - schedutil
```

**Файлы:** `src/lib/bootstrap.sh` (новая функция или расширение `cpu_boost`)

### 3.2 ZRAM — опционально

Сейчас жестко отключен через `disable_swap`. Добавить опцию:

```bash
# build.conf
BUILD_ENABLE_ZRAM=0   # 1 = включить systemd-zram-generator
```

При `BUILD_ENABLE_ZRAM=1` — не вызывать `disable_swap`, вместо этого:
```bash
cat <<EOF >"$target/etc/systemd/zram-generator.conf"
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOF
```

**Файлы:** `build.conf.example`, `src/lib/bootstrap.sh`, `src/lib/modules/services.sh`

### 3.3 SSH hardening

```bash
echo "PermitRootLogin no" >> "$target/etc/ssh/sshd_config"
echo "PasswordAuthentication yes" >> "$target/etc/ssh/sshd_config"  # пока не настроены ключи
```

**Файлы:** `src/lib/bootstrap.sh` (`bootstrap::sshd`)

### 3.4 mDNS через systemd-resolved (без avahi-демона)

В существующий `20-wired.network` добавить `MulticastDNS=yes`:
```ini
[Network]
DHCP=yes
MulticastDNS=yes
```

И в `/etc/systemd/resolved.conf`:
```ini
[Resolve]
MulticastDNS=yes
```

Пакет `avahi` не нужен — `systemd-resolved` сам регистрирует `arch-rpi5.local`.

**Файлы:** `src/lib/bootstrap.sh` (`bootstrap::network`)

### 3.5 fail2ban — настройка

Шаблон в `src/conf/fail2ban/sshd.conf`:
```ini
[sshd]
enabled = true
port = ssh
maxretry = 3
bantime = 3600
findtime = 600
```

Сервис включается при сборке:
```bash
bootstrap::systemd_enable_unit "$target" "fail2ban.service" "multi-user.target.wants"
```

**Файлы:** `src/conf/fail2ban/sshd.conf` (новый), `src/lib/modules/services.sh`, `src/lib/bootstrap.sh`

### 3.6 wpa_supplicant — предварительная настройка без привязки к сети

Добавить `wpa_supplicant` в пакеты. Сервис **не включать** по умолчанию. Добавить опцию:
```bash
BUILD_ENABLE_WIFI=0
```

При `BUILD_ENABLE_WIFI=1`:
- Включить `wpa_supplicant@wlan0.service`
- Добавить конфиг `/etc/wpa_supplicant/wpa_supplicant-wlan0.conf` (пустой, с комментарием)
- Убрать `dtoverlay=disable-wifi` из `config.txt`

**Файлы:** `build.conf.example`, `src/lib/bootstrap.sh`

---

## Этап 4: Рефакторинг firstboot

### 4.1 `ConditionFirstBoot=yes`

Заменить ручной `systemctl disable` + `rm -f` на нативный механизм systemd:

```ini
# rpi5-firstboot.service
[Unit]
ConditionFirstBoot=yes    # systemd сам пропустит после первого выполнения
```

Убрать из `firstboot.sh`:
```bash
systemctl disable rpi5-firstboot.service
rm -f /etc/systemd/system/multi-user.target.wants/rpi5-firstboot.service
```

### 4.2 `firstboot.sh` → минимальный

После замены самодеактивации и паролей, `firstboot.sh` сводится к:
```bash
#!/bin/bash
set -euo pipefail

# Создание пользователя (если еще нет)
if ! id -u "$BUILD_USER_NAME" >/dev/null 2>&1; then
    useradd -m -G wheel "$BUILD_USER_NAME"
    chage -d 0 "$BUILD_USER_NAME"   # смена пароля при первом логине
fi

# Локали
locale-gen >/dev/null

# Расширение раздела
if command -v systemd-repart >/dev/null 2>&1; then
    systemd-repart --dry-run=no
fi
systemctl restart systemd-growfs-root.service || true
```

### 4.3 Выделить `firstboot.sh` в `src/conf/`

Сейчас формируется heredoc'ом. Вынести в `src/conf/firstboot/rpi5-firstboot.sh` и копировать через `assets::write`.

**Файлы:** `src/conf/systemd/rpi5-firstboot.service`, `src/conf/firstboot/rpi5-firstboot.sh` (новый), `src/lib/bootstrap.sh`

---

## Этап 5: Репозиторий и CI

### 5.1 Тесты

| Тест | Что проверяет |
|------|---------------|
| `cmdline_uuid_test.sh` | Подстановка `__ROOT_UUID__` в `bootstrap::cmdline_txt` |
| `sudoers_test.sh` | `bootstrap::enable_wheel_sudo` — раскомментирование `%wheel` |
| `custom_unit_test.sh` | `bootstrap::systemd_enable_custom_unit` — симлинк в `/etc/systemd/system/` |

### 5.2 CI

- Добавить `deps::validate_build_commands` в CI-пайплайн
- Убрать глобальный `shellcheck disable=SC2034`, заменить на целевые директивы

### 5.3 README

Добавить секции:
- NVMe-загрузка (EEPROM `BOOT_ORDER`)
- Смена паролей при первом логине
- `--config PATH` для кастомных настроек

### 5.4 `build.conf.example`

Новые опции:
```bash
BUILD_ENABLE_ZRAM=0
BUILD_ENABLE_WIFI=0
BUILD_CPU_GOVERNOR="schedutil"   # schedutil | ondemand | performance
BUILD_FAIL2BAN_MAXRETRY=3
BUILD_FAIL2BAN_BANTIME=3600
BUILD_USER_PASSWORD=""           # оставить пустым — пользователь сменит при первом логине
```

---

## Этап 6: Документация

- [ ] `IMPROVEMENTS.md` → обновить после реализации
- [ ] `README.md` → дополнить секциями про NVMe, пароли, `--config`
- [ ] Закрыть issues #1, #4 после реализации

---

## Порядок выполнения

| Этап | Приоритет | Зависимости |
|------|-----------|-------------|
| 1.1 Пароли | 🔴 HIGH | нет |
| 1.2 HTTPS + SigLevel | 🔴 HIGH | нет |
| 2.1 Пакеты | 🟡 MEDIUM | нет |
| 3.1 schedutil | 🟡 MEDIUM | пакет `cpupower` |
| 3.2 ZRAM опционально | 🟡 MEDIUM | сборка `build.conf` |
| 3.3 SSH hardening | 🟡 MEDIUM | нет |
| 3.4 mDNS | 🟡 MEDIUM | нет |
| 3.5 fail2ban | 🟡 MEDIUM | пакет `fail2ban` |
| 3.6 wpa_supplicant | 🟢 LOW | пакет `wpa_supplicant` |
| 4.1 ConditionFirstBoot | 🟡 MEDIUM | этап 1.1 |
| 4.2-4.3 Рефакторинг | 🟢 LOW | этапы 1.1, 4.1 |
| 5.1 Тесты | 🟢 LOW | этапы 1-4 |
| 5.2-5.4 CI/README/Config | 🟢 LOW | нет |
| 6 Документация | 🟢 LOW | все этапы |

---

## Про rmux

Проект `rmux` мне неизвестен. Возможно, ты имеешь в виду `zellij` (Rust, современный аналог tmux) или другой инструмент?

Аргументы за `tmux`:
- В официальных репах Arch (`pacman -S tmux`)
- 2 MB, стабилен, предсказуем
- Знаком 100% аудитории
- Не требует runtime-зависимостей (типа Rust-рантайма)

Любой не-tmux мультиплексор пользователь поставит сам, если захочет. В базовом образе достаточно `tmux`. Если знаешь конкретный `rmux` — скинь ссылку, посмотрю.
