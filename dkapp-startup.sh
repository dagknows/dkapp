#!/bin/bash
# DagKnows Application Startup Script for Systemd
# This script handles environment decryption and container startup

set -e

# Configuration - these are set during setup-autorestart.sh installation
DKAPP_DIR="${DKAPP_DIR:-/opt/dkapp}"
PASSPHRASE_FILE="${PASSPHRASE_FILE:-/root/.dkapp-passphrase}"
ENV_FILE="$DKAPP_DIR/.env"
ENV_GPG="$DKAPP_DIR/.env.gpg"
LOG_FILE="/var/log/dkapp-startup.log"

# Compose file to use (passed as argument)
COMPOSE_FILE="${1:-docker-compose.yml}"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log "Starting DagKnows services using $COMPOSE_FILE"

cd "$DKAPP_DIR"

# Ensure network exists
docker network create saaslocalnetwork 2>/dev/null || true

# Check for passphrase file (auto-restart mode)
if [ -f "$PASSPHRASE_FILE" ]; then
    log "Auto-restart mode: Using passphrase file for decryption"

    # Decrypt environment file
    if [ -f "$ENV_GPG" ]; then
        if gpg --batch --yes --passphrase-file "$PASSPHRASE_FILE" -o "$ENV_FILE" -d "$ENV_GPG" 2>/dev/null; then
            log "Environment decrypted successfully"
        else
            log "ERROR: Failed to decrypt environment file"
            exit 1
        fi
    else
        log "ERROR: No encrypted environment file found at $ENV_GPG"
        exit 1
    fi
elif [ -f "$ENV_FILE" ]; then
    log "Using existing unencrypted .env file"
else
    log "ERROR: No environment configuration found. Run 'make install' first."
    exit 1
fi

# Generate versions.env if version-manifest exists
if [ -f "$DKAPP_DIR/version-manifest.yaml" ]; then
    python3 "$DKAPP_DIR/version-manager.py" generate-env 2>/dev/null || true
fi

# Source versions.env if available, then start containers
if [ -f "$DKAPP_DIR/versions.env" ]; then
    log "Loading version overrides from versions.env"
    set -a && . "$DKAPP_DIR/versions.env" && set +a
fi

log "Starting containers with docker compose -f $COMPOSE_FILE..."
if ! docker compose -f "$DKAPP_DIR/$COMPOSE_FILE" up -d; then
    log "ERROR: Failed to start containers"
    # Still clean up .env file on failure
    if [ -f "$PASSPHRASE_FILE" ] && [ -f "$ENV_FILE" ]; then
        rm -f "$ENV_FILE"
    fi
    exit 1
fi

# Wait for containers to stabilize before starting log capture
log "Waiting for containers to stabilize..."
sleep 3

# Start background log capture
LOG_CAPTURE_DIR="$DKAPP_DIR/logs"
DBLOG_CAPTURE_DIR="$DKAPP_DIR/dblogs"

mkdir -p "$LOG_CAPTURE_DIR" "$DBLOG_CAPTURE_DIR"

if [ "$COMPOSE_FILE" = "db-docker-compose.yml" ]; then
    # Start database log capture
    DBLOG_PID_FILE="$DBLOG_CAPTURE_DIR/.capture.pid"
    if [ ! -f "$DBLOG_PID_FILE" ] || ! kill -0 $(cat "$DBLOG_PID_FILE") 2>/dev/null; then
        log "Starting background database log capture"
        nohup docker compose -f "$DKAPP_DIR/db-docker-compose.yml" logs -f >> "$DBLOG_CAPTURE_DIR/$(date +%Y-%m-%d).log" 2>&1 &
        echo $! > "$DBLOG_PID_FILE"
        log "Database log capture started (PID: $!)"
    else
        log "Database log capture already running (PID: $(cat "$DBLOG_PID_FILE"))"
    fi
elif [ "$COMPOSE_FILE" = "docker-compose.yml" ]; then
    # Start application log capture
    LOG_PID_FILE="$LOG_CAPTURE_DIR/.capture.pid"
    if [ ! -f "$LOG_PID_FILE" ] || ! kill -0 $(cat "$LOG_PID_FILE") 2>/dev/null; then
        log "Starting background application log capture"
        nohup docker compose -f "$DKAPP_DIR/docker-compose.yml" logs -f >> "$LOG_CAPTURE_DIR/$(date +%Y-%m-%d).log" 2>&1 &
        echo $! > "$LOG_PID_FILE"
        log "Application log capture started (PID: $!)"
    else
        log "Application log capture already running (PID: $(cat "$LOG_PID_FILE"))"
    fi
fi

# If passphrase file was used, clean up the decrypted .env file
if [ -f "$PASSPHRASE_FILE" ] && [ -f "$ENV_FILE" ]; then
    rm -f "$ENV_FILE"
    log "Cleaned up decrypted environment file"
fi

log "Startup complete for $COMPOSE_FILE"
