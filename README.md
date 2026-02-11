# OpenCarwings Home Assistant Add-on

Home Assistant add-on for [OpenCarwings](https://github.com/developerfromjokela/opencarwings) - a Nissan CARWINGS-compatible server for bringing back Nissan TCUs and online services.

**⚠️ SUPER ALPHA WARNING**: This add-on is experimental software built with AI and lots of reviews. I created this for my own use and am sharing it "as-is". I don't promise long-term maintenance or prompt bug fixing, but I'll do my best to keep it working as long as I use it myself!

## What it does

This add-on packages the upstream OpenCarwings server to run on Home Assistant OS/Supervisor. It enables:

- **Remote A/C & Climate control** for compatible Nissan LEAF models.
- **Charging Management** and battery status monitoring.
- **Trip Data** and efficiency statistics.
- **Direct TCU Communication** via raw TCP protocol.
- **Built-in Infrastructure**: Includes PostgreSQL and Redis (no external setup required).

---

## Connectivity & Privacy (IMPORTANT)

To allow your car to reach this server while you are away, the server must be accessible from the internet. This add-on provides two ways to achieve this:

### Option A: Public VPS (Default / Easy)
This mode uses a built-in **FRP (Fast Reverse Proxy)** client to tunnel your traffic through a shared public server. 
- **Pros**: No router configuration needed; works behind CGNAT.
- **Cons**: **Lower Privacy**. Your car's data flows through a third-party VPS. While the protocol is binary, the VPS owner could theoretically intercept or inject data.

Honestly there's not much difference of using this mode and the actual OCW public server. The only difference is that you're using your own server instead of the public one, but I did not find a way to make it fully private. 
- **Setup**: Simply leave `connection_mode` as `public_vps`.

### Option B: Local Port Forwarding (Private / Recommended)
This mode is completely private. You are responsible for making your Home Assistant instance reachable.
- **Pros**: **Maximum Privacy**. Data goes directly from your car to your home.
- **Cons**: Requires opening ports on your router; might not work with some ISPs (CGNAT).
- **Setup**:
  1. Set `connection_mode: local` in configuration and click **Save**.
  2. Map the following ports on your router to your **Home Assistant IP**:
     - **TCP 55230** (TCU Direct Communication)
     - **TCP 8124** (Car connection)
     - **TCP 8125** (encrypted Web UI via HTTPS)
  3. Ensure you have a stable public IP or a Dynamic DNS (DuckDNS, etc.) service running.

> [!IMPORTANT]
> **Enabling HTTPS (Recommended)**: 
> The add-on includes an internal Nginx proxy for **Local Mode**.
> 1. **Best Practice**: Copy your SSL certificates (`fullchain.pem` and `privkey.pem`) to `/ssl/` for a secure, green-padlock experience.
> 2. **Fallback**: If no certificates are found, the add-on will **automatically generate a Self-Signed Certificate**. This ensures traffic is still encrypted, but your browser will show a "Not Secure" warning that you must bypass.
>
> **Behavior**:
> - Browsers on **Port 8124** (HTTP) are redirected to **8125** (HTTPS).
> - The Car connects on **Port 8124** (HTTP) without redirection.
>
> [!TIP]
> **A Note on Tailscale/Cloudflare**: Currently, Tailscale Funnel and Cloudflare Tunnels do not support the raw, non-encrypted TCP protocol required by the Nissan TCU (port 55230). If Tailscale adds raw TCP support in the future, it will be the preferred secure alternative.

---

## Installation & Setup

1. **Add Repository**:
   - Settings → Add-ons → Add-on Store → menu (⋮) → Repositories.
   - Add: `https://github.com/Chaoscontrol/opencarwings-addon`.
2. **Install**: Find "OpenCarwings" and click Install.
3. **Configure**:
    - **`trusted_domains`**: Add your public domain here (e.g., `ocw-ha.duckdns.org`). This is **mandatory if using HTTPS/SSL** or a secure reverse proxy to prevent "CSRF Verification Failed" errors. It may be optional for simple unencrypted HTTP access.
    - **`connection_mode`**: Choose `public_vps` (default) or `local`.
4. **Start**: Start the add-on and check the logs.
5. **Initial UI Setup**:
   - Access the Web UI at `http://your-ha-ip:8124`.
   - Create an admin account and add your vehicle via VIN.
6. **Car Configuration**:
   - Update your Nissan LEAF's Navigation and TCU settings to point to your public domain/IP.
   - For `public_vps` mode, use the domain provided in the logs. For the Navi VFlash URL use: `http://ocw-ha.duckdns.org/WARCondelivbas/it-m_gw10/`. For the TCU URL use: `ocw-ha.duckdns.org`.
   - For `local` mode, use your own DDNS domain and the same paths. Navi URL: `http://yourdomain.com/WARCondelivbas/it-m_gw10/`. TCU URL: `yourdomain.com`.

---

## Configuration Reference

| Option | Description | Default |
|--------|-------------|---------|
| `timezone` | Your local timezone (e.g., `Europe/Madrid`) | `UTC` |
| `log_level` | Detail of logs (`info`, `debug`, `trace`, etc.) | `info` |
| `connection_mode` | `public_vps` (Relay) or `local` (Direct) | `public_vps` |
| `trusted_domains` | List of domains allowed to access the Web UI | `[]` |
| `ocm_api_key` | [OpenChargeMap](https://openchargemap.org/) API Key (Optional) | `""` |
| `iternio_api_key` | [Iternio/ABRP](https://www.iternio.com/) API Key (Optional) | `""` |

---

## Versioning & Updates

This add-on tracks the [upstream OpenCarwings](https://github.com/developerfromjokela/opencarwings) repository.
- Our build process clones the latest upstream code whenever the add-on is rebuilt.
- When new code is committed upstream, the add-on version number is bumped automatically.
- Your Home Assistant will notify you of an "Update Available". You can choose when to update to pull in the latest upstream changes.

---

## Credits & Links

- **Main Project**: [developerfromjokela/opencarwings](https://github.com/developerfromjokela/opencarwings)
- **Special Thanks**: Huge thanks to `@developerfromjokela` for his incredible work reversing the Nissan protocol and keeping these cars online.
- **Nissan TCU Protocol**: [nissan-leaf-tcu](https://github.com/developerfromjokela/nissan-leaf-tcu)
- [**Guide to Bringing Your Navigator Back Online**](https://opencarwings.viaaq.eu/static/navi_guide.html)
- [**Guide to Bringing Your TCU Back Online**](https://opencarwings.viaaq.eu/static/tcu_guide.html)
- [**OCW Android app**](https://github.com/developerfromjokela/opencarwings-android)
- **Issues**: Report add-on specific issues [on GitHub](https://github.com/Chaoscontrol/opencarwings-addon/issues).
