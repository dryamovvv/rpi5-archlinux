# rpi5-archlinux
Raspberry Pi 5 Arch Linux image build script.

## Structure
- `src/main.sh` — исходный CLI entrypoint сборки.
- `src/lib/core/` — CLI/runtime framework: config loading, module loading, step registry, runner, dependency checks.
- `src/lib/modules/` — build-модули, которые регистрируют шаги pipeline.
- `src/lib/` — низкоуровневые Bash-модули (`disk.sh`, `bootstrap.sh`, `log.sh`).
- `scripts/package.sh` — собирает один исполняемый файл в `dist/bin/` и создает `dist/images/`.
- `dist/bin/rpi5-archlinux-image` — generated packaged CLI для запуска сборки образа.
- `dist/images/` — generated каталог для локальных `archlinux-rpi5-aarch64.img` и `archlinux-rpi5-aarch64.img.xz`; каталог `dist/` не коммитится.
- `build.conf.example` — шаблон build-конфигурации.
- `build.conf` — локальный ignored config; `scripts/package.sh` требует этот файл и embedded-встраивает его значения в `dist/bin/rpi5-archlinux-image` как default config.
- `src/conf/pacman/` — active pacman-конфигурация, embedded в packaged builder и реально используемая `pacstrap`.
- `src/conf/boot/` — active boot-файлы, embedded в packaged builder и записываемые в boot partition.
- `src/conf/systemd/` — active systemd unit для first-boot provisioning, embedded в packaged builder и записываемый в root filesystem.
- `src/conf/firstboot/` — template user identity JSON (`user.json`) для `homectl create --identity` на первом старте; наполняется из `build.conf` (см. [docs/homectl.md](docs/homectl.md)).

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
- `.github/workflows/release.yml` запускается на тегах `v*`, собирает Raspberry Pi образ на native `arm64` runner и публикует `archlinux-rpi5-aarch64.img.xz` с `.sha256`.
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

## Сборка образа

Сборка образа выполняется упакованным CLI, который находится в `dist/bin/rpi5-archlinux-image`.

```bash
# Копируем шаблон конфигурации и редактируем под свои нужды
cp build.conf.example build.conf
# Редактируем build.conf (root-пароль, размер образа и т.д.)
# Собираем упакованный CLI
./scripts/package.sh
# Запускаем сборку образа
./dist/bin/rpi5-archlinux-image build
```

Для использования внешнего конфигурационного файла (не встроенного по умолчанию) передайте его через `--config`:

```bash
./dist/bin/rpi5-archlinux-image --config ./my-build.conf build
```

Для сборки тестового QEMU-образа (запускается в эмуляторе, без записи на SD-карту):

```bash
./dist/bin/rpi5-archlinux-image build-qemu
./dist/bin/rpi5-archlinux-image qemu-run
```

## Первый запуск

- Пользователь (`user` по умолчанию) создаётся через `homectl --storage=subvolume` (btrfs subvolume внутри `@home`). Пароль задаётся хешем из `build.conf` (`BUILD_USER_PASSWORD`), при первом логине система потребует смену пароля.
- Home пользователя — отдельный btrfs subvolume `/home/user.homedir` (bind-mount в `/home/user`). Snapper автоматически настроен на снятие снапшотов home с таймлайном (hourly:5, daily:7, weekly:4, monthly:3).
- Root-пароль задается в `build.conf` (переменная `BUILD_ROOT_PASSWORD`); по умолчанию — `root`.
- После загрузки Raspberry Pi доступен по mDNS:
  ```bash
  ssh user@arch-rpi5.local
  ```
  или по IP-адресу, выданному DHCP-сервером.

## Загрузка с NVMe

Для загрузки с NVMe-диска необходимо прошить EEPROM Raspberry Pi 5 с правильным порядком загрузки:

```bash
sudo rpi-eeprom-config --edit
```

Установите `BOOT_ORDER=0xf416` (NVMe > USB > SD), сохраните и перезагрузите.

Подробнее см. официальную документацию Raspberry Pi: [NVMe SSD boot](https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#nvme-ssd-boot).

## Кастомизация

Сборка поддерживает несколько опций для тонкой настройки образа:

- **ZRAM** — включение сжатой swap-памяти в ОЗУ. Установите `BUILD_ENABLE_ZRAM=1` в `build.conf`:
  ```bash
  BUILD_ENABLE_ZRAM=1
  ```

- **Wi-Fi** — предварительная настройка беспроводной сети. Установите `BUILD_ENABLE_WIFI=1` и заполните `BUILD_WIFI_SSID` / `BUILD_WIFI_PSK`:
  ```bash
  BUILD_ENABLE_WIFI=1
  BUILD_WIFI_SSID="MyNetwork"
  BUILD_WIFI_PSK="my-password"
  ```

- **Быстрая dev-сборка** — для ускорения цикла разработки можно отключить сжатие initramfs, установив `BUILD_MKINITCPIO_COMPRESSION="cat"`:
  ```bash
  BUILD_MKINITCPIO_COMPRESSION="cat"
  ```
  Это создает несжатый initramfs, что значительно ускоряет сборку ценой большего размера boot-раздела.

## Установка через Network Install (без SD-карты)

Raspberry Pi 5 поддерживает установку ОС напрямую через сеть (Ethernet), без необходимости записывать образ на SD-карту с другого компьютера.

### Разовая настройка EEPROM

На **любой** уже работающей Raspberry Pi (с любой ОС) выполните однократно:

```bash
sudo rpi-eeprom-config --edit
```

Добавьте строку:

```
IMAGER_REPO_URL=https://github.com/dryamovvv/archlinux-rpi5-aarch64/releases/latest/download/os_list.json
```

Сохраните и перезагрузитесь. Эта настройка сохраняется в EEPROM навсегда (до следующего сброса EEPROM).

### Установка образа

1. Подключите Raspberry Pi 5 к Ethernet и питанию (SD-карта не нужна)
2. Нажмите **Space** на экране загрузки, затем **N**
3. Raspberry Pi скачает Imager по сети
4. В списке ОС выберите **Arch Linux ARM for Raspberry Pi 5**
5. Выберите целевой накопитель (SD-карту или NVMe)
6. Нажмите Write — образ запишется напрямую с GitHub Releases

После записи извлеките SD-карту (или оставьте NVMe) и перезагрузитесь — система загрузится в Arch Linux ARM.
