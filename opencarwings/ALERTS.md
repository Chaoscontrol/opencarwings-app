# OpenCarwings Alert Matrix (Upstream-First)

This document defines alert behavior using upstream `tcuserver.py` as the source of truth, then maps what this addon implements/overrides.

## Source of Truth

- Upstream file: `upstream-opencarwings/tculink/management/commands/tcuserver.py`
- Addon patch injector: `opencarwings/rootfs/etc/cont-init.d/05-patch-settings.sh`

## Canonical Alert Types

| Type | Meaning                       |
| :--- | :---------------------------- |
| 1    | Charge finished               |
| 2    | Charge start command executed |
| 3    | Cable reminder / unplugged    |
| 4    | A/C started                   |
| 5    | A/C stopped                   |
| 6    | TCU config received           |
| 7    | A/C finished / auto off       |
| 8    | Quick charge finished         |
| 9    | Battery heater on             |
| 10   | Battery heater off            |
| 97   | A/C error                     |
| 99   | System/auth/identity error    |

---

## Upstream Case Matrix

### Identity/Auth failures (`message_type` any non-config path)

| Condition                  | Upstream action |
| :------------------------- | :-------------- |
| TCU ID mismatch            | Alert type `99` |
| Navi ID mismatch           | Alert type `99` |
| ICCID mismatch             | Alert type `99` |
| Missing auth when required | Alert type `99` |
| Invalid auth when required | Alert type `99` |

### DATA packet cases (`message_type == 3`)

| `body_type`     | Key state(s)                | Upstream alert type | Notes                                  |
| :-------------- | :-------------------------- | :------------------ | :------------------------------------- |
| `cp_remind`     | N/A                         | `3`                 | Unplugged reminder                     |
| `ac_result`     | `resultstate == 0x40`       | `4`                 | A/C started                            |
| `ac_result`     | `resultstate == 0x20`       | `5`                 | A/C stopped                            |
| `ac_result`     | `resultstate == 192`        | `7`                 | A/C finished                           |
| `ac_result`     | any other `resultstate`     | `97`                | A/C error/fallback                     |
| `remote_stop`   | `alertstate in {4, 0x44}`   | `1`                 | Normal charge finished                 |
| `remote_stop`   | `alertstate == 8`           | `8`                 | Quick charge finished                  |
| `remote_stop`   | any other `alertstate`      | `7`                 | Treated as A/C finished fallback       |
| `charge_result` | default upstream behavior   | `2`                 | Upstream sets type `2` unconditionally |
| `battery_heat`  | `batt_heat_active == true`  | `9`                 | Heater on                              |
| `battery_heat`  | `batt_heat_active == false` | `10`                | Heater off                             |

### Config packet case (`message_type == 5`)

| Condition                      | Upstream action |
| :----------------------------- | :-------------- |
| `config_read` payload received | Alert type `6`  |

---

## Addon Extensions (No Alert-Type Override)

This addon extends upstream behavior in runtime patching without changing upstream `charge_result` alert typing:

1. Telemetry conflict detail (diagnostic only):

- If `charge_result` has `resultstate == 0` and `pluggedin == false`, addon keeps charge classification but logs conflict detail.
- This does not change alert type.

2. Additional summary logs:

- Addon emits extra tagged summaries prefixed with `[app]`.

3. `ac_result` state `16` interpretation (addon only):

- Upstream does not map `resultstate=16` explicitly and falls back to A/C error alert type.
- Addon summary log interprets observed `A/C Off when already off` packets as:
  - `A/C already off (no action needed)`
- Inference basis:
  - `resultstate == 16`
  - plus protocol/context signal (`pri_ac_stop_result == 1` or command type `4`).
- This is log-message interpretation only; upstream alert persistence behavior is preserved.

---

## `charge_result` Policy (Current Addon)

| Condition                                   | Alert type | Detail behavior                           |
| :------------------------------------------ | :--------- | :---------------------------------------- |
| any `resultstate`                           | `2`        | Logged as charge started                  |
| `resultstate == 0` and `pluggedin == false` | `2`        | Adds telemetry-conflict diagnostic detail |

This is aligned with upstream behavior.

---

## Coverage Map: Upstream vs Addon

Status meanings:

- `Implemented`: matches upstream
- `Overridden`: intentional divergence
- `Extended`: additive behavior without changing upstream classification
- `Missing`: upstream behavior not represented in addon patch logic

| Upstream case                                     | Addon status             | Anchor in `05-patch-settings.sh`                               | Action                                            |
| :------------------------------------------------ | :----------------------- | :------------------------------------------------------------- | :------------------------------------------------ |
| `cp_remind -> type 3`                             | Implemented              | `opencarwings/rootfs/etc/cont-init.d/05-patch-settings.sh:324` | Keep                                              |
| `ac_result` state mapping (`4/5/7/97`)            | Implemented              | `opencarwings/rootfs/etc/cont-init.d/05-patch-settings.sh:343` | Keep                                              |
| `remote_stop` state mapping (`1/8/7`)             | Implemented              | `opencarwings/rootfs/etc/cont-init.d/05-patch-settings.sh:349` | Keep                                              |
| `charge_result -> type 2` upstream default        | Implemented              | `opencarwings/rootfs/etc/cont-init.d/05-patch-settings.sh:303` | Keep                                              |
| `battery_heat -> type 9/10`                       | Implemented              | `opencarwings/rootfs/etc/cont-init.d/05-patch-settings.sh:324` | Keep                                              |
| `message_type == 5 -> type 6`                     | Implemented              | `opencarwings/rootfs/etc/cont-init.d/05-patch-settings.sh:324` | Keep                                              |
| Upstream identity/auth `99` alerts                | Implemented              | `opencarwings/rootfs/etc/cont-init.d/05-patch-settings.sh:324` | Keep                                              |
| Upstream notification text payloads               | Missing (not replicated) | N/A                                                            | Accept for now; no behavior break for alert types |
| Telemetry conflict detail (`state 0 + unplugged`) | Extended                 | `opencarwings/rootfs/etc/cont-init.d/05-patch-settings.sh:356` | Keep for diagnostics                              |
| `ac_result` state `16` no-op summary              | Extended                 | `opencarwings/rootfs/etc/cont-init.d/05-patch-settings.sh`     | Keep (addon interpretation only)                  |

---

## Observed Anomalies / Follow-Up Candidates (Documented Only)

These are intentionally documented only in this iteration. No behavior changes are introduced.

1. Permissive auth check in upstream:

- In `upstream-opencarwings/tculink/management/commands/tcuserver.py`, auth accepts if username matches **or** password hash matches.
- This is more permissive than typical username+password pair validation.

2. Sensitive data exposure risk in logs:

- Upstream logs include full `TCU Payload hex` and `Auth Data`.
- Those fields may expose credential material or sensitive identifiers.

3. Field disagreement in telemetry:

- Protocol fields (`resultstate`, `alertstate`) and interpreted booleans (`pluggedin`, `not_plugin_alert`) can disagree in real packets.
- Diagnostics should explicitly surface disagreement instead of assuming full consistency.

## Why UI Shows `Charge start ... 0,2`

This comes from upstream `charge_result` handling in `tcuserver.py`:

1. When `body_type == "charge_result"`, upstream creates `AlertHistory` with:

- `new_alert.type = 2` (charge start)
- `new_alert.additional_data = f"{req_body['resultstate']},{req_body['alertstate']}"`

2. The UI row `Charge start ... 0,2` means:

- first value (`0`) = `resultstate`
- second value (`2`) = `alertstate`

3. Important implication:

- Even when the car is unplugged, upstream may still emit `type=2` if the packet is `charge_result`.
- In other words, this UI line reflects upstream alert typing plus raw protocol tuple, not a definitive physical plug validation.

---

## Charge-Result App Message Policy

- Upstream alert typing remains unchanged:
  - `charge_result` creates alert type `2`.
- Addon final app message is hybrid-informative:
  - If unplugged indicators are present (`resultstate == 17` OR `not_plugin_alert == true` OR `pluggedin == false`):
    - `Charge command response: vehicle appears unplugged; charging may not start`
  - Otherwise:
    - `Charge command response received`
- Message always appends protocol/debug context:
  - `resultstate`, `alertstate`, `pluggedin`, `not_plugin_alert`, `charge_request_result`.

---

## Webhook for SMS Delivery Confirmation

Purpose:

- Optional standalone webhook endpoint to log inbound SMS delivery confirmations from Monogoto.

Endpoint:

- `POST /api/webhook/monogoto/sms-delivery/`

Token model:

- URL token query parameter is required when enabled:
  - fixed token: `?token=ocw`

Optional behavior:

- If webhook feature is not enabled, endpoint returns `204` silently.
- If enabled with invalid token, endpoint returns `403` silently.

Payload parsing:

- Supports both JSON object and JSON array payloads.
- Parsed payload is logged at debug level for traceability.

Car matching:

- ICCID-only matching:
  - webhook payload ICCID -> `Car.iccid`
- Monogoto ICCID tolerance:
  - if webhook ICCID differs by one trailing digit, prefix-based +/-1 digit matching is applied.
- If matched:
  - logs info line: `Monogoto webhook: SMS delivered`.
- If unmatched:
  - logs debug line with unknown ICCID.

Monogoto setup URL template:

- `https://ocw-ha.duckdns.org:8125/api/webhook/monogoto/sms-delivery/?token=ocw`

---

## Validation Scenarios

1. `charge_result` with `resultstate=17`:

- Expect alert type `2`.

2. `charge_result` with `resultstate=0` and `pluggedin=false`:

- Expect alert type `2`.
- Expect conflict detail in `[app]` line.

3. `ac_result` unknown state:

- Expect alert type `97`.

4. `ac_result` with `resultstate=16` during A/C Off command:

- Addon summary log should report: `A/C already off (no action needed)`.
- This is treated as informational summary output (not error-level summary).

5. `remote_stop` with `alertstate=8`:

- Expect alert type `8`.

6. Logging parity:

- Confirm both upstream-origin `logger.info(...)` lines tagged `[tcuserver]` and addon-generated lines tagged `[app]` appear in addon logs.
