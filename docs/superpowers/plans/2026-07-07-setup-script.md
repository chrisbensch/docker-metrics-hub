# Setup Script Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a safe first-run setup script for Docker Metrics Hub.

**Architecture:** The script prepares local ignored config files, generates a Grafana password when the placeholder remains, creates `./appdata` directories, applies container-user ownership, runs existing validation, and optionally starts the Compose stack. It is idempotent and avoids overwriting existing local secrets.

**Tech Stack:** Bash, Docker Compose, existing project validation scripts.

## Global Constraints

- Do not commit generated `.env` or `proxmox/pve.yml`.
- Do not overwrite existing local secret-bearing files.
- Keep setup usable on Ubuntu Server with Docker Compose.
- Keep stack startup optional.
- Keep `./appdata` bind mounts as the persistent data model.

---

## Tasks

### Task 1: Setup Script

**Files:**
- Create: `scripts/setup.sh`

**Interfaces:**
- Consumes: `.env.example`, `proxmox/pve.yml.example`, `scripts/check.sh`.
- Produces: local `.env`, local `proxmox/pve.yml`, appdata directories, optional running stack.

- [ ] Create an idempotent Bash setup script.
- [ ] Add `--yes`, `--start`, `--no-start`, `--skip-chown`, and `--edit` flags.
- [ ] Generate a Grafana password only when `.env` still contains the placeholder.
- [ ] Run `scripts/check.sh`.

### Task 2: Documentation And Validation

**Files:**
- Modify: `README.md`
- Modify: `scripts/check.sh`

**Interfaces:**
- Consumes: `scripts/setup.sh`.
- Produces: documented quick start and syntax validation.

- [ ] Make `scripts/setup.sh` the recommended quick start.
- [ ] Keep manual setup commands for users who do not want the wizard.
- [ ] Add Bash syntax validation for project scripts.
