# Docker Metrics Hub

Portable Prometheus and Grafana starter stack for a mixed Linux and Windows home lab.

The central Docker Compose stack runs:

- Prometheus
- Grafana OSS
- Blackbox exporter
- Proxmox VE exporter
- Alertmanager

The stack does not scrape the Docker host directly. It does not mount the Docker socket, host root, `/proc`, or `/sys`. Every monitored machine should run its own exporter.

Persistent service data lives under `./appdata/`:

- `appdata/prometheus`
- `appdata/grafana`
- `appdata/alertmanager`

Proxmox API credentials live in `proxmox/pve.yml`, which is ignored by git.

## Ports

| Component | Default bind | Purpose |
| --- | --- | --- |
| Grafana | `0.0.0.0:3000` | Main dashboard UI |
| Prometheus | `127.0.0.1:9090` | Metrics database and target status |
| Blackbox exporter | `127.0.0.1:9115` | HTTP, TCP, and ICMP probe worker |
| Proxmox VE exporter | `127.0.0.1:9221` | Proxmox API metrics proxy |
| Alertmanager | `127.0.0.1:9093` | Alert routing |
| Linux node_exporter | remote host port `9100` | Linux host metrics |
| Windows windows_exporter | remote host port `9182` | Windows host metrics |

## Quick Start On Ubuntu Server

Install Docker Engine and the Compose plugin on the Ubuntu Server that will run the monitoring stack.

Copy this directory to the server, then run:

```bash
cd docker-metrics-hub
./scripts/setup.sh
```

The setup script copies local config templates, generates a Grafana password, creates `appdata` directories, sets local config permissions, offers to open Proxmox config files, runs validation, and asks before starting the stack.

In an interactive terminal, setup also asks how many initial targets you want to add for Linux hosts, Windows hosts, Proxmox VE hosts, HTTP checks, and ping checks. Re-running setup preserves existing target files and appends new entries by default.

For a mostly non-interactive setup that starts the stack after validation:

```bash
./scripts/setup.sh --yes --start
```

Non-interactive setup skips target prompts so automation does not hang. To prepare config and appdata without the target wizard, run:

```bash
./scripts/setup.sh --skip-targets
```

To intentionally rebuild target files from scratch, run setup interactively with:

```bash
./scripts/setup.sh --reset-targets
```

`--reset-targets` restores the target files to their stock comments plus `[]` before adding targets from that run. It cannot be combined with `--yes`.

Manual setup is also fine:

```bash
cp .env.example .env
nano .env
cp proxmox/pve.yml.example proxmox/pve.yml
nano proxmox/pve.yml
chmod 644 proxmox/pve.yml
mkdir -p appdata/prometheus appdata/grafana appdata/alertmanager
sudo chown -R 65534:65534 appdata/prometheus appdata/alertmanager
sudo chown -R 472:472 appdata/grafana
./scripts/check.sh
docker compose up -d
```

Change `GRAFANA_ADMIN_PASSWORD` in `.env` before exposing Grafana to other users.

If you are not ready to monitor Proxmox yet, leave `prometheus/targets/proxmox-hosts.yml` empty. The placeholder `proxmox/pve.yml` is enough for the exporter container to start, and no Proxmox API calls are made until targets are listed.

Open Grafana:

```text
http://<monitoring-server-ip>:3000
```

Prometheus is bound to localhost by default. To inspect targets from your workstation, use an SSH tunnel:

```bash
ssh -L 9090:127.0.0.1:9090 <user>@<monitoring-server-ip>
```

Then open:

```text
http://127.0.0.1:9090/targets
```

## Add A Linux Host

Install node_exporter on the Linux host you want to monitor:

```bash
sudo apt update
sudo apt install prometheus-node-exporter
sudo systemctl enable --now prometheus-node-exporter
curl -fsS http://127.0.0.1:9100/metrics | head
```

If the host uses UFW, allow only the Prometheus server:

```bash
sudo ufw allow from <prometheus-server-ip> to any port 9100 proto tcp
```

On the monitoring server, edit `prometheus/targets/linux-hosts.yml`:

```yaml
- targets:
    - 10.0.10.11:9100
  labels:
    hostname: ubuntu-server-01
    role: server
    site: home
    os: linux
```

Prometheus re-reads target files every 30 seconds. You can also reload immediately:

```bash
./scripts/reload-prometheus.sh
```

## Add A Windows Host

Install `windows_exporter` on the Windows host. See `exporters/windows-exporter.md` for the full runbook.

After installation, confirm the exporter works from the Windows host:

```powershell
Invoke-WebRequest http://127.0.0.1:9182/metrics
```

Allow only the Prometheus server through Windows Firewall:

```powershell
New-NetFirewallRule -DisplayName "windows_exporter from Prometheus" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 9182 -RemoteAddress <prometheus-server-ip>
```

On the monitoring server, edit `prometheus/targets/windows-hosts.yml`:

```yaml
- targets:
    - 10.0.10.21:9182
  labels:
    hostname: windows-workstation-01
    role: workstation
    site: home
    os: windows
```

## Add HTTP Checks

Edit `prometheus/targets/http-services.yml`:

```yaml
- targets:
    - https://grafana.example.lan/
    - http://10.0.10.1/
  labels:
    probe: http
    site: home
```

The default `http_2xx` module follows redirects and accepts any 2xx response.

## Add Ping Checks

Edit `prometheus/targets/ping-targets.yml`:

```yaml
- targets:
    - 10.0.10.1
    - nas.example.lan
  labels:
    probe: icmp
    site: home
```

The Blackbox exporter container includes `NET_RAW` capability so ICMP probes can work in Docker.

## Add Proxmox VE Hosts

Docker Metrics Hub includes a Proxmox VE dashboard backed by `prometheus-pve-exporter`.

Start with the detailed runbook:

```text
exporters/proxmox-pve-exporter.md
```

Short version:

1. On each Proxmox cluster, create a dedicated API token with read-only `PVEAuditor` access.
2. Put the token in ignored `proxmox/pve.yml`.
3. Add one or more Proxmox node API targets to `prometheus/targets/proxmox-hosts.yml`.
4. Run `./scripts/reload-prometheus.sh` or restart the stack.

Example target file:

```yaml
- targets:
    - pve01.example.lan
    - pve02.example.lan
  labels:
    cluster: lab
    module: default
    site: home
    role: virtualization
    os: proxmox
```

The provisioned Grafana dashboard is named `Proxmox Virtualization`.

## Configure Alertmanager

Alertmanager starts with the normal `docker compose up -d` command. The included `alertmanager/alertmanager.yml` has a local drop receiver. Replace it with email, Slack, Discord, Gotify, ntfy, or another receiver when you are ready for notifications.

## Common Operations

Validate local files:

```bash
./scripts/check.sh
```

`scripts/check.sh` uses local `promtool` when it is installed. If `promtool` is not installed but the Docker daemon is available, it runs Prometheus-native config validation through the Prometheus image.

You can also run that validation directly:

```bash
docker run --rm -v "$PWD/prometheus:/etc/prometheus:ro" prom/prometheus:latest promtool check config /etc/prometheus/prometheus.yml
```

Start or update the stack:

```bash
docker compose up -d
```

Show running containers:

```bash
docker compose ps
```

Back up the full critical recovery set:

```bash
./scripts/backup.sh
```

By default, the backup includes local config and secrets, Prometheus rules and targets, Blackbox and Alertmanager config, Proxmox credentials, Grafana provisioning and dashboards, Grafana state, Alertmanager state, and the Prometheus TSDB under `appdata/prometheus`. Archives are written to `backups/`, which is ignored by git. Treat the archive like a secret because it can contain `.env` and `proxmox/pve.yml`.

For the most consistent service-state backup, briefly stop the stack first:

```bash
docker compose stop
./scripts/backup.sh
docker compose up -d
```

Use narrower backups when you only want one part:

```bash
./scripts/backup.sh --config-only
./scripts/backup.sh --grafana-only
./scripts/backup.sh --prometheus-only
./scripts/backup.sh --no-prometheus-data
```

Restore an archive from the project root:

```bash
docker compose down
tar -xzf backups/docker-metrics-hub-YYYYmmdd-HHMMSS.tar.gz -C .
sudo chown -R 65534:65534 appdata/prometheus appdata/alertmanager
sudo chown -R 472:472 appdata/grafana
docker compose up -d
```

Reload Prometheus after changing `prometheus/prometheus.yml`, alert rules, or Blackbox configuration:

```bash
./scripts/reload-prometheus.sh
```

Stop the stack:

```bash
docker compose down
```

Keep persistent metrics and dashboards:

```bash
docker compose down
docker compose up -d
```

Delete persistent metrics and dashboards:

Stop the stack, then remove or archive the relevant subdirectories under `appdata/`. With bind mounts, `docker compose down -v` does not remove this data.

## Security Notes

- Keep exporter ports reachable only from the Prometheus server IP or a private VPN/VLAN.
- Do not expose Prometheus, Alertmanager, or Blackbox exporter directly to the internet.
- Do not expose the Proxmox VE exporter directly to the internet.
- Do not commit `proxmox/pve.yml`; it contains API token secrets.
- `proxmox/pve.yml` must be readable by the `pve-exporter` container. The setup script uses `chmod 644`; use a tighter host ACL if your Docker host has untrusted local shell users.
- Change the Grafana admin password in `.env`.
- Put Grafana behind a reverse proxy or VPN before exposing it outside your LAN.
- Pin image tags in `.env` once the first deployment is stable.

## Upstream References

- Prometheus file service discovery: https://prometheus.io/docs/prometheus/latest/configuration/configuration/#file_sd_config
- Prometheus node_exporter: https://github.com/prometheus/node_exporter
- Prometheus windows_exporter: https://github.com/prometheus-community/windows_exporter
- Prometheus blackbox_exporter: https://github.com/prometheus/blackbox_exporter
- Prometheus Proxmox VE exporter: https://github.com/prometheus-pve/prometheus-pve-exporter
