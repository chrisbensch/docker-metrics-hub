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

## Useful Checks From The Prometheus Server

```bash
curl -fsS http://10.0.10.11:9100/metrics | head
```

If this fails from the Prometheus server but works locally on the Linux host, check host firewalls, VLAN routing, VPN ACLs, and whether node_exporter is listening on the expected interface.

## Optional Collector Tuning

The default node_exporter collectors are a good starting point. For advanced tuning, edit the systemd service override:

```bash
sudo systemctl edit prometheus-node-exporter
```

Then add explicit flags under an override block. Keep collector changes consistent across similar hosts so dashboards compare like with like.
