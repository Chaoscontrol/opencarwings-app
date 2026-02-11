#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

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
