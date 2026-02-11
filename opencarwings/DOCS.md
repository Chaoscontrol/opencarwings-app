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
> **CGNAT Warning**: If your ISP uses CGNAT (you don't have a public IP), this app will not work. You can use the OCW public server instead. There is no tunnel service that works for the ports required by the car.

---

## Requirements

Before installing, ensure you have:

1. **A public IP address** (static or dynamic) from your ISP.
2. **The DuckDNS app (formerly Add-on)** (recommended) for both Dynamic DNS (DDNS) and valid SSL certificates.
3. **Router access** to configure port forwarding.

---

## Installation & Setup

### 1. Install the app

1. Go to **Settings → Apps → Apps Store → menu (⋮) → Repositories**.
2. Add: `https://github.com/Chaoscontrol/opencarwings-app`
3. Find **"OpenCarwings"** and click **Install**.

### 2. Configure the app

In the app **Configuration** tab, set:

| Option | Description | Default |
|--------|-------------|---------|
| `timezone` | Your local timezone (e.g., `Europe/Madrid`) | `UTC` |
| `log_level` | Detail of logs (`info`, `debug`, `trace`, etc.) | `info` |
| `trusted_domains` | **Required.** Your public domain (e.g., `["ocw.duckdns.org"]`) | `[]` |
| `ocm_api_key` | [OpenChargeMap](https://openchargemap.org/) API key (optional) | `""` |
| `iternio_api_key` | [Iternio/ABRP](https://www.iternio.com/) API key (optional) | `""` |

> [!CAUTION]
> **`trusted_domains` is mandatory.** Without it, you will get "CSRF Verification Failed" (403 Forbidden) errors on every form submission. Add your public domain exactly as you access it.

### 3. Configure Port Forwarding

On your **router**, forward these ports to your **Home Assistant IP**:

| Port | Protocol | Purpose |
|------|----------|---------|
| **55230** | TCP | TCU Direct Communication (Nissan protocol) |
| **8124** | TCP | HTTP — Car connection & browser redirect to HTTPS |
| **8125** | TCP | HTTPS — Encrypted Web UI |

### 4. Start the app

Click **Start** and check the **Log** tab. You should see:
```
Starting Nginx HTTPS proxy...
Starting OpenCarwings server with Daphne on port 8000...
Starting OpenCarwings TCU Socket Server...
```

### 5. Initial Web UI Setup

1. Open `https://your-domain.com:8125` in your browser.
2. You will see a **security warning** (self-signed certificate) — accept/proceed.
3. Create an admin account and add your vehicle via VIN.

### 6. Configure Your Car

Update your Nissan LEAF's **Navigation** and **TCU** settings:
- **Navi VFlash URL**: `http://yourdomain.com/WARCondelivbas/it-m_gw10/`
- **TCU Server URL**: `yourdomain.com`

> [!TIP]
> **SSL & Domain Setup (Recommended)**: For the best experience (valid SSL certificates and reliable connection), we strongly recommend using the **DuckDNS App (formerly Add-on)**. 
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
> *Note: You do **not** need to add the SSL certificate paths to your `configuration.yaml` http section like DuckDNS suggests if you only use them for this app. They're only for HA access.*

---

## Architecture

```
Internet → Router Port Forward → Home Assistant
                                      │
                          ┌───────────┴───────────┐
                          │                       │
                     Port 8124/8125          Port 55230
                      (Nginx Proxy)         (TCU Server)
                          │
                     Port 8000
                   (Daphne/Django)
                      │         │
                 PostgreSQL    Redis
```

- **Nginx** handles HTTP→HTTPS redirection for browsers while allowing the car to connect via plain HTTP.
- **Daphne** runs the Django application on internal port 8000.
- **TCU Server** listens on port 55230 for direct Nissan protocol communication.

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
