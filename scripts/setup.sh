#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

AUTO_YES=0
START_STACK=""
SKIP_CHOWN=0
OPEN_EDITOR=0

usage() {
  cat <<'USAGE'
Usage: scripts/setup.sh [options]

Prepare a local Docker Metrics Hub deployment.

Options:
  --yes         Accept default answers for non-destructive prompts.
  --start       Start the stack with docker compose up -d after validation.
  --no-start    Do not prompt to start the stack.
  --skip-chown  Do not adjust appdata ownership.
  --edit        Open local config files with $EDITOR after creating them.
  -h, --help    Show this help.
USAGE
}

log() {
  printf '[setup] %s\n' "$*"
}

warn() {
  printf '[setup] warning: %s\n' "$*" >&2
}

die() {
  printf '[setup] error: %s\n' "$*" >&2
  exit 1
}

confirm() {
  local prompt="$1"
  local default="${2:-no}"
  local suffix answer

  if [[ "$AUTO_YES" -eq 1 ]]; then
    [[ "$default" == "yes" ]]
    return
  fi

  if [[ ! -t 0 ]]; then
    [[ "$default" == "yes" ]]
    return
  fi

  if [[ "$default" == "yes" ]]; then
    suffix='[Y/n]'
  else
    suffix='[y/N]'
  fi

  read -r -p "$prompt $suffix " answer
  case "${answer:-$default}" in
    y|Y|yes|YES|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

generate_password() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 24
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import secrets; print(secrets.token_hex(24))'
  else
    return 1
  fi
}

set_env_value() {
  local file="$1"
  local key="$2"
  local value="$3"
  local tmp

  tmp="$(mktemp)"
  awk -v key="$key" -v value="$value" '
    BEGIN { done = 0 }
    $0 ~ "^" key "=" {
      print key "=" value
      done = 1
      next
    }
    { print }
    END {
      if (!done) {
        print key "=" value
      }
    }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

get_env_value() {
  local file="$1"
  local key="$2"

  grep -E "^${key}=" "$file" | tail -n 1 | cut -d= -f2- || true
}

copy_if_missing() {
  local src="$1"
  local dest="$2"

  if [[ -f "$dest" ]]; then
    log "Keeping existing $dest"
  else
    cp "$src" "$dest"
    log "Created $dest from $src"
  fi
}

open_editor() {
  local file="$1"
  local editor="${EDITOR:-nano}"

  if [[ ! -t 0 ]]; then
    warn "Skipping editor for $file because stdin is not interactive"
    return
  fi

  if command -v "$editor" >/dev/null 2>&1; then
    "$editor" "$file"
  else
    warn "Editor '$editor' is not available; edit $file manually"
  fi
}

preflight() {
  log "Running preflight checks"

  if command -v docker >/dev/null 2>&1; then
    if docker compose version >/dev/null 2>&1; then
      log "Docker Compose plugin found"
    else
      warn "Docker is installed, but 'docker compose' is not available"
    fi

    if docker info >/dev/null 2>&1; then
      log "Docker daemon is reachable"
    else
      warn "Docker daemon is not reachable; setup can prepare files but cannot start containers"
    fi
  else
    warn "Docker is not installed or not in PATH"
  fi

  if ! command -v curl >/dev/null 2>&1; then
    warn "curl is not installed; some manual validation commands will not work"
  fi
}

create_local_files() {
  log "Creating local config files"
  copy_if_missing ".env.example" ".env"
  copy_if_missing "proxmox/pve.yml.example" "proxmox/pve.yml"

  chmod 600 ".env" "proxmox/pve.yml"
  log "Protected .env and proxmox/pve.yml with chmod 600"
}

configure_grafana_password() {
  local current_password generated_password

  current_password="$(get_env_value ".env" "GRAFANA_ADMIN_PASSWORD")"
  if [[ "$current_password" != "change-this-password" && -n "$current_password" ]]; then
    log "Keeping existing Grafana admin password in .env"
    return
  fi

  generated_password="$(generate_password)" || die "Could not generate a password; install openssl or python3"
  set_env_value ".env" "GRAFANA_ADMIN_PASSWORD" "$generated_password"
  GENERATED_GRAFANA_PASSWORD="$generated_password"
  log "Generated Grafana admin password in .env"
}

create_appdata() {
  log "Creating appdata directories"
  mkdir -p appdata/prometheus appdata/grafana appdata/alertmanager
}

fix_appdata_ownership() {
  if [[ "$SKIP_CHOWN" -eq 1 ]]; then
    log "Skipping appdata ownership changes"
    return
  fi

  if ! confirm "Set appdata ownership for container users with chown?" "yes"; then
    warn "Skipped appdata ownership changes"
    return
  fi

  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    chown -R 65534:65534 appdata/prometheus appdata/alertmanager
    chown -R 472:472 appdata/grafana
  elif command -v sudo >/dev/null 2>&1; then
    sudo chown -R 65534:65534 appdata/prometheus appdata/alertmanager
    sudo chown -R 472:472 appdata/grafana
  else
    warn "sudo is not available; run these manually if containers cannot write appdata:"
    warn "  sudo chown -R 65534:65534 appdata/prometheus appdata/alertmanager"
    warn "  sudo chown -R 472:472 appdata/grafana"
    return
  fi

  log "Appdata ownership updated"
}

maybe_edit_configs() {
  if [[ "$OPEN_EDITOR" -eq 1 ]]; then
    open_editor ".env"
    open_editor "proxmox/pve.yml"
    open_editor "prometheus/targets/proxmox-hosts.yml"
    return
  fi

  if confirm "Open .env in an editor now?" "no"; then
    open_editor ".env"
  fi

  if confirm "Open Proxmox credential and target files now?" "no"; then
    open_editor "proxmox/pve.yml"
    open_editor "prometheus/targets/proxmox-hosts.yml"
  fi
}

run_validation() {
  log "Running repository validation"
  ./scripts/check.sh
}

maybe_start_stack() {
  if [[ "$START_STACK" == "no" ]]; then
    log "Skipping stack start"
    return
  fi

  if [[ "$START_STACK" != "yes" ]]; then
    if confirm "Start the stack now with docker compose up -d?" "no"; then
      START_STACK="yes"
    else
      START_STACK="no"
      log "Skipping stack start"
      return
    fi
  fi

  if ! command -v docker >/dev/null 2>&1; then
    warn "Cannot start stack because docker is not installed"
    START_STACK="no"
    return
  fi

  if ! docker info >/dev/null 2>&1; then
    warn "Cannot start stack because Docker daemon is not reachable"
    START_STACK="no"
    return
  fi

  docker compose up -d
  log "Stack started"
}

print_summary() {
  local grafana_user grafana_port grafana_url

  grafana_user="$(get_env_value ".env" "GRAFANA_ADMIN_USER")"
  grafana_port="$(get_env_value ".env" "GRAFANA_PORT")"
  grafana_url="http://<monitoring-server-ip>:${grafana_port:-3000}"

  printf '\nSetup complete.\n\n'
  printf 'Grafana URL: %s\n' "$grafana_url"
  printf 'Grafana user: %s\n' "${grafana_user:-admin}"

  if [[ -n "${GENERATED_GRAFANA_PASSWORD:-}" ]]; then
    printf 'Generated Grafana password: %s\n' "$GENERATED_GRAFANA_PASSWORD"
    printf 'The password was saved in .env.\n'
  else
    printf 'Grafana password: kept existing value in .env.\n'
  fi

  printf '\nNext useful files:\n'
  printf '  .env\n'
  printf '  proxmox/pve.yml\n'
  printf '  prometheus/targets/linux-hosts.yml\n'
  printf '  prometheus/targets/windows-hosts.yml\n'
  printf '  prometheus/targets/proxmox-hosts.yml\n'

  if [[ "$START_STACK" != "yes" ]]; then
    printf '\nStart the stack when ready:\n'
    printf '  docker compose up -d\n'
  fi

  printf '\nPrometheus tunnel from your workstation:\n'
  printf '  ssh -L 9090:127.0.0.1:9090 <user>@<monitoring-server-ip>\n'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes)
      AUTO_YES=1
      ;;
    --start)
      START_STACK="yes"
      ;;
    --no-start)
      START_STACK="no"
      ;;
    --skip-chown)
      SKIP_CHOWN=1
      ;;
    --edit)
      OPEN_EDITOR=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown option: $1"
      ;;
  esac
  shift
done

GENERATED_GRAFANA_PASSWORD=""

preflight
create_local_files
configure_grafana_password
create_appdata
fix_appdata_ownership
maybe_edit_configs
run_validation
maybe_start_stack
print_summary
