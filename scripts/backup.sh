#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MODE="all"
MODE_SET=0
OUTPUT_DIR="backups"
PREFIX="docker-metrics-hub"
DRY_RUN=0
NO_PROMETHEUS_DATA=0
NO_GRAFANA_DATA=0
NO_ALERTMANAGER_DATA=0

INCLUDED_PATHS=()
MISSING_PATHS=()

usage() {
  cat <<'USAGE'
Usage: scripts/backup.sh [options]

Create a tar.gz backup of Docker Metrics Hub configuration, local secrets, and
service data. By default, this backs up the full critical recovery set,
including Prometheus TSDB, Grafana state, and Alertmanager state.

Options:
  --config-only             Back up stack configuration and local secrets only.
  --data-only               Back up appdata service state only.
  --grafana-only            Back up Grafana dashboards, provisioning, and state.
  --prometheus-only         Back up Prometheus config, targets, rules, and TSDB.
  --alertmanager-only       Back up Alertmanager config and state.
  --proxmox-only            Back up Proxmox credentials, targets, and dashboard.
  --no-prometheus-data      Exclude appdata/prometheus from the selected backup.
  --no-grafana-data         Exclude appdata/grafana from the selected backup.
  --no-alertmanager-data    Exclude appdata/alertmanager from the selected backup.
  --output DIR              Write archive, manifest, and checksum to DIR.
                            Default: backups
  --prefix NAME             Archive filename prefix. Default: docker-metrics-hub
  --dry-run                 Print what would be backed up without writing files.
  -h, --help                Show this help.

Examples:
  scripts/backup.sh
  scripts/backup.sh --config-only
  scripts/backup.sh --grafana-only
  scripts/backup.sh --no-prometheus-data
USAGE
}

log() {
  printf '[backup] %s\n' "$*"
}

warn() {
  printf '[backup] warning: %s\n' "$*" >&2
}

die() {
  printf '[backup] error: %s\n' "$*" >&2
  exit 1
}

set_mode() {
  local mode="$1"

  if [[ "$MODE_SET" -eq 1 ]]; then
    die "choose only one backup selector such as --config-only or --grafana-only"
  fi

  MODE="$mode"
  MODE_SET=1
}

resolve_output_dir() {
  case "$OUTPUT_DIR" in
    /*) printf '%s\n' "$OUTPUT_DIR" ;;
    *) printf '%s/%s\n' "$ROOT_DIR" "$OUTPUT_DIR" ;;
  esac
}

path_selected() {
  local candidate="$1"
  local existing

  for existing in "${INCLUDED_PATHS[@]}"; do
    if [[ "$existing" == "$candidate" ]]; then
      return 0
    fi
  done

  return 1
}

add_path() {
  local path="$1"

  if [[ -e "$path" ]]; then
    if ! path_selected "$path"; then
      INCLUDED_PATHS+=("$path")
    fi
  else
    MISSING_PATHS+=("$path")
  fi
}

add_config_paths() {
  add_path "docker-compose.yml"
  add_path ".env.example"
  add_path ".env"
  add_path "prometheus"
  add_path "blackbox"
  add_path "alertmanager"
  add_path "proxmox"
  add_path "grafana/provisioning"
  add_path "grafana/dashboards"
}

add_data_paths() {
  if [[ "$NO_PROMETHEUS_DATA" -eq 0 ]]; then
    add_path "appdata/prometheus"
  fi

  if [[ "$NO_GRAFANA_DATA" -eq 0 ]]; then
    add_path "appdata/grafana"
  fi

  if [[ "$NO_ALERTMANAGER_DATA" -eq 0 ]]; then
    add_path "appdata/alertmanager"
  fi
}

add_grafana_paths() {
  add_path "grafana/provisioning"
  add_path "grafana/dashboards"

  if [[ "$NO_GRAFANA_DATA" -eq 0 ]]; then
    add_path "appdata/grafana"
  fi
}

add_prometheus_paths() {
  add_path "prometheus"
  add_path "blackbox"

  if [[ "$NO_PROMETHEUS_DATA" -eq 0 ]]; then
    add_path "appdata/prometheus"
  fi
}

add_alertmanager_paths() {
  add_path "alertmanager"

  if [[ "$NO_ALERTMANAGER_DATA" -eq 0 ]]; then
    add_path "appdata/alertmanager"
  fi
}

add_proxmox_paths() {
  add_path "proxmox"
  add_path "prometheus/targets/proxmox-hosts.yml"
  add_path "grafana/dashboards/proxmox-virtualization.json"
}

build_include_list() {
  case "$MODE" in
    all)
      add_config_paths
      add_data_paths
      ;;
    config)
      add_config_paths
      ;;
    data)
      add_data_paths
      ;;
    grafana)
      add_grafana_paths
      ;;
    prometheus)
      add_prometheus_paths
      ;;
    alertmanager)
      add_alertmanager_paths
      ;;
    proxmox)
      add_proxmox_paths
      ;;
    *)
      die "unknown backup mode: $MODE"
      ;;
  esac

  if [[ ! -f ".env" && ( "$MODE" == "all" || "$MODE" == "config" ) ]]; then
    warn ".env does not exist yet; local Grafana credentials will not be in this backup"
  fi

  if [[ ! -f "proxmox/pve.yml" && ( "$MODE" == "all" || "$MODE" == "config" || "$MODE" == "proxmox" ) ]]; then
    warn "proxmox/pve.yml does not exist yet; Proxmox API credentials will not be in this backup"
  fi

  if [[ "${#INCLUDED_PATHS[@]}" -eq 0 ]]; then
    die "nothing was found to back up"
  fi
}

print_selection() {
  local path

  log "mode: $MODE"
  log "included paths:"
  for path in "${INCLUDED_PATHS[@]}"; do
    printf '  %s\n' "$path"
  done

  if [[ "${#MISSING_PATHS[@]}" -gt 0 ]]; then
    warn "missing paths skipped:"
    for path in "${MISSING_PATHS[@]}"; do
      printf '  %s\n' "$path" >&2
    done
  fi
}

write_manifest() {
  local manifest="$1"
  local archive_name="$2"
  local path

  {
    printf 'Docker Metrics Hub backup manifest\n'
    printf 'created_at_utc=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf 'root_dir=%s\n' "$ROOT_DIR"
    printf 'mode=%s\n' "$MODE"
    printf 'archive=%s\n' "$archive_name"
    printf '\nIncluded paths:\n'
    for path in "${INCLUDED_PATHS[@]}"; do
      printf '  %s\n' "$path"
    done

    if [[ "${#MISSING_PATHS[@]}" -gt 0 ]]; then
      printf '\nMissing paths skipped:\n'
      for path in "${MISSING_PATHS[@]}"; do
        printf '  %s\n' "$path"
      done
    fi
  } > "$manifest"

  chmod 600 "$manifest"
}

write_checksum() {
  local output_abs="$1"
  local archive_name="$2"
  local checksum_name="$3"

  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$output_abs" && sha256sum "$archive_name" > "$checksum_name")
  elif command -v shasum >/dev/null 2>&1; then
    (cd "$output_abs" && shasum -a 256 "$archive_name" > "$checksum_name")
  else
    warn "neither sha256sum nor shasum is available; checksum was not written"
    return
  fi

  chmod 600 "$output_abs/$checksum_name"
}

create_backup() {
  local output_abs timestamp archive_name archive archive_tmp manifest_name manifest checksum_name

  output_abs="$(resolve_output_dir)"
  timestamp="$(date +%Y%m%d-%H%M%S)"
  archive_name="${PREFIX}-${timestamp}.tar.gz"
  manifest_name="${PREFIX}-${timestamp}.manifest.txt"
  checksum_name="${archive_name}.sha256"
  archive="$output_abs/$archive_name"
  archive_tmp="${archive}.tmp"
  manifest="$output_abs/$manifest_name"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "dry run: no files written"
    log "archive would be: $archive"
    return
  fi

  umask 077
  mkdir -p "$output_abs"
  chmod 700 "$output_abs"

  if [[ -e "$archive" || -e "$archive_tmp" || -e "$manifest" || -e "$output_abs/$checksum_name" ]]; then
    die "backup files already exist for timestamp $timestamp; retry in a moment"
  fi

  write_manifest "$manifest" "$archive_name"

  if ! tar -czf "$archive_tmp" \
    -C "$ROOT_DIR" "${INCLUDED_PATHS[@]}" \
    -C "$output_abs" "$manifest_name"; then
    rm -f "$archive_tmp" "$manifest"
    die "tar failed; if appdata files are not readable, stop the stack and rerun with sudo"
  fi

  mv "$archive_tmp" "$archive"
  chmod 600 "$archive"

  write_checksum "$output_abs" "$archive_name" "$checksum_name"

  log "created $archive"
  log "created $manifest"
  if [[ -f "$output_abs/$checksum_name" ]]; then
    log "created $output_abs/$checksum_name"
  fi
  warn "backup archives may contain credentials, tokens, or service state; store them accordingly"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config-only)
      set_mode "config"
      ;;
    --data-only)
      set_mode "data"
      ;;
    --grafana-only)
      set_mode "grafana"
      ;;
    --prometheus-only)
      set_mode "prometheus"
      ;;
    --alertmanager-only)
      set_mode "alertmanager"
      ;;
    --proxmox-only)
      set_mode "proxmox"
      ;;
    --no-prometheus-data)
      NO_PROMETHEUS_DATA=1
      ;;
    --no-grafana-data)
      NO_GRAFANA_DATA=1
      ;;
    --no-alertmanager-data)
      NO_ALERTMANAGER_DATA=1
      ;;
    --output)
      shift
      [[ $# -gt 0 ]] || die "--output requires a directory"
      OUTPUT_DIR="$1"
      ;;
    --prefix)
      shift
      [[ $# -gt 0 ]] || die "--prefix requires a name"
      PREFIX="$1"
      ;;
    --dry-run)
      DRY_RUN=1
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

case "$PREFIX" in
  ""|*/*)
    die "--prefix must be a filename prefix, not a path"
    ;;
esac

build_include_list
print_selection
create_backup
