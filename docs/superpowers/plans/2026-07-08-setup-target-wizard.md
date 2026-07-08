# Setup Target Wizard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `scripts/setup.sh` into an interactive first-run wizard that can append or deliberately reset Prometheus target files.

**Architecture:** Keep the implementation in `scripts/setup.sh` so the onboarding path remains one command. Add small Bash helper functions for prompt validation, target normalization, stock target-file templates, safe append behavior, and setup summaries. Update README quick-start docs and validate with temp-copy runs so real local secrets and target files are not touched.

**Tech Stack:** Bash, Docker Compose, Prometheus file service discovery YAML, existing `scripts/check.sh`.

## Global Constraints

- `setup.sh` remains repo-local and does not install or repair Docker.
- Docker Engine and the Docker Compose plugin are assumed to already be installed and functional.
- Target setup is additive by default.
- `--reset-targets` is the only path that rewrites target files.
- `--yes` and non-interactive runs skip the target wizard by default.
- `--yes --reset-targets` fails safely.
- Existing ignored local files such as `.env` and `proxmox/pve.yml` are never overwritten.
- Do not add nonstandard runtime dependencies.

---

## File Structure

- Modify `scripts/setup.sh`: add target wizard flags, prompt helpers, target file reset/append helpers, target collection, and summary output.
- Modify `README.md`: document first-run target prompts, non-interactive behavior, append behavior, `--skip-targets`, and `--reset-targets`.
- Preserve `scripts/check.sh`: it already validates shell syntax and YAML parsing for the target files.

---

### Task 1: Setup Flags And Prompt Helpers

**Files:**
- Modify: `scripts/setup.sh`

**Interfaces:**
- Consumes: existing `AUTO_YES`, `START_STACK`, `SKIP_CHOWN`, `OPEN_EDITOR` globals.
- Produces: new `SKIP_TARGETS`, `RESET_TARGETS`, `CHANGED_TARGET_FILES`, `prompt_count`, `prompt_required`, `prompt_default`, `normalize_exporter_target`, and `yaml_quote` helpers.

- [ ] **Step 1: Add new globals and help text**

Add:

```bash
SKIP_TARGETS=0
RESET_TARGETS=0
CHANGED_TARGET_FILES=()
```

Add help lines:

```text
  --skip-targets   Do not run the interactive target wizard.
  --reset-targets  Reset target files before adding targets; interactive only.
```

- [ ] **Step 2: Add argument parsing**

Add cases:

```bash
    --skip-targets)
      SKIP_TARGETS=1
      ;;
    --reset-targets)
      RESET_TARGETS=1
      ;;
```

- [ ] **Step 3: Add reset safety validation**

After argument parsing:

```bash
if [[ "$RESET_TARGETS" -eq 1 && "$AUTO_YES" -eq 1 ]]; then
  die "--reset-targets cannot be used with --yes; run setup interactively"
fi

if [[ "$RESET_TARGETS" -eq 1 && ! -t 0 ]]; then
  die "--reset-targets requires an interactive terminal"
fi
```

- [ ] **Step 4: Add prompt helpers**

Implement:

```bash
prompt_count()       # loops until a non-negative integer is entered
prompt_required()    # loops until a non-empty string is entered
prompt_default()     # returns default when input is blank
normalize_exporter_target() # appends a default port when no colon is present
yaml_quote()         # double-quotes YAML strings and escapes backslash/quote
```

- [ ] **Step 5: Validate syntax**

Run: `bash -n scripts/setup.sh`

Expected: no output and exit code `0`.

---

### Task 2: Target File Reset And Append Helpers

**Files:**
- Modify: `scripts/setup.sh`

**Interfaces:**
- Consumes: target file paths under `prometheus/targets/`.
- Produces: `reset_target_files`, `prepare_target_file_for_entries`, `append_target_entry`, and `record_changed_target_file`.

- [ ] **Step 1: Add stock target templates**

Implement `write_stock_target_file "$path"` with exact templates for:

```text
prometheus/targets/linux-hosts.yml
prometheus/targets/windows-hosts.yml
prometheus/targets/proxmox-hosts.yml
prometheus/targets/http-services.yml
prometheus/targets/ping-targets.yml
```

Each template ends with `[]`.

- [ ] **Step 2: Add reset function**

Implement:

```bash
reset_target_files() {
  write_stock_target_file "prometheus/targets/linux-hosts.yml"
  write_stock_target_file "prometheus/targets/windows-hosts.yml"
  write_stock_target_file "prometheus/targets/proxmox-hosts.yml"
  write_stock_target_file "prometheus/targets/http-services.yml"
  write_stock_target_file "prometheus/targets/ping-targets.yml"
}
```

- [ ] **Step 3: Add empty-list removal**

Implement `prepare_target_file_for_entries "$file"` so a final non-comment `[]` line is removed before appending entries, while comments above it are preserved.

- [ ] **Step 4: Add append helper**

Implement:

```bash
append_target_entry "$file" "$targets_newline_string" key value [key value ...]
```

It writes:

```yaml
- targets:
    - "target"
  labels:
    key: "value"
```

and records the changed file.

- [ ] **Step 5: Validate syntax**

Run: `bash -n scripts/setup.sh`

Expected: no output and exit code `0`.

---

### Task 3: Interactive Target Wizard

**Files:**
- Modify: `scripts/setup.sh`

**Interfaces:**
- Consumes: prompt helpers and append helpers from Tasks 1 and 2.
- Produces: `maybe_configure_targets`, `configure_linux_targets`, `configure_windows_targets`, `configure_proxmox_targets`, `configure_http_targets`, and `configure_ping_targets`.

- [ ] **Step 1: Add target wizard gate**

Implement `maybe_configure_targets`:

```bash
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
```

- [ ] **Step 2: Add Linux and Windows collection**

Linux prompts per host: address, hostname, role default `server`, site default `home`. Append default port `9100` when absent and labels `hostname`, `role`, `site`, `os=linux`.

Windows prompts per host: address, hostname, role default `workstation`, site default `home`. Append default port `9182` when absent and labels `hostname`, `role`, `site`, `os=windows`.

- [ ] **Step 3: Add Proxmox collection**

Prompts per host: address, cluster default `lab`, module default `default`, site default `home`. Do not add a port. Write labels `cluster`, `module`, `site`, `role=virtualization`, `os=proxmox`.

- [ ] **Step 4: Add HTTP and ping collection**

HTTP prompts per check: URL and site default `home`. Write labels `probe=http`, `site`.

Ping prompts per target: host/IP and site default `home`. Write labels `probe=icmp`, `site`.

- [ ] **Step 5: Wire the wizard into main flow**

Call `maybe_configure_targets` after `fix_appdata_ownership` and before `maybe_edit_configs`.

- [ ] **Step 6: Validate syntax**

Run: `bash -n scripts/setup.sh`

Expected: no output and exit code `0`.

---

### Task 4: Summary And Documentation

**Files:**
- Modify: `scripts/setup.sh`
- Modify: `README.md`

**Interfaces:**
- Consumes: `CHANGED_TARGET_FILES`.
- Produces: setup summary output and README usage examples.

- [ ] **Step 1: Extend setup summary**

Update `print_summary` to print changed target files when `CHANGED_TARGET_FILES` is non-empty.

- [ ] **Step 2: Update README quick start**

Document:

```bash
./scripts/setup.sh
./scripts/setup.sh --yes --start
./scripts/setup.sh --skip-targets
./scripts/setup.sh --reset-targets
```

Mention that interactive setup asks for Linux, Windows, Proxmox, HTTP, and ping targets; non-interactive setup skips target prompts; rerunning setup appends targets by default.

- [ ] **Step 3: Validate docs and syntax**

Run:

```bash
bash -n scripts/setup.sh
git diff --check
```

Expected: both commands exit `0`.

---

### Task 5: End-To-End Validation

**Files:**
- Test-only temp copies outside the repo.

**Interfaces:**
- Consumes: final `scripts/setup.sh`.
- Produces: validation evidence for non-interactive setup, interactive target writing, append behavior, reset behavior, and repo checks.

- [ ] **Step 1: Non-interactive setup test**

In a temp copy, run:

```bash
./scripts/setup.sh --yes --no-start --skip-chown
```

Expected: setup completes, target files remain empty `[]`, and no target prompts appear.

- [ ] **Step 2: Interactive target wizard test**

In a temp copy using a PTY, run:

```bash
./scripts/setup.sh --no-start --skip-chown
```

Enter one Linux host, one Windows host, two Proxmox hosts, one HTTP URL, and one ping target. Expected target files contain valid YAML entries with correct labels and default ports.

- [ ] **Step 3: Append behavior test**

Run the interactive wizard again in the same temp copy and add another Linux host. Expected: existing entries remain and the new Linux entry is appended.

- [ ] **Step 4: Reset safety test**

Run:

```bash
./scripts/setup.sh --yes --reset-targets --no-start --skip-chown
```

Expected: command fails with a clear error and does not rewrite target files.

- [ ] **Step 5: Interactive reset test**

In a temp copy using a PTY, run:

```bash
./scripts/setup.sh --reset-targets --no-start --skip-chown
```

Enter zero targets for every section. Expected: target files are restored to stock comments plus `[]`.

- [ ] **Step 6: Repository validation**

Run:

```bash
./scripts/check.sh
git diff --check
git status -sb
```

Expected: `scripts/check.sh` passes, whitespace check passes, and only intended files are modified before commit.
