# AGENTS.md — rpi5-archlinux-image

Bash-скрипт для сборки Arch Linux ARM образа под Raspberry Pi 5.

## Быстрый старт

```bash
cp build.conf.example build.conf
./scripts/package.sh                                    # упаковать в dist/bin/
bash -n src/lib/*.sh src/lib/core/*.sh src/lib/modules/*.sh tests/*.sh
for t in tests/*.sh; do bash "$t" || echo "FAIL: $t"; done
./dist/bin/rpi5-archlinux-image validate
```

## Команды

```bash
./dist/bin/rpi5-archlinux-image build      # собрать RPi5 образ
./dist/bin/rpi5-archlinux-image build-qemu # собрать QEMU образ (тест на x86_64)
./dist/bin/rpi5-archlinux-image qemu-run   # запустить QEMU
./dist/bin/rpi5-archlinux-image validate   # проверить build.conf
./dist/bin/rpi5-archlinux-image list-steps # показать pipeline
```

## Файловая карта

| Путь | Назначение |
|------|-----------|
| `src/main.sh` | CLI entrypoint |
| `src/lib/bootstrap.sh` | in-target настройка (firstboot, fstab, mkinitcpio, network, sshd) |
| `src/lib/disk.sh` | loop-устройства, разделы, формат |
| `src/lib/core/` | config, runner, steps, modules, assets |
| `src/lib/modules/` | build-модули: disk_image, base_system, boot_config, services |
| `src/conf/boot/` | config.txt, cmdline.txt |
| `src/conf/systemd/` | firstboot unit, tty drop-in |
| `src/conf/pacman/` | pacman-arm.conf |
| `build.conf.example` | шаблон конфига |
| `scripts/package.sh` | упаковщик в один файл |
| `tests/` | 13 shell-тестов |
| `os_list.json` | для Network Install (RPi Imager) |

## Ключевые правила

1. **Всегда тестируй через QEMU перед коммитом** — см. `docs/qemu-testing.md`
2. **Не удаляй `config.txt`** — он статический, правки напрямую
3. **Пароли не хранить в коде** — пользователь задает при первой загрузке
4. **Отступ 4 пробела** в .sh, функции с namespace `module::function`
5. **Пуш в `dev`** триггерит ARM-сборку в CI. **В `main` без разрешения НЕ пушить.**
   ```bash
   git branch -f dev main && git push origin dev --force
   ```

## CI/CD

- **x86 (всегда):** bash -n + shellcheck + 13 тестов
- **ARM (только `dev`):** полная сборка + валидация boot-файлов
- **Release (теги `v*`):** ARM сборка → .img.xz + os_list.json → GitHub Release

## Границы (что не трогать)

- `src/conf/boot/config.txt` и `cmdline.txt` — только точечные правки по согласованию
- Не менять формат `build.conf` без обновления `config::validate`
- Не добавлять пароли/секреты в репо

## Подробные доки в `docs/`

- [build-pipeline.md](docs/build-pipeline.md) — 12 шагов сборки
- [qemu-testing.md](docs/qemu-testing.md) — QEMU тестирование и чек-лист
- [configuration.md](docs/configuration.md) — build.conf, config.txt, cmdline.txt
- [first-boot.md](docs/first-boot.md) — systemd-firstboot + firstboot flow
