# RPi5 Arch Linux Image — План улучшений

> Сгенерировано: 2026-05-25, коммит `2e94925`

---

## 1. Выполненные исправления (эта сессия)

| # | Проблема | Файлы | Статус |
|---|----------|-------|--------|
| 1 | `root=/dev/mmcblk0p2` → UUID в cmdline.txt | `cmdline.txt`, `disk_image.sh`, `bootstrap.sh` | ✅ |
| 2 | `device_tree_address=bcm2712-rpi-5-b.dtb` — несуществующий параметр | `config.txt` | ✅ |
| 3 | `%wheel` закомментирован в `/etc/sudoers` | `bootstrap.sh`, `services.sh` | ✅ |
| 4 | Симлинк firstboot-сервиса битый (в `/usr/lib/` вместо `/etc/`) | `bootstrap.sh` (#2) | ✅ |

---

## 2. Статус issues в репозитории

| # | Issue | Статус |
|---|-------|--------|
| [#4](https://github.com/dryamovvv/archlinux-rpi5-aarch64/issues/4) | Пароли в командной строке и heredoc | 🔴 Открыт |
| [#3](https://github.com/dryamovvv/archlinux-rpi5-aarch64/issues/3) | mkinitcpio: изменения после установки могут не примениться | 🟢 Исправлен — `mkinitcpio_conf` вызывается до `regenerate_initramfs` |
| [#2](https://github.com/dryamovvv/archlinux-rpi5-aarch64/issues/2) | Битый симлинк firstboot-сервиса | 🟢 Исправлен — добавлен `systemd_enable_custom_unit` |
| [#1](https://github.com/dryamovvv/archlinux-rpi5-aarch64/issues/1) | `SigLevel = Never`, HTTP-зеркала | 🔴 Открыт |

---

## 3. Рекомендации по пакетам для RPi5

### Tier 1 — Рекомендуется добавить сейчас

| Пакет | Зачем |
|-------|-------|
| `i2c-tools` | Отладка I2C-устройств (GPIO, HAT-ы) |
| `cpupower` | Управление CPU governor (`schedutil` для EAS) |
| `rng-tools` | Питание entropy-пула от hw RNG (важно для headless) |
| `iptables-nft` | Базовый фаервол |
| `git` | Нужен практически всем |
| `man-db` + `man-pages` | Man-страницы (могут отсутствовать в `base`) |
| `vim` | Полноценный редактор (в `base` только `vi`) |

### Tier 2 — Желательно

| Пакет | Зачем |
|-------|-------|
| `wpa_supplicant` | Wi-Fi (если убрать `dtoverlay=disable-wifi`) |
| `libcamera` + `v4l-utils` | Камера/видео |
| `fail2ban` | Защита SSH от брутфорса |
| `avahi` | Доступ по `arch-rpi5.local` |
| `htop` | Мониторинг |
| `logrotate` | Ротация логов на SD-карте |

### Tier 3 — Опционально

| Пакет | Зачем |
|-------|-------|
| `networkmanager` | Для десктоп-сценариев |
| `tmux` | Терминальный мультиплексор |
| `bash-completion` | Автодополнение |

---

## 4. Рекомендации по конфигурации

| Что | Предложение |
|-----|-------------|
| CPU governor | Установить `schedutil` через tmpfiles.d (лучше EAS-aware чем `ondemand`) |
| ZRAM | Сделать опциональным (сейчас жестко отключен). Добавить `BUILD_ENABLE_ZRAM` в `build.conf.example` |
| SSH hardening | Добавить `PermitRootLogin no` в `sshd_config` |
| mDNS | Включить `MulticastDNS=yes` в `systemd-resolved` для `.local`-доступа |
| PACMAN | Переключить зеркала на HTTPS, включить `SigLevel = Required DatabaseOptional` |

---

## 5. Рекомендации по репозиторию

| Область | Предложение |
|---------|-------------|
| **CI** | Добавить `deps::validate_build_commands` в CI (сейчас нет проверки наличия `blkid`, `aria2c`, etc) |
| **CI** | Добавить shellcheck-директиву `disable=SC2034` в начало файла вместо глобального disable |
| **Тесты** | Добавить тест на `systemd_enable_custom_unit` (новый функционал) |
| **Тесты** | Добавить тест на UUID-подстановку в `cmdline_txt` |
| **Тесты** | Добавить тест на `enable_wheel_sudo` |
| **build.conf** | Добавить `BUILD_ENABLE_ZRAM`, `BUILD_ENABLE_WIFI`, `BUILD_CPU_GOVERNOR` опции |
| **README** | Добавить секцию про NVMe-загрузку (EEPROM `BOOT_ORDER`) |
| **README** | Добавить секцию про смену паролей после первой загрузки |
| **README** | Добавить секцию про `--config` для кастомных настроек |
| **Структура** | Рассмотреть выделение `firstboot.sh` в отдельный файл в `src/conf/` вместо heredoc в `bootstrap.sh` |
| **Безопасность** | Убрать пароли из `build.conf.example` (оставить пустыми с комментарием) |

---

## 6. Что проверено

| Проверка | Результат |
|----------|-----------|
| `bash -n` всех `.sh` | ✅ |
| `shellcheck` (в CI) | ✅ passing |
| 10 smoke-тестов `tests/` | ✅ |
| `validate` | ✅ |
| QEMU сборка + загрузка v1 | ✅ `systemctl is-system-running → running`, failed units = 0 |
| QEMU сборка + загрузка v2 (с фиксом #2) | 🔄 в процессе |
| Release `v0.2.5` (ARM-native сборка) | 🔄 в процессе |

---

## 7. Не исправлено (на будущее)

| Проблема | Почему не сейчас |
|----------|------------------|
| `SigLevel = Never` | Требует импорта keyring и проверки доступности ключей на ArchLinuxARM |
| Пароли в `build.conf` | Нужен механизм хеширования/файлов для `systemd-firstboot` |
| Нет HTTPS-зеркал | ArchLinuxARM может не поддерживать HTTPS для некоторых зеркал |
| `autodetect` hook на x86_64 | Не влияет на ARM-native сборку в CI |
