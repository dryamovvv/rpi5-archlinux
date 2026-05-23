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
- `.github/workflows/ci.yml` проверяет shell-скрипты, smoke-тесты и сборку builder-образа.
- `.github/workflows/release.yml` запускается на тегах `v*`, собирает `arch_root.img` и публикует его в GitHub Release вместе с `arch_root.img.sha256`.
- Локальный сценарий релиза:
```bash
git tag v0.1.0
git push origin v0.1.0
```

## Container Build Environment
- `Dockerfile` собирает Arch-based builder image со всеми утилитами, которые нужны текущему build flow.
- В release workflow сборка идет внутри `docker run --privileged`, потому что скрипт использует `losetup`, `mount`, `mkfs`, `sfdisk` и `arch-chroot`.
