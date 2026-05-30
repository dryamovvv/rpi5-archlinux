# Arch Linux Audit Report — `archlinux-develop` (RPi5)

**Date:** 2026-05-30 | **Uptime:** 45 min | **Kernel:** `6.18.33-3-rpi-16k` | **Arch:** `aarch64`

---

## 1. System Overview

| Metric | Value |
|--------|-------|
| RAM | 16212M total, 15790M available (97% free) |
| Storage | 932G NVMe (`/dev/nvme0n1p2`), 19G used (2%) |
| Hostname | `archlinux-develop` |
| Failed services | 0 |
| Installed packages | 299 in pacman cache |

---

## 2. Packages & Databases

| DB | Last Sync | Age | Status |
|----|-----------|-----|--------|
| extra | 2026-05-30 | 5.9h | ✅ OK |
| core | 2026-05-28 | 35.7h | ❌ Stale |
| alarm | 2026-05-28 | 54.1h | ❌ Stale |
| aur | 2026-05-19 | 250.9h | ❌ Very stale |
| community | **2023-05-20** | **26540h** | ❌ 3+ years old |

| Check | Result |
|-------|--------|
| Pending updates | 0 |
| Orphans | 0 |
| Ignored packages | None |

**Fix:** `sudo pacman -Sy` (or `-Syu` for full update). The `community` DB from May 2023 is likely never synced — Arch ARM may not use it; verify if it should be disabled in `pacman.conf`.

---

## 3. Mirrors

| Check | Result |
|-------|--------|
| Health score | **45/100 (critical)** |
| Active mirrors | 1 of 13 |
| Active URL | `http://mirror.archlinuxarm.org/$arch/$repo` |
| Speed test | 510ms → 404 (likely testing wrong arch) |
| Redundancy | ❌ None |

**Fix:** Enable 2-3 geographically close mirrors from the 12 commented-out entries in `/etc/pacman.d/mirrorlist` (e.g., `de.mirror.archlinuxarm.org`, `fr.mirror.archlinuxarm.org`).

---

## 4. BTRFS Filesystem

| Item | Details |
|------|---------|
| Label | `archlinux` |
| Device | `/dev/nvme0n1p2` (932G) |
| Subvolumes | 15 (`@`, `@home`, `@snapshots`, `@swap`, `@var_log`, `@var_cache`, `@var_tmp`, `@var_lib`, ...) |
| Device errors | 0 |
| Scrub | No errors found |
| Snapper config | `root` (6 snapshots) |

**Snapper snapshots:**
| # | Type | Date | Description |
|---|------|------|-------------|
| 0 | single | current | baseline |
| 1-2 | pre/post | 08:25 today | `pacman -U arch-ops-server` |
| 3-4 | pre/post | 08:25 today | `pacman -R arch-ops-server` |
| 5 | single | 09:00 today | timeline |

---

## 5. Boot Logs — Errors

**`arch-ops-mcp.service` EXEC failures** (during boot before 08:25):
```
Failed at step EXEC spawning /root/.local/bin/arch-ops-server-http: No such file or directory
```
The service was restart-looped ~30 times between boot and 08:25, when the binary was installed. After reinstall, the MCP server is running normally. This was likely a transient issue during initial provisioning — the service no longer fails.

**SSH error (08:36):**
```
sshd-session: kex_exchange_identification: read: Connection reset by peer [preauth]
```
One connection reset from an external peer. Likely a port scan or aborted connection — benign unless recurring.

---

## 6. Critical Arch News (Require Attention)

| Title | Date | Severity |
|-------|------|----------|
| Breaking changes for `varnish` → `vinyl-cache` | 2026-05-25 | Critical |
| `kea >= 1:3.0.3-6` requires manual intervention | 2026-04-07 | Critical |
| `.NET` packages may require manual intervention | 2025-12-11 | Critical |
| `waydroid >= 1.5.4-3` may require manual intervention | 2025-11-06 | Critical |
| `dovecot >= 2.4` requires manual intervention | 2025-10-31 | Critical |
| `zabbix >= 7.4.1-2` may require manual intervention | 2025-08-04 | Critical |
| `linux-firmware >= 20250613` requires manual intervention | 2025-06-21 | Critical |

**Assessment:** None of these packages are likely installed on this minimal RPi5 image. Verify with `pacman -Qs "varnish|kea|dotnet|waydroid|dovecot|zabbix"` before ignoring. The `linux-firmware` one may be relevant — check with `pacman -Qs linux-firmware`.

---

## 7. Config (pacman.conf)

| Setting | Value |
|---------|-------|
| Repos | core, extra, alarm, aur |
| ParallelDownloads | 5 |
| SigLevel | Required DatabaseOptional |
| Architecture | aarch64 |
| HoldPkg | pacman, glibc |
| ignored_packages | (none) |

---

## 8. Priority Fixes

### Immediate
1. **Sync package databases:** `sudo pacman -Sy`
2. **Enable backup mirrors:** Uncomment 2-3 mirrors in `/etc/pacman.d/mirrorlist` for redundancy

### Soon
3. **Investigate `community` DB:** If unused on Arch ARM, remove from `pacman.conf` to avoid confusion
4. **Full system update:** `sudo pacman -Syu` (check Arch News for `linux-firmware` intervention if installed)

### Monitor
5. **SSH kex reset:** Watch for recurrence — if frequent, investigate (firewall, rate limiting)
6. **Snapper cleanup:** Ensure retention policy is configured (`snapper -c root set-config TIMELINE_LIMIT_HOURLY=...`)
