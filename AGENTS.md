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
| `src/lib/bootstrap.sh` | in-target настройка (firstboot, fstab, mkinitcpio, network, sshd, mcp_server) |
| `src/lib/disk.sh` | loop-устройства, разделы, формат |
| `src/lib/core/` | config, runner, steps, modules, assets |
| `src/lib/modules/` | build-модули: disk_image, base_system, boot_config, services |
| `src/conf/boot/` | config.txt, cmdline.txt |
| `src/conf/systemd/` | firstboot unit, tty drop-in, arch-ops-mcp.service |
| `src/conf/pacman/` | pacman-arm.conf |
| `src/conf/firstboot/` | deprecated (deleted); user creation is manual after first boot |
| `build.conf.example` | шаблон конфига |
| `scripts/package.sh` | упаковщик в один файл |
| `tests/` | 13 shell-тестов |
| `os_list.json` | для Network Install (RPi Imager) |
| `docs/arch-mcp.md` | arch-ops-server (встроен в образ, Bearer auth) |
| `docs/homectl.md` | попытка интеграции homectl; откат на useradd (v0.5.0) |
| `docs/skills/` | opencode skills (arch-linux-mcp, arch-audit) для `~/.agents/skills/` |

## Ключевые правила

1. **Всегда тестируй через QEMU перед коммитом** — см. `docs/qemu-testing.md`
2. **Не удаляй `config.txt`** — он статический, правки напрямую
3. **Пароли не хранить в коде** — `BUILD_ROOT_PASSWORD` задается в `build.conf`, пользователей создавать вручную после первой загрузки (`useradd -m -G wheel user`)
4. **Отступ 4 пробела** в .sh, функции с namespace `module::function`
5. **Пуш в `dev`** триггерит ARM-сборку в CI. **В `main` без разрешения НЕ пушить.**
   ```bash
   git branch -f dev main && git push origin dev --force
   ```
6. **Релиз:** когда пользователь говорит «релиз» или «выпускаем» — мерж `dev` → `main`, тег `v*`, пуш:
   ```bash
   git checkout main && git merge dev && git tag v0.4.0 && git push origin main --tags
   ```

## /arch_audit

Comprehensive system audit using all MCP tools. Type `/arch_audit` to get a structured report: system overview, health, packages, configs, mirrors, news, orphans, boot logs. Useful after new image releases.

## CI/CD

- **x86 (всегда):** bash -n + shellcheck + 10 тестов в CI
- **ARM (`dev` и `homectl_feature`):** полная сборка + валидация boot-файлов
- **Release (теги `v*`):** ARM сборка → .img.xz + os_list.json → GitHub Release

## Границы (что не трогать)

- `src/conf/boot/config.txt` и `cmdline.txt` — только точечные правки по согласованию
- Не менять формат `build.conf` без обновления `config::validate`
- Не добавлять пароли/секреты в репо

## MCP arch-linux (remote HTTP через arch-ops-server)

23 инструмента для управления RPi5 Arch Linux через opencode:

**Система:** `get_system_info`, `diagnose_system`, `run_system_health_check`, `analyze_storage`
**Пакеты:** `get_official_package_info`, `check_updates_dry_run`, `install_package_secure`, `remove_packages`, `query_file_ownership`, `query_package_history`, `verify_package_integrity`, `manage_install_reason`, `manage_orphans`, `manage_groups`
**AUR:** `search_aur`, `audit_package_security`
**Конфиги:** `analyze_pacman_conf`, `analyze_makepkg_conf`
**Зеркала:** `optimize_mirrors`
**Новости:** `fetch_news`
**База данных:** `check_database_freshness`
**Arch Wiki:** `search_archwiki`
**Безопасность:** `check_failed_services`, `get_boot_logs`

Сервер: [dryamovvv/arch-mcp](https://github.com/dryamovvv/arch-mcp) (форк с Bearer auth), systemd unit `arch-ops-mcp.service` на RPi5, ключ в `~/.config/opencode/api-key`. MCP-сервер встраивается в образ автоматически при сборке (`bootstrap::mcp_server()`). API-ключ сохраняется в `<image>.mcp-key`. См. [docs/arch-mcp.md](docs/arch-mcp.md).

## Подробные доки в `docs/`

- [build-pipeline.md](docs/build-pipeline.md) — 12 шагов сборки
- [qemu-testing.md](docs/qemu-testing.md) — QEMU тестирование и чек-лист
- [configuration.md](docs/configuration.md) — build.conf, config.txt, cmdline.txt
- [first-boot.md](docs/first-boot.md) — systemd-firstboot + firstboot flow
- [arch-mcp.md](docs/arch-mcp.md) — форк arch-ops-server (HTTP + Bearer auth)
- [homectl.md](docs/homectl.md) — попытка интеграции homectl; откат на useradd (v0.5.0)
- [backup.md](docs/backup.md) — btrbk: инкрементальные бэкапы сценарии local/SSH/cold-storage
