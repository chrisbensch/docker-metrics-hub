# Repository Guidelines

## Project Structure & Module Organization

This repository contains a Docker Compose monitoring stack for Prometheus, Grafana, Alertmanager, Blackbox exporter, and Proxmox VE exporter.

- `docker-compose.yml` defines the central services and bind-mounted `./appdata` storage.
- `prometheus/` contains Prometheus config, alert rules, and file discovery targets.
- `grafana/` contains datasource/dashboard provisioning and JSON dashboard assets.
- `blackbox/`, `alertmanager/`, and `proxmox/` contain service-specific configuration.
- `scripts/` contains operational helpers such as setup, validation, backup, and reload.
- `exporters/` contains host exporter runbooks.
- `docs/superpowers/` stores design specs and implementation plans.

There is no conventional application source or unit-test tree; validation is script and config focused.

## Build, Test, and Development Commands

- `./scripts/setup.sh`: prepare local `.env`, `proxmox/pve.yml`, appdata directories, target files, and optionally start the stack.
- `./scripts/check.sh`: validate required files, Compose syntax, Grafana JSON, shell syntax, YAML, and Prometheus config when tooling is available.
- `docker compose up -d`: start or update the stack.
- `docker compose ps`: inspect running services.
- `./scripts/reload-prometheus.sh`: reload Prometheus after config or target changes.
- `./scripts/backup.sh`: create a backup archive of config and persistent service data.

## Coding Style & Naming Conventions

Use Bash for scripts with `#!/usr/bin/env bash`, `set -euo pipefail`, uppercase globals, lowercase function names, and two-space indentation inside functions. Keep YAML two-space indented. Keep JSON dashboards valid and formatted by the existing export style. Prefer descriptive file names such as `linux-hosts.yml` and `proxmox-virtualization.json`.

## Testing Guidelines

Run `./scripts/check.sh` before committing. For script changes, also run `bash -n scripts/<name>.sh`. Test setup and backup behavior in temporary copies so local `.env`, `proxmox/pve.yml`, and `appdata/` are not damaged. If Docker is unavailable, note that Docker-backed `promtool` validation was skipped.

## Commit & Pull Request Guidelines

Recent commits use short imperative subjects, for example `Add setup target wizard` and `Fix Proxmox exporter config permissions`. Keep commits focused. Pull requests should describe the operational impact, list validation commands run, call out skipped runtime checks, and mention any security-sensitive config changes.

## Security & Configuration Tips

Never commit `.env`, `proxmox/pve.yml`, backups, or populated `appdata/`. Keep Prometheus, Alertmanager, Blackbox exporter, and Proxmox exporter bound to localhost unless intentionally exposed. `proxmox/pve.yml` must be readable by the exporter container; use the documented permissions or a tighter host ACL.
