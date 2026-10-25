# July to October 2026 upstream catch-up

The previous app version, `0.0.24-3`, uses upstream commit
`797e6dc0f707169d521841ce400b19bad027e7bd` (13 July 2026), also tagged `1.0`.
The `0.0.25` candidate uses `bfe2ad23a5e973c0a5313b711af4852394aea9a0`
(24 October 2026), which reports upstream application version `1.1`.
There are 238 upstream commits and 31 new database migrations, `0046`–`0076`.

[Full comparison and commit history](https://github.com/developerfromjokela/opencarwings/compare/797e6dc0f707169d521841ce400b19bad027e7bd...bfe2ad23a5e973c0a5313b711af4852394aea9a0)

## Features added since the installed pin

| Area | New capability | Applicability |
| --- | --- | --- |
| Newer TCUs | FICOSA protocol/coordinator, configuration UI, service provisioning, SIM settings and probe-data configuration | Compatible 2016–2017 30 kWh LEAF and 2018–2020 ZE1 vehicles; upstream marks some protocol/configuration work experimental |
| Remote controls | Door lock/unlock, horn/lights and A/C temperature/duration controls | Supported FICOSA vehicles; these commands do not become available on an older Continental TCU simply by updating the server |
| Vehicle health | Health reports, tyre-pressure and diagnostic-code data, cabin temperature, burglar/tow-related configuration | Depends on TCU/model support; upstream still lists remote engine start as unimplemented |
| Charging/status | Plug power availability, interrupted-charging detection, battery-lease status/unblock command, extra gear data and an A/C assumed-off timeout | Many additions are FICOSA-specific |
| Accounts | Optional authenticator-based 2FA with recovery codes, command PINs and failed-PIN protection | Account-wide; the sensitive-command PIN list excludes the existing basic refresh, charge and A/C commands |
| Ownership | Transfer a car to another account using an emailed claim link, expiry and a history-retention choice | Needs working email delivery and a correct public site URL; do not use transfers as an upgrade test on real data |
| SMS | GatewayAPI, seven.io and viaaq mobile providers; USB-modem gateway/PDU handling and binary-message capability checks | Choose a provider that supports the message format required by the vehicle |
| Trips/navigation | FICOSA V2 probe fields, trip TPMS information, DOT viewer, improved location-link handling and coordinate copying, and custom data-channel icons | Individual data fields depend on what the car reports |
| Documentation | New built-in documentation platform, updated setup guides and translations | General |

Upstream also fixed periodic refresh/timers, command acknowledgements and timeouts,
JDM short-VIN handling, trip parsing, pressure/coordinate units, charging-station
updates, token handling, route-planner validation and webhook/map URL sanitisation.
The non-working FICOSA 80% charge option was removed. Django requirements moved
from 5.1 to 6.1, with additional authentication, QR-code and protocol dependencies.

[Upstream supported vehicles and feature checklist](https://github.com/developerfromjokela/opencarwings/blob/bfe2ad23a5e973c0a5313b711af4852394aea9a0/README.md)

## App compatibility changes

- Remove the old CRM warning-counter injection: upstream now separates file
  decoding and data-block parsing, and the old injection creates an uninitialised
  local variable in the second function.
- Update Iternio missing-key protection for the new request limit and reject
  unexpected patch targets instead of claiming success.
- Recognise upstream's new `tcuserver` logger name.
- Explicitly disable the Redis channel connection's socket read timeout. The
  redis-py 8 default of five seconds races Channels' blocking receive and caused
  the browser notification connection to fail every five seconds. The previous
  app override had discarded upstream's explicit timeout. See
  [channels_redis issue 422](https://github.com/django/channels_redis/issues/422).
- Configure WhiteNoise through Django's `STORAGES` setting, then collect static
  files after the final runtime settings have been applied.
- Compile translations during the image build and validate patched Python before
  starting application services.
- Add expired-transfer cleanup to the periodic scheduler.
- Preserve the original HTTP Host port through Nginx so alternate dev ports work
  with Django's same-origin CSRF checks.

## Local validation before publication

Use the repository snapshot deployment helper; do not edit `/addons` by hand.
The first validation runs with `periodic_tasks_enabled: false`, local connection
mode, no FRP token, and host ports `18124`, `18125`, and `55231`. This pauses
scheduled commands and cleanup; it does not block a command explicitly submitted
through the UI or API. Do not issue real vehicle commands during isolated tests.

Require successful migrations through `0076`, patched-source regression tests,
login/static/API checks and a second clean start. Existing vehicles, history and
API identities must survive. A real TCU/FRP test requires an exclusive cutover;
isolated host ports cannot redirect the car's existing public endpoint.

Keep the pre-upgrade dev backup. Reverting source alone cannot reverse database
migrations; a data rollback uses the saved dev backup after the app is stopped.
Publish to GitHub only after the dev validation and intended vehicle tests pass.

## Validation completed on 25 October

- Supervisor built and installed the candidate in `local_opencarwings-dev`.
- The complete deployed source matches the repository by SHA256, file type and
  mode, with only the documented dev name/slug transformation.
- Existing PostgreSQL 17 data migrated successfully through `0076`.
- Patched Python, CRM regression cases, API-key guards, provider-error handling,
  storage configuration and repeated patch application passed.
- HTTP and HTTPS home pages returned `200` and reported `1.1 (bfe2ad2)`.
- CSS returned `200` with gzip compression; the alternate-port sign-in POST
  passed CSRF validation using deliberately invalid test credentials.
- The existing HA integration API identity returned `200`: one Continental TCU
  vehicle and its EV data were readable. After restart, alerts returned `200`
  with 25 records; the location-history endpoint returned `200` with no records.
- The authenticated notification websocket upgraded with `101` and acknowledged
  listening. This initial short check missed the later idle-time failure; the
  dedicated sustained-idle regression replaces handshake-only verification.
  Credentials are sent in a header rather than a URL.
- After correcting the Redis timeout, an authenticated websocket survived 45
  idle seconds, answered a subsequent ping and closed cleanly. The matching
  Nginx request lasted 45 seconds; the new runtime logs contained no Redis read
  timeouts or application exceptions. The authenticated car API still returned
  `200`. CI now includes a real Redis idle-receive and group-delivery regression.
- A second start completed with no pending migrations, successful Django checks
  and static collection, and the disabled-periodic-tasks message.
- Production remains running `0.0.24-3` on its original ports and FRP settings.

The dev HTTPS listener uses its existing self-signed certificate. Startup also
prints Supervisor metadata permission warnings from the base-image startup;
the application has no Supervisor API permission and these did not prevent any
of the checks above. No extra API permission was granted.

The owner subsequently confirmed the dev app works after the notification fix.
Individual new hardware-specific features and a full upstream Django test-suite
run remain unverified by the automated checks.
The dev database is its existing snapshot, so these read checks do not establish
that its history is as current as production. The automatic main-tracking release
workflow is prepared with independent app versions and a pinned first release;
publication and production installation follow the GitHub build gate.
