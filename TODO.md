# TODO — Этап: производительность и расширенные настройки

> На основе NEXT.md, обсуждения и исследования (май 2026)

---

## 1. Bcachefs (отложен)

**Статус:** ⏸️ Отложен до стабилизации в mainline

**Причина:** модуль `bcachefs` удален из дерева ядра в Linux 6.18. Требуется `bcachefs-dkms` (AUR) + `linux-rpi-16k-headers` + DKMS при каждом обновлении ядра.

---

## 2. Новые пакеты

### 2.1 `rpi5-eeprom`

- Репо: `alarm` (Arch Linux ARM)
- Содержит прошивки EEPROM для BCM2712
- Зависимость: `flashrom` (опционально)

**build.conf:**
```bash
BUILD_EEPROM_CHANNEL="latest"   # канал обновлений: "default" или "latest"
```

**Настройка при сборке:**
```bash
echo 'FIRMWARE_RELEASE_STATUS="latest"' > "$target/etc/default/rpi-eeprom-update"
```
⚠️ Путь `/etc/default/rpi-eeprom-update` — проверить на Arch ARM после установки пакета.

### 2.2 `nvme-cli`

NVMe-диски: SMART, прошивка, форматирование.

### 2.3 `stress-ng` + `fio` + `s-tui` + `hdparm` + `btop`

Стресс-тесты, бенчмарки SSD, мониторинг температуры.

---

## 3. config.txt — точечные правки

Файл остается статическим в `src/conf/boot/config.txt`. Точечные изменения:

### 3.1 Убрать `kernel=kernel8.img` (если `linux-rpi-16k` кладет `kernel_2712.img`)

⚠️ **Проверить:** после `pacstrap` зайти в `/boot` на образе, проверить наличие `kernel_2712.img`. Если есть — убрать строку `kernel=kernel8.img` из `config.txt`. Прошивка Pi 5 сама выберет 16K-ядро.

### 3.2 Добавить `disable_splash=1`

Убирает rainbow screen при загрузке. В секцию `[pi5]`.

### 3.3 Параметры разгона

Добавить в секцию `[pi5]` (сейчас нет):
```ini
# Безопасный разгон (Active Cooler обязателен)
arm_freq=2800
over_voltage_delta=25000
# gpu_freq/v3d_freq НЕ ЗАДАВАТЬ — ограничивает потолок CPU
```

### 3.4 SDRAM (EEPROM, не config.txt)

Документировать в README:
```bash
sudo rpi-eeprom-config --edit
# добавить: SDRAM_BANKLOW=1
```

---

## 4. cmdline.txt — точечные правки

Файл остается статическим в `src/conf/boot/cmdline.txt`. Добавить:

```diff
- root=UUID=__ROOT_UUID__ rw rootwait console=tty1 fsck.repair=yes
+ root=UUID=__ROOT_UUID__ rw rootwait console=tty1 fsck.repair=yes quiet loglevel=3 mitigations=off nowatchdog
```

| Параметр | Зачем | Безопасно? |
|----------|-------|------------|
| `quiet` | Нет логов ядра на консоли | ✅ |
| `loglevel=3` | Только KERN_ERR и выше | ✅ |
| `mitigations=off` | +5-10% CPU | ✅ Cortex-A76 не подвержен Spectre/Meltdown |
| `nowatchdog` | Безопасно для headless | ✅ |

### 4.1 NUMA (отдельно)

```
numa=fake=8
```

⚠️ **Проверить** на живой Pi: `ls /sys/devices/system/node/`. Если node0, node1... → добавить в cmdline.txt. Если нет → `CONFIG_NUMA_EMULATION` не собрана в ядре.

---

## Порядок

| # | Задача |
|---|--------|
| 1 | `rpi5-eeprom` + `nvme-cli` + бенчмарки в пакеты |
| 2 | config.txt: убрать kernel8, добавить disable_splash, добавить разгон |
| 3 | cmdline.txt: quiet + mitigations=off + nowatchdog |
| 4 | Проверить `kernel_2712.img` и NUMA на живой Pi |
| 5 | Bcachefs — отложен |
