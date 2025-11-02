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

# Add current directory to Python path
export PYTHONPATH="/opt/opencarwings${PYTHONPATH:+:$PYTHONPATH}"

# Check what settings files exist
bashio::log.info "Checking Django settings structure..."
find . -name "settings*.py" -type f

# Try to determine the correct settings module
if [ -f "carwings/settings/docker.py" ]; then
    export DJANGO_SETTINGS_MODULE="carwings.settings.docker"
    bashio::log.info "Found carwings/settings/docker.py"
elif [ -f "carwings/settings.py" ]; then
    export DJANGO_SETTINGS_MODULE="carwings.settings"
    bashio::log.info "Found carwings/settings.py"
else
    bashio::log.warning "No Django settings found, will create basic settings"
    # Create a minimal settings file
    mkdir -p carwings
    cat > carwings/__init__.py << 'EOF'
# Empty init file
EOF
    cat > carwings/settings.py << 'EOF'
import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent

SECRET_KEY = os.environ.get('SECRET_KEY', 'django-insecure-default-key-change-in-production')

DEBUG = os.environ.get('DEBUG', 'False').lower() == 'true'

ALLOWED_HOSTS = ['*']

INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    'crispy_forms',
    'crispy_bootstrap4',
    'api',
    'carwings',
    'db',
    'ui',
]

AUTH_USER_MODEL = 'db.User'

CRISPY_ALLOWED_TEMPLATE_PACKS = "bootstrap4"
CRISPY_TEMPLATE_PACK = "bootstrap4"

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

ROOT_URLCONF = 'carwings.urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [
            BASE_DIR / 'ui' / 'templates',
            BASE_DIR / 'templates',
        ],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.debug',
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': os.environ.get('PSQL_DATABASE', 'carwings'),
        'USER': os.environ.get('PSQL_USER', 'carwings_user'),
        'PASSWORD': os.environ.get('PSQL_PASSWORD', 'secure_password'),
        'HOST': os.environ.get('PSQL_DATABASE_HOST', 'localhost'),
        'PORT': os.environ.get('PSQL_DATABASE_PORT', '5432'),
    }
}

CACHES = {
    'default': {
        'BACKEND': 'django.core.cache.backends.redis.RedisCache',
        'LOCATION': f"redis://{os.environ.get('REDIS_HOST', 'localhost')}:{os.environ.get('REDIS_PORT', '6379')}",
    }
}

LANGUAGE_CODE = 'en-us'
TIME_ZONE = os.environ.get('TZ', 'UTC')
USE_I18N = True
USE_TZ = True

STATIC_URL = 'static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'

# SMS Providers configuration (required by upstream code)
SMS_PROVIDERS = {}

DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'
EOF

    export DJANGO_SETTINGS_MODULE="carwings.settings"
    bashio::log.info "Created basic Django settings"
fi

# Wait for local database to be ready (PostgreSQL should already be running from previous script)
bashio::log.info "Waiting for local database to be ready..."
sleep 5  # Brief wait since PostgreSQL was started in previous script

# Try to run Django migrations
bashio::log.info "Running Django migrations..."
if python manage.py migrate --noinput --skip-checks 2>&1; then
    bashio::log.info "Django migrations completed successfully"
else
    bashio::log.warning "Django migrations failed, but continuing..."
fi

# Collect static files
bashio::log.info "Collecting static files..."
python manage.py collectstatic --noinput --clear 2>/dev/null || true

bashio::log.info "Django setup completed"