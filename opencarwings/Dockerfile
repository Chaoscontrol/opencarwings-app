ARG BUILD_FROM
FROM ${BUILD_FROM}

# Install system dependencies
RUN apk add --no-cache \
    python3 \
    py3-pip \
    postgresql \
    postgresql-contrib \
    redis \
    git \
    build-base \
    python3-dev \
    postgresql-dev \
    gosu \
    postgresql-client \
    curl \
    libffi-dev \
    openssl-dev \
    && python3 -m pip install --upgrade pip

# Clone OpenCarwings upstream
ARG UPSTREAM_REF=main
WORKDIR /opt
RUN git clone --depth 1 --branch "${UPSTREAM_REF}" \
    https://github.com/developerfromjokela/opencarwings.git opencarwings

# Install Python dependencies
WORKDIR /opt/opencarwings
RUN pip3 install -r requirements.txt psycopg2-binary \
    daphne channels channels-redis \
    django-crispy-forms crispy-tailwind \
    whitenoise djangorestframework djangorestframework-simplejwt \
    django-mathfilters drf-yasg
    
# Create directories for data persistence
RUN mkdir -p /data/postgres /data/redis /data/static /data/media /data/logs

# Configure PostgreSQL
RUN mkdir -p /run/postgresql && chown postgres:postgres /run/postgresql

# Copy root filesystem
COPY rootfs/ /

# Set permissions for service scripts
RUN chmod +x /etc/cont-init.d/*.sh || true
RUN chmod +x /etc/services.d/*/run || true

# Set environment variables
ENV PSQL_DATABASE=carwings \
    PSQL_USER=carwings_user \
    PSQL_PASSWORD=secure_password \
    PSQL_DATABASE_HOST=localhost \
    PSQL_DATABASE_PORT=5432 \
    REDIS_HOST=localhost \
    REDIS_PORT=6379 \
    BACKEND_PORT=8124 \
    TCPSERVER_PORT=55230 \
    SECRET_KEY=django-insecure-default-key-change-in-production

# Expose ports
EXPOSE 8124 8125 55230

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8899/health || exit 1