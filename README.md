# rpi5-archlinux
Raspberry Pi 5 Arch Linux image build script.

## Structure
- `scripts/main.sh` — основной entrypoint сборки.
- `lib/` — Bash-модули (`disk.sh`, `bootstrap.sh`, `log.sh`).
- `conf/` — активные статические ресурсы сборки; сейчас в реальном build path используется `pacman-arm.conf`.
- `conf/reference/` — шаблоны и reference-файлы, которые не подключены автоматически к текущему build flow.

## Usage
```bash
sudo ./scripts/main.sh
```

## Validation
```bash
bash -n scripts/*.sh lib/*.sh tests/*.sh
shellcheck scripts/*.sh lib/*.sh tests/*.sh
```

## GitHub Actions
- `.github/workflows/ci.yml` проверяет shell-скрипты и smoke-тесты.
- `.github/workflows/release.yml` запускается на тегах `v*`, собирает образ на native `arm64` runner и публикует `arch_root.img.xz` вместе с `arch_root.img.xz.sha256`.
- Локальный сценарий релиза:
```bash
git tag v0.1.0
git push origin v0.1.0
```

## GitHub Actions Build Environment
- Release workflow использует native `arm64` runner `ubuntu-24.04-arm`.
- Build dependencies ставятся напрямую через `apt`, после чего workflow запускает `sudo ./scripts/main.sh` без собственного builder-контейнера.
- `pacstrap` и post-install hooks выполняются без `qemu-user-static` и `binfmt`.
- Основная пост-конфигурация вынесена в `systemd-firstboot` и `rpi5-firstboot.service`, чтобы минимизировать build-time `arch-chroot`.
