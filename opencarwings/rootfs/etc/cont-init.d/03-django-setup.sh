#!/command/with-contenv bashio
# shellcheck shell=bash

cd /opt/opencarwings

# Set environment variables from add-on config
export TZ=$(bashio::config 'timezone' 'UTC')
export LOG_LEVEL=$(bashio::config 'log_level' 'info')
export ACTIVATION_SMS_MESSAGE="NISSAN_EVIT_TELEMATICS_CENTER"

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