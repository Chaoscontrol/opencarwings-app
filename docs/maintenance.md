# OpenCarwings maintenance runbook

## Normal operating state

- `57720a1b_opencarwings` is the only production runtime.
- `local_opencarwings-dev` is stopped, boots manually, has automatic updates
  and watchdog disabled, and uses host ports `18124`, `18125`, and `55231`.
- Dev uses `connection_mode: local`; FRP address and token are empty.
- GitHub `main` is authoritative. The local add-on directory is generated only
  by `scripts/deploy-opencarwings-dev.ps1` and is never edited directly.

## Before any maintenance

1. Fetch `origin` with pruning and tags and fast-forward local `main`.
2. Record both full app IDs, installed versions, current Supervisor state,
   network mappings, boot/watchdog/auto-update settings, and a redacted options
   comparison. Store any unredacted options in a mode-`0600` local file only.
3. Confirm both persistent clusters report `PG_VERSION` exactly `17`.
4. Create separate encrypted partial Supervisor backups for
   `57720a1b_opencarwings` and `local_opencarwings-dev`, plus a full Home
   Assistant backup. Verify each job completed, its manifest includes the
   intended full app ID, and an off-host copy is readable. Keep the Home
   Assistant emergency kit/password available.
5. Stop the dev app and confirm Supervisor reports `stopped` before running the
   one-shot deployment command. Use `-DryRun` first after a long gap.

## One-time dev-to-official data consolidation

This operation needs direct Home Assistant OS host access. Advanced SSH & Web
Terminal and the Samba add-on do not expose the Supervisor host data tree.
Enabling HAOS debug SSH on port `22222` grants full root access and therefore
requires a separately approved, temporary key and a planned reboot/removal
check. Prefer the local HAOS console when practical.

1. Keep both encrypted app backups and the full backup outside the host before
   changing data.
2. Stop both OpenCarwings apps and poll until both are fully stopped. Verify no
   PostgreSQL process is using either cluster and require the live-runtime
   `postgres/postmaster.pid` sentinel to be absent. If it remains, abort and
   investigate; never delete it to force this check.
3. Discover the exact Supervisor data mount for each full app ID with live
   Supervisor/Docker inspection. Do not assume a path and do not identify a
   target by the short slug alone. Reject symlink/reparse roots.
4. Confirm the dev source cluster and official destination cluster both contain
   `PG_VERSION=17`, and confirm enough free space for source, staging, and the
   retained previous destination.
5. Copy the complete stopped dev data tree to a same-filesystem staging
   directory using a host-native tool that preserves numeric owners, modes,
   timestamps, hard links, ACLs, xattrs, sparse files, and safe in-tree
   symlinks. Compare file lists, sizes, metadata, and a checksum manifest.
6. Rename the existing official data directory to a dated quarantine path,
   then rename the verified staging directory into the exact official data
   path. Keep both the dev source and quarantined official data unchanged.
7. Apply the authoritative dev Supervisor options to official through the
   Supervisor API, but preserve the official app ID, production ports, boot,
   auto-update, and watchdog settings. Validate options before starting.
8. Start official only. Require PostgreSQL 17, Redis, all s6 services, Django
   migrations, and static collection to succeed without ignored errors.
9. Verify existing vehicles/history/configuration, UI/API/HTTPS, TCU, FRP, and
   the existing Home Assistant integration. The integration gate is the prior
   `/api/car/` `403` changing to an authenticated `200` with the migrated API
   identity.
10. Perform a full stop/start and repeat the data, API, port, and log checks.
    Leave dev stopped/manual on isolated ports for one week before uninstalling
    it. Keep the backups after uninstall.
11. Remove the temporary HAOS host key, reboot if required by the HAOS key
    import mechanism, and verify port `22222` is closed.

If any validation fails, stop official before it can make further writes,
restore the complete quarantined official data and Supervisor settings, then
restart the unchanged dev app on its previous production settings. Never copy
or restore PostgreSQL files while either app is running.

## Release flow

1. Create a short-lived branch from current `origin/main`.
2. For an upstream release, update `.upstream_sync` on that branch to the exact
   40-character upstream commit before deployment. The release workflow will
   not change runtime source after dev validation.
3. Deploy once to stopped dev and rebuild the local app.
4. Test dev on isolated ports. A TCU/FRP test is an exclusive cutover: capture
   settings, stop official, temporarily apply production settings to dev, test,
   and restore dev isolation in a guaranteed cleanup step before official is
   restarted.
5. Commit and push the tested source. Branch/PR CI must pass the full image
   build and smoke test.
6. Manually dispatch the upstream or add-on patch release from `main`, confirm
   dev validation, and enter the exact 40-character tested commit SHA.
7. Back up and manually update official only after the release build gate and
   atomic commit/tag push succeed.

Upstream base releases use `0.0.X`; add-on-only fixes use `0.0.X-N`.

## Separate security hardening

Track embedded application secrets, PostgreSQL trust authentication, safe API
key injection, query-string logging, restrictive FRP token-file permissions,
and checksum/digest pinning separately from database-sensitive maintenance.
Do not expose existing secret values in issues, logs, commits, or test reports.
