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

# --- Patch 3: Force Console Logging & Dynamic Debug Level ---
# We force all logs to the console so we can debug.
# We also dynamically set the log level based on the DEBUG env var.

LOGGING_PATCH_MARKER="# --- OpenCarwings Logging Patch ---"

if ! grep -q "$LOGGING_PATCH_MARKER" "$SETTINGS_FILE"; then
    bashio::log.info "Patching settings.py for Console Logging & Debug Level..."
    cat <<'EOF' >> "$SETTINGS_FILE"

# --- OpenCarwings Logging Patch ---
import os
import sys

# Determine log level based on DEBUG environment variable
DEBUG_MODE = os.environ.get('DEBUG', 'False') == 'True'
LOG_LEVEL = 'DEBUG' if DEBUG_MODE else 'INFO'

# Overwrite logging to ensure everything goes to stdout/stderr
LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'handlers': {
        'console': {
            'class': 'logging.StreamHandler',
            'stream': sys.stdout,
        },
    },
    'root': {
        'handlers': ['console'],
        'level': LOG_LEVEL,
    },
    'loggers': {
        'django': {
            'handlers': ['console'],
            'level': 'INFO',  # Keep django quiet unless critical, even in debug
            'propagate': False,
        },
        'carwings': {
            'handlers': ['console'],
            'level': LOG_LEVEL,
            'propagate': True,
        },
        'tcuserver': {
            'handlers': ['console'],
            'level': 'DEBUG', # Force DEBUG for tcuserver to see everything
            'propagate': True,
        },
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


# --- Patch 5: Instrument TCUserver for Debugging ---
# We inject a log message right at the start of handle_client to see if connections reach Python.
TCUSERVER_FILE="/opt/opencarwings/tculink/management/commands/tcuserver.py"

if [ -f "$TCUSERVER_FILE" ]; then
    bashio::log.info "Instrumenting tcuserver.py for connection debugging..."
    # Inject logging after the function definition
    sed -i "/async def handle_client(self, reader, writer):/a \\        logger.info(f'CONNECTION DEBUG: New connection from {writer.get_extra_info(\"peername\")}')" "$TCUSERVER_FILE"
else
    bashio::log.warning "Could not find tcuserver.py to instrument!"
fi

