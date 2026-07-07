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
  "prometheus/targets/http-services.yml"
  "prometheus/targets/ping-targets.yml"
  "prometheus/alerts/homelab.yml"
  "blackbox/blackbox.yml"
  "alertmanager/alertmanager.yml"
  "grafana/provisioning/datasources/prometheus.yml"
  "grafana/provisioning/dashboards/dashboards.yml"
  "grafana/dashboards/homelab-overview.json"
)

required_dirs=(
  "appdata/prometheus"
  "appdata/grafana"
  "appdata/alertmanager"
)

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
  echo "grafana dashboard json: ok"
else
  echo "grafana dashboard json: skipped because python3 is not installed"
fi

if command -v ruby >/dev/null 2>&1; then
  ruby -e 'require "yaml"; ARGV.each { |path| YAML.load_file(path) }' \
    prometheus/prometheus.yml \
    prometheus/targets/linux-hosts.yml \
    prometheus/targets/windows-hosts.yml \
    prometheus/targets/http-services.yml \
    prometheus/targets/ping-targets.yml \
    prometheus/alerts/homelab.yml \
    blackbox/blackbox.yml \
    alertmanager/alertmanager.yml \
    grafana/provisioning/datasources/prometheus.yml \
    grafana/provisioning/dashboards/dashboards.yml
  echo "yaml parse: ok"
else
  echo "yaml parse: skipped because ruby is not installed"
fi

if [[ ! -f ".env" ]]; then
  echo "note: .env does not exist yet; copy .env.example to .env before first deploy"
fi

echo "starter validation complete"
