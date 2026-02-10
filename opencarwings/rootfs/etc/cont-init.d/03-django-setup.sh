#!/command/with-contenv bashio
# shellcheck shell=bash

cd /opt/opencarwings

# Set environment variables from add-on config
export TZ=$(bashio::config 'timezone' 'UTC')
export LOG_LEVEL=$(bashio::config 'log_level' 'info')
export ACTIVATION_SMS_MESSAGE="NISSAN_EVIT_TELEMATICS_CENTER"

# Ensure persistent logs directory
if [ ! -L "logs" ]; then
    bashio::log.info "Configuring persistent logs..."
    mkdir -p /data/logs
    [ -d "logs" ] && rm -rf logs
    ln -s /data/logs logs
fi

# Database configuration - use local PostgreSQL
export PSQL_DATABASE=carwings
export PSQL_USER=carwings_user
export PSQL_PASSWORD=secure_password
export PSQL_DATABASE_HOST=localhost
export PSQL_DATABASE_PORT=5432
export REDIS_HOST=localhost
export REDIS_PORT=6379

# Add current directory to Python path
export PYTHONPATH="/opt/opencarwings${PYTHONPATH:+:$PYTHONPATH}"

bashio::log.info "Setting up Django configuration..."

# Use the existing settings.docker.py file
if [ -f "carwings/settings.docker.py" ]; then
    cp carwings/settings.docker.py carwings/settings.py
    bashio::log.info "Using settings.docker.py as base"
    
    # Modify settings for addon environment
    sed -i "s/ALLOWED_HOSTS = .*/ALLOWED_HOSTS = ['*']/" carwings/settings.py
    
    # Update DEBUG based on log level
    if [ "$(bashio::config 'log_level')" = "debug" ]; then
        sed -i "s/DEBUG = .*/DEBUG = True/" carwings/settings.py
    else
        sed -i "s/DEBUG = .*/DEBUG = False/" carwings/settings.py
    fi
    
    # Build CSRF trusted origins list
    TRUSTED_ORIGINS="['http://homeassistant.local:8124', 'http://localhost:8124', 'http://127.0.0.1:8124'"
    
    # Add user's domains if configured (with wildcard for all subdomains)
    if bashio::config.has_value 'trusted_domains'; then
        for domain in $(bashio::config 'trusted_domains'); do
            TRUSTED_ORIGINS="${TRUSTED_ORIGINS}, 'https://*.${domain}', 'http://*.${domain}'"
            bashio::log.info "Added trusted domain: ${domain}"
        done
    fi
    
    TRUSTED_ORIGINS="${TRUSTED_ORIGINS}]"
    
    # Append CSRF configuration to settings
    echo "
# CSRF trusted origins configuration (for web UI security)
CSRF_TRUSTED_ORIGINS = ${TRUSTED_ORIGINS}
" >> carwings/settings.py
    
    bashio::log.info "CSRF trusted origins configured"
    
    export DJANGO_SETTINGS_MODULE="carwings.settings"

    # ==========================================================================
    # UPSTREAM COMPATIBILITY PATCHES
    # The following block patches the upstream OpenCarwings source code to fix
    # issues that are either specific to the HA addon environment (like Python 3.12)
    # or bugs in error handling that cause server crashes.
    # ==========================================================================

    # 1. Inject API Keys from configuration
    OCM_KEY=$(bashio::config 'ocm_api_key' '' | xargs)
    ITERNIO_KEY=$(bashio::config 'iternio_api_key' '' | xargs)
    
    # Use | as delimiter to handle cases where API keys might contain /
    sed -i "s|OPENCHARGEMAP_API_KEY = .*|OPENCHARGEMAP_API_KEY = '${OCM_KEY}'|" carwings/settings.py
    sed -i "s|ITERNIO_API_KEY = .*|ITERNIO_API_KEY = '${ITERNIO_KEY}'|" carwings/settings.py
    # 2. Robust Compatibility and Stability Patching
    # This Python block handles both regex syntax fixes and API error handling.
    # It is designed to be idempotent and resilient to minor upstream changes.
    bashio::log.info "Applying system compatibility and crash prevention patches..."
    
    python3 - << 'EOF'
import os
import re
import sys

def patch_file(path, search_str, replacement, description):
    if not os.path.exists(path):
        return
    with open(path, 'r') as f:
        content = f.read()
    
    # Idempotent replacement
    if search_str in content:
        new_content = content.replace(search_str, replacement)
        with open(path, 'w') as f:
            f.write(new_content)
        print(f"[INFO] {description} patched in {path}")
    else:
        print(f"[DEBUG] {description} in {path} already correct or pattern not found.")

# Fix Python 3.12 SyntaxWarnings for invalid escape sequence '\D'
# We replace the exact forbidden patterns with their raw string equivalents
patch_file("ui/views.py", "re.sub('\\D'", "re.sub(r'\\D'", "Python 3.12 regex syntax")
patch_file("tculink/sms/46elks.py", "re.sub('\\D'", "re.sub(r'\\D'", "Python 3.12 regex syntax")

# Patch CP application for crash prevention (graceful OCM/Iternio handling)
cp_path = "tculink/carwings_proto/applications/cp.py"
if os.path.exists(cp_path):
    with open(cp_path, 'r') as f:
        content = f.read()
    
    if 'if not settings.OPENCHARGEMAP_API_KEY' in content:
        print("[DEBUG] CP application already patched.")
    else:
        print("[INFO] Patching CP application for crash prevention...")
        
        # Patch OCM (Req ID 277)
        old_ocm_block = """            chargers_resp = requests.get('https://api.openchargemap.io/v3/poi', params={
                'client': 'OpenCARWINGS',
                'compact': 'true',
                # Type 1,2 & Chademo
                'connectiontypeid': '2,1,25',
                'boundingbox': ",".join([str(boundingbox_tl), str(boundingbox_br)]),
                'maxresults': "10000",
            }, headers={'X-API-Key': settings.OPENCHARGEMAP_API_KEY})
            try:
                chargers_resp = chargers_resp.json()
            except Exception as e:
                logger.error("Failed to parse OCM chargers, response: status %d, %s", chargers_resp.status_code, chargers_resp.text)
                raise e"""

        new_ocm_block = """            if not settings.OPENCHARGEMAP_API_KEY or not settings.OPENCHARGEMAP_API_KEY.strip():
                logger.warning("OpenChargeMap API Key missing, skipping station update.")
                chargers_resp = []
            else:
                try:
                    chargers_resp = requests.get('https://api.openchargemap.io/v3/poi', params={
                        'client': 'OpenCARWINGS',
                        'compact': 'true',
                        # Type 1,2 & Chademo
                        'connectiontypeid': '2,1,25',
                        'boundingbox': ",".join([str(boundingbox_tl), str(boundingbox_br)]),
                        'maxresults': "10000",
                    }, headers={'X-API-Key': settings.OPENCHARGEMAP_API_KEY.strip()})
                    if chargers_resp.status_code != 200:
                        logger.error("OCM API returned status %d", chargers_resp.status_code)
                        chargers_resp = []
                    else:
                        chargers_resp = chargers_resp.json()
                except Exception as e:
                    logger.error("Failed to fetch OCM stations: %s", str(e))
                    chargers_resp = []"""

        # Patch Iternio (Req ID 281)
        old_iternio_block = """            chargers = requests.get("https://api.iternio.com/1/get_chargers", params={
                'lat': str(location_center[0]),
                'lon': str(location_center[1]),
                'radius': '35000',
                'types': 'j1772,type2,chademo',
                'sort_by_distance': 'true',
                'sort_by_power': 'false',
                'limit': '100'
            }, headers={"User-Agent": "OpenCARWINGS", "Authorization": f"APIKEY {settings.ITERNIO_API_KEY}"})
            try:
                chargers = chargers.json().get("result", [])
            except Exception as e:
                logger.error("Failed to parse iternio chargers, response: status %d, %s", chargers.status_code, chargers.text)
                raise e"""

        new_iternio_block = """            if not settings.ITERNIO_API_KEY or not settings.ITERNIO_API_KEY.strip():
                logger.warning("Iternio API Key missing, skipping nearby station update.")
                chargers = []
            else:
                try:
                    chargers = requests.get("https://api.iternio.com/1/get_chargers", params={
                        'lat': str(location_center[0]),
                        'lon': str(location_center[1]),
                        'radius': '35000',
                        'types': 'j1772,type2,chademo',
                        'sort_by_distance': 'true',
                        'sort_by_power': 'false',
                        'limit': '100'
                    }, headers={"User-Agent": "OpenCARWINGS", "Authorization": f"APIKEY {settings.ITERNIO_API_KEY.strip()}"})
                    if chargers.status_code != 200:
                        logger.error("Iternio API returned status %d", chargers.status_code)
                        chargers = []
                    else:
                        chargers = chargers.json().get("result", [])
                except Exception as e:
                    logger.error("Failed to fetch iternio stations: %s", str(e))
                    chargers = []"""

        content = content.replace(old_ocm_block, new_ocm_block)
        content = content.replace(old_iternio_block, new_iternio_block)
        
        with open(cp_path, 'w') as f:
            f.write(content)
        print("[INFO] CP application patched successfully.")
EOF
else
    bashio::log.error "settings.docker.py not found!"
    exit 1
fi

# Wait for local database to be ready
bashio::log.info "Waiting for local database to be ready..."
sleep 5

# Try to run Django migrations
bashio::log.info "Running Django migrations..."
if python manage.py migrate --noinput 2>&1; then
    bashio::log.info "Django migrations completed successfully"
else
    bashio::log.warning "Django migrations failed, but continuing..."
fi

# Collect static files
bashio::log.info "Collecting static files..."
python manage.py collectstatic --noinput --clear 2>/dev/null || true

bashio::log.info "Django setup completed"