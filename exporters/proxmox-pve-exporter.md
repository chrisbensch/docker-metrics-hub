# Proxmox VE Exporter Runbook

Docker Metrics Hub uses `prometheus-pve-exporter` to collect Proxmox VE metrics through the Proxmox API.

The exporter runs centrally in the Compose stack. Prometheus sends it a Proxmox host target, and the exporter authenticates to that host with credentials from `proxmox/pve.yml`.

## Files

| File | Purpose |
| --- | --- |
| `proxmox/pve.yml.example` | Safe example credential modules |
| `proxmox/pve.yml` | Real credential modules, ignored by git |
| `prometheus/targets/proxmox-hosts.yml` | Proxmox hosts to scrape |
| `grafana/dashboards/proxmox-virtualization.json` | Provisioned Grafana dashboard |

## Create A Proxmox API Token

Run these commands on a Proxmox VE node as a user with permission to manage users and ACLs:

```bash
pveum user add prometheus@pve --comment "Prometheus metrics reader"
pveum user token add prometheus@pve docker-metrics-hub --privsep 1
pveum aclmod / -token prometheus@pve!docker-metrics-hub -role PVEAuditor
```

Save the token value printed by `pveum user token add`. Proxmox only shows the secret once.

Use one token per independent Proxmox cluster or security boundary. A single token can normally read all nodes in the cluster when its ACL is assigned at `/`.

## Configure Exporter Credentials

On the Docker Metrics Hub server:

```bash
cp proxmox/pve.yml.example proxmox/pve.yml
chmod 600 proxmox/pve.yml
nano proxmox/pve.yml
```

For one cluster, use the `default` module:

```yaml
default:
  user: prometheus@pve
  token_name: docker-metrics-hub
  token_value: paste-token-secret-here
  verify_ssl: true
```

For multiple independent clusters, add one module per cluster:

```yaml
default:
  user: prometheus@pve
  token_name: docker-metrics-hub
  token_value: paste-first-cluster-token-secret-here
  verify_ssl: true

lab2:
  user: prometheus@pve
  token_name: docker-metrics-hub
  token_value: paste-second-cluster-token-secret-here
  verify_ssl: true
```

If your Proxmox hosts use self-signed certificates and you have not installed the CA certificate into the exporter container trust store, set `verify_ssl: false`. Trusted certificates are better long-term.

## Add Proxmox Targets

Edit `prometheus/targets/proxmox-hosts.yml`:

```yaml
- targets:
    - pve01.example.lan
    - pve02.example.lan
    - pve03.example.lan
  labels:
    cluster: lab
    module: default
    site: home
    role: virtualization
    os: proxmox
```

For a second credential module:

```yaml
- targets:
    - 10.20.0.11
    - 10.20.0.12
  labels:
    cluster: lab2
    module: lab2
    site: garage
    role: virtualization
    os: proxmox
```

Prometheus passes each target to:

```text
http://pve-exporter:9221/pve?target=<target>&module=<module>&cluster=1&node=1
```

The dashboard expects `cluster=1` and `node=1`, which collect cluster, node, VM, LXC, and storage metrics.

## Validate

Check the exporter container is running:

```bash
docker compose ps pve-exporter
```

Test the exporter from the Docker host:

```bash
curl -fsS "http://127.0.0.1:9221/pve?target=pve01.example.lan&module=default&cluster=1&node=1" | head
```

Reload Prometheus after editing target files:

```bash
./scripts/reload-prometheus.sh
```

Then inspect Prometheus targets:

```text
http://127.0.0.1:9090/targets
```

If Prometheus is still bound to localhost on the Docker host, use an SSH tunnel from your workstation:

```bash
ssh -L 9090:127.0.0.1:9090 <user>@<monitoring-server-ip>
```

## Dashboard

Grafana provisions a dashboard named `Proxmox Virtualization`.

It includes:

- exporter scrape health
- Proxmox node health
- running VM/LXC count
- node CPU, memory, and disk usage
- storage usage
- top guest CPU and memory
- top guest network RX/TX
- top guest disk read/write
- guest inventory
- HA error count

## Notes For Large Clusters

The exporter supports separate cluster and node scrapes. This starter uses `cluster=1&node=1` for simplicity. For very large clusters, split cluster-wide and node-level collection into separate jobs to reduce duplicate cluster API calls.
