# OpenCarwings Home Assistant App

Home Assistant app for [OpenCarwings](https://github.com/developerfromjokela/opencarwings) — a Nissan CARWINGS-compatible server for bringing back Nissan TCUs and online services.

**⚠️ SUPER ALPHA WARNING**: This app is experimental software built with AI and lots of reviews. I created this for my own use and am sharing it "as-is". I don't promise long-term maintenance or prompt bug fixing, but I'll do my best to keep it working as long as I use it myself!

## What it does

This app packages the upstream OpenCarwings server to run on Home Assistant OS/Supervisor. It enables:

- **Remote A/C & Climate control** for compatible Nissan LEAF models.
- **Charging Management** and battery status monitoring.
- **Trip Data** and efficiency statistics.
- **Direct TCU Communication** via raw TCP protocol.
- **Built-in Infrastructure**: Includes PostgreSQL and Redis (no external setup required).

---

## How It Works

Your car's TCU (Telematics Control Unit) needs to reach this server from the internet. This app runs locally on your Home Assistant and you expose it through your router via **port forwarding**.

> [!IMPORTANT]
> **Privacy**: Your data goes directly from your car to your home. No third-party servers involved.

> [!NOTE]
> **CGNAT Warning**: If your ISP uses CGNAT (you don't have a public IP), this app will not work. You can use the OCW public server instead. There is no tunnel service that allows raw TCP for the ports required by the car. An alternative is using a VPS to forward that data port, but that requires some more complex setup.

---

## Requirements

Before installing, ensure you have:

1. **A public IP address** (static or dynamic) from your ISP.
2. **The DuckDNS app (formerly Add-on)** (recommended) for Dynamic DNS (DDNS) and forwarding TCU raw TCP traffic.
3. **Router access** to configure port forwarding for (at least) port 55230.
4. To access the UI or the API, you can either port forward those ports as well just like 55230, or you can use Cloudflare (what I do) as tunnel for them, which will handle edge SSL certificates as well. They only need HTTP traffic, so Cloudflare or any other tunnel works for them.

---

## Installation & Setup

### 1. Install the app

1. Go to **Settings → Apps → Apps Store → menu (⋮) → Repositories**.
2. Add: `https://github.com/Chaoscontrol/opencarwings-app`
3. Find **"OpenCarwings"** and click **Install**.

### 2. Configure the app

In the app **Configuration** tab, set:

| Option                                  | Description                                                                                           | Default |
| --------------------------------------- | ----------------------------------------------------------------------------------------------------- | ------- |
| `timezone`                              | Your local timezone (e.g., `Europe/Madrid`)                                                           | `UTC`   |
| `log_level`                             | Detail of logs (`info`, `debug`, `trace`, etc.)                                                       | `info`  |
| `trusted_domains`                       | **Required.** Your public domain (e.g., `["ocw.duckdns.org"]`)                                        | `[]`    |
| `ocm_api_key`                           | [OpenChargeMap](https://openchargemap.org/) API key (optional for updating stations from the navi)    | `""`    |
| `iternio_api_key`                       | [Iternio/ABRP](https://www.iternio.com/) API key (paid, optional for planning routes in the car navi) | `""`    |
| `monogoto_sms_delivery_webhook_enabled` | Enable Monogoto SMS delivery confirmation webhook endpoint/logging                                    | `false` |

> [!CAUTION]
> **`trusted_domains` is mandatory.** It now controls both Django CSRF trust and the Nginx host allowlist.
>
> - Add every public hostname that points to this add-on.
> - Requests using hosts not in `trusted_domains` are dropped at Nginx.
> - If `trusted_domains` is empty, Nginx fails closed and rejects all requests on `8124` and `8125`.

### 3. Configure Port Forwarding

On your **router**, forward these ports to your **Home Assistant IP**:

| Port      | Protocol | Purpose                                                        |
| --------- | -------- | -------------------------------------------------------------- |
| **55230** | TCP      | TCU Direct Communication (Nissan protocol)                     |
| **8124**  | TCP      | HTTP origin for car endpoint + browser UI + Home Assistant API |
| **8125**  | TCP      | Optional direct HTTPS access to browser UI + API               |

### 3.5 Domain and URL setup (simple mode, recommended)

Use one public domain for browser + HA API through your reverse proxy/tunnel (ie Cloudflare):

- Public domain: `ocw.example.com`
- Proxy/Tunnel origin: `http://<HA_IP>:8124`

You will also need a second domain for car TCU flows. Add that too.  
Every hostname that reaches OCW must be in `trusted_domains`.

Example:

```yaml
trusted_domains:
  - ocw.example.com
  - ocw-tcu.duckdns.org
```

### 3.6 Why HTTPS still works if origin uses HTTP `8124`

For the recommended setup:

- `8125` is completely optional.
- The only tunnel/proxy origin you need is `http://<HA_IP>:8124`.
- Use your public domain over HTTPS for browser and HA API.
- The add-on handles routing for browser, API, and car endpoint behind port `8124`.

> [!IMPORTANT]
> URLs with or without explicit ports depend on your external routing:
>
> - **Cloudflare/reverse proxy mode** (proxy terminates HTTPS): usually use URLs **without** `:8125`.
> - **Direct DuckDNS/port-forward mode** (you expose OCW directly): usually use `:8125` for HTTPS URLs.

### 4. Start the app

Click **Start** and check the **Log** tab. You should see:

```
Starting Nginx HTTPS proxy...
Starting OpenCarwings server with Daphne on port 8000...
Starting OpenCarwings TCU Socket Server...
```

### 5. Initial Web UI Setup

1. Open `https://your-domain.com` in your browser (or `https://your-domain.com:8125` for direct access without a proxy/tunnel).
2. You will see a **security warning** (if using self-signed certificate) — accept/proceed.
3. Create an admin account and add your vehicle via VIN.

### 6. For (my own) Home Assistant Integration

- Use your public HTTPS URL:
  - `https://your-domain.com`
- Point your reverse proxy/tunnel origin to `http://<HA_IP>:8124`.
- API auth is preserved because `/api/*` is served directly on `8124` (no redirect hop).

### 7. Configure Your Car

Update your Nissan LEAF's **Navigation** and **TCU** settings:

- **Navi VFlash URL**: `http://your-domain.com/WARCondelivbas/it-m_gw10/` (notice HTTP!)
- **TCU Server URL**: `yoursubdomain.duckdns.org`

> [!NOTE]
> The Navi VFlash URL must be reachable over HTTP on port `8124` and must include the exact path `/WARCondelivbas/it-m_gw10/`.

> [!TIP]
> **SSL & Domain Setup (Recommended)**: For the best experience (valid SSL certificates and reliable connection), we strongly recommend using the **DuckDNS App (formerly Add-on)**.
>
> - It handles your public domain (DDNS).
> - It automatically manages Let's Encrypt SSL certificates.
> - **Why DuckDNS?** Even if you use Tailscale or Cloudflare Tunnels for remote HA access, they **cannot** handle as of yet the raw TCP traffic required by the car (port 55230). DuckDNS combined with port forwarding is the only way for the car to connect.
>
> **Example DuckDNS App (formerly Add-on) Configuration**:

> ```yaml
> domains:
>   - [yoursubdomain].duckdns.org
> token: YOUR_TOKEN_HERE
> aliases: []
> lets_encrypt:
>   accept_terms: true
>   algo: secp384r1
>   certfile: fullchain.pem
>   keyfile: privkey.pem
> seconds: 300
> ```
>
> _Note: You do **not** need to add the SSL certificate paths to your `configuration.yaml` http section like DuckDNS suggests if you only use them for this app. They're only for HA access._

---

## Architecture

```
Internet → Router Port Forward → Home Assistant
                                      │
                          ┌───────────┴───────────┐
                          │                       │
                     Port 8124/8125          Port 55230
                 (Nginx: car + UI/API)      (TCU Server)
                          │
                     Port 8000
                   (Daphne/Django)
                      │         │
                 PostgreSQL    Redis
```

- **Nginx** enforces strict port roles:
  - `8124`: single-domain compatible HTTP origin for car + UI + HA API
  - `8125`: optional direct HTTPS access for UI/API
- **Host allowlist** comes from `trusted_domains`; unknown hosts are dropped.
- **Daphne** runs the Django application on internal port 8000.
- **TCU Server** listens on port 55230 for direct Nissan protocol communication.

---

## Monogoto SMS Delivery Webhook

If `monogoto_sms_delivery_webhook_enabled: true`, the app exposes:

- `POST /api/webhook/monogoto/sms-delivery/?token=ocw`
- Cloudflare/reverse proxy example: `https://your-domain.com/api/webhook/monogoto/sms-delivery/?token=ocw`
- Direct DuckDNS/port-forward example: `https://your-domain.com:8125/api/webhook/monogoto/sms-delivery/?token=ocw`

Behavior:

- Logs parsed webhook payloads at debug level.
- Accepts both JSON object and JSON array payloads.
- Matches car by ICCID (with tolerance for Monogoto one-digit-short ICCID).
- Logs confirmation line:
  - `[app] Monogoto webhook: SMS delivered`

Startup convenience:

- On startup, the app logs copy-ready webhook URL(s) using `trusted_domains`.

---

## Versioning & Updates

This app tracks the [upstream OpenCarwings](https://github.com/developerfromjokela/opencarwings) repository.

- Our build process clones the latest upstream code whenever the app is rebuilt.
- When new code is committed upstream, the app version number is bumped automatically.
- Your Home Assistant will notify you of an "Update Available". You can choose when to update to pull in the latest upstream changes.

---

## Credits & Links

- **Main Project**: [developerfromjokela/opencarwings](https://github.com/developerfromjokela/opencarwings)
- **Special Thanks**: Huge thanks to `@developerfromjokela` for his incredible work reversing the Nissan protocol and keeping these cars online.
- **Nissan TCU Protocol**: [nissan-leaf-tcu](https://github.com/developerfromjokela/nissan-leaf-tcu)
- [**Guide to Bringing Your Navigator Back Online**](https://opencarwings.viaaq.eu/static/navi_guide.html)
- [**Guide to Bringing Your TCU Back Online**](https://opencarwings.viaaq.eu/static/tcu_guide.html)
- [**OCW Android app**](https://github.com/developerfromjokela/opencarwings-android)
- **Issues**: Report app specific issues [on GitHub](https://github.com/Chaoscontrol/opencarwings-app/issues).
