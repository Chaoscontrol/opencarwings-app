# OpenCarwings Home Assistant App

Home Assistant app for [OpenCarwings](https://github.com/developerfromjokela/opencarwings) — a Nissan CARWINGS-compatible server for bringing back Nissan TCUs and online services.

**⚠️ SUPER ALPHA WARNING**: This app is experimental software built with AI and lots of reviews. I created this for my own use and am sharing it "as-is".

## What it does

- Remote A/C and climate control for compatible Nissan LEAF models.
- Charging management and battery status monitoring.
- Trip data and efficiency statistics.
- Direct TCU communication using Nissan raw TCP protocol.
- Built-in PostgreSQL and Redis (no external setup required).

## Connection Modes

OpenCarwings now supports two connection modes for TCU connectivity.

| Mode | Best for | How TCU reaches OCW | Privacy |
| --- | --- | --- | --- |
| `local` (default) | Users with public IP + router control | Direct port-forwarded TCP `55230` to Home Assistant | Highest |
| `vps_frp` | Users behind CGNAT | TCP `55230` terminates at your VPS and is relayed by FRP to Home Assistant | Depends on VPS trust |

Important scope note:

- FRP mode only tunnels the TCU raw TCP channel (`55230`).
- UI/API/webhook traffic (`8124`/`8125`) is still handled by your existing HTTP setup (direct forwarding, reverse proxy, Cloudflare, etc.).

## Requirements

### Common

1. Home Assistant OS/Supervisor with this app installed.
2. Public domain(s):
- `http_domain` for UI/API/webhook.
- `tcu_domain` for TCU endpoint.
3. Car-side configuration access (Navi/TCU URLs).

### Additional for `local`

1. Router port forwarding for TCP `55230` to Home Assistant.
2. If needed, forwarding/proxying for `8124`/`8125`.
3. DDNS (DuckDNS or equivalent) when ISP IP changes.

### Additional for `vps_frp`

1. A VPS with public IP.
2. FRPS running on VPS.
3. VPS firewall opened for:
- TCP `7000` (FRP control)
- TCP `55230` (public TCU endpoint)
4. `tcu_domain` must resolve to your VPS public IP.

## Install

1. Home Assistant: **Settings → Apps → Apps Store → Repositories**.
2. Add `https://github.com/Chaoscontrol/opencarwings-app`.
3. Install **OpenCarwings**.

## App Configuration

| Option | Description | Default |
| --- | --- | --- |
| `timezone` | Local timezone | `UTC` |
| `log_level` | Log verbosity | `info` |
| `connection_mode` | `local` or `vps_frp` | `local` |
| `http_domain` | Public domain for UI/API/webhook | `""` |
| `tcu_domain` | Public domain for TCU raw TCP `55230` | `""` |
| `frp_server_addr` | VPS IP/hostname running FRPS (required in `vps_frp`) | `""` |
| `frp_server_port` | FRPS control port (required in `vps_frp`) | `7000` |
| `frp_auth_token` | FRP auth token (required in `vps_frp`) | `""` |
| `ocm_api_key` | Optional OpenChargeMap API key | `""` |
| `iternio_api_key` | Optional Iternio API key | `""` |
| `monogoto_sms_delivery_webhook_enabled` | Enable webhook endpoint/logging | `false` |

## Setup: Local Mode (`connection_mode: local`)

1. Keep `connection_mode: local`.
2. Forward TCP `55230` on router to Home Assistant.
3. Set `tcu_domain` to public hostname resolving to your home IP.
4. Configure HTTP exposure for UI/API as you already do (e.g. `8124` origin + optional `8125`).

## Setup: VPS + FRP Mode (`connection_mode: vps_frp`)

### 1. Install FRPS on VPS

Example using FRP v0.64.0:

```bash
cd /opt
curl -fsSL -o frp.tar.gz https://github.com/fatedier/frp/releases/download/v0.64.0/frp_0.64.0_linux_amd64.tar.gz
tar -xzf frp.tar.gz
sudo mv frp_0.64.0_linux_amd64/frps /usr/local/bin/frps
sudo chmod +x /usr/local/bin/frps
```

### 2. Create `/etc/frp/frps.toml`

```toml
bindPort = 7000

auth.method = "token"
auth.token = "replace-with-strong-random-token"

[[proxies]]
name = "ocw_tcu_55230"
type = "tcp"
remotePort = 55230
```

### 3. Create systemd service on VPS

`/etc/systemd/system/frps.service`

```ini
[Unit]
Description=FRP Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/frps -c /etc/frp/frps.toml
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```

Enable/start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now frps
sudo systemctl status frps
```

### 4. Open VPS firewall

Allow inbound TCP `7000` and TCP `55230`.

### 5. Set DNS

Point `tcu_domain` to VPS public IP (A/AAAA record).

### 6. Configure addon

```yaml
connection_mode: vps_frp
http_domain: ocw.example.com
tcu_domain: tcu.example.com
frp_server_addr: your-vps.example.com
frp_server_port: 7000
frp_auth_token: replace-with-strong-random-token
```

### 7. Verify in logs

On app start, look for FRP client startup log for VPS mode and verify FRPS shows connected client.

## Car Configuration

- Navi VFlash URL: `http://<http_domain>/WARCondelivbas/it-m_gw10/`
- TCU Server URL: `<tcu_domain>`

`/WARCondelivbas/it-m_gw10/` must be reachable over your HTTP path.

## Ports

| Port | Protocol | Purpose |
| --- | --- | --- |
| `55230` | TCP | TCU raw protocol (direct in `local`, relayed by FRP in `vps_frp`) |
| `8124` | TCP | HTTP origin for car endpoint + UI + HA API |
| `8125` | TCP | Optional direct HTTPS UI/API |

## Monogoto SMS Delivery Webhook

If `monogoto_sms_delivery_webhook_enabled: true`, endpoint is:

- `POST /api/webhook/monogoto/sms-delivery/?token=ocw`

Examples:

- Reverse proxy: `https://<http_domain>/api/webhook/monogoto/sms-delivery/?token=ocw`
- Direct HTTPS: `https://<http_domain>:8125/api/webhook/monogoto/sms-delivery/?token=ocw`

## Credits & Links

- Main Project: [developerfromjokela/opencarwings](https://github.com/developerfromjokela/opencarwings)
- Nissan TCU Protocol: [nissan-leaf-tcu](https://github.com/developerfromjokela/nissan-leaf-tcu)
- Android App: [opencarwings-android](https://github.com/developerfromjokela/opencarwings-android)
- Issues: [Chaoscontrol/opencarwings-app/issues](https://github.com/Chaoscontrol/opencarwings-app/issues)
