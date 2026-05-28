# homectl integration — plan

## Goal
Replace `useradd` with `homectl --storage=subvolume` in the RPi5 image build pipeline, with two modes:
1. **Interactive** — no user config in `build.conf`, wizard at first boot
2. **Non-interactive (config-driven)** — all settings in `build.conf`, silent first boot

Two modes are distinguished by whether `BUILD_USER_NAME` is set.

## Current architecture

```
Build time:
  systemd-firstboot --root=$target --force --setup-machine-id
  → writes /etc/machine-id → ConditionFirstBoot=NO for ALL services

First boot:
  rpi5-firstboot.service
    ├── After=systemd-firstboot.service
    └── firstboot.sh
          └── useradd -m -G wheel user; chage -d 0 user
```

## Target architecture

```
First boot:
  systemd-homed.service (enabled in build, starts at boot)
    ↓
  rpi5-firstboot.service (After=systemd-homed.service)
    └── firstboot.sh
          ├── [ -f user.json ] && homectl create --identity=user.json --storage=subvolume
          ├── homectl update user --member-of=wheel --stop-delay=30 --password-change-now=yes
          ├── loginctl enable-linger user
          └── snapper -c user_home create-config /home/user.homedir
```

**Ключевые решения:**
- `systemd-homed-firstboot.service` НЕ включаем — он лишний, ConditionFirstBoot=yes не играет
- `--setup-machine-id` ОСТАЁТСЯ в build-time — не лезем в поведение PID1
- Всё управление пользователем — в одном firstboot.sh

## Files to change

### `src/lib/bootstrap.sh`

#### `bootstrap::systemd_firstboot()`
No changes — `--setup-machine-id` stays. We don't rely on `ConditionFirstBoot=yes`.

#### `bootstrap::firstboot_service()`
Current:
```bash
if ! id -u "$user_name" >/dev/null 2>&1; then
    useradd -m -G wheel "$user_name"
    chage -d 0 "$user_name"
fi
```

New:

**Build time** (generates identity JSON):
```bash
local identity_path="$target/usr/local/lib/rpi5-archlinux/user.json"

if [[ -n "$user_name" ]]; then
    # Mode 2: pre-configured
    local password_hash
    password_hash=$(openssl passwd -6 "$BUILD_USER_PASSWORD" 2>/dev/null || echo "")
    [[ -z "$password_hash" ]] && password_hash=$(python3 -c "
import crypt; print(crypt.crypt('$BUILD_USER_PASSWORD', crypt.mksalt(crypt.METHOD_SHA512)))
")

    cat > "$identity_path" <<JSON
{
    "userName": "$user_name",
    "uid": 1000,
    "gid": 1000,
    "realName": "",
    "shell": "/usr/bin/bash",
    "memberOf": [],
    "privileged": {
        "hashedPassword": [["password", "", {"crypt": {"salted": "$password_hash"}}]]
    }
}
JSON
    chmod 0600 "$identity_path"
fi

# Create .ssh directory with authorized_keys placeholder
mkdir -p "$target/home/.ssh"
chmod 0700 "$target/home/.ssh"
```

**First boot (firstboot.sh)**:
```bash
#!/bin/bash
set -euo pipefail

USER_NAME="${BUILD_USER_NAME:-}"
IDENTITY_FILE="/usr/local/lib/rpi5-archlinux/user.json"

# Wait for systemd-homed to be ready
for i in 1 2 3 4 5; do
    if systemctl is-active systemd-homed.service >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

# Check if user already exists (via homectl or /etc/passwd)
if ! id -u "$USER_NAME" >/dev/null 2>&1; then
    if [[ -f "$IDENTITY_FILE" ]]; then
        # Mode 2: create from identity file
        homectl create --identity="$IDENTITY_FILE" --storage=subvolume
    else
        # Mode 1: interactive wizard (physical TTY or serial console)
        homectl firstboot --prompt-new-user --prompt-shell=no --prompt-groups=no --mute-console=yes
        USER_NAME=$(homectl list -j 2>/dev/null | python3 -c "
import sys,json; data=json.load(sys.stdin);
print(data[0]['userName'] if data else '')" 2>/dev/null)
    fi
fi

if [[ -n "$USER_NAME" ]]; then
    # Post-setup (замена старого chage -d 0 — принудительная смена пароля при первом входе)
    homectl update "$USER_NAME" --member-of=wheel --stop-delay=30 --password-change-now=yes || true

    # Linger for tmux
    loginctl enable-linger "$USER_NAME" 2>/dev/null || true

    # SSH authorized_keys from skeleton
    if [[ -f "/home/.ssh/authorized_keys" ]]; then
        local user_home
        user_home=$(getent passwd "$USER_NAME" | cut -d: -f6)
        mkdir -p "$user_home/.ssh"
        chmod 0700 "$user_home/.ssh"
        cp "/home/.ssh/authorized_keys" "$user_home/.ssh/"
        chmod 0600 "$user_home/.ssh/authorized_keys"
        chown -R "$USER_NAME:$USER_NAME" "$user_home/.ssh"
    fi

    # Snapper config for home subvol
    if ! snapper -c user_home list >/dev/null 2>&1; then
        user_home_dir=$(getent passwd "$USER_NAME" | cut -d: -f6)
        snapper -c user_home create-config "$user_home_dir"
        # Custom retention for home
        sed -i 's/^TIMELINE_LIMIT_HOURLY=.*/TIMELINE_LIMIT_HOURLY="5"/' /etc/snapper/configs/user_home
        sed -i 's/^TIMELINE_LIMIT_DAILY=.*/TIMELINE_LIMIT_DAILY="7"/' /etc/snapper/configs/user_home
        sed -i 's/^TIMELINE_LIMIT_WEEKLY=.*/TIMELINE_LIMIT_WEEKLY="4"/' /etc/snapper/configs/user_home
        sed -i 's/^TIMELINE_LIMIT_MONTHLY=.*/TIMELINE_LIMIT_MONTHLY="3"/' /etc/snapper/configs/user_home
    fi
fi
```

### Snapshot non-recursion (why it works)

**Вопрос:** Не попадут ли снапшоты внутрь себя (рекурсия)?

**Ответ:** Нет, и вот почему.

`snapper -c user_home create-config /home/user.homedir` по умолчанию создаёт `.snapshots/` как **nested subvolume** (вложенный подтом), а не как обычную папку:

```
/home/user.homedir/            ← btrfs subvol (live, RW)
  ├── .snapshots/              ← btrfs subvol (nested, RW)
  │   └── 1/snapshot/          ← btrfs subvol (read-only)
  ├── Documents/file1
  └── .bashrc
```

Когда homectl снимает снапшот:

```bash
btrfs subvolume snapshot -r /home/user.homedir /home/user.homedir/.snapshots/2/snapshot
```

btrfs snapshot **не рекурсивен** — вложенный subvolume `.snapshots/` **не копируется**, вместо него в снапшоте появляется пустая заглушка:

```
/home/user.homedir/.snapshots/2/snapshot/
  ├── .snapshots/              ← заглушка (empty stub, nested subvol не скопирован)
  ├── Documents/file1          ← скопирован
  └── .bashrc                  ← скопирован
```

Каждый снапшот содержит только данные самого home, без предыдущих снапшотов.

**Отличие от root:** Корневой snapper использует отдельный top-level subvolume `@snapshots`, смонтированный в `/.snapshots`. Это нужно, потому что корень (`@`) и его снапшоты на одном уровне. Для home это не требуется — nested subvolume внутри `@home` решает проблему изолированности.

**Итог:** Рекурсии нет. Snapshot содержит только актуальное состояние home, `.snapshots/` внутри — пустой stub.

#### `bootstrap::configure_services()` (or equivalent)
Add:

```bash
# systemd-homed (необходим для homectl create на первом старте)
bootstrap::systemd_enable_unit "$target" "systemd-homed.service" "multi-user.target.wants"
```

`systemd-homed-firstboot.service` **НЕ включаем** — он не нужен (ConditionFirstBoot не сработает, wizard интерактивный).

#### `bootstrap::generate_btrfs_fstab()`
No changes needed — systemd-homed with `--storage=subvolume` creates its own subvolume inside `/home` (within `@home`), managed by homed. No extra fstab entry needed.

### `src/conf/systemd/rpi5-firstboot.service`

Add dependency on systemd-homed:

```ini
[Unit]
Description=Complete first boot provisioning
After=systemd-firstboot.service systemd-homed.service
Wants=systemd-homed.service

[Service]
Type=oneshot
ExecStart=/usr/local/lib/rpi5-archlinux/firstboot.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

### `src/lib/modules/services.sh`
Add `systemd-homed.service` enablement in `services::configure_services()`.

### `build.conf.example`
No changes — variables stay the same.

## Blockers / Risks

1. **`homectl firstboot` (interactive) on serial console:** Works if `console=ttyAMA0` and there's a terminal connected. On headless (SSH-only), it blocks indefinitely. Our firstboot script should timeout.

2. **`snapper -c user_home create-config /home/user.homedir`:** The homectl subvolume is created by homed at first boot (via `homectl create`). The snapper config creation runs AFTER user creation in firstboot.sh. This is fine — the subvolume exists at that point.

## Why `loginctl enable-linger` is needed for tmux

Arch Linux defaults to `KillUserProcesses=yes` (since systemd v246). When SSH disconnects, systemd kills the session scope — including tmux server and all processes inside it.

`loginctl enable-linger user` exempts the user from this: the `user@.service` persists after logout, and processes survive.

Tested on the target system: `#KillUserProcesses=no` in `/etc/systemd/logind.conf` (commented out = default `yes`), no linger files in `/var/lib/systemd/linger/`. Without linger, tmux dies on SSH disconnect. With linger, it survives.

The per-user approach is better than `KillUserProcesses=no` (system-wide, weaker security).

## Open questions

(нет)
