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
LOGGING_PATCH_MARKER="# --- OpenCarwings Logging Patch V2 ---"

if ! grep -q "$LOGGING_PATCH_MARKER" "$SETTINGS_FILE"; then
    bashio::log.info "Patching settings.py for Colorized Console Logging (V2)..."
    cat <<'EOF' >> "$SETTINGS_FILE"

# --- OpenCarwings Logging Patch V2 ---
import os
import sys
import logging

# Determine log level (fallback to INFO)
# Sanitize environment variable (fix for '6' or other non-standard levels)
RAW_LEVEL = os.environ.get('LOG_LEVEL', 'INFO').upper()
VALID_LEVELS = ['DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL']

if RAW_LEVEL in VALID_LEVELS:
    LOG_LEVEL = RAW_LEVEL
elif RAW_LEVEL == '6' or RAW_LEVEL == 'TRACE':
    LOG_LEVEL = 'DEBUG'
else:
    LOG_LEVEL = 'INFO'

if os.environ.get('DEBUG', 'False') == 'True':
    LOG_LEVEL = 'DEBUG'

class AppColorFormatter(logging.Formatter):
    # Match Home Assistant style: green for INFO, red for ERROR, etc.
    COLORS = {'DEBUG': '35', 'INFO': '32', 'WARNING': '33', 'ERROR': '31', 'CRITICAL': '1;31'}
    def format(self, record):
        color = self.COLORS.get(record.levelname, '0')
        # Differentiator: tag the message
        if "daphne" in record.name:
            tag = "[daphne]"
        elif "tculink" in record.name:
            tag = "[app]"
        else:
            tag = "[django]"
        
        # Ensure message is a string for tagging
        msg = str(record.msg)
        if record.args:
            msg = msg % record.args
        
        if "[" == msg[0] and "]" in msg:
            tag = msg[:msg.find("]")+1]
            msg = msg[msg.find("]")+1:].strip()
        elif " - - [" in msg:
            # Daphne Access Log detected: '127.0.0.1:39728 - - [14/Feb/2026:13:54:29] "GET /api/car/" 200 804'
            tag = "[daphne]"
            msg = msg.strip()
        
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
        },
        'file': {
            'class': 'logging.FileHandler',
            'filename': '/opt/opencarwings/tcuserver.log',
            'formatter': 'color',
            'mode': 'a',
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
TC_INSTRUMENT_MARKER="# --- OpenCarwings Instrumentation Patch V10 ---"

# Check if file exists and hasn't been V9-patched yet
if [ -f "$TCUSERVER_FILE" ]; then
    if ! grep -q "$TC_INSTRUMENT_MARKER" "$TCUSERVER_FILE"; then
        bashio::log.info "Instrumenting tcuserver.py with V9 Unified Logging..."
        python3 - <<'EOF'
import sys
import os

file_path = "/opt/opencarwings/tculink/management/commands/tcuserver.py"
with open(file_path, 'r') as f:
    lines = f.readlines()

new_lines = [ "# --- OpenCarwings Instrumentation Patch V10 ---\n" ]
CMD_MAP = '{1: "Refresh data", 2: "Start Charge", 3: "AC On", 4: "AC Off", 5: "Read TCU Config", 6: "Set Auth"}'

connection_logged_injected = False
in_charge_result = False
comment_depth = 0

for i, line in enumerate(lines):
    indent = line[:len(line) - len(line.lstrip())]
    
    # 0. Initialize flags at start of handle_client loop/function
    if "authenticated = False" in line and not connection_logged_injected:
        new_lines.append(line)
        new_lines.append(f"{indent}connection_logged = False\n")
        new_lines.append(f"{indent}auth_logged = False\n")
        new_lines.append(f"{indent}CMD_MAP = {CMD_MAP}\n")
        connection_logged_injected = True
        continue

    # 1. Comment out basicConfig and print/stdout.write
    targets = ["logging.basicConfig(", "self.stdout.write(", "print("]
    if any(t in line for t in targets) and "logger" not in line and comment_depth == 0:
        comment_depth = line.count('(') - line.count(')')
        new_lines.append(f"{indent}# {line.lstrip()}")
        if comment_depth == 0: continue
        continue
    
    # V10 Logging Refinements (Comprehensive Alerts & No Emojis)
    if comment_depth > 0:
        new_lines.append(f"{indent}# {line.lstrip()}")
        comment_depth += line.count('(') - line.count(')')
        if comment_depth <= 0: comment_depth = 0
        continue

    # 1.1 Auth Bypass Log -> DEBUG
    if "TCU Authentication check status:" in line:
        new_lines.append(f"{indent}bypass_msg = f\"Auth bypass enabled (disable_auth=True)\" if authenticated else f\"Auth required (disable_auth=False)\"\n")
        new_lines.append(f"{indent}logger.debug(bypass_msg)\n")
        continue

    # 2. Downgrade verbose INFO logs to DEBUG & Inject Summaries
    
    # TCU Info -> Removed (Merged into check-in log)
    if 'logger.info(f"TCU Info:' in line:
        continue

    # GPS Data -> Removed (Redundant)
    if 'logger.info(f"GPS Data:' in line:
        continue

    # Auth Data -> Removed (Redundant, keep Authenticated summary)
    if 'logger.info(f"Auth Data:' in line:
        new_lines.append(f"{indent}if parsed_data.get('auth') and not auth_logged:\n")
        new_lines.append(f"{indent}    logger.debug(f\"Authenticated: {{parsed_data['auth'].get('user', '?')}}\")\n")
        new_lines.append(f"{indent}    auth_logged = True\n")
        continue

    # 2.1 Always log full parsed data at DEBUG
    if 'parsed_data = parse_gdc_packet(data)' in line:
        new_lines.append(line)
        new_lines.append(f"{indent}logger.debug(f\"Raw Parsed Data: {{parsed_data}}\")\n")
        new_lines.append(f"{indent}if parsed_data.get('message_type') == (3, 'DATA') and getattr(car, 'pending_refresh_feedback', False):\n")
        new_lines.append(f"{indent}    logger.info(f\"Refresh data completed for {{car.nickname}}\")\n")
        new_lines.append(f"{indent}    car.pending_refresh_feedback = False\n")
        continue

    # Body Type -> Removed (Redundant)
    if 'logger.info(f"Body Type:' in line:
        continue

    # 2.2 Refine Charge Result Status (Differentiate Unplugged)
    if 'if body_type == "charge_result":' in line:
        in_charge_result = True
    
    if in_charge_result and "new_alert.type = 2" in line:
        new_lines.append(f"{indent}new_alert.type = 3 if req_body.get('resultstate') == 17 else 2\n")
        in_charge_result = False
        continue
        
    if 'logger.info("Connection closed")' in line:
        new_lines.append(line.replace("logger.info", "logger.debug"))
        continue

    # 3. Inject EV Status Summary (Removed manual injection, now handled by Alerts)
    if "car.ev_info.last_updated = timezone.now()" in line:
        new_lines.append(line)
        continue

    # 4. Inject Config Summary (Removed manual injection, now handled by Alerts)
    if 'logger.info(f"Car Config:' in line:
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
        
        new_lines.append(f"{indent}if _b_type == 'ac_result':\n")
        new_lines.append(f"{indent}    if r_state == 64: detail_msg = 'A/C Started successfully'\n")
        new_lines.append(f"{indent}    elif r_state == 32: detail_msg = 'A/C Stopped successfully'\n")
        new_lines.append(f"{indent}    elif r_state == 192: detail_msg = 'A/C Finished / Auto-off'\n")
        new_lines.append(f"{indent}    else: detail_msg = f'A/C Error/Unknown (State {{r_state}})'\n")
        
        new_lines.append(f"{indent}elif _b_type == 'remote_stop':\n")
        new_lines.append(f"{indent}    if a_state in [4, 68]: detail_msg = 'Normal Charge Finished'\n")
        new_lines.append(f"{indent}    elif a_state == 8: detail_msg = 'Quick Charge Finished'\n")
        new_lines.append(f"{indent}    else: detail_msg = f'A/C Finished / Default (State {{a_state}})'\n")
        
        new_lines.append(f"{indent}elif _b_type == 'charge_result':\n")
        new_lines.append(f"{indent}    if r_state == 17: detail_msg = 'Vehicle Unplugged (Cable Reminder)'\n")
        new_lines.append(f"{indent}    else: detail_msg = f'Charge Started (State {{r_state}})'\n")
        
        new_lines.append(f"{indent}msg = ALERT_MAP.get(new_alert.type, f'SYSTEM ALERT [Type {{new_alert.type}}]')\n")
        new_lines.append(f"{indent}if detail_msg:\n")
        new_lines.append(f"{indent}    msg += f': {{detail_msg}}'\n")
        new_lines.append(f"{indent}elif new_alert.additional_data:\n")
        new_lines.append(f"{indent}    msg += f': {{new_alert.additional_data}}'\n")
        
        new_lines.append(f"{indent}alert_logger = logger.error if new_alert.type >= 96 else logger.info\n")
        new_lines.append(f"{indent}alert_logger(msg)\n")
    
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
        new_lines.append(f"{indent}logger.info(f\"Car state saved to database for VIN: {{car.vin}}\")\n")
        continue

    # 7. Command Parsing (No Emoji)
    if "Command found:" in line:
        cmd_name = 'CMD_MAP.get(car.command_type, "Unknown")'
        new_lines.append(f"{indent}if car.command_type == 1: car.pending_refresh_feedback = True\n")
        # Consolidated delivery log as requested by user
        new_lines.append(f"{indent}logger.info(f\"Vehicle connected: {{ {cmd_name} }} command delivered\")\n")
        new_lines.append(f"{indent}# {line.lstrip()}")
        continue

    if 'logger.info("No command or another in progress, send success false")' in line:
        new_lines.append(f"{indent}logger.info(f\"Vehicle check-in: {{car.nickname}} (VIN: {{car.vin}})\")\n")
        new_lines.append(f"{indent}# {line.lstrip()}")
        continue

    # 8. Patch error handler: reset command_result on processing failure
    if '"Processing packet failed"' in line:
        new_lines.append(line)
        new_lines.append(f"{indent}try:\n")
        new_lines.append(f"{indent}    if car and car.command_result == 3:\n")
        new_lines.append(f"{indent}        car.command_result = 1\n")
        new_lines.append(f"{indent}        car.command_requested = False\n")
        new_lines.append(f"{indent}        await sync_to_async(car.save)()\n")
        new_lines.append(f"{indent}        logger.warning(f\"Command state reset to FAILED for {{car.nickname}} due to processing error\")\n")
        new_lines.append(f"{indent}except: pass\n")
        continue

    new_lines.append(line)

with open(file_path, 'w') as f:
    f.writelines(new_lines)
EOF
    else
        bashio::log.info "tcuserver.py already patched with V10+ logging."
    fi
else
    bashio::log.warning "tcuserver.py not found, skipping instrumentation."
fi

# --- Patch 6: Instrument api/views.py for Command Initiation ---
VIEWS_FILE="/opt/opencarwings/api/views.py"
VIEWS_PATCH_MARKER="# --- OpenCarwings Command Init Patch ---"

if [ -f "$VIEWS_FILE" ]; then
    if ! grep -q "$VIEWS_PATCH_MARKER" "$VIEWS_FILE"; then
        bashio::log.info "Instrumenting api/views.py for Command Initiation..."
        python3 - <<'EOF'
import sys

file_path = "/opt/opencarwings/api/views.py"
with open(file_path, 'r') as f:
    lines = f.readlines()

new_lines = [ "# --- OpenCarwings Command Init Patch ---\n" ]
for line in lines:
    indent = line[:len(line) - len(line.lstrip())]
    
    if "command_type = request.data.get('command_type')" in line:
        new_lines.append(line)
        new_lines.append(f"{indent}import logging\n")
        new_lines.append(f"{indent}logger = logging.getLogger('tculink')\n")
        new_lines.append(f"{indent}CMD_MAP = {{1: 'Refresh data', 2: 'Start Charge', 3: 'A/C On', 4: 'A/C Off', 5: 'Read TCU config', 6: 'Set Auth'}}\n")
        new_lines.append(f"{indent}try:\n")
        new_lines.append(f"{indent}    c_name = CMD_MAP.get(int(command_type), f'Type {{command_type}}')\n")
        new_lines.append(f"{indent}    logger.info(f\"{{c_name}} command initiated for {{car.nickname}} (VIN: {{vin}})\")\n")
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

# --- Patch 7: Clear stale commands on startup ---
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

