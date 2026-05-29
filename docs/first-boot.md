# First Boot Flow

## Boot order

```
sysinit.target
  └─ systemd-firstboot.service   # interactive tty: hostname, timezone, root password
  └─ systemd-repart.service      # expands root partition
  └─ systemd-growfs-root.service # expands filesystem

multi-user.target
  └─ systemd-homed.service       # starts before rpi5-firstboot (Wants=, After=)
  └─ rpi5-firstboot.service      # homectl create / interactive / useradd fallback
```

## systemd-firstboot

**At build time** (`bootstrap::systemd_firstboot`): writes locale, keymap, shell, machine-id with `--force`.
When `BUILD_HOSTNAME`, `BUILD_TIMEZONE`, `BUILD_ROOT_PASSWORD` are set — writes those too.
When unset, the corresponding files are not created, so `systemd-firstboot` prompts interactively at runtime.

**tty drop-in** (`src/conf/systemd/systemd-firstboot.service.d/prompt.conf`):
```ini
[Service]
StandardInput=tty
StandardOutput=tty
TTYPath=/dev/console
```
Grabs the console — prompts are not overwritten by log output.

## rpi5-firstboot.service

### Dependencies

```ini
[Unit]
After=systemd-firstboot.service systemd-homed.service
Wants=systemd-homed.service
```

The service waits for `systemd-homed.service` to start (with `Wants=`, not `Requires=`, so firstboot proceeds even if homed fails).

### Script (`/usr/local/lib/rpi5-archlinux/firstboot.sh`)

At build time, `bootstrap::firstboot_service()`:
1. If `BUILD_USER_PASSWORD` is set: generates `/usr/local/lib/rpi5-archlinux/user.json` with a SHA-512 hashed password (`openssl passwd -6`).
2. Creates `/home/.ssh/` skeleton directory for SSH authorized_keys.
3. Writes `firstboot.sh` with `__USER_NAME__` and `__SWAPFILE_SIZE__` substituted.

At first boot, the script runs a 3-tier user creation logic:

#### Tier 1: `homectl create --identity=user.json`

If `user.json` exists and `homectl create` succeeds, the user is created as a systemd-homed user with `--storage=subvolume`. Home directory: `/home/$USER.homedir` (btrfs subvolume inside `@home`).

#### Tier 2: `homectl firstboot` (interactive)

If tier 1 fails or `user.json` is missing, and a TTY is present (`[[ -t 0 ]]`):
- `homectl firstboot --prompt-new-user` launches an interactive wizard on the console.
- After creation, the script extracts the username via `homectl list -j`.

#### Tier 3: `useradd` (headless fallback)

If tier 1 fails AND there is no TTY (headless/QEMU):
- `useradd -m -G wheel "$USER_NAME"` creates a traditional local user.
- If `user.json` exists: sets the password via `chpasswd -e` (extracts hash from JSON).
- If `user.json` is missing: sets empty password via `passwd -d`.

### Post-creation setup

After user creation (regardless of tier):

1. **homed update**: if the user is managed by systemd-homed, runs:
   ```
   homectl update $USER_NAME --member-of=wheel --stop-delay=30 --password-change-now=yes
   ```
   This forces a password change on first login (replaces the old `chage -d 0`).

2. **linger**: `loginctl enable-linger $USER_NAME` — keeps user services (tmux, etc.) alive after SSH disconnect.

3. **SSH keys**: copies `/home/.ssh/authorized_keys` to the user's actual home directory (`~/.ssh/`).

4. **snapper**: creates a snapper config for the user home subvolume (`snapper -c user_home create-config`) with custom retention:
   - Hourly: 5, Daily: 7, Weekly: 4, Monthly: 3

5. **swapfile** (btrfs only): if `SWAPFILE_SIZE` is set, creates a btrfs swapfile in the `@swap` subvolume and activates it.

## Partition / filesystem grow

Native systemd units, enabled at build time:
- `systemd-repart.service` — expands root partition using `/etc/repart.d/50-root.conf` (`GrowFileSystem=yes`)
- `systemd-growfs-root.service` — expands the filesystem to fill the partition

## Locales

`locale-gen` runs at build time (chroot) after `systemd-firstboot`.
`en_US.UTF-8` is added to `/etc/locale.gen` via `bootstrap::locale_gen_file()`.
