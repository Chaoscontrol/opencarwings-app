#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
source /etc/cont-init.d/00-log-fix.sh

bashio::log.info "Running runtime patch for Django settings..."

SETTINGS_FILE="/opt/opencarwings/carwings/settings.py"

# --- Patch 1: Inject CSRF_TRUSTED_ORIGINS + Proxy SSL Header ---
# Upstream settings.py doesn't read CSRF_TRUSTED_ORIGINS from env,
# and doesn't trust X-Forwarded-Proto from a reverse proxy.
# We append both fixes so Django correctly handles HTTPS behind Nginx.
PATCH_MARKER="# --- OpenCarwings CSRF/Proxy Patch ---"

if ! grep -q "$PATCH_MARKER" "$SETTINGS_FILE"; then
    bashio::log.info "Patching settings.py for CSRF + reverse proxy support..."
    cat <<'EOF' >> "$SETTINGS_FILE"

# --- OpenCarwings CSRF/Proxy Patch ---
import os

# Trust X-Forwarded-Proto from Nginx so Django knows the real scheme (https)
SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')
USE_X_FORWARDED_HOST = True
USE_X_FORWARDED_PORT = True

# Read CSRF trusted origins from environment variable
csrf_env = os.getenv('CSRF_TRUSTED_ORIGINS')
if csrf_env:
    CSRF_TRUSTED_ORIGINS = [o.strip() for o in csrf_env.split(',') if o.strip()]
EOF
else
    bashio::log.info "settings.py already patched for CSRF/Proxy."
fi

# --- Patch 2: Inject WhiteNoise for Static Files ---
# In production (DEBUG=False), Django doesn't serve static files.
# We inject WhiteNoise middleware and set STATIC_ROOT to ensure they are served.
STATIC_PATCH_MARKER="# --- OpenCarwings Static Files Patch ---"

if ! grep -q "$STATIC_PATCH_MARKER" "$SETTINGS_FILE"; then
    bashio::log.info "Patching settings.py for WhiteNoise static file serving..."
    cat <<'EOF' >> "$SETTINGS_FILE"

# --- OpenCarwings Static Files Patch ---
# Ensure STATIC_ROOT is set to where we collect files
STATIC_ROOT = '/opt/opencarwings/staticfiles'

# Inject WhiteNoise Middleware if not present
MIDDLEWARE_TO_ADD = 'whitenoise.middleware.WhiteNoiseMiddleware'
if MIDDLEWARE_TO_ADD not in MIDDLEWARE:
    # Add it after SecurityMiddleware (usually first) or at the top
    try:
        sec_index = MIDDLEWARE.index('django.middleware.security.SecurityMiddleware')
        MIDDLEWARE.insert(sec_index + 1, MIDDLEWARE_TO_ADD)
    except ValueError:
        MIDDLEWARE.insert(0, MIDDLEWARE_TO_ADD)

# Enabled compression/caching
STATICFILES_STORAGE = 'whitenoise.storage.CompressedManifestStaticFilesStorage'
EOF
else
    bashio::log.info "settings.py already patched for Static Files."
fi

# --- Patch 3: Force Colorized Console Logging & Dynamic Debug Level ---
LOGGING_PATCH_MARKER="# --- OpenCarwings Logging Patch V7 ---"

if ! grep -q "$LOGGING_PATCH_MARKER" "$SETTINGS_FILE"; then
    bashio::log.info "Patching settings.py for Colorized Console Logging (V7)..."
    cat <<'EOF' >> "$SETTINGS_FILE"

# --- OpenCarwings Logging Patch V7 ---
import os
import sys
import logging

# Add TRACE level for deep protocol parser diagnostics.
TRACE_LEVEL_NUM = 5
if not hasattr(logging, "TRACE"):
    logging.addLevelName(TRACE_LEVEL_NUM, "TRACE")
    def trace(self, message, *args, **kws):
        if self.isEnabledFor(TRACE_LEVEL_NUM):
            self._log(TRACE_LEVEL_NUM, message, args, **kws)
    logging.Logger.trace = trace
    logging.TRACE = TRACE_LEVEL_NUM

# Determine log level (fallback to INFO).
RAW_LEVEL = os.environ.get('LOG_LEVEL', 'INFO').upper()
VALID_LEVELS = ['TRACE', 'DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL']

if RAW_LEVEL in VALID_LEVELS:
    LOG_LEVEL = RAW_LEVEL
elif RAW_LEVEL == '6':
    LOG_LEVEL = 'DEBUG'
else:
    LOG_LEVEL = 'INFO'

if os.environ.get('DEBUG', 'False') == 'True':
    LOG_LEVEL = 'DEBUG'

LOG_IS_TRACE = LOG_LEVEL == 'TRACE'

class AppNoiseFilter(logging.Filter):
    def filter(self, record):
        msg = str(record.getMessage())

        # PIL emits very chatty PNG chunk traces as DEBUG; hide them unless TRACE mode.
        if record.name.startswith("PIL.PngImagePlugin") and msg.startswith("STREAM b'"):
            if not LOG_IS_TRACE:
                return False
            record.levelno = TRACE_LEVEL_NUM
            record.levelname = "TRACE"
        return True

class AppColorFormatter(logging.Formatter):
    # Match Home Assistant style: green for INFO, red for ERROR, etc.
    COLORS = {'TRACE': '36', 'DEBUG': '35', 'INFO': '32', 'WARNING': '33', 'ERROR': '31', 'CRITICAL': '1;31'}
    def format(self, record):
        color = self.COLORS.get(record.levelname, '0')
        
        # Ensure message is a string for tagging
        msg = str(record.msg)
        if record.args:
            msg = msg % record.args
        
        # 1) Explicit in-message prefix always wins
        if msg and msg[0] == "[" and "]" in msg:
            tag = msg[:msg.find("]")+1]
            msg = msg[msg.find("]")+1:].strip()
        elif " - - [" in msg:
            # Daphne Access Log detected: '127.0.0.1:39728 - - [14/Feb/2026:13:54:29] "GET /api/car/" 200 804'
            tag = "[daphne]"
            msg = msg.strip()
        # 2) Source-based default tags
        elif "tculink.management.commands.tcuserver" in record.name:
            tag = "[tcuserver]"
        elif "tculink" in record.name:
            tag = "[app]"
        elif "daphne" in record.name:
            tag = "[daphne]"
        else:
            tag = "[django]"

        # Show upstream tcuserver INFO lines as DEBUG to reduce user-facing noise.
        if tag == "[tcuserver]" and record.levelname == "INFO":
            record.levelname = "DEBUG"
        
        # Color mapping by level (as requested, revert tag-based overrides)
        color = self.COLORS.get(record.levelname, color)
        
        record.msg = f"{tag} {msg}"
        record.args = () # Clear args since we pre-formatted
        record.levelname = record.levelname # Ensure level is preserved

        # Format the base message
        formatted = super().format(record)

        # Color the entire line except the timestamp
        idx = formatted.find(']')
        if idx != -1:
            timestamp = formatted[:idx+1]
            rest = formatted[idx+1:]
            return f"{timestamp}\033[{color}m{rest}\033[0m"
        return formatted

LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'formatters': {
        'color': {
            '()': 'carwings.settings.AppColorFormatter',
            'format': '[%(asctime)s] %(levelname)s: %(message)s',
            'datefmt': '%H:%M:%S',
        },
    },
    'handlers': {
        'console': {
            'class': 'logging.StreamHandler',
            'stream': sys.stdout,
            'formatter': 'color',
            'filters': ['app_noise'],
        },
        'file': {
            'class': 'logging.FileHandler',
            'filename': '/opt/opencarwings/tcuserver.log',
            'formatter': 'color',
            'mode': 'a',
            'filters': ['app_noise'],
        },
    },
    'filters': {
        'app_noise': {
            '()': 'carwings.settings.AppNoiseFilter',
        },
    },
    'loggers': {
        'django': {
            'handlers': ['console'],
            'level': 'INFO',
            'propagate': False,
        },
        'django.request': {
            'handlers': ['console'],
            'level': 'INFO',
            'propagate': False,
        },
        'django.server': {
            'handlers': ['console'],
            'level': 'INFO',
            'propagate': False,
        },
        'daphne': {
            'handlers': ['console'],
            'level': 'INFO',
            'propagate': False,
        },
        'daphne.access': {
            'handlers': ['console'],
            'level': 'WARNING',
            'propagate': False,
        },
        'daphne.server': {
            'handlers': ['console'],
            'level': 'INFO',
            'propagate': False,
        },
        'django.channels.server': {
            'handlers': ['console'],
            'level': 'INFO',
            'propagate': False,
        },
        'tculink': {
            'handlers': ['console', 'file'],
            'level': LOG_LEVEL,
            'propagate': False,
        },
    },
    'root': {
        'handlers': ['console'],
        'level': LOG_LEVEL,
    },
}
EOF
else
    bashio::log.info "settings.py already patched for Logging."
fi

# --- Patch 4: Force Redis Channel Layer ---
# In production, we must ensure:
# 1. Channels uses Redis (not InMemory) so Daphne and TCUserver can talk.

REDIS_PATCH_MARKER="# --- OpenCarwings Redis Patch ---"

if ! grep -q "$REDIS_PATCH_MARKER" "$SETTINGS_FILE"; then
    bashio::log.info "Patching settings.py for Redis Channel Layer..."
    cat <<'EOF' >> "$SETTINGS_FILE"

# --- OpenCarwings Redis Patch ---
import os

# Force Redis Channel Layer
# This ensures daphne (web) and tcuserver (worker) share the same bus.
CHANNEL_LAYERS = {
    "default": {
        "BACKEND": "channels_redis.core.RedisChannelLayer",
        "CONFIG": {
            "hosts": [("localhost", 6379)],
        },
    },
}

# Safety: Ensure Loopback is Allowed for internal communication
if "localhost" not in ALLOWED_HOSTS:
    ALLOWED_HOSTS.append("localhost")
if "127.0.0.1" not in ALLOWED_HOSTS:
    ALLOWED_HOSTS.append("127.0.0.1")
if "0.0.0.0" not in ALLOWED_HOSTS:
    ALLOWED_HOSTS.append("0.0.0.0")
EOF
else
    bashio::log.info "settings.py already patched for Redis."
fi


# --- Patch 5: Instrument TCUserver for Debugging & Error Escalation ---
TCUSERVER_FILE="/opt/opencarwings/tculink/management/commands/tcuserver.py"
TC_INSTRUMENT_MARKER="# --- OpenCarwings Instrumentation Patch V17 ---"

# Check if file exists and hasn't been V16-patched yet
if [ -f "$TCUSERVER_FILE" ]; then
    if ! grep -q "$TC_INSTRUMENT_MARKER" "$TCUSERVER_FILE"; then
        bashio::log.info "Instrumenting tcuserver.py with V17 Unified Logging..."
        python3 - <<'EOF'
import sys
import os

file_path = "/opt/opencarwings/tculink/management/commands/tcuserver.py"
with open(file_path, 'r') as f:
    lines = f.readlines()

new_lines = [ "# --- OpenCarwings Instrumentation Patch V17 ---\n" ]
CMD_MAP = '{1: "Refresh data", 2: "Start Charge", 3: "AC On", 4: "AC Off", 5: "Read TCU Config", 6: "Set Auth"}'

connection_logged_injected = False
in_charge_result = False

for i, line in enumerate(lines):
    indent = line[:len(line) - len(line.lstrip())]
    
    # 0. Initialize flags at start of handle_client loop/function
    if "authenticated = False" in line and not connection_logged_injected:
        new_lines.append(line)
        new_lines.append(f"{indent}refresh_completion_pending = False\n")
        new_lines.append(f"{indent}refresh_completion_message = None\n")
        new_lines.append(f"{indent}CMD_MAP = {CMD_MAP}\n")
        connection_logged_injected = True
        continue

    # 1.1 Keep upstream auth status line; no addon bypass noise
    if "TCU Authentication check status:" in line:
        new_lines.append(line)
        continue

    # 2.1 Keep parser call intact; emit parsed payload after payload hex line
    if 'parsed_data = parse_gdc_packet(data)' in line:
        new_lines.append(line)
        continue

    if 'logger.info(f"TCU Payload hex:' in line:
        new_lines.append(line)
        new_lines.append(f"{indent}logger.debug(f\"[app] Raw Parsed Data: {{parsed_data}}\")\n")
        continue

    # 2.2 Keep charge_result alert mapping aligned with upstream
    if 'if body_type == "charge_result":' in line:
        in_charge_result = True
    
    if in_charge_result and "new_alert.type = 2" in line:
        new_lines.append(f"{indent}new_alert.type = 2\n")
        in_charge_result = False
        continue
        
    if 'logger.info("Connection closed")' in line:
        new_lines.append(f"{indent}try:\n")
        new_lines.append(f"{indent}    if refresh_completion_pending and refresh_completion_message:\n")
        new_lines.append(f"{indent}        logger.info(refresh_completion_message)\n")
        new_lines.append(f"{indent}        refresh_completion_pending = False\n")
        new_lines.append(f"{indent}        refresh_completion_message = None\n")
        new_lines.append(f"{indent}except Exception:\n")
        new_lines.append(f"{indent}    pass\n")
        new_lines.append(line.replace("logger.info", "logger.debug"))
        continue

    # 3. Inject EV Status Summary (Removed manual injection, now handled by Alerts)
    if "car.ev_info.last_updated = timezone.now()" in line:
        new_lines.append(line)
        continue

    # 4. Keep upstream config log line as-is (summary emitted via alert mapping)
    if 'logger.info(f"Car Config:' in line:
        new_lines.append(line)
        continue

    # 4. Inject Comprehensive Alert Logging
    if "new_alert.car = car" in line:
        new_lines.append(line)
        # Dictionary mapping for alerts
        new_lines.append(f"{indent}ALERT_MAP = {{\n")
        new_lines.append(f"{indent}    1: 'Charge stop', 2: 'Charge start', 3: 'Cable reminder',\n")
        new_lines.append(f"{indent}    4: 'A/C on', 5: 'A/C off', 6: 'TCU Config received',\n")
        new_lines.append(f"{indent}    7: 'A/C auto off', 8: 'Quick charge stop',\n")
        new_lines.append(f"{indent}    9: 'Battery heater start', 10: 'Battery heater stop',\n")
        new_lines.append(f"{indent}    96: 'Charge error', 97: 'A/C error', 98: 'Timeout', 99: 'Error'\n")
        new_lines.append(f"{indent}}}\n")
        
        # Determine specific detailed message based on result state
        new_lines.append(f"{indent}detail_msg = None\n")
        new_lines.append(f"{indent}_body = parsed_data.get('body', {{}})\n")
        new_lines.append(f"{indent}_b_type = parsed_data.get('body_type')\n")
        new_lines.append(f"{indent}r_state = _body.get('resultstate') if isinstance(_body, dict) else None\n")
        new_lines.append(f"{indent}a_state = _body.get('alertstate') if isinstance(_body, dict) else None\n")
        new_lines.append(f"{indent}plugged_state = _body.get('pluggedin') if isinstance(_body, dict) else None\n")
        new_lines.append(f"{indent}not_plugin_alert = _body.get('not_plugin_alert') if isinstance(_body, dict) else None\n")
        new_lines.append(f"{indent}charge_request_result = _body.get('charge_request_result') if isinstance(_body, dict) else None\n")
        new_lines.append(f"{indent}pri_ac_req_result = _body.get('pri_ac_req_result') if isinstance(_body, dict) else None\n")
        new_lines.append(f"{indent}pri_ac_stop_result = _body.get('pri_ac_stop_result') if isinstance(_body, dict) else None\n")
        
        new_lines.append(f"{indent}if _b_type == 'ac_result':\n")
        new_lines.append(f"{indent}    if r_state == 64: detail_msg = 'A/C Started successfully'\n")
        new_lines.append(f"{indent}    elif r_state == 32: detail_msg = 'A/C Stopped successfully'\n")
        new_lines.append(f"{indent}    elif r_state == 192: detail_msg = 'A/C Finished / Auto-off'\n")
        new_lines.append(f"{indent}    elif r_state == 128 or pri_ac_req_result == 2: detail_msg = 'A/C start rejected (likely low battery SOC)'\n")
        new_lines.append(f"{indent}    elif r_state == 16 and (pri_ac_stop_result == 1 or getattr(car, 'command_type', None) == 4): detail_msg = 'A/C already off (no action needed)'\n")
        new_lines.append(f"{indent}    else: detail_msg = f'A/C Error/Unknown (State {{r_state}})'\n")
        
        new_lines.append(f"{indent}elif _b_type == 'remote_stop':\n")
        new_lines.append(f"{indent}    if a_state in [4, 68]: detail_msg = 'Normal Charge Finished'\n")
        new_lines.append(f"{indent}    elif a_state == 8: detail_msg = 'Quick Charge Finished'\n")
        new_lines.append(f"{indent}    else: detail_msg = f'A/C Finished / Default (State {{a_state}})'\n")
        
        new_lines.append(f"{indent}elif _b_type == 'charge_result':\n")
        new_lines.append(f"{indent}    unplugged = (r_state == 17) or (not_plugin_alert is True) or (plugged_state is False)\n")
        new_lines.append(f"{indent}    if unplugged:\n")
        new_lines.append(f"{indent}        detail_msg = 'Charge command response: vehicle appears unplugged; charging may not start'\n")
        new_lines.append(f"{indent}    else:\n")
        new_lines.append(f"{indent}        detail_msg = 'Charge command response received'\n")
        new_lines.append(f"{indent}    detail_msg += f\" (resultstate={{r_state}}, alertstate={{a_state}}, pluggedin={{plugged_state}}, not_plugin_alert={{not_plugin_alert}}, charge_request_result={{charge_request_result}})\"\n")
        
        new_lines.append(f"{indent}if _b_type == 'ac_result' and r_state == 16:\n")
        new_lines.append(f"{indent}    msg = 'A/C off'\n")
        new_lines.append(f"{indent}else:\n")
        new_lines.append(f"{indent}    msg = ALERT_MAP.get(new_alert.type, f'SYSTEM ALERT [Type {{new_alert.type}}]')\n")
        new_lines.append(f"{indent}if detail_msg:\n")
        new_lines.append(f"{indent}    msg += f': {{detail_msg}}'\n")
        new_lines.append(f"{indent}elif new_alert.additional_data:\n")
        new_lines.append(f"{indent}    msg += f': {{new_alert.additional_data}}'\n")
        
        new_lines.append(f"{indent}if _b_type == 'ac_result' and r_state == 16:\n")
        new_lines.append(f"{indent}    alert_logger = logger.info\n")
        new_lines.append(f"{indent}else:\n")
        new_lines.append(f"{indent}    alert_logger = logger.error if new_alert.type >= 96 else logger.info\n")
        new_lines.append(f"{indent}alert_logger(f\"[app] {{msg}}\")\n")
    
    # 5. Fix AlertHistory save() bug
    if "new_alert.command_id = car.command_id" in line:
        new_lines.append(line)
        has_save = False
        for k in range(i+1, min(i+10, len(lines))):
            if "save()" in lines[k] and "new_alert" in lines[k]:
                has_save = True
                break
        if not has_save:
            new_lines.append(f"{indent}await sync_to_async(new_alert.save)()\n")
        continue

    # 6. Save Confirmation (No Emoji)
    if "Car state saved" in line and "logger.info" in line:
        new_lines.append(f"{indent}logger.info(f\"[app] Car state saved to database for VIN: {{car.vin}}\")\n")
        continue

    # 7. Command Parsing (No Emoji)
    if "Command found:" in line:
        cmd_name = 'CMD_MAP.get(car.command_type, "Unknown")'
        new_lines.append(f"{indent}if car.command_type == 1: car.pending_refresh_feedback = True\n")
        new_lines.append(line)
        # Consolidated delivery log appears after upstream command-found line
        new_lines.append(f"{indent}logger.info(f\"[app] Vehicle connected: {{ {cmd_name} }} command delivered\")\n")
        continue

    if 'logger.info("No command or another in progress, send success false")' in line:
        new_lines.append(f"{indent}logger.info(f\"[app] Vehicle check-in: {{car.nickname}} (VIN: {{car.vin}})\")\n")
        new_lines.append(line)
        continue

    # Keep upstream Body Type log as-is and arm refresh-complete tail log.
    if 'logger.info(f"Body Type: {body_type}")' in line:
        new_lines.append(line)
        new_lines.append(f"{indent}try:\n")
        new_lines.append(f"{indent}    if body_type == 'charge_status' and getattr(car, 'command_type', None) == 1:\n")
        new_lines.append(f"{indent}        refresh_completion_pending = True\n")
        new_lines.append(f"{indent}        refresh_completion_message = f\"[app] Refresh data command completed for {{car.nickname}} (VIN: {{car.vin}})\"\n")
        new_lines.append(f"{indent}except Exception:\n")
        new_lines.append(f"{indent}    pass\n")
        continue

    # 8. Patch error handler: reset command_result on processing failure
    if '"Processing packet failed"' in line:
        new_lines.append(line)
        new_lines.append(f"{indent}try:\n")
        new_lines.append(f"{indent}    if car and car.command_result == 3:\n")
        new_lines.append(f"{indent}        car.command_result = 1\n")
        new_lines.append(f"{indent}        car.command_requested = False\n")
        new_lines.append(f"{indent}        await sync_to_async(car.save)()\n")
        new_lines.append(f"{indent}        logger.warning(f\"[app] Command state reset to FAILED for {{car.nickname}} due to processing error\")\n")
        new_lines.append(f"{indent}except: pass\n")
        continue

    new_lines.append(line)

with open(file_path, 'w') as f:
    f.writelines(new_lines)
EOF
    else
        bashio::log.info "tcuserver.py already patched with V17+ logging."
    fi
else
    bashio::log.warning "tcuserver.py not found, skipping instrumentation."
fi

# --- Patch 6: Instrument api/views.py for Command Initiation ---
VIEWS_FILE="/opt/opencarwings/api/views.py"
VIEWS_PATCH_MARKER="# --- OpenCarwings Command Init Patch V2 ---"

if [ -f "$VIEWS_FILE" ]; then
    if ! grep -q "$VIEWS_PATCH_MARKER" "$VIEWS_FILE"; then
        bashio::log.info "Instrumenting api/views.py for Command Initiation..."
        python3 - <<'EOF'
import sys

file_path = "/opt/opencarwings/api/views.py"
with open(file_path, 'r') as f:
    lines = f.readlines()

new_lines = [ "# --- OpenCarwings Command Init Patch V2 ---\n" ]
for line in lines:
    indent = line[:len(line) - len(line.lstrip())]
    
    if "command_type = request.data.get('command_type')" in line:
        new_lines.append(line)
        new_lines.append(f"{indent}import logging\n")
        new_lines.append(f"{indent}logger = logging.getLogger('tculink')\n")
        new_lines.append(f"{indent}CMD_MAP = {{1: 'Refresh data', 2: 'Start Charge', 3: 'A/C On', 4: 'A/C Off', 5: 'Read TCU config', 6: 'Set Auth'}}\n")
        new_lines.append(f"{indent}try:\n")
        new_lines.append(f"{indent}    c_name = CMD_MAP.get(int(command_type), f'Type {{command_type}}')\n")
        new_lines.append(f"{indent}    logger.info(f\"[app] {{c_name}} command initiated for {{car.nickname}} (VIN: {{vin}})\")\n")
        new_lines.append(f"{indent}except: pass\n")
        continue
    
    new_lines.append(line)

with open(file_path, 'w') as f:
    f.writelines(new_lines)
EOF
    else
        bashio::log.info "api/views.py already patched for Command Initiation."
    fi
else
    bashio::log.warning "api/views.py not found, skipping instrumentation."
fi

# --- Patch 7: Add optional Monogoto SMS delivery webhook endpoint ---
WEBHOOK_PATCH_MARKER="# --- OpenCarwings Monogoto Webhook Patch V10 ---"
API_VIEWS_FILE="/opt/opencarwings/api/views.py"
URLS_FILE="/opt/opencarwings/carwings/urls.py"

if [ -f "$API_VIEWS_FILE" ] && [ -f "$URLS_FILE" ]; then
    if ! grep -q "$WEBHOOK_PATCH_MARKER" "$API_VIEWS_FILE"; then
        bashio::log.info "Patching API for Monogoto SMS delivery webhook..."
        python3 - <<'EOF'
import re

api_views_path = "/opt/opencarwings/api/views.py"
urls_path = "/opt/opencarwings/carwings/urls.py"
marker = "# --- OpenCarwings Monogoto Webhook Patch V10 ---"

with open(api_views_path, "r", encoding="utf-8") as f:
    api_views = f.read()

# Backward-compatibility cleanup:
# Older patch versions injected @permission_classes without importing the decorator.
api_views = api_views.replace("@permission_classes([permissions.AllowAny])\n", "")

if marker not in api_views:
    webhook_func = f"""

{marker}
@api_view(['POST'])
def monogoto_sms_delivery_webhook(request):
    import json
    import logging
    import os
    import re
    from datetime import datetime, UTC

    logger = logging.getLogger('tculink')
    enabled = os.getenv("MONOGOTO_SMS_DELIVERY_WEBHOOK_ENABLED", "false").lower() == "true"
    if not enabled:
        return Response(status=status.HTTP_204_NO_CONTENT)

    expected_token = (os.getenv("MONOGOTO_SMS_DELIVERY_WEBHOOK_TOKEN", "ocw") or "ocw").strip()
    provided_token = (request.query_params.get("token", "") if hasattr(request, "query_params") else "").strip()
    if provided_token != expected_token:
        return Response(status=status.HTTP_403_FORBIDDEN)

    content_type = request.headers.get("Content-Type", "")
    raw_body_bytes = request.body or b""
    raw_body_text = raw_body_bytes.decode("utf-8", errors="replace")

    try:
        parsed = request.data
    except Exception:
        logger.debug("[app] Monogoto webhook: request.data parsing failed")
        return Response(status=status.HTTP_400_BAD_REQUEST)

    if isinstance(parsed, dict):
        payload = parsed
    elif isinstance(parsed, list):
        payload = parsed
    elif raw_body_text.strip():
        try:
            payload = json.loads(raw_body_text)
        except Exception:
            payload = {{}}
    else:
        payload = {{}}

    logger.debug(f"[app] Monogoto webhook payload: {{payload}}")
    if payload in ({{}}, [], None):
        logger.debug(f"[app] Monogoto webhook payload empty after parsing (content-type: {{content_type}})")

    received_at = datetime.now(UTC).isoformat(timespec="seconds")

    def _find_first(data, keys):
        if isinstance(data, dict):
            for k, v in data.items():
                lk = str(k).lower()
                if lk in keys and v not in (None, ""):
                    return v
                found = _find_first(v, keys)
                if found not in (None, ""):
                    return found
        elif isinstance(data, list):
            for item in data:
                found = _find_first(item, keys)
                if found not in (None, ""):
                    return found
        return None

    text_val = _find_first(payload, {{"text", "message", "description", "body"}})
    title_val = _find_first(payload, {{"title"}})
    desc_val = _find_first(payload, {{"description"}})

    payload_time = _find_first(payload, {{"time", "timestamp", "event_time", "created_at"}})
    if not payload_time and isinstance(text_val, str):
        m_time = re.search(r"Time:\\s*([^,]+,\\s*\\d{{2}}:\\d{{2}})", text_val, flags=re.IGNORECASE)
        if m_time:
            payload_time = m_time.group(1).strip()

    status_or_event = _find_first(payload, {{"status", "event", "event_type", "state", "delivery_status", "title", "result"}}) or "unknown"
    if status_or_event == "unknown":
        haystack = " ".join([str(v) for v in [title_val, desc_val, text_val] if v]).lower()
        if "success" in haystack or "delivered" in haystack:
            status_or_event = "success"
        elif "fail" in haystack or "error" in haystack:
            status_or_event = "failed"

    iccid = _find_first(payload, {{"iccid"}})
    thing = _find_first(payload, {{"thingid", "thing_id", "thing"}})
    if not iccid and isinstance(thing, str):
        m = re.search(r"ICCID_(\\d+)", thing)
        if m:
            iccid = m.group(1)
    if not iccid and isinstance(text_val, str):
        m = re.search(r"ICCID[:\\s]+(\\d+)", text_val, flags=re.IGNORECASE)
        if m:
            iccid = m.group(1)

    if not iccid:
        logger.debug(f"[app] Monogoto webhook: SMS delivery event received (status: {{status_or_event}}, iccid: missing, received_at: {{received_at}}, payload_time: {{payload_time}})")
        return Response(status=status.HTTP_200_OK)

    iccid = str(iccid).strip()
    norm_iccid = re.sub(r"\\D", "", iccid)

    car = Car.objects.filter(iccid=norm_iccid).first()
    if not car and norm_iccid:
        for candidate in Car.objects.exclude(iccid__isnull=True).all():
            cand_iccid = re.sub(r"\\D", "", candidate.iccid or "")
            # Monogoto can report ICCID missing one trailing digit; allow +/-1 trailing-digit tolerance.
            if cand_iccid == norm_iccid:
                car = candidate
                break
            if len(cand_iccid) == len(norm_iccid) + 1 and cand_iccid.startswith(norm_iccid):
                car = candidate
                break
            if len(norm_iccid) == len(cand_iccid) + 1 and norm_iccid.startswith(cand_iccid):
                car = candidate
                break
    if car:
        logger.info("[app] Monogoto webhook: SMS delivered")
    else:
        logger.debug(f"[app] Monogoto webhook: event received for unknown ICCID {{iccid}} (status: {{status_or_event}}, received_at: {{received_at}}, payload_time: {{payload_time}})")

    return Response(status=status.HTTP_200_OK)

# DRF function-view auth/permission setup without decorator imports
monogoto_sms_delivery_webhook.cls.authentication_classes = []
monogoto_sms_delivery_webhook.cls.permission_classes = [permissions.AllowAny]
"""
    api_views = api_views.rstrip() + "\n" + webhook_func.strip("\n") + "\n"
    with open(api_views_path, "w", encoding="utf-8") as f:
        f.write(api_views)

with open(urls_path, "r", encoding="utf-8") as f:
    urls_content = f.read()

url_line = "    path('api/webhook/monogoto/sms-delivery/', api_views.monogoto_sms_delivery_webhook, name='monogoto_sms_delivery_webhook'),"
if "monogoto_sms_delivery_webhook" not in urls_content:
    insert_after = "    path('api/command/<str:vin>/', api_views.command_api, name='command_api'),"
    urls_content = urls_content.replace(insert_after, insert_after + "\n" + url_line)
    with open(urls_path, "w", encoding="utf-8") as f:
        f.write(urls_content)
EOF
    else
        bashio::log.info "Monogoto webhook patch already applied."
    fi
else
    bashio::log.warning "api/views.py or carwings/urls.py not found, skipping Monogoto webhook patch."
fi

# --- Patch 8: Demote probe parser spam to TRACE + add compact summaries ---
PROBE_TRACE_PATCH_MARKER="# --- OpenCarwings Probe Trace Patch V1 ---"
PROBE_DOT_FILE="/opt/opencarwings/tculink/carwings_proto/probe_dot.py"
PROBE_CRM_FILE="/opt/opencarwings/tculink/carwings_proto/probe_crm.py"
PROBE_PI_FILE="/opt/opencarwings/tculink/carwings_proto/applications/pi.py"

if [ -f "$PROBE_DOT_FILE" ] && [ -f "$PROBE_CRM_FILE" ] && [ -f "$PROBE_PI_FILE" ]; then
    bashio::log.info "Patching probe parser logs (TRACE demotion + summaries)..."
    python3 - <<'EOF'
from pathlib import Path

marker = "# --- OpenCarwings Probe Trace Patch V1 ---"

def apply_replacements(content, replacements):
    changed = False
    for old, new in replacements:
        if old in content:
            content = content.replace(old, new)
            changed = True
    return content, changed

def patch_file(path, replacements):
    path_obj = Path(path)
    content = path_obj.read_text(encoding="utf-8")
    if marker in content:
        return False
    content, changed = apply_replacements(content, replacements)
    if changed:
        content = marker + "\n" + content
        path_obj.write_text(content, encoding="utf-8")
        return True
    return False

dot_changed = patch_file(
    "/opt/opencarwings/tculink/carwings_proto/probe_dot.py",
    [
        ('logger.debug("TYPE: %d/%s, %s", item_type, hex(item_type), str(prb_type[0]))', 'logger.trace("TYPE: %d/%s, %s", item_type, hex(item_type), str(prb_type[0]))'),
        ('logger.debug("DATALEN: %d", prb_type[1])', 'logger.trace("DATALEN: %d", prb_type[1])'),
        ('logger.debug("DATA: %s", data.hex())', 'logger.trace("DATA: %s", data.hex())'),
        ('logger.debug("-------------------")', 'logger.trace("-------------------")'),
    ],
)

crm_changed = patch_file(
    "/opt/opencarwings/tculink/carwings_proto/probe_crm.py",
    [
        ('logger.debug("Label: %d,%s", item_type, hex(item_type))', 'logger.trace("Label: %d,%s", item_type, hex(item_type))'),
        ('logger.debug("Datafield type: %d", meta["type"])', 'logger.trace("Datafield type: %d", meta["type"])'),
        ('logger.debug("Block count: %d", size_field)', 'logger.trace("Block count: %d", size_field)'),
        ('logger.debug("MSN Byte count: %s", size_field)', 'logger.trace("MSN Byte count: %s", size_field)'),
        ('logger.debug("Size: %s", hex(size))', 'logger.trace("Size: %s", hex(size))'),
        ('logger.debug("DATALEN: %d",size-1)', 'logger.trace("DATALEN: %d",size-1)'),
        ('logger.debug("-------------------")', 'logger.trace("-------------------")'),
        ('logger.debug("Starting to parse crmblock %s", crmblock["struct"])', 'logger.trace("Starting to parse crmblock %s", crmblock["struct"])'),
        ('logger.debug("Block change, closing block: %s", currentblock)', 'logger.trace("Block change, closing block: %s", currentblock)'),
        ('logger.info("Identified head item! saving previous object and opening new")', 'logger.trace("Identified head item! saving previous object and opening new")'),
        ('logger.info("Block %d", crmblock["type"])', 'logger.trace("Block %d", crmblock["type"])'),
        ('logger.debug(item_data.hex())', 'logger.trace(item_data.hex())'),
    ],
)

pi_path = Path("/opt/opencarwings/tculink/carwings_proto/applications/pi.py")
pi_content = pi_path.read_text(encoding="utf-8")
pi_changed = False
if marker not in pi_content:
    old_crm = "                                            update_crm_to_db(car_ref, crm_data)\n"
    new_crm = (
        "                                            update_crm_to_db(car_ref, crm_data)\n"
        "                                            summary_blocks = sum(1 for value in crm_data.values() if (isinstance(value, dict) and len(value) > 0) or (isinstance(value, list) and len(value) > 0))\n"
        "                                            logger.debug(\"[probe] Parsed CRM blocks: %d, file=%s, navi_id=%s, vin=%s\", summary_blocks, filename, xml_data.get('authentication', {}).get('navi_id', '?'), xml_data.get('authentication', {}).get('vin', '?'))\n"
    )
    if old_crm in pi_content:
        pi_content = pi_content.replace(old_crm, new_crm)
        pi_changed = True

    old_dot = "                                            dot_data = parse_dotfile(decrypted_data)\n"
    new_dot = (
        "                                            dot_data = parse_dotfile(decrypted_data)\n"
        "                                            logger.debug(\"[probe] Parsed DOT entries: %d, file=%s, navi_id=%s, vin=%s\", len(dot_data), filename, xml_data.get('authentication', {}).get('navi_id', '?'), xml_data.get('authentication', {}).get('vin', '?'))\n"
    )
    if old_dot in pi_content:
        pi_content = pi_content.replace(old_dot, new_dot)
        pi_changed = True

    if pi_changed:
        pi_content = marker + "\n" + pi_content
        pi_path.write_text(pi_content, encoding="utf-8")

if dot_changed:
    print("[INFO] probe_dot.py patched for TRACE parser logs")
if crm_changed:
    print("[INFO] probe_crm.py patched for TRACE parser logs")
if pi_changed:
    print("[INFO] applications/pi.py patched with compact probe summaries")
if not any([dot_changed, crm_changed, pi_changed]):
    print("[DEBUG] Probe trace/summaries already patched or patterns not found.")
EOF
else
    bashio::log.warning "Probe parser files not found, skipping TRACE demotion patch."
fi

# --- Patch 9: Tune CP/XML envelope logs (INFO -> DEBUG/TRACE) ---
CP_LOG_TUNE_MARKER="# --- OpenCarwings CP Log Tuning Patch V1 ---"
CP_FILE="/opt/opencarwings/tculink/carwings_proto/applications/cp.py"
TCULINK_VIEWS_FILE="/opt/opencarwings/tculink/views.py"
DATABUFFER_FILE="/opt/opencarwings/tculink/carwings_proto/databuffer.py"

if [ -f "$CP_FILE" ] && [ -f "$TCULINK_VIEWS_FILE" ] && [ -f "$DATABUFFER_FILE" ]; then
    bashio::log.info "Tuning CP/XML/envelope log verbosity..."
    python3 - <<'EOF'
from pathlib import Path

marker = "# --- OpenCarwings CP Log Tuning Patch V1 ---"

def apply_replacements(content, replacements):
    changed = False
    for old, new in replacements:
        if old in content:
            content = content.replace(old, new)
            changed = True
    return content, changed

def patch_file(path, replacements):
    path_obj = Path(path)
    content = path_obj.read_text(encoding="utf-8")
    if marker in content:
        return False
    content, changed = apply_replacements(content, replacements)
    if changed:
        content = marker + "\n" + content
        path_obj.write_text(content, encoding="utf-8")
        return True
    return False

cp_changed = patch_file(
    "/opt/opencarwings/tculink/carwings_proto/applications/cp.py",
    [
        ('logger.debug("Mesh ID: %d, chargers: %d", mesh_id, len(chargers))', 'logger.trace("Mesh ID: %d, chargers: %d", mesh_id, len(chargers))'),
        ('logger.debug((len(chargers_resp)))', 'logger.trace((len(chargers_resp)))'),
        ('logger.info(cpinfo_obj)', 'logger.trace(cpinfo_obj)'),
        ('logger.info("get CPINFO! %d", len(charger_ids))', 'logger.debug("get CPINFO! %d", len(charger_ids))'),
    ],
)

views_changed = patch_file(
    "/opt/opencarwings/tculink/views.py",
    [
        ('logger.info("XML:")', 'logger.debug("XML:")'),
        ('logger.info(parsed_xml)', 'logger.debug(parsed_xml)'),
    ],
)

dbuf_changed = patch_file(
    "/opt/opencarwings/tculink/carwings_proto/databuffer.py",
    [
        ('logger.info("- Files count: %d", file_count)', 'logger.debug("- Files count: %d", file_count)'),
        ('logger.info("- Body size: %d", body_size)', 'logger.debug("- Body size: %d", body_size)'),
        ('logger.info("------- Length content: %d", len(file_content))', 'logger.debug("------- Length content: %d", len(file_content))'),
    ],
)

if cp_changed:
    print("[INFO] cp.py log levels tuned")
if views_changed:
    print("[INFO] tculink/views.py XML logs moved to debug")
if dbuf_changed:
    print("[INFO] databuffer.py envelope logs moved to debug")
if not any([cp_changed, views_changed, dbuf_changed]):
    print("[DEBUG] CP/XML/envelope tuning already patched or patterns not found.")
EOF
else
    bashio::log.warning "CP/XML/databuffer files not found, skipping log tuning patch."
fi

# --- Patch 10: Car request summary + DJ/PI/CP log demotion ---
CAR_LOG_TUNE_MARKER="# --- OpenCarwings Car Request Log Tuning Patch V2 ---"
DJ_FILE="/opt/opencarwings/tculink/carwings_proto/applications/dj.py"
PI_FILE="/opt/opencarwings/tculink/carwings_proto/applications/pi.py"
PROBE_CRM_FILE="/opt/opencarwings/tculink/carwings_proto/probe_crm.py"
AUTODJ_OCW_FILE="/opt/opencarwings/tculink/carwings_proto/autodj/opencarwings.py"

if [ -f "$TCULINK_VIEWS_FILE" ] && [ -f "$DATABUFFER_FILE" ] && [ -f "$CP_FILE" ] && [ -f "$DJ_FILE" ] && [ -f "$PI_FILE" ] && [ -f "$PROBE_CRM_FILE" ] && [ -f "$AUTODJ_OCW_FILE" ]; then
    bashio::log.info "Applying car request log tuning (INFO summary + DEBUG/TRACE demotions)..."
    python3 - <<'EOF'
from pathlib import Path

marker = "# --- OpenCarwings Car Request Log Tuning Patch V2 ---"

def apply_replacements(content, replacements):
    changed = False
    for old, new in replacements:
        if old in content:
            content = content.replace(old, new)
            changed = True
    return content, changed

def patch_file(path, replacements):
    path_obj = Path(path)
    content = path_obj.read_text(encoding="utf-8")
    if marker in content:
        return False
    content, changed = apply_replacements(content, replacements)
    if changed:
        content = marker + "\n" + content
        path_obj.write_text(content, encoding="utf-8")
        return True
    return False

views_changed = patch_file(
    "/opt/opencarwings/tculink/views.py",
    [
        ('logger.info("Binary response length: %d", len(resp_buffer))', 'logger.debug("Binary response length: %d", len(resp_buffer))'),
        (
            '    return HttpResponse(io.BytesIO(resp_buffer), content_type="application/x-carwings-nz")',
            '    app_name = parsed_xml.get("service_info", {}).get("application", {}).get("name", "UNK")\n'
            '    req_hint = "-"\n'
            '    if len(files) > 1 and isinstance(files[1], dict):\n'
            '        req_hint = files[1].get("name", "-")\n'
            '        payload = files[1].get("content", b"")\n'
            '        if isinstance(payload, (bytes, bytearray)) and len(payload) >= 6 and app_name in ["CP", "PI"]:\n'
            '            req_hint = f"{req_hint}/0x{int.from_bytes(payload[4:6], byteorder=\'big\'):03x}"\n'
            '    logger.info("[car] app=%s req=%s in=%d out=%d status=ok", app_name, req_hint, len(compressed_data), len(resp_buffer))\n\n'
            '    return HttpResponse(io.BytesIO(resp_buffer), content_type="application/x-carwings-nz")'
        ),
    ],
)

dbuf_changed = patch_file(
    "/opt/opencarwings/tculink/carwings_proto/databuffer.py",
    [
        ('logger.info("- Files count: %d", file_count)', 'logger.debug("- Files count: %d", file_count)'),
        ('logger.info("- Body size: %d", body_size)', 'logger.debug("- Body size: %d", body_size)'),
        ('logger.info("--- File %d, %s", num, file)', 'logger.debug("--- File %d, %s", num, file)'),
        ('logger.info("------- Length content: %d", len(file_content))', 'logger.debug("------- Length content: %d", len(file_content))'),
    ],
)

cp_changed = patch_file(
    "/opt/opencarwings/tculink/carwings_proto/applications/cp.py",
    [
        ('logger.info("Searching for nearest meshid: %f %f", lat, lon)', 'logger.debug("Searching for nearest meshid: %f %f", lat, lon)'),
        ('logger.info("chargingstations: %d", len(chargers))', 'logger.debug("chargingstations: %d", len(chargers))'),
    ],
)

dj_changed = patch_file(
    "/opt/opencarwings/tculink/carwings_proto/applications/dj.py",
    [
        ('logger.info("CWS lang: ")', 'logger.debug("CWS lang: ")'),
        ('logger.info(get_language())', 'logger.debug(get_language())'),
        ('logger.info("Save to Favorite list func!")', 'logger.debug("Save to Favorite list func!")'),
        ('logger.info("POS: %d, CHAN ID: %d", pos_num, chan_id)', 'logger.debug("POS: %d, CHAN ID: %d", pos_num, chan_id)'),
        ('logger.info("Handler ID: %s", hex(handler_id))', 'logger.debug("Handler ID: %s", hex(handler_id))'),
        ('logger.info("  ->Channel ID: %s", hex(channel_id))', 'logger.debug("  ->Channel ID: %s", hex(channel_id))'),
        ('logger.info("  ->Flag: %s", hex(flag))', 'logger.debug("  ->Flag: %s", hex(flag))'),
    ],
)

pi_changed = patch_file(
    "/opt/opencarwings/tculink/carwings_proto/applications/pi.py",
    [
        ('logger.info("0x583 Init!")', 'logger.debug("0x583 Init!")'),
        ('logger.info("0x583 Version1: %s", hex(file_content[6]))', 'logger.debug("0x583 Version1: %s", hex(file_content[6]))'),
        ('logger.info("0x583 Version2: %s", hex(file_content[7]))', 'logger.debug("0x583 Version2: %s", hex(file_content[7]))'),
        ('logger.info("0x584 Config change result")', 'logger.debug("0x584 Config change result")'),
        ('logger.info("0x584 Result code: %d", cfg_change_result)', 'logger.debug("0x584 Result code: %d", cfg_change_result)'),
        ('logger.info("0x581 Incoming Data")', 'logger.debug("0x581 Incoming Data")'),
        ('logger.info("0x581 Filename LEN: %d", filename_length)', 'logger.debug("0x581 Filename LEN: %d", filename_length)'),
        ('logger.info("0x581 Filename: %s", filename)', 'logger.debug("0x581 Filename: %s", filename)'),
        ('logger.info("Retrieving file %s", filename)', 'logger.debug("Retrieving file %s", filename)'),
        ('logger.info("Probe File too small, %s", filename)', 'logger.debug("Probe File too small, %s", filename)'),
        ('logger.info("Probe file metadata:")', 'logger.debug("Probe file metadata:")'),
        ('logger.info("  DataLength: %d", data_length)', 'logger.debug("  DataLength: %d", data_length)'),
        ('logger.info("  FileNumber: %d", file_number)', 'logger.debug("  FileNumber: %d", file_number)'),
        ('logger.info("  XORKey: %s", hex(xor_key))', 'logger.debug("  XORKey: %s", hex(xor_key))'),
        ('logger.info("  Checksum: %s", hex(checksum_byte))', 'logger.debug("  Checksum: %s", hex(checksum_byte))'),
        ('logger.info("  CoordinateSystem: %s", hex(coordinate_system))', 'logger.debug("  CoordinateSystem: %s", hex(coordinate_system))'),
        ('logger.info("Probe file checksum error!")', 'logger.debug("Probe file checksum error!")'),
        ('logger.info("CRM File!")', 'logger.debug("CRM File!")'),
        ('logger.info("Starting CRM file parse")', 'logger.debug("Starting CRM file parse")'),
        ('logger.info("DOT file!")', 'logger.debug("DOT file!")'),
        ('logger.info("Starting DOT file parse")', 'logger.debug("Starting DOT file parse")'),
    ],
)

crm_changed = patch_file(
    "/opt/opencarwings/tculink/carwings_proto/probe_crm.py",
    [
        ('parsingblocks = []', 'parsingblocks = []\n    mismatch_block_size_count = 0'),
        ('logger.info("-- Start parsing crmblocks --")', 'logger.debug("-- Start parsing crmblocks --")'),
        ('logger.warning("WARN! mismatch block size")', 'mismatch_block_size_count += 1\n                logger.trace("WARN! mismatch block size")'),
        ('    return parse_result', '    if mismatch_block_size_count > 0:\n        logger.warning("CRM parse block-size mismatches: %d", mismatch_block_size_count)\n    return parse_result'),
    ],
)

autodj_changed = patch_file(
    "/opt/opencarwings/tculink/carwings_proto/autodj/opencarwings.py",
    [
        ('print(header_font.size)', 'logger.trace("header_font.size=%s", header_font.size)'),
        ('print(halftrees, fulltrees)', 'logger.trace("halftrees=%s fulltrees=%s", halftrees, fulltrees)'),
        ('print(round(halftrees * 5))', 'logger.trace("halftree_steps=%s", round(halftrees * 5))'),
        ('logger.info(tree_records)', 'logger.debug(tree_records)'),
    ],
)

if views_changed:
    print("[INFO] tculink/views.py updated with concise [car] summary")
if dbuf_changed:
    print("[INFO] databuffer.py file envelope logs demoted to debug")
if cp_changed:
    print("[INFO] cp.py noisy info lines demoted")
if dj_changed:
    print("[INFO] dj.py verbose info lines demoted")
if pi_changed:
    print("[INFO] pi.py verbose info lines demoted")
if crm_changed:
    print("[INFO] probe_crm.py mismatch warnings aggregated")
if autodj_changed:
    print("[INFO] autodj/opencarwings.py print/debug spam demoted")
if not any([views_changed, dbuf_changed, cp_changed, dj_changed, pi_changed, crm_changed, autodj_changed]):
    print("[DEBUG] Car request log tuning already patched or patterns not found.")
EOF
else
    bashio::log.warning "Car request log tuning files not found, skipping V2 log patch."
fi

# --- Patch 11: Clear stale commands on startup ---
# If the addon restarted while a command was in "delivered, awaiting response"
# state (command_result=3), it will be stuck forever. Reset them to "failed" (1).
bashio::log.info "Checking for stale commands stuck in delivered state..."
cd /opt/opencarwings || exit 1
python3 - <<'EOF'
import os, django
# Force safe log level for startup script to avoid "Unknown level: '6'" errors
os.environ["LOG_LEVEL"] = "INFO"
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'carwings.settings')
django.setup()

from db.models import Car
stuck = Car.objects.filter(command_result=3)
count = stuck.count()
if count > 0:
    stuck.update(command_result=1, command_requested=False)
    import logging
    logger = logging.getLogger('tculink')
    logger.warning(f"Startup cleanup: reset {count} stale command(s) from delivered to failed")
else:
    import logging
    logger = logging.getLogger('tculink')
    logger.info("Startup cleanup: no stale commands found")
EOF
