# Setup Target Wizard Design

## Goal

Enhance `scripts/setup.sh` into the main first-run onboarding wizard for Docker Metrics Hub. The script remains repo-local and assumes Docker Engine and the Docker Compose plugin are already installed and functional. Its job is to prepare local stack files, collect initial monitoring targets, validate the result, and optionally start the stack.

## Architecture

`setup.sh` stays the single obvious entry point. It keeps the existing setup behavior for `.env`, `proxmox/pve.yml`, Grafana password generation, `./appdata` directories, appdata ownership, validation, and optional stack startup. It adds an interactive target wizard that writes Prometheus file service discovery YAML under `prometheus/targets/`.

Target setup is additive by default. Re-running `setup.sh` appends new target groups while preserving existing target files. A deliberate `--reset-targets` flag rewrites target files back to their stock comments plus an empty `[]` before adding targets from the current run.

## User Flow

The normal interactive flow is:

1. Check Docker and Compose availability.
2. Create local ignored config files if missing.
3. Generate a Grafana admin password when `.env` still has the placeholder.
4. Create `appdata/prometheus`, `appdata/grafana`, and `appdata/alertmanager`.
5. Offer to set appdata ownership for the container users.
6. Ask how many targets to add for each supported target type.
7. Collect details for each target.
8. Write target YAML.
9. Run `./scripts/check.sh`.
10. Ask whether to start the stack, or start directly when `--start` is used.
11. Print a summary with Grafana URL, credential status, changed target files, and next steps.

Non-interactive mode and `--yes` skip the target wizard by default so automation does not hang.

## CLI Flags

Existing flags remain:

- `--yes`: accept safe defaults for prompts.
- `--start`: start the stack after validation.
- `--no-start`: do not prompt to start the stack.
- `--skip-chown`: do not adjust appdata ownership.
- `--edit`: open local config files with `$EDITOR`.

New flags:

- `--skip-targets`: skip the target wizard during an interactive run.
- `--reset-targets`: reset target YAML files to their stock empty state before writing new targets.

`--yes --reset-targets` fails safely because it could wipe target files without replacement. No unattended reset override is part of this design.

## Target Prompts

Each target section begins with a count prompt. A count of `0` skips that section.

Linux hosts:

- Address or hostname, with default port `9100` added when no port is present.
- Friendly hostname label.
- Role label, default `server`.
- Site label, default `home`.

Windows hosts:

- Address or hostname, with default port `9182` added when no port is present.
- Friendly hostname label.
- Role label, default `workstation`.
- Site label, default `home`.

Proxmox hosts:

- Address or hostname, with no port added.
- Cluster label, default `lab`.
- Module label, default `default`.
- Site label, default `home`.

HTTP checks:

- Full URL.
- Site label, default `home`.

Ping checks:

- Hostname or IP address.
- Site label, default `home`.

## File Writing

Target files stay plain, human-editable YAML:

- Linux targets: `prometheus/targets/linux-hosts.yml`
- Windows targets: `prometheus/targets/windows-hosts.yml`
- Proxmox targets: `prometheus/targets/proxmox-hosts.yml`
- HTTP checks: `prometheus/targets/http-services.yml`
- Ping checks: `prometheus/targets/ping-targets.yml`

When a target file contains only comments plus `[]`, the script replaces `[]` with the new entries. When a file already has entries, the script appends new entries at the bottom. Existing comments at the top stay intact.

Prometheus file service discovery labels apply to the entire target group, so the wizard only groups targets that share the exact same labels. Linux and Windows hosts normally get one YAML entry per host because each host has a distinct `hostname` label. Proxmox, HTTP, and ping targets can be grouped when their labels match, such as multiple Proxmox nodes in the same `cluster`, `module`, and `site`.

## Safety And Errors

The script does not install Docker or repair host-level Docker configuration. It only checks Docker availability and reports problems.

Required fields reject blank input and ask again. Counts must be non-negative integers. Optional labels use defaults when left blank.

Existing ignored local files such as `.env` and `proxmox/pve.yml` are never overwritten. Target files are only rewritten when `--reset-targets` is explicitly used in an interactive run.

After writing targets, `setup.sh` runs `./scripts/check.sh` so malformed YAML or Compose problems are caught before startup.

## Documentation

The README should describe:

- Normal first-run setup with `./scripts/setup.sh`.
- Non-interactive setup with `./scripts/setup.sh --yes --start`, noting that target prompts are skipped.
- Re-running `./scripts/setup.sh` to append more targets.
- Using `./scripts/setup.sh --reset-targets` to intentionally rebuild target files.
- Using `./scripts/setup.sh --skip-targets` for config-only preparation.

## Testing

Implementation testing should use temporary repo copies so real local files and secrets are not touched.

Required checks:

- `bash -n scripts/setup.sh`
- `./scripts/setup.sh --yes --no-start --skip-chown` skips the target wizard.
- Simulated interactive input writes Linux, Windows, Proxmox, HTTP, and ping targets.
- YAML parsing succeeds for all target files after wizard output.
- Re-running setup appends new target groups without deleting existing entries.
- `--reset-targets` restores stock empty target files before adding new entries.
- `--yes --reset-targets` fails safely.
- `./scripts/check.sh` passes after the changes.
