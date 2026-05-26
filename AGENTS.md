# Repository Guidelines

## Project Overview
Bash-скрипты для сборки Arch Linux ARM образа под Raspberry Pi 5. Один бинарник (`dist/bin/rpi5-archlinux-image`) умеет:
- `build` — собрать img для RPi5
- `build-qemu` — собрать img для QEMU (тестирование на x86_64)
- `qemu-run` — запустить QEMU с собранным образом
- `validate` — проверить build.conf
- `list-steps` — показать pipeline сборки

## Key Architecture Decisions (2026-05-26)
- **firstboot**: systemd-firstboot (интерактивный, tty) + rpi5-firstboot.service (useradd)
- **root**: UUID-based (не /dev/mmcblk0p2)
- **filesystem**: EXT4 (Bcachefs отложен — удален из mainline, медленный, баги на aarch64)
- **kernel**: linux-rpi-16k (16K pages), Pi 5 auto-detects
- **governor**: schedutil (EAS-aware для big.LITTLE)
- **packages**: 40+ утилит (git, vim, tmux, fail2ban, s-tui, stress-ng, nvme-cli, etc.)
- **overclock**: arm_freq=2800, over_voltage_delta=25000 в config.txt
- **cmdline**: quiet loglevel=3 mitigations=off nowatchdog
- **CI**: shell-checks на x86 (всегда) + build-arm на ARM runner (только ветка `dev`)
- **release**: native ubuntu-24.04-arm, публикует .img.xz + os_list.json (для Network Install)

## File Map (для быстрой навигации)

| Path | Role |
|------|------|
| `src/main.sh` | CLI entrypoint |
| `src/lib/core/config.sh` | Загрузка + валидация build.conf |
| `src/lib/core/runner.sh` | Оркестрация шагов сборки |
| `src/lib/core/steps.sh` | Реестр шагов (steps::add) |
| `src/lib/core/modules.sh` | Загрузка build-модулей |
| `src/lib/core/assets.sh` | Embedded assets (src/conf/ → heredoc) |
| `src/lib/bootstrap.sh` | Вся in-target настройка (firstboot, fstab, mkinitcpio, network, sshd) |
| `src/lib/disk.sh` | Loop-устройства, разделы, форматирование |
| `src/lib/modules/disk_image.sh` | Шаги: create → map → partition → format → mount |
| `src/lib/modules/base_system.sh` | pacstrap + mkinitcpio + fstab |
| `src/lib/modules/boot_config.sh` | cmdline.txt + config.txt |
| `src/lib/modules/services.sh` | network, sshd, fail2ban, ZRAM, Wi-Fi, EEPROM |
| `src/conf/boot/config.txt` | Статический Pi-конфиг (overclock, GPU, boot) |
| `src/conf/boot/cmdline.txt` | Kernel command line (шаблон с __ROOT_UUID__) |
| `src/conf/systemd/rpi5-firstboot.service` | First-boot unit (user creation) |
| `src/conf/systemd/systemd-firstboot.service.d/prompt.conf` | tty drop-in для интерактивных промптов |
| `src/conf/pacman/pacman-arm.conf` | Pacman-конфиг для pacstrap |
| `build.conf.example` | Шаблон конфига сборки |
| `scripts/package.sh` | Упаковщик в один файл |
| `tests/` | 13 shell-тестов |
| `os_list.json` | Запись для Raspberry Pi Imager Network Install |
| `TODO.md` | План дальнейших улучшений |
| `IMPROVEMENTS.md` | История выполненных правок |

## Build Pipeline (12 шагов)
```
prepare_image → map_loop → partition_image → create_filesystems → mount_filesystems
→ prepare_base_config → install_base (pacstrap + mkinitcpio + fstab)
→ configure_boot (cmdline.txt + config.txt) → configure_system (firstboot + locale)
→ configure_services (network, sshd, fail2ban, etc.) → validate_boot_files → shrink_image
```

## Quick Start для LLM
```bash
cp build.conf.example build.conf
./scripts/package.sh
bash -n src/lib/*.sh src/lib/core/*.sh src/lib/modules/*.sh tests/*.sh
for t in tests/*.sh; do bash "$t" || echo "FAIL: $t"; done
./dist/bin/rpi5-archlinux-image validate
```

## Пуш в dev (триггерит ARM-сборку в CI)
```bash
git branch -f dev main && git push origin dev --force
```

## QEMU — локальное тестирование на x86_64

**Порядок работы:** изменил код → пересобрал `./scripts/package.sh` → собрал QEMU-образ → запустил → проверил загрузку → только потом коммит и пуш.
Сборка на x86_64 через qemu-user-static занимает ~25 минут (против 2 минут на ARM).

```bash
# Собрать QEMU-образ (использует linux-aarch64 вместо linux-rpi-16k)
./dist/bin/rpi5-archlinux-image build-qemu

# Запустить (SSH на localhost:2222, Ctrl+A X для выхода)
./dist/bin/rpi5-archlinux-image qemu-run
```

**Важно:** QEMU не тестирует config.txt и Pi-специфичные параметры (overclock, device tree).
Для них — только CI на `dev` ветке или реальное железо.

**Известные ограничения:**
- systemd-firstboot не интерактивен в QEMU (нет tty) — hostname будет `archlinux`
- `arm_freq`, `over_voltage_delta`, `disable_splash` — только на реальном Pi
- Порты переиспользуются — убить старый QEMU: `sudo pkill -f qemu-system`
