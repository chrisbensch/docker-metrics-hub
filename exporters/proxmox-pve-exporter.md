# Proxmox VE Exporter Runbook

Docker Metrics Hub uses `prometheus-pve-exporter` to collect Proxmox VE metrics through the Proxmox API.

The exporter runs centrally in the Compose stack. Prometheus sends it a Proxmox host target, and the exporter authenticates to that host with credentials from `proxmox/pve.yml`.

## Files

| File | Purpose |
| --- | --- |
| `proxmox/pve.yml.example` | Safe example credential modules |
| `proxmox/pve.yml` | Real credential modules, ignored by git |
| `prometheus/targets/proxmox-hosts.yml` | Proxmox cluster API endpoints to scrape |
| `grafana/dashboards/proxmox-virtualization.json` | Provisioned Grafana dashboard |

## Create A Proxmox API Token

Run these commands on a Proxmox VE node as a user with permission to manage users and ACLs:

```bash
pveum user add prometheus@pve --comment "Prometheus metrics reader"
pveum user token add prometheus@pve docker-metrics-hub --privsep 1
pveum aclmod / -token 'prometheus@pve!docker-metrics-hub' -role PVEAuditor
```

Save the token value printed by `pveum user token add`. Proxmox only shows the secret once.

Use one token per independent Proxmox cluster or security boundary. A single token can normally read all nodes in the cluster when its ACL is assigned at `/`.

The quotes around the token ID are intentional. In interactive Bash, an unquoted `!` can trigger history expansion and fail with `event not found`.

If you choose to use a token owned by another user, grant the ACL to that exact token ID. For example:

```bash
pveum aclmod / -token 'root@pam!docker-metrics-hub' -role PVEAuditor
```

You can confirm the ACL with:

```bash
pveum acl list /
```

## Configure Exporter Credentials

On the Docker Metrics Hub server:

```bash
cp proxmox/pve.yml.example proxmox/pve.yml
chmod 644 proxmox/pve.yml
nano proxmox/pve.yml
```

The exporter runs as a non-root user inside the container, so `proxmox/pve.yml`
must be readable through the bind mount. If your Docker host has untrusted local
shell users, use a tighter host ACL that grants read access to the exporter user
instead of world-readable mode.

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
    - pve-api.example.lan
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

For a clustered Proxmox deployment, one reachable API endpoint per cluster is normally enough. The Proxmox API can return cluster, node, VM, LXC, and storage resources through a single cluster member. Listing multiple nodes from the same cluster usually duplicates `pve_*` metrics under different `instance` labels and can double-count dashboard totals.

These targets are Proxmox API targets for the `Proxmox Virtualization` dashboard. They do not replace Linux `node_exporter` targets. If you also want Proxmox host CPU, memory, filesystem, and OS metrics on the `Homelab Overview` dashboard, install `node_exporter` on each Proxmox node and add every node's `host:9100` endpoint to `prometheus/targets/linux-hosts.yml`.

Prometheus target files are not secret-bearing files, and the Prometheus container must be able to read them through the bind mount. If target discovery fails with `permission denied`, fix the modes on the monitoring server:

```bash
chmod 644 prometheus/targets/*.yml
```

## Validate

Check the exporter container is running:

```bash
docker compose ps pve-exporter
```

If it keeps restarting with `PermissionError: [Errno 13] Permission denied:
'/etc/prometheus/pve.yml'`, fix the host-side file mode and recreate the
container:

```bash
chmod 644 proxmox/pve.yml
docker compose up -d --force-recreate pve-exporter
```

Test the exporter from the Docker host:

```bash
curl -fsS "http://127.0.0.1:9221/pve?target=pve01.example.lan&module=default&cluster=1&node=1" | head
```

Check whether Prometheus sees successful Proxmox API scrapes:

```bash
docker compose exec -T prometheus wget -qO- 'http://localhost:9090/api/v1/query?query=up%7Bjob%3D%22proxmox-pve%22%7D'
docker compose exec -T prometheus wget -qO- 'http://localhost:9090/api/v1/query?query=count(pve_up%7Bjob%3D%22proxmox-pve%22%7D)'
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

## Troubleshooting

If Prometheus shows Proxmox targets with `up=0`, inspect the scrape error in Prometheus targets or in the exporter logs:

```bash
docker compose logs --tail=100 pve-exporter
```

`403 Forbidden: Permission check failed (/, Sys.Audit)` means the API token exists and is being used, but it lacks `PVEAuditor` on `/`. Re-run `pveum aclmod` for the exact token ID in `proxmox/pve.yml`.

If Prometheus logs `Error reading file ... /etc/prometheus/targets/proxmox-hosts.yml ... permission denied`, the host-side target file mode is too restrictive. Run:

```bash
chmod 644 prometheus/targets/proxmox-hosts.yml
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
