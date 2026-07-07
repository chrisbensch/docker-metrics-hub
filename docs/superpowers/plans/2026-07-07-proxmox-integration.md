# Proxmox Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Proxmox VE exporter support and a Grafana virtualization dashboard to Docker Metrics Hub.

**Architecture:** Run `prometheus-pve-exporter` centrally and scrape multiple Proxmox hosts through its `/pve` multi-target endpoint. Store real Proxmox API credentials in ignored `proxmox/pve.yml`, list scrape targets in `prometheus/targets/proxmox-hosts.yml`, and provision a repo-native Grafana dashboard from `grafana/dashboards/proxmox-virtualization.json`.

**Tech Stack:** Docker Compose, Prometheus, Grafana OSS, prometheus-pve-exporter, Proxmox VE API token authentication, shell validation scripts.

## Global Constraints

- Proxmox hosts are Proxmox VE 9.x or compatible API targets.
- Real Proxmox API credentials must not be committed.
- The central stack must continue using `./appdata` bind mounts for persistent service data.
- The Proxmox exporter must be a normal Compose service, not a Compose profile.
- Proxmox targets must be editable through `prometheus/targets/proxmox-hosts.yml`.
- The dashboard must be provisioned automatically by the existing Grafana dashboard provider.

---

## File Structure

- Create `proxmox/pve.yml.example` for credential module examples.
- Create `prometheus/targets/proxmox-hosts.yml` for Proxmox API targets.
- Create `grafana/dashboards/proxmox-virtualization.json` for the Grafana dashboard.
- Create `exporters/proxmox-pve-exporter.md` for Proxmox setup and validation.
- Modify `.env.example` with Proxmox exporter image and port defaults.
- Modify `.gitignore` to exclude `proxmox/pve.yml`.
- Modify `docker-compose.yml` to add `pve-exporter`.
- Modify `prometheus/prometheus.yml` to add Proxmox scrape jobs.
- Modify `prometheus/alerts/homelab.yml` to add Proxmox starter alerts.
- Modify `README.md` to link setup and dashboard usage.
- Modify `scripts/check.sh` to validate new files and examples.

### Task 1: Proxmox Exporter Service

**Files:**
- Modify: `docker-compose.yml`
- Modify: `.env.example`
- Modify: `.gitignore`
- Create: `proxmox/pve.yml.example`

**Interfaces:**
- Consumes: `proxmox/pve.yml` at runtime.
- Produces: service `pve-exporter` on the `monitoring` network at `pve-exporter:9221`.

- [ ] Add `PVE_EXPORTER_IMAGE`, `PVE_EXPORTER_BIND_ADDR`, and `PVE_EXPORTER_PORT` defaults.
- [ ] Add `pve-exporter` using `prompve/prometheus-pve-exporter`.
- [ ] Mount `./proxmox:/etc/prometheus:ro`.
- [ ] Ignore `proxmox/pve.yml` while committing `proxmox/pve.yml.example`.

### Task 2: Prometheus Integration

**Files:**
- Modify: `prometheus/prometheus.yml`
- Create: `prometheus/targets/proxmox-hosts.yml`
- Modify: `prometheus/alerts/homelab.yml`

**Interfaces:**
- Consumes: `pve-exporter:9221` and `prometheus/targets/proxmox-hosts.yml`.
- Produces: `pve_*` metrics under job `proxmox-pve`.

- [ ] Add `pve-exporter` self-scrape job.
- [ ] Add `proxmox-pve` scrape job with `metrics_path: /pve`.
- [ ] Relabel target address into `__param_target`.
- [ ] Relabel optional target `module` label into `__param_module`.
- [ ] Add alerts for exporter down, Proxmox node down, high storage usage, and HA errors.

### Task 3: Grafana Dashboard

**Files:**
- Create: `grafana/dashboards/proxmox-virtualization.json`

**Interfaces:**
- Consumes: Prometheus datasource UID `prometheus`.
- Produces: dashboard `Proxmox Virtualization` with UID `proxmox-virtualization`.

- [ ] Add variables for Proxmox target and guest type.
- [ ] Add node health, CPU, memory, disk, storage, guest, network, disk IO, and HA panels.
- [ ] Use documented `pve_*` metrics from `prometheus-pve-exporter`.

### Task 4: Documentation And Validation

**Files:**
- Create: `exporters/proxmox-pve-exporter.md`
- Modify: `README.md`
- Modify: `scripts/check.sh`

**Interfaces:**
- Consumes: new Proxmox files from previous tasks.
- Produces: operator guidance and validation coverage.

- [ ] Document Proxmox API token creation with `PVEAuditor`.
- [ ] Document copying `proxmox/pve.yml.example` to ignored `proxmox/pve.yml`.
- [ ] Document adding one cluster, multiple clusters, and validation commands.
- [ ] Extend `scripts/check.sh` to require the new example, target file, dashboard, and docs.
- [ ] Validate YAML, JSON, Compose, and git cleanliness before commit.
