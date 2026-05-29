# QEMU Testing

**Порядок работы:** изменил код → `./scripts/package.sh` → `validate` + тесты → коммит → пуш в `dev` → CI собирает на ARM (~2 мин) → проверяем результат.

Локальный QEMU — только если нет интернета или CI недоступен (x86_64, ~25 мин).

## Команды

```bash
# Быстрая проверка без QEMU (30 сек)
cp build.conf.example build.conf && ./scripts/package.sh && for t in tests/*.sh; do bash $t >/dev/null 2>&1 && echo PASS: $t || echo FAIL: $t; done && ./dist/bin/rpi5-archlinux-image validate

# Полный цикл (25 мин)
rm -f dist/images/archlinux-qemu-aarch64.img
./dist/bin/rpi5-archlinux-image build-qemu 2>&1 | tee build-qemu.log
sudo pkill -f qemu-system 2>/dev/null; sleep 1
./dist/bin/rpi5-archlinux-image qemu-run 2>&1 | tee qemu-boot.log &
```

## Чек-лист после QEMU

```bash
# 1. В сборке 0 ошибок
grep -c '\[FAIL\]' build-qemu.log  # → 0

# 2. Сборка завершена
grep 'Image build completed' build-qemu.log  # должен быть

# 3. Firstboot отработал
grep 'Finished Complete first boot' qemu-boot.log  # должен быть

# 4. Нет ошибок при загрузке (regulatory.db можно игнорировать)
grep 'FAILED\|error\|Error' qemu-boot.log | grep -v regulatory.db

# 5. Пробуем SSH
ssh -p 2222 user@localhost  # пароль из BUILD_USER_PASSWORD (по умолчанию 'user'), сменит при входе
systemctl is-system-running  # → running
systemctl list-units --state=failed  # → пусто
# Для homectl: проверка пользователя
homectl list  # должен показать user
systemctl status systemd-homed.service  # → active
# Проверка MCP-сервера (порт 8080)
curl http://localhost:8080/health
cat dist/images/archlinux-qemu-aarch64.img.mcp-key  # API-ключ
```

## Ограничения QEMU

- `config.txt` не используется — overclock, GPU, device tree не тестируются
- `systemd-firstboot` не интерактивен — hostname из `BUILD_HOSTNAME` (по умолчанию `archlinux-develop`)
- Ядро: `linux-aarch64` (не `linux-rpi-16k`)
- Сборка x86_64 через qemu-user-static: ~25 мин (ARM: 2 мин)

## Что проверять на реальном Pi

- Загрузка с `config.txt` (overclock, disable_splash)
- Интерактивный `systemd-firstboot` (hostname, timezone, root password)
- `vcgencmd get_throttled` → `0x0` (нет троттлинга)
- Температура: `vcgencmd measure_temp`
