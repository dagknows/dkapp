# Auto-Restart on System Reboot

This document explains how dkapp survives system reboots and automatically restarts all services.

## Overview

DagKnows dkapp uses a combination of Docker restart policies and systemd services to ensure reliable automatic restart after system reboots.

## Why Both Docker Restart Policies AND Systemd?

### Docker `restart: always` Alone is NOT Sufficient

You might wonder: "Why not just use `restart: always` in docker-compose and let Docker handle it?"

**The Problem:**
1. **Encrypted Environment**: dkapp uses GPG-encrypted `.env.gpg` for security
2. **Docker compose needs `.env`**: Containers need environment variables to start
3. **No automatic decryption**: Docker cannot automatically decrypt `.env.gpg` on boot
4. **Result**: With only `restart: always`, containers fail to start because `.env` doesn't exist

**What happens with restart:always alone:**
```
System Boot
    |
    v
Docker Daemon Starts
    |
    v
Docker tries to restart containers
    |
    v
ERROR: .env file not found
(because .env.gpg needs decryption)
```

### Why Systemd is Required

Systemd services provide:

1. **Pre-startup decryption**: Decrypt `.env.gpg` before starting containers
2. **Proper ordering**: Start databases before application services
3. **Health checks**: Wait for PostgreSQL and Elasticsearch to be healthy
4. **Cleanup**: Remove decrypted `.env` after containers start (security)
5. **Logging**: Audit trail in `/var/log/dkapp-startup.log`

**What happens with systemd + restart:always:**
```
System Boot
    |
    v
Docker Daemon Starts
    |
    v
systemd: dkapp-db.service
    |
    +-- Read passphrase from /root/.dkapp-passphrase
    +-- Decrypt .env.gpg -> .env
    +-- docker compose -f db-docker-compose.yml up -d
    +-- Delete .env (security)
    |
    v
systemd: dkapp.service (after dkapp-db)
    |
    +-- Wait for PostgreSQL (pg_isready)
    +-- Wait for Elasticsearch (cluster health)
    +-- Decrypt .env.gpg -> .env
    +-- docker compose up -d
    +-- Delete .env (security)
    |
    v
All Services Running
```

### Why We Still Need `restart: always`

Even with systemd, `restart: always` is important for:

1. **Container crashes**: If a container crashes mid-operation, Docker restarts it
2. **OOM kills**: If a container is killed due to memory, Docker restarts it
3. **Docker daemon restarts**: If Docker is restarted, containers come back
4. **Defense in depth**: Multiple layers of reliability

## Architecture Decisions

### Passphrase File vs Interactive Prompt

We chose to store the passphrase in `/root/.dkapp-passphrase` because:

| Option | Pros | Cons |
|--------|------|------|
| **Passphrase file** | Fully automated, no intervention needed | Passphrase stored on disk |
| **Interactive** | More secure | Requires human at console after every reboot |
| **Unencrypted .env** | Simple | Secrets in plaintext |

The passphrase file is secured with:
- `chmod 600` (only root can read)
- `chown root:root` (root ownership)
- Stored in `/root/` (root home directory)

### Two Systemd Services (Not One)

We use two separate services because:

1. **Database startup is slow**: Elasticsearch can take 30-60 seconds
2. **App depends on databases**: Application services need healthy databases
3. **Independent lifecycle**: Can restart app without restarting databases
4. **Better error isolation**: Database failures don't cascade to app service

### Type=oneshot with RemainAfterExit

We use `Type=oneshot` because:
- Docker compose is a "fire and forget" command
- It starts containers and exits
- `RemainAfterExit=yes` keeps the service "active" for status checks

## Impact on Fresh Deployments

### New Installations

Fresh deployments are **not affected**:

1. `./install.sh` works exactly as before
2. `make updb && make up` still works
3. Auto-restart is **optional** (run `make setup-autorestart` to enable)

### Existing Installations

Existing installations gain:

1. `restart: always` on all containers (immediate benefit)
2. Option to enable auto-restart with `make setup-autorestart`
3. New unified commands: `make start`, `make stop`, `make restart`, `make update`

### Migration Path

For existing deployments to enable auto-restart:

```bash
# 1. Pull latest changes
git pull

# 2. Restart to apply restart:always policies
make down
make updb && make up

# 3. (Optional) Enable auto-restart
make setup-autorestart
```

## Testing Steps

### Pre-Setup Verification

```bash
# 1. Verify scripts are executable
ls -la dkapp-startup.sh setup-autorestart.sh
# Should show -rwxr-xr-x (executable)

# 2. Check current restart policies (before changes)
docker inspect dkapp-postgres-1 | grep -A5 RestartPolicy
# Will show "always" after pulling latest
```

### Setup Auto-Restart

```bash
# 3. Run setup wizard
make setup-autorestart
# Choose option 1 (passphrase file)
# Enter your GPG passphrase

# 4. Verify setup completed
make autorestart-status
```

**Expected output:**
```
=== Auto-Restart Status ===

Docker service:
  Enabled

DagKnows Database Service (dkapp-db):
  Enabled
  Status: inactive

DagKnows Application Service (dkapp):
  Enabled
  Status: inactive

Passphrase file:
  Present (auto-decrypt enabled)
```

### Test Service Start/Stop

```bash
# 5. Test make start
make start
# Should show: "Starting services via systemd (auto-restart mode)..."

# 6. Verify services running
make status
docker ps

# 7. Test make stop
make stop

# 8. Test make restart
make restart
```

### Test System Reboot

```bash
# 9. Reboot the system
sudo reboot

# 10. After reboot, verify (no manual intervention needed)
make status              # Should show all services running
docker ps                # All containers should be up
make autorestart-status  # Should show services as "active"
```

### Test Update Flow

```bash
# 11. Test update workflow
make update
# Should: stop -> pull -> start (no passphrase prompts)
```

## Troubleshooting

### Services Not Starting After Reboot

```bash
# Check systemd service status
sudo systemctl status dkapp-db.service
sudo systemctl status dkapp.service

# Check startup logs
cat /var/log/dkapp-startup.log

# Check systemd journal
sudo journalctl -u dkapp-db.service -n 50
sudo journalctl -u dkapp.service -n 50
```

### Passphrase Verification Failed

```bash
# Test GPG decryption manually
gpg -o /tmp/test.env -d .env.gpg
# If this works but setup fails, the passphrase might have trailing spaces
```

### make start Shows "manual mode"

This means auto-restart isn't configured. Run:
```bash
make setup-autorestart
```

## Security Considerations

1. **Passphrase file**: Stored at `/root/.dkapp-passphrase` with 600 permissions
2. **Decrypted .env**: Automatically deleted after containers start
3. **Audit trail**: All operations logged to `/var/log/dkapp-startup.log`
4. **No plaintext secrets**: .env.gpg remains encrypted at rest

## Files Created/Modified

| File | Purpose |
|------|---------|
| `dkapp-startup.sh` | Startup script for systemd (handles decryption) |
| `dkapp-db.service` | Systemd service for databases |
| `dkapp.service` | Systemd service for application |
| `setup-autorestart.sh` | Setup wizard for auto-restart |
| `docker-compose.yml` | Added `restart: always` to all services |
| `db-docker-compose.yml` | Added `restart: always` to all services |
| `Makefile` | Added start/stop/restart/update targets |

## Command Reference

| Command | Description |
|---------|-------------|
| `make setup-autorestart` | Configure auto-restart (one-time setup) |
| `make disable-autorestart` | Remove auto-restart configuration |
| `make autorestart-status` | Check auto-restart status |
| `make start` | Start all services (auto-detects mode) |
| `make stop` | Stop all services |
| `make restart` | Restart all services |
| `make update` | Pull latest images and restart |
