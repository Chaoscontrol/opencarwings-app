#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
# ==========================================================================
# Shared environment variables for all OpenCarwings services.
# Source this file from any service script that needs Django/DB access.
# ==========================================================================

# Database
export PSQL_DATABASE=carwings
export PSQL_USER=carwings_user
export PSQL_PASSWORD=secure_password
export PSQL_DATABASE_HOST=localhost
export PSQL_DATABASE_PORT=5432

# Redis
export REDIS_HOST=localhost
export REDIS_PORT=6379

# Django
export PYTHONPATH="/opt/opencarwings${PYTHONPATH:+:$PYTHONPATH}"
export DJANGO_SETTINGS_MODULE=carwings.settings
export SECRET_KEY=django-insecure-default-key-change-in-production

# Debug mode — only enable when log_level is set to debug
if [ "$(bashio::config 'log_level')" = "debug" ]; then
    export DEBUG=True
else
    export DEBUG=False
fi
