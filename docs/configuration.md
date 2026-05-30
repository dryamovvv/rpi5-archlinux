# Configuration

## build.conf

Основной конфиг сборки. Шаблон: `build.conf.example`. Локальный `build.conf` в `.gitignore`.

### Обязательные поля

```bash
BUILD_IMAGE_PATH="$BUILD_PROJECT_ROOT/dist/images/archlinux-rpi5-aarch64.img"
BUILD_IMAGE_SIZE="4g"
BUILD_MOUNT_ROOT="/mnt/arch_build"
BUILD_MOUNT_BOOT="$BUILD_MOUNT_ROOT/boot"
BUILD_SSH_USER=""                # пусто = только root; имя для AllowUsers
BUILD_SSH_ALLOW_USERS=""           # дополнительные пользователи для AllowUsers
BUILD_SSH_PERMIT_ROOT_LOGIN="yes"  # yes (password+key) | prohibit-password (key only) | no
BUILD_ROOT_SSH_KEY=""              # публичный SSH-ключ для root
BUILD_MKINITCPIO_HOOKS="HOOKS=(base systemd autodetect modconf kms keyboard keymap sd-vconsole block filesystems fsck)"
BUILD_MODULES=(...)   # минимум 1 модуль
BUILD_PACKAGES=(...)  # минимум 1 пакет
```

### Опциональные поля

```bash
BUILD_HOSTNAME=""                # пусто = systemd-firstboot спросит при загрузке
BUILD_TIMEZONE=""                # пусто = спросит
BUILD_ROOT_PASSWORD=""           # пусто = спросит
BUILD_LOCALE="en_US.UTF-8"       # дефолт
BUILD_KEYMAP="us"                # дефолт
BUILD_FILESYSTEM="btrfs"         # btrfs (subvolumes + snapper) | ext4
BUILD_SWAPFILE_SIZE="16G"        # btrfs swapfile; пусто = без swapfile
BUILD_IMAGE_SHRINK_MARGIN="256M" # запас места при shrink
BUILD_EEPROM_CHANNEL="latest"    # default | latest
BUILD_MKINITCPIO_COMPRESSION="gzip"  # gzip | cat (быстрее)
BUILD_ENABLE_ZRAM=0              # 0 | 1
BUILD_ENABLE_WIFI=0              # 0 | 1
```

## config.txt

Статический файл `src/conf/boot/config.txt`. Правки вносятся напрямую.

Текущие настройки для `[pi5]`:
- `arm_freq=2800`, `over_voltage_delta=25000` — безопасный разгон (нужен Active Cooler)
- `disable_splash=1` — без rainbow screen
- `dtoverlay=disable-wifi`, `dtoverlay=disable-bt` — headless
- `dtparam=pciex1_gen=3` — PCIe Gen 3 для NVMe
- `kernel=` явно не задан — прошивка auto-detects

## cmdline.txt

Шаблон `src/conf/boot/cmdline.txt` с плейсхолдером `__ROOT_UUID__`.

Текущие параметры:
- `quiet loglevel=3` — минимум логов
- `mitigations=off` — +5-10% CPU (Cortex-A76 не подвержен)
- `nowatchdog` — без watchdog-таймеров
- UUID подставляется при сборке из `BUILD_ROOT_UUID`
