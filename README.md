# rpi5-archlinux
Raspberry Pi 5 Arch Linux image build script.

## Structure
- `src/main.sh` — исходный CLI entrypoint сборки.
- `src/lib/core/` — CLI/runtime framework: config loading, module loading, step registry, runner, dependency checks.
- `src/lib/modules/` — build-модули, которые регистрируют шаги pipeline.
- `src/lib/` — низкоуровневые Bash-модули (`disk.sh`, `bootstrap.sh`, `log.sh`).
- `scripts/package.sh` — собирает один исполняемый файл в `dist/bin/` и создает `dist/images/`.
- `dist/bin/rpi5-archlinux-image` — generated packaged CLI для запуска сборки образа.
- `dist/images/` — generated каталог для локальных `archlinux-rpi5-aarch64.img` и `archlinux-qemu-aarch64.img`, boot-файлов QEMU в `qemu-boot/` и release artifacts вида `archlinux-rpi5-aarch64-${TAG}.img.xz` / `archlinux-qemu-aarch64-${TAG}.img.xz`; каталог `dist/` не коммитится.
- `build.conf.example` — шаблон build-конфигурации.
- `build.conf` — локальный ignored config; `scripts/package.sh` требует этот файл и embedded-встраивает его значения в `dist/bin/rpi5-archlinux-image` как default config.
- `src/conf/pacman/` — active pacman-конфигурация, embedded в packaged builder и реально используемая `pacstrap`.
- `src/conf/boot/` — active boot-файлы, embedded в packaged builder и записываемые в boot partition.
- `src/conf/systemd/` — active systemd unit для first-boot provisioning, embedded в packaged builder и записываемый в root filesystem.

## Usage
```bash
cp build.conf.example build.conf
./scripts/package.sh
./dist/bin/rpi5-archlinux-image help
./dist/bin/rpi5-archlinux-image list-steps
./dist/bin/rpi5-archlinux-image validate
./dist/bin/rpi5-archlinux-image build
./dist/bin/rpi5-archlinux-image build-qemu
./dist/bin/rpi5-archlinux-image qemu-run
./dist/bin/rpi5-archlinux-image --config ./my-build.conf build
```

`BUILD_IMAGE_SIZE` задает staging-размер образа для сборки. Финальный шаг `image_shrink` уменьшает готовый ext4 root-раздел и сам `.img` до фактически занятого места плюс запас `BUILD_IMAGE_SHRINK_MARGIN`; при первой загрузке root-раздел снова расширяется на весь диск через systemd-growfs/repart конфигурацию.

## QEMU testing
```bash
./dist/bin/rpi5-archlinux-image build-qemu
./dist/bin/rpi5-archlinux-image qemu-run
ssh -p 2222 dryam@localhost
```

QEMU target builds `dist/images/archlinux-qemu-aarch64.img` and exports direct-boot files to `dist/images/qemu-boot/`. The runner uses `qemu-system-aarch64 -M virt` with virtio disk, serial console, user networking, and host SSH forwarding from `localhost:2222` to guest port `22`.

## Validation
```bash
bash -n scripts/*.sh src/main.sh src/lib/*.sh src/lib/core/*.sh src/lib/modules/*.sh tests/*.sh
shellcheck scripts/*.sh src/main.sh src/lib/*.sh src/lib/core/*.sh src/lib/modules/*.sh tests/*.sh
./scripts/package.sh
./dist/bin/rpi5-archlinux-image validate
```

## GitHub Actions
- `.github/workflows/ci.yml` проверяет shell-скрипты и smoke-тесты.
- `.github/workflows/release.yml` запускается на тегах `v*`, собирает Raspberry Pi образ на native `arm64` runner и публикует `archlinux-rpi5-aarch64-${TAG}.img.xz` с `.sha256`. QEMU образ публикуется только при ручном запуске workflow с `include_qemu=true`.
- Локальный сценарий релиза:
```bash
git tag v0.1.0
git push origin v0.1.0
```

## GitHub Actions Build Environment
- Release workflow использует native `arm64` runner `ubuntu-24.04-arm`.
- Build dependencies ставятся напрямую через `apt`, после чего workflow запускает `./dist/bin/rpi5-archlinux-image build` без собственного builder-контейнера. Builder сам повышает права через `sudo` только для привилегированных команд. Образ и release artifacts создаются в `dist/images/`.
- `pacstrap` и post-install hooks выполняются без `qemu-user-static` и `binfmt`.
- Основная пост-конфигурация вынесена в `systemd-firstboot` и `rpi5-firstboot.service`, чтобы минимизировать build-time `arch-chroot`.
