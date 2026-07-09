#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

AUTO_YES=0
START_STACK=""
SKIP_CHOWN=0
OPEN_EDITOR=0
SKIP_TARGETS=0
RESET_TARGETS=0
CHANGED_TARGET_FILES=()

usage() {
  cat <<'USAGE'
Usage: scripts/setup.sh [options]

Prepare a local Docker Metrics Hub deployment.

Options:
  --yes         Accept default answers for non-destructive prompts.
  --start       Start the stack with docker compose up -d after validation.
  --no-start    Do not prompt to start the stack.
  --skip-chown  Do not adjust appdata ownership.
  --skip-targets
               Do not run the interactive target wizard.
  --reset-targets
               Reset target files before adding targets; interactive only.
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

prompt_count() {
  local prompt="$1"
  local answer

  while true; do
    read -r -p "$prompt " answer
    if [[ "$answer" =~ ^[0-9]+$ ]]; then
      printf '%s\n' "$answer"
      return
    fi
    warn "Enter a non-negative whole number"
  done
}

prompt_required() {
  local prompt="$1"
  local answer

  while true; do
    read -r -p "$prompt " answer
    if [[ -n "$answer" ]]; then
      printf '%s\n' "$answer"
      return
    fi
    warn "This value is required"
  done
}

prompt_default() {
  local prompt="$1"
  local default="$2"
  local answer

  read -r -p "$prompt [$default] " answer
  printf '%s\n' "${answer:-$default}"
}

normalize_exporter_target() {
  local target="$1"
  local default_port="$2"

  if [[ "$target" == *:* ]]; then
    printf '%s\n' "$target"
  else
    printf '%s:%s\n' "$target" "$default_port"
  fi
}

yaml_quote() {
  local value="$1"

  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "$value"
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

  chmod 600 ".env"
  chmod 644 "proxmox/pve.yml"
  log "Protected .env with chmod 600"
  log "Set proxmox/pve.yml to chmod 644 so the pve-exporter container can read it"
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

write_stock_target_file() {
  local path="$1"

  case "$path" in
    prometheus/targets/linux-hosts.yml)
      cat > "$path" <<'EOF'
# Linux node_exporter targets.
#
# Example:
# - targets:
#     - 192.168.1.10:9100
#   labels:
#     hostname: ubuntu-server-01
#     role: server
#     site: home
#     os: linux
[]
EOF
      ;;
    prometheus/targets/windows-hosts.yml)
      cat > "$path" <<'EOF'
# Windows windows_exporter targets.
#
# Example:
# - targets:
#     - 192.168.1.20:9182
#   labels:
#     hostname: windows-workstation-01
#     role: workstation
#     site: home
#     os: windows
[]
EOF
      ;;
    prometheus/targets/proxmox-hosts.yml)
      cat > "$path" <<'EOF'
# Proxmox VE API targets scraped through prometheus-pve-exporter.
#
# Use one target per Proxmox node you want node-level metrics from.
# For a cluster, list every node when node=1 is enabled. Cluster-wide metrics
# may be duplicated across nodes; the dashboard groups by target and node.
#
# Targets normally omit the Proxmox API port because the exporter uses the
# Proxmox API default. Use DNS names or management IPs reachable from the
# Docker host.
#
# Example, single cluster using the "default" module:
# - targets:
#     - pve01.example.lan
#     - pve02.example.lan
#     - pve03.example.lan
#   labels:
#     cluster: lab
#     module: default
#     site: home
#     role: virtualization
#     os: proxmox
#
# Example, second cluster using the "lab2" module from proxmox/pve.yml:
# - targets:
#     - 10.20.0.11
#     - 10.20.0.12
#   labels:
#     cluster: lab2
#     module: lab2
#     site: garage
#     role: virtualization
#     os: proxmox
[]
EOF
      ;;
    prometheus/targets/http-services.yml)
      cat > "$path" <<'EOF'
# HTTP or HTTPS URLs probed through Blackbox exporter.
#
# Example:
# - targets:
#     - https://grafana.example.lan/
#     - http://192.168.1.1/
#   labels:
#     probe: http
#     site: home
[]
EOF
      ;;
    prometheus/targets/ping-targets.yml)
      cat > "$path" <<'EOF'
# Hosts or IPs probed with ICMP through Blackbox exporter.
#
# Example:
# - targets:
#     - 192.168.1.1
#     - nas.example.lan
#   labels:
#     probe: icmp
#     site: home
[]
EOF
      ;;
    *)
      die "unknown target file for reset: $path"
      ;;
  esac
}

reset_target_files() {
  write_stock_target_file "prometheus/targets/linux-hosts.yml"
  record_changed_target_file "prometheus/targets/linux-hosts.yml"
  write_stock_target_file "prometheus/targets/windows-hosts.yml"
  record_changed_target_file "prometheus/targets/windows-hosts.yml"
  write_stock_target_file "prometheus/targets/proxmox-hosts.yml"
  record_changed_target_file "prometheus/targets/proxmox-hosts.yml"
  write_stock_target_file "prometheus/targets/http-services.yml"
  record_changed_target_file "prometheus/targets/http-services.yml"
  write_stock_target_file "prometheus/targets/ping-targets.yml"
  record_changed_target_file "prometheus/targets/ping-targets.yml"
}

prepare_target_file_for_entries() {
  local file="$1"
  local tmp

  if [[ ! -f "$file" ]]; then
    write_stock_target_file "$file"
  fi

  tmp="$(mktemp)"
  awk '
    { lines[NR] = $0 }
    END {
      last = NR
      while (last > 0 && lines[last] ~ /^[[:space:]]*$/) {
        last--
      }

      if (last > 0 && lines[last] ~ /^[[:space:]]*\[\][[:space:]]*$/) {
        for (i = 1; i < last; i++) {
          print lines[i]
        }
      } else {
        for (i = 1; i <= NR; i++) {
          print lines[i]
        }
      }
    }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

record_changed_target_file() {
  local file="$1"
  local existing

  for existing in "${CHANGED_TARGET_FILES[@]}"; do
    if [[ "$existing" == "$file" ]]; then
      return
    fi
  done

  CHANGED_TARGET_FILES+=("$file")
}

append_target_entry() {
  local file="$1"
  local targets="$2"
  local target label_key label_value
  shift 2

  prepare_target_file_for_entries "$file"

  {
    if [[ -s "$file" ]]; then
      printf '\n'
    fi
    printf -- '- targets:\n'
    while IFS= read -r target; do
      if [[ -n "$target" ]]; then
        printf '    - %s\n' "$(yaml_quote "$target")"
      fi
    done <<< "$targets"
    printf '  labels:\n'
    while [[ $# -gt 0 ]]; do
      label_key="$1"
      label_value="$2"
      shift 2
      printf '    %s: %s\n' "$label_key" "$(yaml_quote "$label_value")"
    done
  } >> "$file"

  record_changed_target_file "$file"
}

configure_linux_targets() {
  local count i address target hostname role site

  count="$(prompt_count "How many Linux node_exporter hosts do you want to add?")"
  for ((i = 1; i <= count; i++)); do
    address="$(prompt_required "Linux host ${i} address or hostname:")"
    target="$(normalize_exporter_target "$address" "9100")"
    hostname="$(prompt_required "Linux host ${i} friendly hostname label:")"
    role="$(prompt_default "Linux host ${i} role label" "server")"
    site="$(prompt_default "Linux host ${i} site label" "home")"

    append_target_entry \
      "prometheus/targets/linux-hosts.yml" \
      "$target" \
      hostname "$hostname" \
      role "$role" \
      site "$site" \
      os "linux"
  done
}

configure_windows_targets() {
  local count i address target hostname role site

  count="$(prompt_count "How many Windows windows_exporter hosts do you want to add?")"
  for ((i = 1; i <= count; i++)); do
    address="$(prompt_required "Windows host ${i} address or hostname:")"
    target="$(normalize_exporter_target "$address" "9182")"
    hostname="$(prompt_required "Windows host ${i} friendly hostname label:")"
    role="$(prompt_default "Windows host ${i} role label" "workstation")"
    site="$(prompt_default "Windows host ${i} site label" "home")"

    append_target_entry \
      "prometheus/targets/windows-hosts.yml" \
      "$target" \
      hostname "$hostname" \
      role "$role" \
      site "$site" \
      os "windows"
  done
}

configure_proxmox_targets() {
  local count i address cluster module site

  count="$(prompt_count "How many Proxmox VE hosts do you want to add?")"
  for ((i = 1; i <= count; i++)); do
    address="$(prompt_required "Proxmox host ${i} address or hostname:")"
    cluster="$(prompt_default "Proxmox host ${i} cluster label" "lab")"
    module="$(prompt_default "Proxmox host ${i} pve.yml module label" "default")"
    site="$(prompt_default "Proxmox host ${i} site label" "home")"

    append_target_entry \
      "prometheus/targets/proxmox-hosts.yml" \
      "$address" \
      cluster "$cluster" \
      module "$module" \
      site "$site" \
      role "virtualization" \
      os "proxmox"
  done
}

configure_http_targets() {
  local count i url site

  count="$(prompt_count "How many HTTP or HTTPS checks do you want to add?")"
  for ((i = 1; i <= count; i++)); do
    url="$(prompt_required "HTTP check ${i} full URL:")"
    site="$(prompt_default "HTTP check ${i} site label" "home")"

    append_target_entry \
      "prometheus/targets/http-services.yml" \
      "$url" \
      probe "http" \
      site "$site"
  done
}

configure_ping_targets() {
  local count i target site

  count="$(prompt_count "How many ping checks do you want to add?")"
  for ((i = 1; i <= count; i++)); do
    target="$(prompt_required "Ping check ${i} host or IP:")"
    site="$(prompt_default "Ping check ${i} site label" "home")"

    append_target_entry \
      "prometheus/targets/ping-targets.yml" \
      "$target" \
      probe "icmp" \
      site "$site"
  done
}

maybe_configure_targets() {
  if [[ "$SKIP_TARGETS" -eq 1 ]]; then
    log "Skipping target wizard"
    return
  fi

  if [[ "$AUTO_YES" -eq 1 || ! -t 0 ]]; then
    log "Skipping target wizard for non-interactive setup"
    return
  fi

  if [[ "$RESET_TARGETS" -eq 1 ]]; then
    log "Resetting Prometheus target files"
    reset_target_files
  fi

  configure_linux_targets
  configure_windows_targets
  configure_proxmox_targets
  configure_http_targets
  configure_ping_targets
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
  local grafana_user grafana_port grafana_url file

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
  printf '  prometheus/targets/http-services.yml\n'
  printf '  prometheus/targets/ping-targets.yml\n'

  if [[ "${#CHANGED_TARGET_FILES[@]}" -gt 0 ]]; then
    printf '\nTarget files updated this run:\n'
    for file in "${CHANGED_TARGET_FILES[@]}"; do
      printf '  %s\n' "$file"
    done
  fi

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
    --skip-targets)
      SKIP_TARGETS=1
      ;;
    --reset-targets)
      RESET_TARGETS=1
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

if [[ "$RESET_TARGETS" -eq 1 && "$AUTO_YES" -eq 1 ]]; then
  die "--reset-targets cannot be used with --yes; run setup interactively"
fi

if [[ "$RESET_TARGETS" -eq 1 && "$SKIP_TARGETS" -eq 1 ]]; then
  die "--reset-targets cannot be used with --skip-targets"
fi

if [[ "$RESET_TARGETS" -eq 1 && ! -t 0 ]]; then
  die "--reset-targets requires an interactive terminal"
fi

GENERATED_GRAFANA_PASSWORD=""

preflight
create_local_files
configure_grafana_password
create_appdata
fix_appdata_ownership
maybe_configure_targets
maybe_edit_configs
run_validation
maybe_start_stack
print_summary
