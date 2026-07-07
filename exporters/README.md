# Exporter Setup Summary

The central Prometheus stack scrapes exporter endpoints. Install exporters on the machines being monitored.

| Host type | Exporter | Default port | Target file |
| --- | --- | --- | --- |
| Linux | node_exporter | `9100` | `prometheus/targets/linux-hosts.yml` |
| Windows | windows_exporter | `9182` | `prometheus/targets/windows-hosts.yml` |
| HTTP services | Blackbox exporter probe | central `9115` | `prometheus/targets/http-services.yml` |
| Ping targets | Blackbox exporter probe | central `9115` | `prometheus/targets/ping-targets.yml` |

Recommended firewall posture:

- Exporters listen on their host's LAN or management-network IP.
- Firewall rules allow TCP `9100` or `9182` only from the Prometheus server.
- Grafana is exposed to trusted users.
- Prometheus and Blackbox exporter stay bound to localhost unless you deliberately expose them.

From the starter directory, use:

```bash
./scripts/check.sh
```

This verifies the central stack files before deployment.
