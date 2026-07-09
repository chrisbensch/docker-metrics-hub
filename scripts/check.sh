#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

required_files=(
  ".env.example"
  "docker-compose.yml"
  "prometheus/prometheus.yml"
  "prometheus/targets/linux-hosts.yml"
  "prometheus/targets/windows-hosts.yml"
  "prometheus/targets/proxmox-hosts.yml"
  "prometheus/targets/http-services.yml"
  "prometheus/targets/ping-targets.yml"
  "prometheus/alerts/homelab.yml"
  "blackbox/blackbox.yml"
  "alertmanager/alertmanager.yml"
  "proxmox/pve.yml.example"
  "grafana/provisioning/datasources/prometheus.yml"
  "grafana/provisioning/dashboards/dashboards.yml"
  "grafana/dashboards/homelab-overview.json"
  "grafana/dashboards/proxmox-virtualization.json"
  "scripts/setup.sh"
  "scripts/backup.sh"
  "scripts/reload-prometheus.sh"
  "scripts/check.sh"
)

required_dirs=(
  "appdata/prometheus"
  "appdata/grafana"
  "appdata/alertmanager"
)

target_files=(
  "prometheus/targets/linux-hosts.yml"
  "prometheus/targets/windows-hosts.yml"
  "prometheus/targets/proxmox-hosts.yml"
  "prometheus/targets/http-services.yml"
  "prometheus/targets/ping-targets.yml"
)

check_world_readable() {
  local file="$1"
  local mode other_digit

  if ! command -v stat >/dev/null 2>&1; then
    echo "target file permissions: skipped because stat is not installed"
    return
  fi

  mode="$(stat -c '%a' "$file")"
  other_digit="${mode: -1}"

  if (( (10#$other_digit & 4) == 0 )); then
    echo "$file is not world-readable; Prometheus runs as uid 65534 and must be able to read file_sd targets" >&2
    echo "fix with: chmod 644 $file" >&2
    exit 1
  fi
}

for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "missing required file: $file" >&2
    exit 1
  fi
done

for dir in "${required_dirs[@]}"; do
  if [[ ! -d "$dir" ]]; then
    echo "missing required directory: $dir" >&2
    exit 1
  fi
done

for file in "${target_files[@]}"; do
  check_world_readable "$file"
done
echo "target file permissions: ok"

if grep -Eq 'docker\.sock|/proc|/sys|/:/host|:/host' docker-compose.yml; then
  echo "docker-compose.yml appears to mount local host internals; this starter should stay portable" >&2
  exit 1
fi

if grep -Eq 'prometheus-data|grafana-data|alertmanager-data' docker-compose.yml; then
  echo "docker-compose.yml still references named data volumes; expected ./appdata bind mounts" >&2
  exit 1
fi

if grep -Eq '^[[:space:]]*profiles:' docker-compose.yml; then
  echo "docker-compose.yml still uses Compose profiles; expected all core services to start by default" >&2
  exit 1
fi

if command -v docker >/dev/null 2>&1; then
  docker compose config --quiet
  echo "compose config: ok"
else
  echo "compose config: skipped because docker is not installed"
fi

if command -v python3 >/dev/null 2>&1; then
  python3 -m json.tool grafana/dashboards/homelab-overview.json >/dev/null
  python3 -m json.tool grafana/dashboards/proxmox-virtualization.json >/dev/null
  echo "grafana dashboard json: ok"
else
  echo "grafana dashboard json: skipped because python3 is not installed"
fi

if command -v bash >/dev/null 2>&1; then
  bash -n scripts/check.sh
  bash -n scripts/reload-prometheus.sh
  bash -n scripts/setup.sh
  bash -n scripts/backup.sh
  echo "shell syntax: ok"
else
  echo "shell syntax: skipped because bash is not installed"
fi

if command -v ruby >/dev/null 2>&1; then
  ruby -e 'require "yaml"; ARGV.each { |path| YAML.load_file(path) }' \
    prometheus/prometheus.yml \
    prometheus/targets/linux-hosts.yml \
    prometheus/targets/windows-hosts.yml \
    prometheus/targets/proxmox-hosts.yml \
    prometheus/targets/http-services.yml \
    prometheus/targets/ping-targets.yml \
    prometheus/alerts/homelab.yml \
    blackbox/blackbox.yml \
    alertmanager/alertmanager.yml \
    proxmox/pve.yml.example \
    grafana/provisioning/datasources/prometheus.yml \
    grafana/provisioning/dashboards/dashboards.yml
  if [[ -f "proxmox/pve.yml" ]]; then
    ruby -e 'require "yaml"; YAML.load_file(ARGV.fetch(0))' proxmox/pve.yml
    echo "proxmox credential yaml: ok"
  else
    echo "proxmox credential yaml: skipped because proxmox/pve.yml does not exist yet"
  fi
  echo "yaml parse: ok"
else
  echo "yaml parse: skipped because ruby is not installed"
fi

if command -v promtool >/dev/null 2>&1; then
  promtool check config prometheus/prometheus.yml
  promtool check rules prometheus/alerts/homelab.yml
  echo "promtool: ok"
elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  prometheus_image="${PROMETHEUS_IMAGE:-prom/prometheus:latest}"
  docker run --rm \
    -v "$ROOT_DIR/prometheus:/etc/prometheus:ro" \
    "$prometheus_image" \
    promtool check config /etc/prometheus/prometheus.yml
  docker run --rm \
    -v "$ROOT_DIR/prometheus:/etc/prometheus:ro" \
    "$prometheus_image" \
    promtool check rules /etc/prometheus/alerts/homelab.yml
  echo "promtool via docker: ok"
else
  echo "promtool: skipped because promtool is not installed and docker daemon is unavailable"
fi

if [[ ! -f ".env" ]]; then
  echo "note: .env does not exist yet; copy .env.example to .env before first deploy"
fi

echo "starter validation complete"
