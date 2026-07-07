# Docker Metrics Hub Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a portable Prometheus and Grafana Docker Compose starter for a home lab where Linux and Windows hosts expose their own exporter endpoints.

**Architecture:** The central Compose stack runs Prometheus, Grafana, Blackbox exporter, and Alertmanager by default. Prometheus uses file service discovery target lists, so the stack can move between Ubuntu Server Docker hosts without depending on local host mounts or Docker socket access.

**Tech Stack:** Docker Compose, Prometheus, Grafana OSS, Prometheus Blackbox exporter, Alertmanager, node_exporter, windows_exporter, shell scripts.

## Global Constraints

- Target deployment host is Ubuntu Server Linux running Docker Compose.
- Central Compose stack must not mount the Docker socket.
- Central Compose stack must not mount host root, `/proc`, or `/sys`.
- Linux metrics must come from remote `node_exporter` endpoints on port `9100`.
- Windows metrics must come from remote `windows_exporter` endpoints on port `9182`.
- Target additions should be editable through YAML files under `prometheus/targets/`.
- Grafana must provision its Prometheus datasource and starter dashboard automatically.
- Alertmanager must start with the normal `docker compose up -d` command.
- Persistent service data must use `./appdata` bind mounts rather than named Docker volumes.
- This workspace is not a git repository, so commit steps are intentionally omitted.

---

## File Structure

- `docker-compose.yml`: central monitoring services and `./appdata` bind mounts.
- `.env.example`: operator-editable defaults for ports, image tags, retention, and credentials.
- `.gitignore`: ignores generated local environment files and runtime scratch data.
- `README.md`: Ubuntu Server quick start and exporter onboarding guide.
- `prometheus/prometheus.yml`: Prometheus scrape and alert rule configuration.
- `prometheus/targets/linux-hosts.yml`: Linux node_exporter targets.
- `prometheus/targets/windows-hosts.yml`: Windows windows_exporter targets.
- `prometheus/targets/http-services.yml`: HTTP probe targets.
- `prometheus/targets/ping-targets.yml`: ICMP probe targets.
- `prometheus/alerts/homelab.yml`: starter alert rules.
- `blackbox/blackbox.yml`: Blackbox exporter modules.
- `alertmanager/alertmanager.yml`: local drop receiver scaffold.
- `grafana/provisioning/datasources/prometheus.yml`: Grafana Prometheus datasource.
- `grafana/provisioning/dashboards/dashboards.yml`: Grafana dashboard provider.
- `grafana/dashboards/homelab-overview.json`: starter dashboard.
- `exporters/linux-node-exporter.md`: Linux exporter setup guide.
- `exporters/windows-exporter.md`: Windows exporter setup guide.
- `exporters/README.md`: exporter port and verification summary.
- `appdata/prometheus/.gitkeep`: placeholder for Prometheus TSDB bind mount.
- `appdata/grafana/.gitkeep`: placeholder for Grafana data bind mount.
- `appdata/alertmanager/.gitkeep`: placeholder for Alertmanager data bind mount.
- `scripts/check.sh`: static validation script.
- `scripts/reload-prometheus.sh`: Prometheus lifecycle reload helper.

### Task 1: Compose Stack

**Files:**
- Create: `docker-compose.yml`
- Create: `.env.example`
- Create: `.gitignore`

**Interfaces:**
- Consumes: `.env` values copied from `.env.example`.
- Produces: service names `prometheus`, `grafana`, `blackbox-exporter`, and `alertmanager` on the `monitoring` network.

- [ ] **Step 1: Add central services**

Create a Compose file with Prometheus, Grafana, Blackbox exporter, and Alertmanager.

- [ ] **Step 2: Add portable defaults**

Set Grafana to bind to `0.0.0.0:3000`, while Prometheus, Blackbox exporter, and Alertmanager bind to `127.0.0.1` by default. Store persistent data in `./appdata/prometheus`, `./appdata/grafana`, and `./appdata/alertmanager`.

- [ ] **Step 3: Verify no local host metric mounts**

Check that the Compose file does not include `docker.sock`, `/proc`, `/sys`, or host root mounts.

### Task 2: Prometheus and Blackbox Configuration

**Files:**
- Create: `prometheus/prometheus.yml`
- Create: `prometheus/targets/linux-hosts.yml`
- Create: `prometheus/targets/windows-hosts.yml`
- Create: `prometheus/targets/http-services.yml`
- Create: `prometheus/targets/ping-targets.yml`
- Create: `prometheus/alerts/homelab.yml`
- Create: `blackbox/blackbox.yml`
- Create: `alertmanager/alertmanager.yml`

**Interfaces:**
- Consumes: service names from Task 1.
- Produces: file service discovery jobs for Linux, Windows, HTTP probes, and ICMP probes.

- [ ] **Step 1: Add scrape jobs**

Create scrape jobs for Prometheus itself, Linux exporters, Windows exporters, Blackbox exporter internals, HTTP probes, and ICMP probes.

- [ ] **Step 2: Add empty target files with examples**

Represent no configured targets as `[]` while preserving commented examples in each file.

- [ ] **Step 3: Add starter alerts**

Alert on down exporters, failed probes, high Linux filesystem usage, high Linux memory usage, high Windows logical disk usage, and high Windows memory usage.

### Task 3: Grafana Provisioning

**Files:**
- Create: `grafana/provisioning/datasources/prometheus.yml`
- Create: `grafana/provisioning/dashboards/dashboards.yml`
- Create: `grafana/dashboards/homelab-overview.json`

**Interfaces:**
- Consumes: Prometheus URL `http://prometheus:9090`.
- Produces: default datasource named `Prometheus` and a dashboard named `Homelab Overview`.

- [ ] **Step 1: Provision datasource**

Configure Grafana to use Prometheus as the default datasource.

- [ ] **Step 2: Provision dashboard folder**

Load dashboard JSON files from `/var/lib/grafana/dashboards`.

- [ ] **Step 3: Add overview dashboard**

Add panels for target health, probe health, Linux CPU/memory/disk, and Windows CPU/memory/disk.

### Task 4: Exporter Runbooks and Operator Scripts

**Files:**
- Create: `README.md`
- Create: `exporters/linux-node-exporter.md`
- Create: `exporters/windows-exporter.md`
- Create: `exporters/README.md`
- Create: `scripts/check.sh`
- Create: `scripts/reload-prometheus.sh`

**Interfaces:**
- Consumes: target files and service ports from earlier tasks.
- Produces: copy-pasteable setup guidance and repeatable validation commands.

- [ ] **Step 1: Document Ubuntu quick start**

Document copying `.env.example`, setting Grafana credentials, running `docker compose config --quiet`, and starting the stack.

- [ ] **Step 2: Document Linux exporter setup**

Use the Ubuntu `prometheus-node-exporter` package path and firewall rule scoped to the Prometheus server IP.

- [ ] **Step 3: Document Windows exporter setup**

Use the upstream MSI installation path, default port `9182`, and a firewall rule scoped to the Prometheus server IP.

- [ ] **Step 4: Add validation scripts**

Make `scripts/check.sh` validate expected files and Compose syntax, and make `scripts/reload-prometheus.sh` call the Prometheus lifecycle reload endpoint.

### Task 5: Static Validation

**Files:**
- Modify: generated files only if validation finds a defect.

**Interfaces:**
- Consumes: all generated files.
- Produces: a validated starter directory.

- [ ] **Step 1: Run file inventory**

Run `find outputs/docker-metrics-hub -maxdepth 4 -type f | sort`.

- [ ] **Step 2: Run validation script**

Run `outputs/docker-metrics-hub/scripts/check.sh`.

- [ ] **Step 3: Run Compose config validation**

Run `docker compose -f outputs/docker-metrics-hub/docker-compose.yml config --quiet`.

- [ ] **Step 4: Record any runtime limitation**

If Docker or Prometheus tooling is unavailable locally, state that runtime validation should be performed on the Ubuntu Server Docker host.
