# VPS FRP Mode Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reintroduce a safe optional `vps_frp` connection mode for TCU TCP 55230 while preserving existing `local` mode behavior.

**Architecture:** Keep current OpenCarwings web/API runtime unchanged and add a dedicated `frpc` service that is mode-gated by addon config. In `vps_frp`, generate an ephemeral FRP config from user options at startup and tunnel only TCU TCP 55230 to the user VPS.

**Tech Stack:** Home Assistant addon (`config.yaml` schema/options), Bash/s6 service scripts, FRP (frpc/frps), Alpine Docker image build, markdown docs.

---

## Task 1: Add FRP options to addon configuration

**Files:**
- Modify: `opencarwings/config.yaml`
- Modify: `opencarwings/translations/en.yaml`

**Steps:**
1. Add `connection_mode` with values `local|vps_frp`, default `local`.
2. Add `frp_server_addr`, `frp_server_port`, `frp_auth_token` options and schema entries.
3. Add translation labels/descriptions for all FRP fields and mode behavior.
4. Verify YAML parses and fields render under HA config UI.

## Task 2: Add FRP runtime in addon image

**Files:**
- Modify: `opencarwings/Dockerfile`

**Steps:**
1. Download/install `frpc` binary during image build.
2. Keep existing package/runtime behavior unchanged.
3. Ensure service scripts remain executable in image.
4. Verify Dockerfile syntax and FRP binary path `/usr/local/bin/frpc`.

## Task 3: Add mode-gated FRP service script

**Files:**
- Create: `opencarwings/rootfs/etc/services.d/frpc/run`

**Steps:**
1. Implement service gating:
- `local`: log disabled and sleep.
- `vps_frp`: validate required FRP fields and proceed.
2. Generate runtime TOML with addon values and fixed `remotePort = 55230`.
3. Persist FRP logs to `/data/logs/frpc.log`.
4. Fail fast with clear log errors for missing/invalid config.

## Task 4: Update docs for dual-mode operation

**Files:**
- Modify: `README.md`
- Modify: `opencarwings/README.md`
- Modify: `opencarwings/CHANGELOG.md`

**Steps:**
1. Document `local` and `vps_frp` mode selection and scope.
2. Add complete FRPS VPS setup:
- FRPS install
- example `frps.toml`
- systemd unit
- firewall ports
- DNS requirement (`tcu_domain -> VPS`)
- addon config example
3. Clarify FRP only tunnels TCU TCP 55230.
4. Add changelog entry summarizing feature reintroduction.

## Task 5: Verification checklist

**Run commands:**
- `bash -n opencarwings/rootfs/etc/services.d/frpc/run`
- `bash -n opencarwings/rootfs/etc/services.d/opencarwings/run`
- `bash -n opencarwings/rootfs/etc/services.d/nginx/run`
- `git diff -- opencarwings/config.yaml opencarwings/translations/en.yaml opencarwings/Dockerfile opencarwings/rootfs/etc/services.d/frpc/run README.md opencarwings/README.md opencarwings/CHANGELOG.md docs/plans/2026-03-03-vps-frp-mode.md`

**Expected outcomes:**
- New options are present with correct defaults.
- `frpc` script is syntactically valid and mode-gated.
- Docs and changelog reflect both connection modes and FRPS setup.
- No unexpected modifications outside planned files.
