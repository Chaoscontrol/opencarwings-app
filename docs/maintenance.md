# OpenCarwings maintenance runbook

## Normal operating state

- `57720a1b_opencarwings` is the only production runtime.
- `local_opencarwings-dev` is stopped, boots manually, has automatic updates
  and watchdog disabled, and uses host ports `18124`, `18125`, and `55231`.
- Dev uses `connection_mode: local`; FRP address and token are empty.
- GitHub `main` is authoritative. The local app directory is generated only by
  `scripts/deploy-opencarwings-dev.ps1` or `scripts/deploy-opencarwings-dev.py`
  and is never edited directly.

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
2. For an upstream catch-up requiring local validation, update `.upstream_sync`
   on that branch to the exact 40-character upstream commit before deployment.
   The release triggered by a push to `main` uses that checked-in pin.
3. Deploy once to stopped dev and rebuild the local app.
4. Test dev on isolated ports. A TCU/FRP test is an exclusive cutover: capture
   settings, stop official, temporarily apply production settings to dev, test,
   and restore dev isolation in a guaranteed cleanup step before official is
   restarted.
5. Commit and push the tested source. Branch/PR CI must pass the full image
   build and smoke test.
6. Merge the tested upstream change to `main`. The upstream workflow builds and
   releases the checked-in pin automatically. App-only patches use the manual
   patch workflow with dev validation and the exact tested app commit SHA.
7. Back up and manually update official only after the release build gate and
   atomic commit/tag push succeed.

All new releases increment the app's own numeric patch counter (`0.0.25`,
`0.0.26`, ...), including app-only fixes. Legacy `-N` versions remain readable.
The upstream version and exact source SHA are recorded separately in release
notes and `.upstream_sync`; upstream tags do not determine the app version.

## Automatic upstream releases

- Every day at 03:17 UTC, resolve upstream `main` once, verify forward history
  from the last release, and build a candidate pinned to that exact commit.
- An unchanged upstream SHA skips code publication and version changes.
- The read-only gate runs a full amd64 image build, metadata checks, startup
  patch regressions and a real Redis idle-receive/message-delivery test.
- Only a passing candidate is committed and tagged atomically. Publishing checks
  that app `main` has not moved, and never overwrites an existing release tag.
- GitHub Release notes identify the app version, upstream version, source SHA
  and comparison range. A missing notes publication can be retried without
  incrementing the version again.
- A push to `main` uses its checked-in upstream pin; scheduled/default manual
  runs follow upstream `main`. Manual dispatch can select an explicit upstream
  SHA. Historical tag recovery remains a separate manual operation.
- These releases do not install themselves in HA unless app automatic updates
  are enabled there. Keep dev stopped/manual and isolated after testing.
- To avoid GitHub's 60-day inactivity rule, an unchanged-upstream check creates
  an empty keepalive commit after 30 days without another main-branch commit.
  It changes no source files, app version or tags. This write has its own stale
  main check and never force-pushes. Manually disabled workflows still need to be
  re-enabled in Actions.

## Separate security hardening

Track embedded application secrets, PostgreSQL trust authentication, safe API
key injection, query-string logging, restrictive FRP token-file permissions,
and checksum/digest pinning separately from database-sensitive maintenance.
Do not expose existing secret values in issues, logs, commits, or test reports.
