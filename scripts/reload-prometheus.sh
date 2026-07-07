#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -f ".env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source ".env"
  set +a
fi

host="${PROMETHEUS_BIND_ADDR:-127.0.0.1}"
port="${PROMETHEUS_PORT:-9090}"

if [[ "$host" == "0.0.0.0" ]]; then
  host="127.0.0.1"
fi

curl -fsS -X POST "http://${host}:${port}/-/reload"
echo "Prometheus reload requested at http://${host}:${port}/-/reload"
