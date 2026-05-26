# TODO — Этап: производительность и расширенные настройки

> На основе NEXT.md, обсуждения и исследования

---

## 1. Bcachefs (отложен)

**Статус:** ⏸️ Отложен до стабилизации в mainline

**Причина:** модуль `bcachefs` удален из дерева ядра в Linux 6.18 как экспериментальный. Для работы требуется `bcachefs-dkms` (AUR) + `linux-rpi-16k-headers` + компиляция модуля через DKMS при каждом обновлении ядра. Это усложняет сборку и загрузку.

**План на будущее:**
- Когда bcachefs вернется в mainline — добавить опцию `BUILD_ROOT_FS="bcachefs"`
- Нужен будет отдельный `/boot` (vfat) + root (bcachefs)
- Снапшоты: `bcachefs subvolume snapshot`
- Хук `bcachefs` в mkinitcpio

---

## 2. Разгон CPU/GPU → `build.conf`

### 2.1 Параметры

```bash
# CPU frequency: 2400 (stock), 2800 (safe), 3000 (max, needs cooling)
BUILD_ARM_FREQ=2800
# GPU 3D frequency: 960 (stock), 1000 (safe)
BUILD_V3D_FREQ=960
# Core frequency: 910 (stock)
BUILD_CORE_FREQ=910
# Voltage offset in microvolts: 0 (stock), 20000-50000
BUILD_OVER_VOLTAGE_DELTA=20000
# Force turbo (keeps max freq, enables higher voltages): 0 or 1
BUILD_FORCE_TURBO=0
```

### 2.2 Генерация config.txt

В секцию `[pi5]` config.txt добавляются **только заданные** параметры:
```ini
arm_freq=2800
over_voltage_delta=20000
```

Динамическая частота (`schedutil`) уже настроена в `cpu-power.conf`.

### 2.3 Файлы

- `build.conf.example` — новые переменные
- `src/lib/bootstrap.sh` — `bootstrap::config_txt()` или `bootstrap::overclock_config()`
- `src/conf/boot/config.txt` — убрать частоты (будут из конфига)

---

## 3. Два профиля cmdline.txt

### 3.1 Переменная

```bash
# "prod" — тихая загрузка (только warn/crit), "debug" — подробный лог
BUILD_BOOT_PROFILE="debug"
```

### 3.2 Профиль `debug`

```
root=UUID=... rw rootwait console=tty1 fsck.repair=yes
```

### 3.3 Профиль `prod`

```
root=UUID=... rw rootwait console=tty1 fsck.repair=yes quiet loglevel=3 mitigations=off nowatchdog
```

### 3.4 Дополнительные параметры (обсуждаемы)

| Параметр | Эффект | Рекомендация |
|----------|--------|--------------|
| `mitigations=off` | +5-10% CPU perf, Pi 5 не подвержен Spectre/Meltdown | ✅ prod |
| `nowatchdog` | Отключает hardware watchdog, +perf | ✅ prod |
| `quiet` | Меньше логов на консоли | ✅ prod |
| `loglevel=3` | Только ошибки и критические | ✅ prod |
| `zswap.enabled=1` | Сжатие swap в RAM | ⚠️ только с ZRAM |

### 3.5 Файлы

- `build.conf.example` — `BUILD_BOOT_PROFILE`
- `src/lib/bootstrap.sh` — `bootstrap::cmdline_txt()`
- `src/conf/boot/cmdline.txt` — шаблон с плейсхолдерами

---

## 4. `config.txt` → `build.conf`

### 4.1 Параметры

```bash
# CPU
BUILD_CONFIG_ARM_BOOST=1          # 2.4 GHz boost (recommended)
BUILD_CONFIG_ARM_64BIT=1          # 64-bit kernel
# GPU
BUILD_CONFIG_VC4_KMS_V3D=1        # DRM graphics driver
BUILD_CONFIG_MAX_FRAMEBUFFERS=2   # dual display support
BUILD_CONFIG_DISABLE_OVERSCAN=1   # no overscan
BUILD_CONFIG_DISABLE_FW_KMS=1     # prefer KMS over firmware
# Connectivity
BUILD_CONFIG_DISABLE_WIFI=1       # disable onboard Wi-Fi
BUILD_CONFIG_DISABLE_BT=1         # disable onboard Bluetooth
BUILD_CONFIG_DT_PARAM_AUDIO=1     # onboard audio
# PCIe / NVMe
BUILD_CONFIG_PCIE_GEN=3           # 2 or 3
# Camera / Display
BUILD_CONFIG_CAMERA_AUTO=0
BUILD_CONFIG_DISPLAY_AUTO=0
# Overclocking (from section 2)
BUILD_ARM_FREQ=2800
BUILD_V3D_FREQ=960
BUILD_CORE_FREQ=910
BUILD_OVER_VOLTAGE_DELTA=20000
BUILD_FORCE_TURBO=0
```

### 4.2 Генерация config.txt

`bootstrap::config_txt()` собирает `config.txt` динамически из заданных параметров:
- Базовая структура ([pi5], [all]) — в коде
- Параметры подставляются через heredoc с условиями

### 4.3 Файлы

- `build.conf.example` — все переменные
- `src/lib/bootstrap.sh` — логика генерации
- `src/conf/boot/config.txt` — удалить (генерируется динамически)

---

## 5. `rpi5-eeprom` + `flashrom`

### 5.1 Пакеты

- `rpi5-eeprom` — из репозитория `alarm` (Arch Linux ARM), содержит прошивки EEPROM для BCM2712
- `flashrom` — опционально, для обновления прошивки

### 5.2 Переменная в build.conf

```bash
# Канал обновлений EEPROM: "default" (стабильный), "latest" (новейший)
BUILD_EEPROM_CHANNEL="default"
```

### 5.3 Настройка при сборке

```bash
# Установить конфиг для rpi-eeprom-update
echo "FIRMWARE_RELEASE_STATUS=\"$BUILD_EEPROM_CHANNEL\"" > "$target/etc/default/rpi-eeprom-update"
```

### 5.4 Файлы

- `build.conf.example` — `BUILD_EEPROM_CHANNEL`
- `src/lib/modules/services.sh` — настройка

---

## 6. Новая утилита: `nvme-cli`

Для NVMe-дисков: мониторинг SMART, прошивка, форматирование.

**Статус:** добавить в `BUILD_PACKAGES`, `build.conf.example`, `bootstrap.sh`.

---

## 7. Из официальной документации `config.txt`

### 7.1 Параметры, которые стоит рассмотреть

| Параметр | Эффект | Рекомендация |
|----------|--------|--------------|
| `kernel=kernel_2712.img` | 16K-оптимизированное ядро для Pi 5 | ✅ вместо `kernel8.img` |
| `boot_ramdisk=1` | Загрузка boot.img для secure-boot | ⚠️ опционально |
| `os_check=0` | Отключает проверку совместимости DTB | ❌ для dev, ✅ для prod |
| `DISABLE_HDMI=1` | Отключает HDMI-диагностику | ✅ headless (prod) |
| `kernel_watchdog_timeout=30` | Hardware watchdog на 30 сек | ⚠️ для серверов |
| `disable_splash=1` | Отключает rainbow screen | ✅ prod |
| `bootloader_update=0` | Блокирует самообновление bootloader | ❌ для prod |

### 7.2 `kernel_2712.img`

Pi 5 firmware по умолчанию ищет `kernel_2712.img` (16K pages) и fallback на `kernel8.img`. `linux-rpi-16k` должен предоставлять `kernel_2712.img`. Переключиться на него вместо `kernel8.img`.

---

## Порядок выполнения

| # | Задача | Приоритет | Зависимости |
|---|--------|-----------|-------------|
| 1 | `rpi5-eeprom` в пакеты + настройка канала | 🔴 HIGH | нет |
| 2 | `nvme-cli` в пакеты | 🔴 HIGH | нет |
| 3 | config.txt → build.conf (вынос параметров) | 🟡 MEDIUM | нет |
| 4 | kernel_2712.img вместо kernel8.img | 🟡 MEDIUM | нет |
| 5 | Разгон CPU/GPU в build.conf | 🟡 MEDIUM | п.3 |
| 6 | Два профиля cmdline.txt (debug/prod) | 🟡 MEDIUM | нет |
| 7 | Bcachefs | ⏸️ Отложен | ждать mainline |
