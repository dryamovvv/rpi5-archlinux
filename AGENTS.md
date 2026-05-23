# Repository Guidelines

## Project Structure & Module Organization
Этот репозиторий собирает образ Arch Linux для Raspberry Pi 5 с помощью Bash-скриптов. `scripts/main.sh` — единственный поддерживаемый entrypoint. Общая логика вынесена в `lib/` (`disk.sh`, `bootstrap.sh`, `log.sh`, `colors.sh`). Каталог `conf/` хранит активные статические ресурсы сборки; reference-шаблоны вынесены в `conf/reference/`. В текущем build path реально используется `conf/pacman-arm.conf`, а `cmdline.txt` и `config.txt` сейчас генерируются из `lib/bootstrap.sh`. Артефакты сборки, такие как `arch_root.img`, не должны попадать в коммиты.

## Build, Test, and Development Commands
Запускайте основной сценарий командой `sudo ./scripts/main.sh`; он создает и настраивает `arch_root.img`. Перед коммитом выполняйте `bash -n scripts/*.sh lib/*.sh tests/*.sh` для быстрой проверки синтаксиса всех поддерживаемых shell-файлов. Если установлен `shellcheck`, запускайте `shellcheck scripts/*.sh lib/*.sh tests/*.sh`, чтобы поймать проблемы с quoting, `source` и переносимостью. Релизный workflow публикует `arch_root.img.xz`, а не сырой `.img`, из-за лимита GitHub Release на размер asset, и собирает образ напрямую на native `ubuntu-24.04-arm` runner без собственного builder-контейнера. Проверять итоговый образ удобно стандартными системными утилитами, например `losetup -fP arch_root.img` и `mount`.

## Coding Style & Naming Conventions
Пишите Bash-скрипты с `#!/bin/bash`, `set -e` и `set -o pipefail`, если скрипт оркестрирует системные изменения. Придерживайтесь текущего стиля: отступ 4 пробела, глобальные конфигурационные переменные в `readonly` и верхнем регистре, функции с namespace, например `disk::create_image` и `bootstrap::install_base`. Имена файлов держите в нижнем регистре с суффиксом `.sh`. Вместо обычного `echo` предпочитайте явное логирование через `log::info`, `log::warn` и `log::die`.

## Testing Guidelines
Формального тестового фреймворка пока нет, поэтому проверка сейчас в основном shell-based и ручная. Минимум — прогонять `bash -n`, запускать smoke-проверки из `tests/` и валидировать workflow YAML. Проверять измененный build path нужно через `sudo ./scripts/main.sh` или соответствующий GitHub Actions workflow. Build-time настройка должна по возможности избегать `arch-chroot`; предпочтительны `systemd-firstboot`, прямые file writes и first-boot service. При изменении `conf/` сначала проверьте, подключен ли файл к реальному build path; не предполагается, что любой файл из `conf/` автоматически попадает в образ. Ручную валидацию фиксируйте в описании PR.

## Commit & Pull Request Guidelines
Текущая история использует короткие заголовки в повелительном наклонении (`Initial commit`). Сохраняйте commit message краткими и ориентированными на действие, например `Fix loop device cleanup` или `Update pacstrap package list`. В pull request описывайте изменение в процессе сборки образа, перечисляйте команды для проверки и отдельно отмечайте требования к хосту, потенциально опасные операции с дисками и любые изменения, влияющие на загрузку Raspberry Pi.

## Security & Configuration Tips
Эти скрипты предполагают root-права и работают с loop-устройствами, mount-операциями и boot-конфигурацией. Не хардкодьте реальные учетные данные; значения по умолчанию, включая временные пароли, допустимы только для разработки и должны быть заменены перед использованием образа.
