#!/command/with-contenv bashio
# shellcheck shell=bash

bashio::log.info "=== Starting PostgreSQL and Redis Setup ==="

# Create PostgreSQL directories and set permissions
bashio::log.info "Creating PostgreSQL directories..."
mkdir -p /data/postgres /run/postgresql
chown -R postgres:postgres /data/postgres /run/postgresql
chmod 700 /data/postgres
bashio::log.info "PostgreSQL directories created and permissions set"

# Initialize PostgreSQL database if not already done
if [ ! -f "/data/postgres/PG_VERSION" ]; then
    bashio::log.info "Initializing PostgreSQL database..."
    gosu postgres initdb -D /data/postgres --username=postgres --encoding=UTF8 --lc-collate=C --lc-ctype=C 2>&1
    if [ $? -eq 0 ]; then
        bashio::log.info "PostgreSQL database initialized successfully"
    else
        bashio::log.error "Failed to initialize PostgreSQL database"
        exit 1
    fi
else
    bashio::log.info "PostgreSQL database already initialized"
fi

# Create basic PostgreSQL config
bashio::log.info "Creating PostgreSQL configuration..."
cat > /data/postgres/postgresql.conf << 'EOF'
listen_addresses = 'localhost'
port = 5432
max_connections = 20
shared_buffers = 128MB
dynamic_shared_memory_type = posix
max_wal_size = 1GB
min_wal_size = 80MB
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
log_statement = 'ddl'
logging_collector = on
log_directory = '/data/postgres'
log_filename = 'postgresql.log'
EOF

# Create pg_hba.conf for local connections
bashio::log.info "Creating PostgreSQL authentication configuration..."
cat > /data/postgres/pg_hba.conf << 'EOF'
local all all trust
host all all 127.0.0.1/32 trust
host all all ::1/128 trust
EOF

# Start PostgreSQL
bashio::log.info "Starting PostgreSQL service..."
gosu postgres pg_ctl -D /data/postgres -l /data/postgres/logfile -o "-c listen_addresses='localhost'" start 2>&1
if [ $? -eq 0 ]; then
    bashio::log.info "PostgreSQL service started successfully"
else
    bashio::log.error "Failed to start PostgreSQL service"
    exit 1
fi

# Wait for PostgreSQL to be ready - longer wait with logging
bashio::log.info "Waiting for PostgreSQL to be ready..."
for i in {1..60}; do
    bashio::log.debug "Checking PostgreSQL readiness (attempt $i/60)..."
    if gosu postgres psql -U postgres -c 'SELECT 1;' > /dev/null 2>&1; then
        bashio::log.info "PostgreSQL is ready and accepting connections"
        break
    fi
    if [ $i -eq 60 ]; then
        bashio::log.error "PostgreSQL failed to become ready after 60 attempts"
        exit 1
    fi
    sleep 2
done

# Create database and user with proper schema permissions
bashio::log.info "Creating database and user..."
if gosu postgres psql -U postgres -c "CREATE DATABASE carwings;" 2>/dev/null; then
    bashio::log.info "Database 'carwings' created"
else
    bashio::log.warning "Database 'carwings' may already exist"
fi

if gosu postgres psql -U postgres -c "CREATE USER carwings_user WITH ENCRYPTED PASSWORD 'secure_password';" 2>/dev/null; then
    bashio::log.info "User 'carwings_user' created"
else
    bashio::log.warning "User 'carwings_user' may already exist"
fi

# Grant schema permissions to the user
if gosu postgres psql -U postgres -d carwings -c "GRANT ALL ON SCHEMA public TO carwings_user;" 2>/dev/null; then
    bashio::log.info "Schema permissions granted to user"
else
    bashio::log.warning "Failed to grant schema permissions"
fi

if gosu postgres psql -U postgres -d carwings -c "GRANT ALL PRIVILEGES ON DATABASE carwings TO carwings_user;" 2>/dev/null; then
    bashio::log.info "Database privileges granted to user"
else
    bashio::log.warning "Failed to grant database privileges (may already be granted)"
fi

# Test database connection
bashio::log.info "Testing database connection..."
if gosu postgres psql -U carwings_user -d carwings -c 'SELECT version();' > /dev/null 2>&1; then
    bashio::log.info "Database connection test successful"
else
    bashio::log.error "Database connection test failed"
    exit 1
fi

# Start Redis with memory overcommit fix
bashio::log.info "Starting Redis..."
# Try to set memory overcommit, ignore if read-only filesystem
if sysctl -w vm.overcommit_memory=1 2>/dev/null; then
    bashio::log.info "Set vm.overcommit_memory=1 successfully"
else
    bashio::log.warning "Could not set vm.overcommit_memory (read-only filesystem) - this is normal in HA containers"
fi
redis-server --daemonize yes --port 6379 --loglevel notice --logfile /data/redis.log

# Wait for Redis to start
bashio::log.info "Waiting for Redis to be ready..."
sleep 5

# Test Redis connection
if redis-cli ping > /dev/null 2>&1; then
    bashio::log.info "Redis is ready and responding to ping"
else
    bashio::log.error "Redis failed to start or is not responding"
    exit 1
fi

bashio::log.info "=== Database setup completed successfully ==="