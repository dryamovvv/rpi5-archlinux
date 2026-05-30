# btrbk backup

`btrbk` is a backup tool for BTRFS subvolumes. It uses `btrfs send` / `btrfs receive` for incremental
transfers and supports local, remote (SSH), and file-based (`raw_target`) targets.

`btrbk` is included in the image as a package — no timers or configs are enabled by default.
Configure manually after first boot.

## Quick local snapshot

```bash
# Show what would be backed up (dry-run)
sudo btrbk -v dryrun

# Run once (snapshot only, no send)
sudo btrbk snapshot

# List snapshots
sudo btrfs subvolume list -t /btrbk
```

Default snapshots go to `/btrbk/<hostname>.<subvol>.*` at the top level (subvolid=5).

## Scenario 1: local incremental backups

Create `/etc/btrbk/btrbk.conf`:

```conf
transaction_log         /var/log/btrbk.log
timestamp_format        long

snapshot_preserve_min      7d
snapshot_preserve          7 4 1

target_preserve_min        7d
target_preserve            7 4 1

volume /mnt/btrfs_pool
    subvolume @
        snapshot_name      root
    subvolume @home
        snapshot_name      home

    target send-receive    /mnt/btrfs_backup
```

Run daily via systemd timer:

```bash
sudo systemctl enable --now btrbk.timer  # daily by default
```

## Scenario 2: cold storage to any filesystem (raw_target)

Useful for backing up to a router with USB drive (ext4/NTFS/exFAT — no BTRFS needed).

```conf
transaction_log         /var/log/btrbk.log
timestamp_format        long

target_preserve_min        30d
target_preserve            7 4

volume /
    subvolume @
        snapshot_name      root
    subvolume @home
        snapshot_name      home

    target raw_target      /mnt/backup/
```

The router USB drive must be mounted first:

```bash
# Mount the USB drive
sudo mount /dev/sda1 /mnt/backup
# Run backup (incremental, compressed)
sudo btrbk -v run
```

raw_target outputs `.btrfs.xz` files to any filesystem. Restore is two-step:
`xz -d < snapshot.btrfs.xz | btrfs receive <target>`.

### SSH-only access to the router

Use ssh_filter_btrbk.sh to restrict the SSH key to btrbk commands only:

```bash
# On the router, create a dedicated user
sudo useradd -m -s /bin/bash btrbk-backup
# Copy ssh_filter_btrbk.sh to the router
sudo cp /usr/share/btrbk/ssh_filter_btrbk.sh /home/btrbk-backup/
sudo chmod 755 /home/btrbk-backup/ssh_filter_btrbk.sh
```

In `/home/btrbk-backup/.ssh/authorized_keys` on the router:

```
command="/home/btrbk-backup/ssh_filter_btrbk.sh",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty ssh-ed25519 AAA...
```

In `btrbk.conf` on RPi5:

```conf
target raw_target ssh://btrbk-backup@192.168.1.1/mnt/backup/
```

```bash
sudo btrbk -v run
```

## Scenario 3: full BTRFS remote server

If the target is also BTRFS, use `send-receive` for native incremental transfers:

```conf
volume /
    subvolume @
        snapshot_name root
    subvolume @home
        snapshot_name home

    target send-receive ssh://btrbk@backup-server/mnt/btrfs_backup
```

The target server needs:
- BTRFS filesystem
- btrbk package installed
- SSH key with ssh_filter_btrbk.sh

## Restore

### From raw_target (.btrfs.xz file)

```bash
# Decompress and restore @ subvolume
mount /dev/sda1 /mnt/backup
xz -d < /mnt/backup/root.latest.btrfs.xz | sudo btrfs receive /mnt/restore
```

### From send-receive target

```bash
# The target already has the subvolumes, just snapshot them back
sudo btrfs subvolume snapshot /mnt/btrfs_backup/root /mnt/btrfs_backup/root.restore
# Then send back to RPi5
sudo btrfs send /mnt/btrfs_backup/root.restore | ssh root@rpi5 "btrfs receive /mnt/restore"
```

## Arch Wiki

https://wiki.archlinux.org/title/btrbk
