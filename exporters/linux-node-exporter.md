# Linux node_exporter Runbook

Use this on each Ubuntu or Debian Linux host you want Prometheus to monitor.

## Install

```bash
sudo apt update
sudo apt install prometheus-node-exporter
sudo systemctl enable --now prometheus-node-exporter
```

## Verify Locally

```bash
systemctl status prometheus-node-exporter --no-pager
curl -fsS http://127.0.0.1:9100/metrics | head
```

## Restrict Firewall Access

With UFW:

```bash
sudo ufw allow from <prometheus-server-ip> to any port 9100 proto tcp
sudo ufw status numbered
```

With nftables or another firewall, allow TCP `9100` only from the Prometheus server IP.

## Add The Host To Prometheus

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

Prometheus re-reads target files every 30 seconds.

Proxmox VE nodes are Linux hosts too. If `node_exporter` is installed on a Proxmox node, add its `:9100` endpoint here for host CPU, memory, filesystem, and OS metrics. Listing the same node in `prometheus/targets/proxmox-hosts.yml` only enables Proxmox API metrics for VMs, LXCs, storage, and cluster state.

The target file must be readable by the Prometheus container. If Prometheus logs `Error reading file ... /etc/prometheus/targets/linux-hosts.yml ... permission denied`, fix the mode on the monitoring server:

```bash
chmod 644 prometheus/targets/linux-hosts.yml
```

## Useful Checks From The Prometheus Server

```bash
curl -fsS http://10.0.10.11:9100/metrics | head
```

Check stored samples through Prometheus:

```bash
docker compose exec -T prometheus wget -qO- 'http://localhost:9090/api/v1/query?query=count(node_uname_info%7Bjob%3D%22linux-node-exporter%22%7D)'
```

If this fails from the Prometheus server but works locally on the Linux host, check host firewalls, VLAN routing, VPN ACLs, and whether node_exporter is listening on the expected interface.

## Optional Collector Tuning

The default node_exporter collectors are a good starting point. For advanced tuning, edit the systemd service override:

```bash
sudo systemctl edit prometheus-node-exporter
```

Then add explicit flags under an override block. Keep collector changes consistent across similar hosts so dashboards compare like with like.
