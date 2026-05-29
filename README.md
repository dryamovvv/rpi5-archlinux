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
- `src/conf/firstboot/` — deprecated (deleted); `user.json` is now generated at build time in `bootstrap::firstboot_service()` from `build.conf` variables (see [docs/homectl.md](docs/homectl.md)).
- `docs/skills/` — готовые opencode skills для копирования в `~/.agents/skills/`.

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
ssh -p 2222 user@localhost                     # password from BUILD_USER_PASSWORD (default: user)
curl http://localhost:8080/health              # MCP server (embedded at build time)
```

QEMU target builds `dist/images/archlinux-qemu-aarch64.img` and exports direct-boot files to `dist/images/qemu-boot/`. The runner uses `qemu-system-aarch64 -M virt` with virtio disk, serial console, user networking, SSH forwarding from `localhost:2222` to guest port `22`, and MCP forwarding from `localhost:8080` to guest port `8080`.

## Validation
```bash
bash -n scripts/*.sh src/main.sh src/lib/*.sh src/lib/core/*.sh src/lib/modules/*.sh tests/*.sh
shellcheck scripts/*.sh src/main.sh src/lib/*.sh src/lib/core/*.sh src/lib/modules/*.sh tests/*.sh
./scripts/package.sh
./dist/bin/rpi5-archlinux-image validate
```

## GitHub Actions
- `.github/workflows/ci.yml` runs shell checks, smoke tests, and ARM build (on `dev` and `homectl_feature` branches). The ARM build validates boot files and uploads `archlinux-rpi5-aarch64.img.xz` as an artifact.
- `.github/workflows/release.yml` runs on `v*` tags, builds the Raspberry Pi image on a native `arm64` runner, and publishes `archlinux-rpi5-aarch64.img.xz` with `.sha256` to GitHub Releases.
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

## First boot

- User (`user` by default) is created via `homectl --storage=subvolume` (btrfs subvolume inside `@home`). Password is pre-hashed from `BUILD_USER_PASSWORD` in `build.conf`; the system forces a password change on first login. If `BUILD_USER_PASSWORD` is unset, an interactive wizard runs on TTY, or a `useradd` fallback on headless systems.
- User home is a separate btrfs subvolume `/home/user.homedir`. Snapper auto-configures timeline snapshots (hourly:5, daily:7, weekly:4, monthly:3).
- Root password is set from `BUILD_ROOT_PASSWORD` in `build.conf` (default: `root`).
- The MCP server (`arch-ops-mcp.service`) is embedded at build time. The API key is saved as `<image>.mcp-key` alongside the image file.
- After boot, the Raspberry Pi is reachable via mDNS:
  ```bash
  ssh user@arch-rpi5.local
  ```
  or by the IP address assigned by DHCP.

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

## opencode Integration

Проект поддерживает работу через [opencode](https://opencode.ai) — AI-агент для командной строки. Конфигурация разделена на три уровня:

### 1. Проектный `AGENTS.md`

Файл [`AGENTS.md`](AGENTS.md) в корне репозитория — основная инструкция для AI. Содержит команды, файловую карту, правила, CI/CD. Автоматически подхватывается opencode при работе в этом каталоге. Дополнительной установки не требует.

### 2. Глобальный `AGENTS.md`

Устанавливается в `~/.config/opencode/AGENTS.md` и работает во всех проектах. Добавляет правила для arch-linux MCP:

```bash
mkdir -p ~/.config/opencode
# скопировать содержимое секции <!-- arch-linux --> из проектного AGENTS.md
# в ~/.config/opencode/AGENTS.md
```

Содержимое: список MCP-инструментов (`get_system_info`, `install_package_secure`, `check_updates_dry_run` и др.), категории (система, пакеты, AUR, конфиги, зеркала), примеры вызова и правила безопасности.

### 3. Skills (`~/.agents/skills/`)

Скиллы — это markdown-файлы с инструкциями для конкретных сценариев. Устанавливаются в `~/.agents/skills/<name>/SKILL.md`:

```bash
mkdir -p ~/.agents/skills/arch-linux-mcp ~/.agents/skills/arch-audit
```

**arch-linux-mcp** — справочник по всем MCP-инструментам. Активируется при упоминании RPi5, Arch, pacman, AUR.

**arch-audit** — скилл-команда `/arch_audit`. При запуске выполняет все MCP-инструменты параллельно и собирает структурированный отчёт: система, здоровье, пакеты, конфиги, зеркала, новости, orphan-пакеты, boot logs. Полезен после установки нового образа для проверки здоровья RPi5.

Готовые файлы лежат в [`docs/skills/`](docs/skills/). Установка одной командой:

```bash
cp -r docs/skills/* ~/.agents/skills/
```

### 4. MCP-сервер (`opencode.json`)

Для удалённого управления RPi5 используется HTTP-форк arch-ops-server (`dryamovvv/arch-mcp`) с Bearer-аутентификацией. Конфигурация:

```json
{
  "mcp": {
    "arch-linux": {
      "type": "remote",
      "url": "http://<rpi5-ip>:8080/mcp",
      "enabled": true,
      "headers": {
        "Authorization": "Bearer {file:~/.config/opencode/api-key}"
      },
      "oauth": false,
      "timeout": 30000
    }
  }
}
```

Устанавливается либо в `~/.config/opencode/opencode.json` (глобально), либо в `opencode.json` корня проекта (локально). API-ключ хранится в `~/.config/opencode/api-key`.

The MCP server is embedded in the image at build time via `bootstrap::mcp_server()`. It runs as a systemd service (`arch-ops-mcp.service`) and the API key is saved as `<image>.mcp-key` next to the image file.

Подробнее — в [`docs/arch-mcp.md`](docs/arch-mcp.md).
