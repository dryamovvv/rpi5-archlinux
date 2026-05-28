---
name: arch-linux-mcp
description: Load when the user mentions Raspberry Pi 5, Arch Linux ARM, package management, system diagnostics, pacman, AUR, or the remote rpi5-archlinux project. Activates for troubleshooting, health checks, package operations, and system configuration questions.
---

When the user asks about their Arch Linux RPi5 server, use the `arch-linux` MCP to manage it remotely.

## Available Tools

| Category | Tools |
|----------|-------|
| **System** | `get_system_info`, `diagnose_system` (failed_services, boot_logs), `run_system_health_check`, `analyze_storage` (disk_usage, cache_stats) |
| **Official packages** | `get_official_package_info`, `check_updates_dry_run`, `install_package_secure`, `remove_packages`, `query_file_ownership` (3 modes), `query_package_history` (4 types), `verify_package_integrity`, `manage_install_reason`, `manage_orphans`, `manage_groups` |
| **AUR** | `search_aur`, `audit_package_security` |
| **Configs** | `analyze_pacman_conf` (full / ignored_packages / parallel_downloads), `analyze_makepkg_conf` |
| **Mirrors** | `optimize_mirrors` (status / test / suggest / health) |
| **News** | `fetch_news` (latest / critical / since_update) |
| **Wiki** | `search_archwiki` |
| **DB** | `check_database_freshness` |

## How to Use

Call tools using `arch-linux_TOOL_NAME`. For example:

- `arch-linux_get_system_info` — check kernel, uptime, disk
- `arch-linux_run_system_health_check` — comprehensive health
- `arch-linux_install_package_secure` — install with security audit
- `arch-linux_optimize_mirrors action="suggest" country="RU"` — suggest mirrors

## Safety

- All tools are read-only by default (system info, searches, checks)
- Package install/remove require explicit user confirmation via `--noconfirm`
- AUR packages get automatic security audit before install
