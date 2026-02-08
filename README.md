# OpenCarwings Home Assistant Add-on

Home Assistant add-on for [OpenCarwings](https://github.com/developerfromjokela/opencarwings) - a Nissan CARWINGS-compatible server for bringing back Nissan TCUs and online services.

**⚠️ SUPER ALPHA WARNING**: This is one of my first add-ons ever created, and it was fully vibe-coded as I'm not a dev. I just did this for myself, but I think it can be useful for others, so I'm glad to share it. I don't promise to maintain it long term, but I'll do my best as long as I keep my interest in it. Same for bug fixing etc.

I haven't even tested the update process yet from upstream changes. But once it's working, it will update ANY commits done daily. No testing, no alerts. So considering this your warning.

## What it does

This add-on packages the upstream OpenCarwings server so you can run it directly on Home Assistant OS/Supervisor, making it full private and own all the information yourself. It provides:

- Remote A/C control for Nissan LEAF
- Charging management
- Trip data and efficiency stats
- TCU (Telematics Control Unit) communication
- Built-in PostgreSQL and Redis databases (no external setup needed)

## Quick Setup

### 1. Add Repository

In Home Assistant:

- Settings → Add-ons → Add-on Store → menu (⋮) → Repositories
- Add: `https://github.com/Chaoscontrol/opencarwings-addon`
- Find "OpenCarwings" and click Install

### 2. Configure Trusted Domains

**IMPORTANT**: You need a public domain for remote car access. Configure trusted domains in add-on options:

```yaml
trusted_domains:
  - "yourdomain.com" # Adding a first level domain automatically includes all subdomains
```

This is necessary because your car needs to reach the server remotely for TCU communication.

### 3. Set Up Port Forwarding/Tunnels

You need to expose these ports publicly so your car can connect:

- **8124** (Web UI) - Forward to your HA IP
- **55230** (TCU TCP Server) - Forward to your HA IP

Use port forwarding on your router, or services like Cloudflare Tunnel (my recommendation), ngrok, etc.

Example:

- ocw.mydomain.com -> http://homeassistant:8124 (for WebUI)
- ocw-tcu.mydomain.com -> tcp://homeassistant:55230 (for TCU communication. Notice the TCP!)

### 4. Configure Your Car

In your Nissan LEAF's navigation system and TCU settings, use your public domain/IP as the CARWINGS server URL.

From the previous example: ocw-tcu.mydomain.com

## Configuration Options

| `timezone`        | Your timezone                                  | `UTC`   |
| `log_level`       | Logging level                                  | `info`  |
| `trusted_domains` | Allowed domains (include wildcards)            | `[]`    |
| `ocm_api_key`     | OpenChargeMap API Key (Optional)               | `""`    |
| `iternio_api_key` | Iternio (ABRP) API Key (Optional/Paid)         | `""`    |

### External API Keys (Optional)

When updating charging stations from the car, we use external services. These are **optional**. You'll need to create and add your own keys for these to work.

- **OpenChargeMap (`ocm_api_key`)**: Used for the primary charging station database. If provided, your car's map will show nearby chargers. You can get a free key [here](https://openchargemap.org/site/develop/api).
- **Iternio (`iternio_api_key`)**: Provided by the creators of *A Better Routeplanner (ABRP)*. This API is used for **Real-time Status** (is a charger busy?) and some "Near Me" search features. Note that Iternio is a **paid service** for commercial/heavy use.
- **If left empty**: The add-on will gracefully skip these updates. Your car will simply not show external chargers or their live status, but the server will remain stable.

## Usage

1. Start the add-on
2. Access WebUI in http://homeassistant:8124
3. Create an admin account
4. Add your Nissan vehicle using VIN and TCU details
5. Configure SMS gateway if needed for TCU wake-up
6. Your car should now connect remotely!

## Ports Used

- **8124**: Web interface (HTTP)
- **8125**: Web interface (HTTPS) - configure SSL separately
- **55230**: TCU communication (TCP)

## Links

- **Upstream Project**: [developerfromjokela/opencarwings](https://github.com/developerfromjokela/opencarwings)
- **Upstream Website and Public Server**: [opencarwings.viaaq.eu](https://opencarwings.viaaq.eu)
- **Nissan TCU Protocol**: [nissan-leaf-tcu](https://github.com/developerfromjokela/nissan-leaf-tcu)
- [**Guide to Bringing Your Navigator Back Online**](https://opencarwings.viaaq.eu/static/navi_guide.html)
- [**Guide to Bringing Your TCU Back Online**](https://opencarwings.viaaq.eu/static/tcu_guide.html)
- [**OCW Android app**](https://github.com/developerfromjokela/opencarwings-android)

## Support

This is experimental software. Use at your own risk. Check the logs if something doesn't work.

- **Issues**: [GitHub Issues](https://github.com/Chaoscontrol/opencarwings-addon/issues)

## Thanks

This is just the addon for this amazing work that @developerfromjokela has done with project.
My heartfelt thanks to allow all of us oldie Leaf users to make it even a better little EV than it already is.

Full credits to him for OpenCarwings, related projects and guides created to help us navigate this not so straightforward re-connection process.
