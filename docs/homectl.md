# homectl integration

## Goal (implemented)

Replace `useradd` with `homectl --storage=subvolume` in the RPi5 image build pipeline.
Two modes at first boot:
1. **Pre-configured** — `user.json` generated at build time, `homectl create --identity`
2. **Interactive** — no `user.json`, `homectl firstboot` wizard on TTY
3. **Headless fallback** — no TTY, `useradd` + `chpasswd` (for QEMU/CI)

`BUILD_USER_NAME` is always required in `config::validate`. `BUILD_USER_PASSWORD` is optional — empty means interactive or headless fallback.

## Architecture

```
Build time:
  systemd-firstboot --root=$target --force --setup-machine-id
  → writes /etc/machine-id → ConditionFirstBoot=NO for ALL services
  bootstrap::firstboot_service()
    → [BUILD_USER_PASSWORD set] → generates user.json (openssl passwd -6)
    → creates /home/.ssh/ skeleton
    → writes firstboot.sh with __USER_NAME__ / __SWAPFILE_SIZE__ substituted

First boot:
  systemd-homed.service (enabled in build, Wants= in rpi5-firstboot.service)
    ↓
  rpi5-firstboot.service (After=systemd-firstboot.service systemd-homed.service)
    └── firstboot.sh
          ├── [user.json exists] → homectl create --identity=user.json --storage=subvolume
          ├── [fail, tty]        → homectl firstboot --prompt-new-user
          ├── [fail, no tty]     → useradd -m -G wheel + chpasswd -e
          ├── homectl update --member-of=wheel --stop-delay=30 --password-change-now=yes
          ├── loginctl enable-linger user
          ├── snapper -c user_home create-config (custom retention)
          └── btrfs swapfile creation (if SWAPFILE_SIZE is set)
```

Key decisions:
- `systemd-homed-firstboot.service` NOT enabled — redundant, `ConditionFirstBoot=yes` is false
- `--setup-machine-id` STAYS at build time — we don't touch PID1 behavior
- All user management in a single `firstboot.sh`

## Identity JSON format

Generated at build time in `bootstrap::firstboot_service()`:

```json
{
    "userName": "user",
    "uid": 1000,
    "gid": 1000,
    "realName": "",
    "shell": "/usr/bin/bash",
    "memberOf": [],
    "privileged": {
        "hashedPassword": ["$6$..."]
    }
}
```

The password hash is generated with `openssl passwd -6 $BUILD_USER_PASSWORD`.
Format: `hashedPassword` is a flat array of crypt strings (not nested lists with objects).

## Implementation files

| File | Changes |
|------|---------|
| `src/conf/systemd/firstboot.sh` | 3-tier user creation (homectl create → interactive → useradd), journal logging, homectl update, loginctl linger, snapper config, swapfile |
| `src/lib/bootstrap.sh` `bootstrap::firstboot_service()` | Generates `user.json` with openssl passwd -6, creates `/home/.ssh` skeleton, `__USER_NAME__`/`__SWAPFILE_SIZE__` substitution |
| `src/lib/bootstrap.sh` `bootstrap::mcp_server()` | Installs arch-ops-server via uv, generates API key, creates systemd unit |
| `src/conf/systemd/rpi5-firstboot.service` | `After=systemd-homed.service`, `Wants=systemd-homed.service` |
| `src/conf/systemd/arch-ops-mcp.service` | MCP HTTP server unit (EnvironmentFile, Restart=on-failure) |
| `src/lib/modules/services.sh` | Enables `systemd-homed.service` in `multi-user.target.wants`, calls `bootstrap::mcp_server()` |
| `build.conf.example` | `BUILD_USER_PASSWORD` comment mentions interactive mode, `uv` in packages |

## Snapshot non-recursion

`snapper -c user_home create-config /home/user.homedir` creates `.snapshots/` as a **nested subvolume**:

```
/home/user.homedir/            ← btrfs subvol (live, RW)
  ├── .snapshots/              ← nested btrfs subvol (RW)
  │   └── 1/snapshot/          ← read-only snapshot subvol
  ├── Documents/file1
  └── .bashrc
```

btrfs snapshot is **not recursive** — the nested `.snapshots/` subvolume is not copied into snapshots. Instead, an empty stub appears:

```
/home/user.homedir/.snapshots/2/snapshot/
  ├── .snapshots/              ← empty stub (nested subvol not copied)
  ├── Documents/file1          ← copied
  └── .bashrc                  ← copied
```

Each snapshot contains only the actual home data, without previous snapshots.

For root, snapper uses the separate top-level subvolume `@snapshots` (mounted at `/.snapshots`). For home, the nested subvolume approach is sufficient — no need for a separate top-level subvolume.

## Why `loginctl enable-linger` is needed for tmux

Arch Linux defaults to `KillUserProcesses=yes` (since systemd v246). When SSH disconnects, systemd kills the session scope — including tmux server and all child processes.

`loginctl enable-linger user` exempts the user: `user@.service` persists after logout, processes survive.

The per-user approach is better than `KillUserProcesses=no` (system-wide, weaker security).
