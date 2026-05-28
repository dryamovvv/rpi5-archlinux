---
name: arch-audit
description: |
  Triggered by `/arch_audit` — comprehensive Arch Linux system audit using all arch-linux MCP tools.
  Runs all diagnostics and produces a structured report. Use after new image releases to verify RPi5 health.
---

When the user types `/arch_audit`, perform a comprehensive system audit of the remote RPi5
using the `arch-linux` MCP. Run ALL tools in parallel where possible, compile results into
a structured report.

## Audit Plan (run in parallel batches)

### Batch 1 — no dependencies (all parallel)
- `arch-linux_get_system_info`
- `arch-linux_run_system_health_check`
- `arch-linux_analyze_storage action="disk_usage"`
- `arch-linux_analyze_storage action="cache_stats"`
- `arch-linux_diagnose_system action="failed_services"`
- `arch-linux_check_updates_dry_run`
- `arch-linux_check_database_freshness`
- `arch-linux_manage_orphans action="list"`
- `arch-linux_analyze_pacman_conf`
- `arch-linux_analyze_makepkg_conf`
- `arch-linux_fetch_news action="critical"`
- `arch-linux_optimize_mirrors action="health"`

### Batch 2 (after batch 1 if needed)
- `arch-linux_diagnose_system action="boot_logs" lines=50` — if health check shows issues
- `arch-linux_get_official_package_info package_name="linux-rpi-16k"` — verify kernel package status
- `arch-linux_get_official_package_info package_name="systemd"` — verify systemd status

## Report Format

Present the results as a structured markdown report:

```markdown
## 🖥 System Overview
- Hostname, kernel, arch, uptime, RAM

## ❤️ Health
- Failed services, disk usage, orphan count
- Database freshness, updates available

## 📦 Packages
- Update count and size
- Integrity of key packages (linux-rpi-16k, systemd)

## ⚙️ Config
- Pacman settings (parallel downloads, ignored packages)
- Makepkg settings (MAKEFLAGS, compression)

## 📡 Mirrors
- Status and health
- Recommendations if any

## 📰 Critical News
- Any Arch Linux news requiring manual intervention

## 🗑 Orphans
- Orphaned packages and reclaimable space

## 🐚 Boot Logs (if issues found)
```

If any tool returns an error or timeouts, note it in the report but continue with remaining tools.

After presenting the report, ask if the user wants to:
- Fix any identified issues
- Run deeper diagnostics on specific areas
