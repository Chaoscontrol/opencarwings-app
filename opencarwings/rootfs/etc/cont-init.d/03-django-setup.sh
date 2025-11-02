#!/command/with-contenv bashio
# shellcheck shell=bash

cd /opt/opencarwings

# Set environment variables from add-on config
export TZ=$(bashio::config 'timezone' 'UTC')
export LOG_LEVEL=$(bashio::config 'log_level' 'info')
export ACTIVATION_SMS_MESSAGE="ACTIVATE"

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
    sed -i "s/DEBUG = .*/DEBUG = True/" carwings/settings.py  # Change to False in production
    
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