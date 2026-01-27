## v0.0.17 - 2026-01-27 [Upstream Update]

Synced with latest upstream changes from opencarwings repository.

- Add support for CWS_SYS connection profile file editing for Qy8XXX navigation units (a029440)

## v0.0.16 - 2026-01-20 [Upstream Update]

Synced with latest upstream changes from opencarwings repository.

- Fix logic with soft errors (e356095)
- Fix logic with soft errors (b557b74)
- Add another channel to blacklist and add alerts for TCU parameter & auth mismatches for easier debugging (dff8943)

## v0.0.15 - 2026-01-19 [Upstream Update]

Synced with latest upstream changes from opencarwings repository.

- Merge remote-tracking branch 'origin/main' (25c9403)
- Add logging for unknown requested channels (586852e)

## v0.0.14 - 2026-01-12 [Upstream Update]

Synced with latest upstream changes from opencarwings repository.

- Update README.md (cbb0e2a)

## v0.0.13 - 2025-12-15 [Upstream Update]

Synced with latest upstream changes from opencarwings repository.

- Add apk-tools upgrade before installing packages (4fff48e)
- Upgrade alpine version (356f6b4)
- Remove mysql deps (8b81881)
- Fix ecotree channel bug for page 2 (e650564)

## v0.0.12 - 2025-12-14 [Upstream Update]

Synced with latest upstream changes from opencarwings repository.

- Add missing page argument to custom autodj (2b8f2b5)
- Enhance weather dark mode and exclude channel 0x270f to avoid weekly popups (e3179ba)
- Landing page fixes and misc patches (b24e5f1)
- Change battery pack temperature to bars and add Hx note for resistance (7f106bc)

## v0.0.11 - 2025-12-13 [Upstream Update]

Synced with latest upstream changes from opencarwings repository.

- Fix thumbnail picture in Google POI search and enable streaming in information channels with multiple channels (26fdc98)
- Unwrap cp (3b038bd)
- Wrap charging point update items in new encoding function and check cellular signal type (7cd3645)

## v0.0.10 - 2025-12-09 [Upstream Update]

Synced with latest upstream changes from opencarwings repository.

- Fix charge point requests (1576a65)

## v0.0.9 - 2025-12-08 [Upstream Update]

Synced with latest upstream changes from opencarwings repository.

- Apply text field limit to all AutoDJ fields and log failed charge point update responses (cdfa97b)
- Add limit to textfield (292d168)

## v0.0.8 - 2025-12-02 [Upstream Update]

Synced with latest upstream changes from opencarwings repository.

- Improvements and fixes to probe_crm on battery_degradation_analysis parsing and added new release notes for december (8f72422)
- Update README.md (e5cfeb6)
- Increase provider configuration max length to 512 for longer webhook URLs (8bda2a9)
- Update docker-publish.yml (50b1ead)
- Update docker-publish.yml (4b85aac)
- Delete .github/workflows/docker-image.yml (3b6b45f)
- Create docker-publish.yml (55ed9ca)
- Create docker-image.yml (c239b05)

## v0.0.7 - 2025-12-01 [Upstream Update]

Synced with latest upstream changes from opencarwings repository.

- Merge pull request #7 from Chaoscontrol/monogoto (663815e)
- Fix "from" sms max length limit for Monogoto (32dbaef)

## v0.0.6-1 - 2025-12-01 [Addon Patch]

- Merge branch 'main' of https://github.com/Chaoscontrol/opencarwings-addon
- Removed all Tailscale implementation as it cannot expose custom TCP ports (55230)
- Commented tailscale additions to debug. Working version without tailscale.
- Attempt 1 at integrating Tailscale for TCU port tunnel. Not starting.

## v0.0.6 - 2025-11-29 [Upstream Update]

Synced with latest upstream changes from opencarwings repository.

- Localize new strings and fix duplicate notifications issue (e30c8ba)
- Merge pull request #5 from Chaoscontrol/monogoto (ce788da)
- New Monogoto IoT provider (6710ea8)

## v0.0.5 - 2025-11-25 [Upstream Update]

Synced with latest upstream changes from opencarwings repository.

- Visualize heading of ABS events (50ca825)
- Fix few fields on probe energy info (8ff74f0)

## v0.0.4 - 2025-11-24 [Upstream Update]

Synced with latest upstream changes from opencarwings repository.

- Add carrier and signal level to list API (cd3bd9f)
- Revert weather channel background to maintain nice compression (2b43197)
- Small patch to probe crm charges longitude field (45594b5)
- Another attempt at fixing weather icons (b200e99)
- Fix MSN data length (5692b3f)
- More fixes to probe parsing (5b8975e)
- Bugfixes: Probe CRM MSN and Charge fields, Charge Point remove debug log and weather channel fix snow icon (79fdd9f)

## v0.0.3-1 - 2025-11-04 [Addon Patch]

- Changed server to daphne, now it starts the TCU TCP 55230 port and it's listening
- Repo cleanup, removed s6-overlay

## v0.0.3 - 2025-11-03 [Upstream Update]

Synced with latest upstream changes from opencarwings repository.

- Update time formatting from probe (9480180)
- Add slideshow to landing page (33643e0)
- Implement timezone setting for user and make datetimes timezone-aware in probe data (76088dd)
- Small patches to probe data viewer (bba4f1d)
- Enable max speed field (b37f238)
- Correctly implement ABS probe data parsing and other fixes (52ee21c)
- Fix field (4244d35)
- Handle timeout wait if last command timed out (330d17a)
- Change periodic data update order (205c0cd)
- Fix in Apple maps for new link format (28d3506)

## v0.0.2 - 2025-11-03

- Updated github workflows for updates and reset versioning
- Fixing addon-patch workflow
- Added icon and logo
- New readme and instructions
- Added trusted domains option Removed configurable Activation SMS message
- Refactored django-setup and dockerfile to use the existing settings, and added all necessary dependencies
- bootstrap4 added in attempt to fix forms not loading properly
- Sign up works. Forms missing CSS, and Radio options not loading.
- Added more dependencies
- All files changes to LF and adjusted shebangs
- Changed file to LF
- Sign up page working
- UI loads
- Debugging health check
- Django running, health check issues
- Main skeleton and runtime working. App still not accessible.
- Upstream repo folder and gitignore

# Changelog

## 2025-11-02 - Initial Add-on Release

- Initial Home Assistant add-on for OpenCarwings
- Built-in PostgreSQL and Redis databases

---

## Upstream Changes

_No upstream changes tracked yet_
