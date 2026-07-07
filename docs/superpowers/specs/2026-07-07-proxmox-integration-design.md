# Proxmox Integration Design

## Goal

Add first-class Proxmox VE virtualization monitoring to Docker Metrics Hub for multiple Proxmox 9.x hosts or clusters.

## Architecture

Docker Metrics Hub will run `prometheus-pve-exporter` as a central exporter service. Prometheus will use the exporter's multi-target `/pve` endpoint, with Proxmox hosts listed in `prometheus/targets/proxmox-hosts.yml`. API credentials will live in an ignored `proxmox/pve.yml` file, while `proxmox/pve.yml.example` documents the safe module structure for one or more clusters.

## Components

- `docker-compose.yml`: adds a `pve-exporter` service on port `9221`.
- `.env.example`: adds image and bind-port defaults for the Proxmox exporter.
- `.gitignore`: ignores the real `proxmox/pve.yml` credential file.
- `proxmox/pve.yml.example`: shows token-based modules for Proxmox API access.
- `prometheus/prometheus.yml`: adds exporter self-scrape and Proxmox multi-target scrape jobs.
- `prometheus/targets/proxmox-hosts.yml`: lists Proxmox API targets and optional credential modules.
- `prometheus/alerts/homelab.yml`: adds starter Proxmox alerts.
- `grafana/dashboards/proxmox-virtualization.json`: adds a provisioned Grafana dashboard.
- `exporters/proxmox-pve-exporter.md`: documents API token setup, target config, and validation.
- `README.md`: links the Proxmox integration from the main quick start.

## Data Flow

1. Prometheus reads Proxmox API targets from `prometheus/targets/proxmox-hosts.yml`.
2. Prometheus calls `pve-exporter:9221/pve` with `target`, `module`, `cluster=1`, and `node=1` parameters.
3. The exporter authenticates to the selected Proxmox host using the matching module in `proxmox/pve.yml`.
4. Exported `pve_*` metrics are stored in Prometheus and displayed by Grafana.

## Security

The real `proxmox/pve.yml` must not be committed. Proxmox API tokens should use a dedicated `prometheus@pve` user and the `PVEAuditor` role, preferably through a privilege-separated token. The exporter should stay bound to localhost on the Docker host unless intentionally exposed.

## Validation

The stack should continue passing `scripts/check.sh` and `docker compose config --quiet`. JSON dashboards and YAML examples should parse locally. On a running Docker host, `scripts/check.sh` should run Prometheus-native validation through `promtool` or the Prometheus image.
