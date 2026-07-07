# Docker Metrics Hub Design

## Goal

Create a portable Docker Compose monitoring core for a diverse home lab. The stack runs on an Ubuntu Server Docker host, but it does not collect host metrics directly from that Docker host. Metrics come from exporters installed on each Linux or Windows host, making the central stack portable across machines.

## Architecture

The Compose stack runs Prometheus, Grafana, Blackbox exporter, and Alertmanager by default. Prometheus discovers scrape targets from small file-based target lists under `prometheus/targets/`. Grafana is provisioned automatically with a Prometheus datasource and a starter homelab overview dashboard.

Remote hosts run their own exporters:

- Linux hosts run Prometheus `node_exporter` on TCP port `9100`.
- Windows hosts run `windows_exporter` on TCP port `9182`.
- HTTP and ICMP checks are probed from the central Blackbox exporter.
- SNMP and application-specific exporters are future additions, not part of the first core stack.

## Components

- `docker-compose.yml`: central services only; no Docker socket, host root, `/proc`, or `/sys` mounts. Persistent data uses `./appdata` bind mounts rather than named Docker volumes.
- `prometheus/prometheus.yml`: scrape jobs for Prometheus itself, Linux exporters, Windows exporters, HTTP probes, ICMP probes, and Blackbox exporter internals.
- `prometheus/targets/*.yml`: editable file service discovery lists for lab hosts and services.
- `blackbox/blackbox.yml`: HTTP, TCP, and ICMP probe modules.
- `grafana/provisioning/`: datasource and dashboard provisioning.
- `grafana/dashboards/homelab-overview.json`: initial dashboard for host reachability and common Linux/Windows metrics.
- `exporters/*.md`: Linux and Windows exporter setup runbooks.
- `scripts/check.sh`: local sanity checks for Compose/config shape.
- `scripts/reload-prometheus.sh`: convenience reload for target edits.

## Data Flow

1. A host runs an exporter and exposes `/metrics` to the Prometheus server.
2. The operator adds the exporter address to the matching target file.
3. Prometheus refreshes target files every 30 seconds and scrapes each exporter.
4. Grafana reads metrics from Prometheus through the provisioned datasource.
5. Blackbox exporter probes endpoint health for HTTP, TCP, and ICMP targets.

## Security

Exporter ports should be reachable only from the Prometheus server IP or over a private network such as a VLAN, WireGuard, or Tailscale. Grafana is the only service intended to be LAN-accessible by default. Prometheus, Blackbox exporter, and Alertmanager bind to localhost by default and can be exposed deliberately by changing `.env`.

## Operations

The normal workflow is:

1. Copy `.env.example` to `.env` and set the Grafana admin password.
2. Create `appdata/prometheus`, `appdata/grafana`, and `appdata/alertmanager`.
3. Set ownership for the container users on the `appdata` directories.
4. Run `docker compose config --quiet`.
5. Run `docker compose up -d`.
6. Install exporters on remote Linux and Windows hosts.
7. Add targets under `prometheus/targets/`.
8. Run `scripts/reload-prometheus.sh` or wait for file discovery refresh.

## Testing

Static validation checks should verify that Compose parses, required files exist, Prometheus target files are present, and the central Compose stack does not mount host internals or the Docker socket. Runtime validation on the Ubuntu host should confirm Grafana, Prometheus, Blackbox exporter, Linux exporters, and Windows exporters appear as expected in Prometheus targets.
