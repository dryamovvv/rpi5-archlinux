# Build Pipeline

12-шаговый процесс сборки образа. Каждый шаг — функция в соответствующем модуле.

```
prepare_image → map_loop → partition_image → create_filesystems → mount_filesystems
→ prepare_base_config → install_base → configure_boot → configure_system
→ configure_services → validate_boot_files → shrink_image
```

| Шаг | Модуль | Что делает |
|-----|--------|------------|
| `prepare_image` | `disk_image.sh` | `truncate -s 4g archlinux-rpi5-aarch64.img` |
| `map_loop` | `disk_image.sh` | `losetup --find -P --show` |
| `partition_image` | `disk_image.sh` | GPT: 512M ESP (vfat) + остальное root (ext4 или btrfs) |
| `create_filesystems` | `disk_image.sh` | `mkfs.vfat` + ext4/btrfs; для btrfs: создаёт 8 subvolume (`@`, `@home`, `@snapshots`, ...) |
| `mount_filesystems` | `disk_image.sh` | root → `/mnt/arch_build`, boot → `/mnt/arch_build/boot` |
| `prepare_base_config` | `base_system.sh` | `/etc/vconsole.conf` |
| `install_base` | `base_system.sh` | `pacstrap` пакетов из `BUILD_PACKAGES` + `mkinitcpio` + `genfstab` |
| `configure_boot` | `boot_config.sh` | Запись `cmdline.txt` (UUID-подстановка) и `config.txt` |
| `configure_system` | `services.sh` | `systemd-firstboot` (locale, keymap, machine-id), `locale-gen`, `firstboot_service` (user.json) |
| `configure_services` | `services.sh` | network, sshd, fail2ban, systemd-homed, MCP server, snapper (btrfs only), rollback script, ZRAM, Wi-Fi, EEPROM, repart/growfs |
| `validate_boot_files` | `release_validation.sh` | Проверка наличия 5 boot-файлов |
| `shrink_image` | `image_shrink.sh` | `resize2fs -M` → `truncate` → `sgdisk -e` |

## Где что происходит

- **Разметка диска:** `src/lib/modules/disk_image.sh` + низкоуровневые функции в `src/lib/disk.sh`
- **Установка пакетов:** `src/lib/bootstrap.sh` → `bootstrap::install_base()`
- **Настройка системы:** `src/lib/bootstrap.sh` → `bootstrap::systemd_firstboot()`, `bootstrap::firstboot_service()`
- **Сервисы:** `src/lib/modules/services.sh` → `services::configure_services()`

## Важные нюансы

- `BUILD_ROOT_UUID` сохраняется при форматировании и подставляется в `cmdline.txt` через `sed`
- `genfstab -U` генерирует fstab с UUID; для btrfs: fstab записывается вручную с subvolume-маунтами (не через `genfstab`)
- `bootstrap::mkinitcpio_conf` вызывается ДО `bootstrap::regenerate_initramfs`; для btrfs: добавляет `MODULES=(vfat btrfs)`, убирает хук `fsck`
- QEMU-сборка пропускает `boot_config` и `release_validation`, добавляет `qemu_boot_config`
