# Windows windows_exporter Runbook

Use this on each Windows desktop or Windows Server host you want Prometheus to monitor.

## Install

Download the latest MSI from the upstream releases page:

```text
https://github.com/prometheus-community/windows_exporter/releases
```

Open PowerShell as Administrator and install the MSI:

```powershell
msiexec /i C:\Users\Administrator\Downloads\windows_exporter-<version>-amd64.msi --% ENABLED_COLLECTORS="[defaults]" LISTEN_PORT=9182 ADDLOCAL=FirewallException REMOTE_ADDR=<prometheus-server-ip>
```

If you prefer to create the firewall rule yourself, omit `ADDLOCAL=FirewallException REMOTE_ADDR=<prometheus-server-ip>` and use the firewall command below.

## Verify Locally

```powershell
Get-Service windows_exporter
Invoke-WebRequest http://127.0.0.1:9182/metrics
Invoke-WebRequest http://127.0.0.1:9182/health
```

## Restrict Firewall Access

If the MSI did not create the scoped firewall rule, run PowerShell as Administrator:

```powershell
New-NetFirewallRule -DisplayName "windows_exporter from Prometheus" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 9182 -RemoteAddress <prometheus-server-ip>
```

## Add The Host To Prometheus

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

Prometheus re-reads target files every 30 seconds.

## Useful Checks From The Prometheus Server

```bash
curl -fsS http://10.0.10.21:9182/metrics | head
```

If this fails from the Prometheus server but works locally on Windows, check Windows Firewall, network profile type, VLAN routing, VPN ACLs, and whether the exporter was installed with the expected listen port.

## Collector Notes

The default collectors cover CPU, memory, logical disks, network, OS, service, and system metrics. Add specialized collectors later only when you know you need them, such as IIS, Hyper-V, MSSQL, or process-level metrics.
