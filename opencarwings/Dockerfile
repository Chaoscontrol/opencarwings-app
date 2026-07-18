FROM ghcr.io/hassio-addons/base:20.2.0

ARG BUILD_VERSION="0.0.0"
ARG BUILD_ARCH="amd64"

LABEL \
    io.hass.type="addon" \
    io.hass.name="OpenCarwings" \
    io.hass.description="Nissan CARWINGS-compatible server" \
    io.hass.url="https://github.com/Chaoscontrol/opencarwings-app" \
    io.hass.version="${BUILD_VERSION}" \
    io.hass.arch="${BUILD_ARCH}"

# Install system dependencies. LibreSSL supplies the certificate-generation CLI
# without upgrading the OpenSSL runtime libraries pinned by the base image.
# postgresql17-dev is intentionally omitted: psycopg2-binary does not compile
# against it, and the available dev dependency set pulls openssl-dev newer than
# the runtime pinned by base 20.2.0, making apk reject the valid runtime image.
RUN apk add --no-cache \
    python3 \
    py3-pip \
    py3-setuptools \
    postgresql17 \
    postgresql17-contrib \
    redis \
    git \
    gosu \
    postgresql17-client \
    curl \
    libressl \
    nginx \
    netcat-openbsd \
    pngquant \
    dos2unix \
    && ln -sf /usr/bin/libressl-openssl /usr/local/bin/openssl \
    && printf '%s\n' \
        '[req]' \
        'distinguished_name = req_distinguished_name' \
        '[req_distinguished_name]' \
        > /etc/ssl/libressl.cnf \
    && python3 -m pip --version \
    && command -v openssl \
    && openssl version \
    && openssl req -x509 -nodes -days 1 -newkey rsa:2048 \
        -keyout /tmp/opencarwings-smoke.key \
        -out /tmp/opencarwings-smoke.pem \
        -subj '/CN=opencarwings-build-smoke' >/dev/null 2>&1 \
    && test -s /tmp/opencarwings-smoke.key \
    && test -s /tmp/opencarwings-smoke.pem \
    && rm -f /tmp/opencarwings-smoke.key /tmp/opencarwings-smoke.pem

# Clone OpenCarwings upstream
COPY .upstream_sync /tmp/upstream_sync_marker
WORKDIR /opt
RUN test "$(wc -l < /tmp/upstream_sync_marker)" -eq 1 \
    && grep -Eq '^[0-9a-f]{40}$' /tmp/upstream_sync_marker \
    && UPSTREAM_COMMIT="$(cat /tmp/upstream_sync_marker)" \
    && git init opencarwings \
    && git -C opencarwings remote add origin https://github.com/developerfromjokela/opencarwings.git \
    && git -C opencarwings fetch --depth 1 origin "${UPSTREAM_COMMIT}" \
    && git -C opencarwings checkout --detach "${UPSTREAM_COMMIT}" \
    && test "$(git -C opencarwings rev-parse HEAD)" = "${UPSTREAM_COMMIT}"

# Install Python dependencies
WORKDIR /opt/opencarwings
RUN python3 -m pip install --no-cache-dir --break-system-packages --only-binary=:all: \
    -r requirements.txt psycopg2-binary \
    daphne channels channels-redis \
    django-crispy-forms crispy-tailwind \
    whitenoise djangorestframework djangorestframework-simplejwt \
    django-mathfilters drf-yasg \
    && python3 -m pip check

# Install FRP client binary (frpc) for optional VPS relay mode.
ARG FRP_VERSION=0.64.0
RUN curl -fsSL "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_amd64.tar.gz" -o /tmp/frp.tar.gz \
    && tar -xzf /tmp/frp.tar.gz -C /tmp \
    && mv "/tmp/frp_${FRP_VERSION}_linux_amd64/frpc" /usr/local/bin/frpc \
    && chmod +x /usr/local/bin/frpc \
    && rm -rf /tmp/frp.tar.gz "/tmp/frp_${FRP_VERSION}_linux_amd64"


# Create directories for data persistence
RUN mkdir -p /data/postgres /data/redis /data/static /data/media /data/logs

# Configure PostgreSQL
RUN mkdir -p /run/postgresql && chown postgres:postgres /run/postgresql

# Copy root filesystem
COPY rootfs/ /

# Set permissions for service scripts
# Fix Windows line endings and set permissions
RUN dos2unix /etc/cont-init.d/*.sh && \
    dos2unix /etc/services.d/*/run && \
    chmod +x /etc/cont-init.d/*.sh && \
    chmod +x /etc/services.d/*/run


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
