# Backup Script Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a backup script that captures the full Docker Metrics Hub recovery set by default while still allowing focused backups of specific stack areas.

**Architecture:** `scripts/backup.sh` builds a relative-path tarball from the project root, writes a sidecar manifest and checksum, protects archive permissions, and warns when local secret-bearing files are missing. The default includes configuration, local secrets, provisioned dashboards, and all service data under `./appdata`.

**Tech Stack:** Bash, tar, sha256sum or shasum, existing project validation.

## Global Constraints

- Do not commit generated backups, `.env`, or `proxmox/pve.yml`.
- Keep the default backup comprehensive enough to recover the stack and historical data.
- Keep selector flags available for smaller targeted backups.
- Preserve the `./appdata` bind-mount data model.
- Avoid nonstandard dependencies so the script works on Ubuntu Server.

---

## Tasks

### Task 1: Backup Script

**Files:**
- Create: `scripts/backup.sh`

**Interfaces:**
- Consumes: project config, local ignored secret files, and `./appdata` service state.
- Produces: `backups/docker-metrics-hub-*.tar.gz`, `.manifest.txt`, and `.sha256`.

- [ ] Add default full critical backup behavior.
- [ ] Add specific selectors for config, data, Grafana, Prometheus, Alertmanager, and Proxmox.
- [ ] Add data exclusion switches for large or unwanted appdata areas.
- [ ] Write a manifest and checksum for each archive.

### Task 2: Documentation And Validation

**Files:**
- Modify: `README.md`
- Modify: `.gitignore`
- Modify: `scripts/check.sh`

**Interfaces:**
- Consumes: `scripts/backup.sh`.
- Produces: documented backup/restore workflow and validation coverage.

- [ ] Document default backup behavior and restore commands.
- [ ] Ignore local backup archives.
- [ ] Add backup script presence and Bash syntax checks.
