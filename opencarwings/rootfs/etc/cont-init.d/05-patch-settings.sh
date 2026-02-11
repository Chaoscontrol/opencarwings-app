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
