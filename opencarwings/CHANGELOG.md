## v0.0.25 - 2026-10-25 [Upstream Update]

- Advance upstream from `797e6dc` to `bfe2ad2` (238 commits; upstream version 1.1).
- Add upstream FICOSA support, vehicle-health features, optional 2FA/command PINs,
  account transfers, SMS providers, navigation improvements and translations.
- Update startup patches for the new CRM parser, Iternio request and logger names.
- Configure current Django static storage and compile translations.
- Add expired-transfer cleanup and an option to pause periodic jobs during dev tests.
- Preserve HTTP Host ports for dev login on isolated ports.
- Fix idle notification reconnect loops caused by redis-py 8's default timeout.
- [Detailed features and validation notes](https://github.com/Chaoscontrol/opencarwings-app/blob/main/docs/upstream-catchup-2026-10.md)
- [Complete upstream comparison](https://github.com/developerfromjokela/opencarwings/compare/797e6dc0f707169d521841ce400b19bad027e7bd...bfe2ad23a5e973c0a5313b711af4852394aea9a0)

Upstream source: [`1.1 / bfe2ad23a5e973c0a5313b711af4852394aea9a0`](https://github.com/developerfromjokela/opencarwings/commit/bfe2ad23a5e973c0a5313b711af4852394aea9a0).
Comparison: [797e6dc...bfe2ad2](https://github.com/developerfromjokela/opencarwings/compare/797e6dc0f707169d521841ce400b19bad027e7bd...bfe2ad23a5e973c0a5313b711af4852394aea9a0).

### Upstream commits

- Merge remote-tracking branch 'origin/main' (bfe2ad2)
- Fix tests (3f63c9a)
- Merge pull request #91 from developerfromjokela/dependabot/pip/pycryptodome-approx-eq-4.1.0 (0c94e40)
- Implement command pin brute force protection and cleanup coordinate copy & map link + other misc fixes (caed4c0)
- Merge pull request #90 from tdaroczi/codex/location-walking-directions (e7ce3e9)
- Enhance sorting in probeview, move (invalid) dates from future to low priority and few fixes in probe_crm.py (f109c63)
- Simplify location coordinate handling after review (69cd21a)
- Issue #59 (d4bf4c0)
- Move test to right workflow (026a7e4)
- Remove old test and make tests run with github actions (1464bf4)
- Merge pull request #92 from developerfromjokela/dependabot/pip/xxhash-approx-eq-4.0.2 (982391f)
- Update pycryptodome requirement from ~=3.23.0 to ~=4.1.0 (fd0aa34)
- Merge pull request #89 from developerfromjokela/dependabot/pip/pillow-13.0.0 (d22ee11)
- Update xxhash requirement from ~=4.0.1 to ~=4.0.2 (a467e59)
- Revise Home Assistant add-on repository information (23829b2)
- Make car coordinates usable from the Location page (6d1d0c6)
- Move tcuserver into same style logging as other parts like carwings (85611fa)
- Fix compatibility with transfers without email defined and allow admin to create transfers without email. (7b25fff)
- Merge pull request #82 from osexpert/feature/ac-assume-off-timeout (7b6a5ab)
- Create migration for ac_last_started field in evinfo (08fec2e)
- Merge pull request #80 from developerfromjokela/dependabot/pip/drf-yasg-approx-eq-1.21.18 (e675078)
- Merge pull request #79 from developerfromjokela/dependabot/pip/suntime-approx-eq-1.4.0 (7871413)
- Merge pull request #81 from albertbm/user-car-transfer (6210019)
- Merge pull request #87 from spma123/gatewayapi-sender (1c8e108)
- Let owners transfer a car to another account (d388ea1)
- nits (7c05fee)
- changes from feedback (fbb6858)
- Bump pillow from 12.3.0 to 13.0.0 (0d7c0fb)
- Add sender field to payload in gatewayapi.py (d4ed4fb)
- Merge pull request #85 from developerfromjokela/dependabot/pip/gitpython-approx-eq-3.2.1 (6062527)
- Update gitpython requirement from ~=3.2.0 to ~=3.2.1 (8a4ad40)
- Update suntime requirement from ~=1.3.2 to ~=1.4.0 (6f1cbae)
- Merge pull request #77 from developerfromjokela/dependabot/pip/pytz-2026.5 (b6760e5)
- Merge pull request #76 from developerfromjokela/dependabot/pip/djangorestframework-approx-eq-3.18.3 (02db709)
- Merge pull request #83 from tdaroczi/codex/route-planner-location-names (11f21a6)
- Fix Route Planner location names and validation (8768274)
- consider last_updated (35cdf97)
- Setting to assume AC is off after X minutes. (7614578)
- Merge remote-tracking branch 'origin/main' (9e4f3e3)
- Handle new gear data (B-mode and neutral) (bf8918a)
- Update Discord server link in README.md (60b7a88)
- Fix Discord server link in README (7858e7c)
- Update drf-yasg requirement from ~=1.21.15 to ~=1.21.18 (3715915)
- docs: rebuild static docs (cc41967)
- Add note about base template icon. (bcf87e7)
- Implement custom data channel icons (f318742)
- Merge remote-tracking branch 'origin/main' (6085803)
- URL sanitization for webhook and map resolver (4797b64)
- Update djangorestframework requirement from ~=3.18.0 to ~=3.18.3 (b134560)
- Merge pull request #75 from developerfromjokela/dependabot/pip/gitpython-approx-eq-3.2.0 (a1946af)
- Bump pytz from 2026.3 to 2026.5 (d98da63)
- Update gitpython requirement from ~=3.1.62 to ~=3.2.0 (91e505c)
- Create dependabot.yml (aa9103b)
- Fix comment (ee24f65)
- Add timesync and serviceprovisioning fields to 0x27 Auth fail ACK message and apply new API changes to seven.py (2bed210)
- Add missing timesync element also to evauth ACK (25b7981)
- docs: rebuild static docs (5015c24)
- Merge pull request #73 from tdaroczi/docs/hungarian-localization (73d775c)
- Merge remote-tracking branch 'origin/main' (64e2b9e)
- Add missing timesync element to acp response (08e179d)
- docs: add reviewed Hungarian documentation (81be96c)
- Merge pull request #72 from opencarwings-bot/weblate-opencarwings-server-server (ad47f33)
- chore(l10n): update Portuguese translation (ce0dfe6)
- chore(l10n): add Portuguese translation (2937ed6)
- chore(l10n): update Swedish translation (cc8452d)
- chore(l10n): update Swedish translation (649bf90)
- docs: rebuild static docs (3d9c83e)
- Merge remote-tracking branch 'origin/main' (4150b83)
- Introduce proper Documentation platform (b6241be)
- Merge pull request #71 from opencarwings-bot/weblate-opencarwings-server-server (fd6f536)
- Merge remote-tracking branch 'origin/main' (ef14b8a)
- Fix a bug in checking current navigation guidance status (761b7fe)
- Limit title text (0a60ba0)
- Add check for already requested command (3531bc3)
- Implement feature #63 (c159c33)
- chore(l10n): update Icelandic translation (4349196)
- chore(l10n): add Icelandic translation (633d29e)
- chore(l10n): update Swedish translation (3a1a78b)
- Fix a bug in CP meshutils bounding box generation, which caused a small gap to be present. (efa40ba)
- Change carwings cp logic, do not tie revision ID into DateLastVerified, instead calculate hash of the info (75b0d96)
- chore(l10n): update Russian translation (dfb5e5b)
- Fix maps.goo.gl link parsing (f8791cf)
- Removed 80% charge option from ficosa, it has not been working on any models (528f4ce)
- Implement reading RDIAG probe info into trouble records. issue #65 (162c106)
- chore(l10n): update Swedish translation (e442140)
- chore(l10n): update Finnish translation (1c744af)
- chore(l10n): update Estonian translation (6e232dc)
- Send partial temperature value for A/C command instead of full degree value. (43cc195)
- Declutter settings tab, issue #58 (8bd3eeb)
- Fix issue #50 (e092804)
- Add fresh translations and rename estonian translation language code (c5ad285)
- Merge pull request #68 from opencarwings-bot/weblate-opencarwings-server-server (ce45d03)
- chore(l10n): update Russian translation (e5848f7)
- chore(l10n): update Finnish translation (f927d11)
- chore(l10n): update Ewe translation (9ce8551)
- chore(l10n): update Swedish translation (6411289)
- chore(l10n): add Swedish translation (323bc35)
- chore(l10n): update Spanish translation (ef63648)
- Add translation status badge (27ecaff)
- Implement support for charge plug power detection with FICOSA TCU EVInfo, including detecting interrupted charging session (power lost) (8301534)
- Encode minus information in DMS coordinates (2f88e29)
- Add parsing STD Precise Location header for negative DMS values (cab8ca9)
- Add logging to catch DMS coordinate negative flag and make quality-of-life improvements on connection status (b9f9dd1)
- Fix DMS coordinate parsing (e7d4d3d)
- Fix heading (2227af9)
- Fix heading (5be04d9)
- Fix TPMS pressures in trips and implement DOT file viewer (bea54cb)
- Merge remote-tracking branch 'origin/main' (fb3d2f9)
- Fix units for email notifications and add a check for timers date and time, to not be in the past or present. (be72a97)
- Update docker-publish.yml (c724d0a)
- Do localization and change naming for the command (5c203e3)
- Add handling for Battery Lease Charging Unblock result, and added battery lease status to evinfo parsing (a2e2f79)
- Included EVCommandTail for unblock request (a2c2140)
- Add new migration for battery lease program commands (51b3df2)
- Implement battery lease program's charging block disabling command (68b2140)
- Improvements on setup guides and make trip items underlined, to indicate them being a clickable link. (d95991a)
- Fix IE element decoder, make multiple length octets supported. Assumed incorrectly to be capped at only two. (dcb799d)
- Add safe parsing for probe dot timestamps (51005a0)
- Fix typo (914a9f2)
- Fix typo (58f3abf)
- Implement generating random message reference for TCU SMS PDUs (d1c3cb1)
- Merge remote-tracking branch 'origin/main' (2e7bccf)
- Implement V2 Probe fields for FICOSA TCUs, DOT data for FICOSA and add TPMS info for Trips (only FICOSA). + Changed source of capacity bars for FICOSA, and added new field (GIDS when new) (1228b62)
- Update README to remove app download links (f404792)
- Update README with app download links (5dc99c7)
- Fix VCan speed (0540d2b)
- one last div by 100 (1283e64)
- one last div by 100 (9c2ac1b)
- add type conversion (75bd3f2)
- Fix calculation behind G forces (8ff803c)
- One more fix (ddfbe4f)
- One more fix (a6488c3)
- Fix few issues with probe trips (179872d)
- Merge remote-tracking branch 'origin/main' (1765160)
- Implement filling VehDesc fields with exact expected length. Previously, JDM shorter VIN numbers were packed as shorter buffer and this was rejected by TCU parser. (6557d4a)
- Update README.md (7bb3d76)
- Do last fixes for probe config proto generator (8cb9d1e)
- Fix can param mask, which is actually uint32. (11363c5)
- Use composer instead of sending raw (02cde98)
- Small fix to probe config payload generation (35183aa)
- Small fix to probe config payload generation (fdc9d54)
- Implement experimental Probe Data Configuration (ecfba7b)
- Allow signing in with email and reject data with invalid source ID. + add Probe Data Config protocol composer, for upcoming configuration function (b5cdb0b)
- Return ACK 0 when auth is failing. (eee1082)
- Convert tire pressure data to properly readable values (7d815c2)
- Enhance navi_guide2 and make slide PNG data more compatible. Refactor saving car objects, update only modified fields. (99f5412)
- Enhance navi_guide2 and make slide PNG data more compatible (408425e)
- Fix recursive translation of configs (1ada939)
- Add allow null if field not required on change command pin (b5e56d4)
- Fix device type for 2018+ e-NV200 (c621073)
- Fix division by zero (12d2678)
- Fix SMSError message being translated string (96d9ce2)
- Make the timer date timezone-aware on the frontend (9cef7c1)
- Merge remote-tracking branch 'origin/main' (c43873c)
- Add server settings configuration (45b066d)
- Update README with supported vehicles and features (b30ea96)
- Buffix: Add configuration for SIM card settings 1 and 2 (edbd04d)
- Add configuration for SIM card settings 1 and 2 (c52b4bd)
- Add configuration for SIM card settings 1 and 2 (d87a5e2)
- Do translation compiling during docker compile and add error message for viaaq mobile 404 error (3c44fe9)
- Fix issue in Probe Information Parser, where attachment files were processed as main files. (5106ac3)
- Fix issue in JWTTokenObtainSerializer, mistakenly taking all accounts having 2FA (89efbc4)
- Run docker as normal user, implement 2FA & command PIN, upgrade dependencies and other misc tweaks (cc3c42a)
- Add 6.6 OBC flag to EVInfo parser (030ab9c)
- Enhance PNG compression to be more compatible with ancient PNG processor on head units (e7e9b54)
- Add missing ecu label for short DTCs and implement time-outs also for waiting a response. (0462527)
- Small fix on timezone input for signup (5817cc2)
- Implement car transfer requests and redirect to previous url in sign in process (4d688b6)
- Make translations (0255d11)
- Implement vehicle health data reporting (655bc34)
- Fix timer id (e8a1797)
- Fix timer typo (845bc94)
- Translate TCU configuration screen (c7cdbe0)
- Implement viaaq mobile SMS provider and fix timer id getting thrown out in command payload -> timers not working (5add99c)
- Add rejecting requests that do not match command ID + log command output (f5eb42c)
- Add new guide for 2016-2020 models and improve older guides. Also skip SIM ID check for CARWINGS AP. (17f65db)
- Include Probe Service provisioning switches (171138d)
- Include new redis config with timeout, now also in settings.example.py (3ae5792)
- Fix ACP ack issues (1524f70)
- Small cosmetic UI changes (f56e88c)
- Add seven.io SMS provider (81a7546)
- Add vehicle health, tow and burglar destination. Up-to-date translations and small tweak in car_detail.html (f3342ef)
- Add more fields to service provisioning (a70231c)
- Fix current value in configuration.html for provisioning fields (f33e4cb)
- Merge remote-tracking branch 'origin/main' (59ef3f4)
- Fix ServiceProvisioning encoder (a2fc4d5)
- Create LICENSE (a73a36e)
- Implement service provisioning function for Ficosa TCU (6d89a5e)
- Implement service provisioning function for Ficosa TCU (1c76163)
- Fix i18n (3572872)
- Fix i18n (2ff6f4a)
- Fix typo (f953ad4)
- Tweak vehicle health config and add listener for any incoming data (68c58ad)
- Fix acp config parser (95e8b04)
- Add exception for app id 0x1d (f6e11ae)
- Fix data field querying (ee0f39b)
- Implement beta TCU configuration UI and logic for ficosa and do slight adjustments to AutoDJ channels (ee8a506)
- Disable checking DCM ID and ICCID, because on JDM models it causes issues. (19640fb)
- Implement A/C temperature setpoint payload (accurate with protocol, not tested) (daf964d)
- Add unconfirmed cabin temperature for ZE1 (fbe9e5a)
- Add unconfirmed cabin temperature for ZE1 (5deef26)
- Add caching around eco forest tree query (43fa943)
- Enhance image generation with compressed assets, trying to reduce size (016d368)
- Fix PDU number type to 0x91 (2f3ff02)
- Add safe datetime & time parsing (f13c953)
- Swap acon and acoff for ficosa, add max limit for SOC display and clarify API documentation (ccb3feb)
- Add logging for sms failures (efb4ba2)
- Fix prb (7a3adec)
- Change type of msn and fix its decoding type (3d9b224)
- Fix small typo (2ecc9f5)
- Implement backwards-compatible probe data handling and misc fixes (407eb8d)
- Fix ZE1 body (f23b5ee)
- Remove Useragent check (99e454c)
- Implement better ACK response and rejecting (7f4d999)
- Add gatewayapi.com provider (818f1b2)
- Fix stub (9f911a3)
- Fix periodic update logic and fix PDU size calculator (78702d3)
- Fix periodic update logic and fix PDU size calculator (c4c0470)
- Fix type issue in smsgateway.py (8b4e589)
- Add support for USB modem SMS gateways and sending PDUs (a41f2c6)
- Fix broken alerts for continental tcuserver (8d3c328)
- Fix horn request encoding (d037c8d)
- Fix horn request encoding (c8c690d)
- Fix command map (ae3d3eb)
- Typefix duration for horn (426a75f)
- Add AC autostop destination (ea66d6a)
- Add succession trigger also when source ID matches with command ID (4a072ef)
- Fix car serializer (04e16e7)
- Fix invalid AC Off (8d641d4)
- Change evauth logic, cushion leftover requests and fallback to evinfo instead of ACK, which freezes tcu communication for few minutes (3649b82)
- Fix missing version block for probe (32e0f8e)
- Small adjustments to Ficosa TCU handling (782aaab)
- Fix bug in serializer, causing real-time status updates to fault (cd5fc3b)
- Implement remote start command (not tested, but protocol-wise accurate) (ea6ea44)
- Implement horn & light functionality and minor adjustments to door lock unlock (ce69af0)
- Implement door lock unlock handling (429766b)
- Fix typo (c1bfdc6)
- First beta implementation of newer generation FICOSA TCUs (e4037ba)

## v0.0.24-3 - 2026-07-18 [Addon Patch]

- Harden dev deployment and release workflow

## v0.0.24-2 - 2026-07-17 [Addon Patch]

- Fix fresh TLS certificate generation

## v0.0.24-1 - 2026-07-17 [Addon Patch]

- Repair v0.24 app build and release gates

## v0.0.24 - 2026-07-14 [Upstream Update]

Synced with latest upstream changes from opencarwings repository.

- Fix redis timeout issue (797e6dc)
- Fix osm tile referrer policy (0a70db0)
- Merge remote-tracking branch 'origin/main' (4814987)
- Improve checksum exception log info and make manytomanyfields optional (756fd6c)

## v0.0.23 - 2026-04-21 [Upstream Update]

Synced with latest upstream changes from opencarwings repository.

- Update README.md (3927dad)
- Update README.md (118ac58)
- Fix issue with OSM Referer problem (c7c87bb)

## v0.0.22 - 2026-03-27 [Upstream Update]

Synced with latest upstream changes from opencarwings repository.

- Update README.md (c1589a3)

## v0.0.21-1 - 2026-03-08 [Addon Patch]

- VPS+FRP option added back
- Improvement: Timeouts promoted to WARNING

## v0.0.21-1 - 2026-03-03 [Addon Patch]

- Reintroduced optional FRP connectivity mode (`vps_frp`) for CGNAT users while keeping `local` as default.
- Added addon options for FRP server address, FRP server port, and FRP auth token.
- Added bundled FRP client runtime and dynamic `frpc` configuration generation for secure per-user VPS setup.
- Updated root and addon READMEs with dual-mode guidance and full FRPS VPS setup instructions.

## v0.0.21 - 2026-02-23 [Upstream Update]

Synced with latest upstream changes from opencarwings repository.

- Add new navigation guide for AZE0 & ZE1 vehicles + warnings to not mismatch guides. (fe0c8c1)
- Refactor result handling, switch from alertstate and resultstate to using subfields (516487c)

## v0.0.20-3 - 2026-02-21 [Addon Patch]

- Added alert for ac error 128
- Split trusted_sources in 2 options for clarity and simplified setup and webhook use
- Configure port 8124 as unified HTTP origin for car endpoint + browser UI + HA API, making port 8125 optional. Add car endpoint User-Agent check to block non-car requests.

## v0.0.20-2 - 2026-02-16 [Addon Patch]

- Updated HA Readme
- chore: remove upstream link and ignore local workspace files

## v0.0.20-1 - 2026-02-15 [Addon Patch]

- feat: add Monogoto SMS delivery webhook support. feat: revamp full logging docs: Update ALERTS.md with upstream-first alert matrix documentation
- Log revamp v1

## v0.0.20 - 2026-02-15 [Upstream Update]

Synced with latest upstream changes from opencarwings repository.

- Merge remote-tracking branch 'origin/main' (6120eda)
- Add sub-fields inside alertstate and resultstate and logging to determine all possible values (738165d)

## v0.0.19-2 - 2026-02-12 [Addon Patch]

- Fix log spam for heartbeat
- Merge branch 'main' of https://github.com/Chaoscontrol/opencarwings-app
- Added dos2unix to ensure LF on files Added redis fix for better debug logging Added extra debug logs

## v0.0.19-1 - 2026-02-12 [Addon Patch]

- Updated readme Fix for serving static files in production
- One more addon reference
- Updated all references from addon to app
- Refactor by removing VPS connection mode. Only local mode supported. DuckDNS highly recommended in the readme to handle SSL.
- Nginx added to handle https connection on local mode
- Cleaned logs Added TCU ports to HA config to listen in local mode Updated readme
- Added new option to choose public VPS or local port forwarding Updated readme with all new option and setup
- Fix car map requests by fixing API key with spaces Improve heartbeat logs to 1 per hour
- tcuserver service added Daphne TCP endpoint removed Persisten logs fixed Fix for upstream patches Fix for crash on missing API keys
- OCM and Iternio services added Readme updated Upstream compatibility patches
- Added periodic services to handle timeouts Updated frp config to toml
- Fix upstream sync to fetch latest
- Merge branch 'main' of https://github.com/Chaoscontrol/opencarwings-addon
- Upstream sync - v0.0.19
- Upstream sync - v0.0.18
- Upstream sync - v0.0.17
- Upstream sync - v0.0.16
- Upstream sync - v0.0.15
- Upstream sync - v0.0.14
- Upstream sync - v0.0.13
- Upstream sync - v0.0.12
- Upstream sync - v0.0.11
- Upstream sync - v0.0.10
- Upstream sync - v0.0.9
- Upstream sync - v0.0.8
- Bundled frpc to expose necessary ports via VPS
- Upstream sync - v0.0.7
- Bump addon version to v0.0.6-1
- Merge branch 'main' of https://github.com/Chaoscontrol/opencarwings-addon
- Removed all Tailscale implementation as it cannot expose custom TCP ports (55230)
- Upstream sync - v0.0.6
- Upstream sync - v0.0.5
- Upstream sync - v0.0.4
- Commented tailscale additions to debug. Working version without tailscale.
- Attempt 1 at integrating Tailscale for TCU port tunnel. Not starting.
- Bump addon version to v0.0.3-1
- Changed server to daphne, now it starts the TCU TCP 55230 port and it's listening
- Repo cleanup, removed s6-overlay
- Upstream sync - v0.0.3
- Merge branch 'main' of https://github.com/Chaoscontrol/opencarwings-addon
- Better versioning, splitting addon patch and upstream update
- Bump version to v0.0.2
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

## v0.0.19 - 2026-02-02 [Upstream Update]

Synced with latest upstream changes from opencarwings repository.

- Fix bug in identifier mismatch notifications (917842d)

## v0.0.18 - 2026-01-28 [Upstream Update]

Synced with latest upstream changes from opencarwings repository.

- Implement logic to authenticate without user&pass for QY8XXX models which don't have authentication. (85c043c)

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
