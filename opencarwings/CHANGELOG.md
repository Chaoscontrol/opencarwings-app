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
