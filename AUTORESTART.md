# DagKnows Auto-Restart Configuration

This guide explains how to configure DagKnows to automatically start after system reboots.

---

## TL;DR - Quick Setup

```bash
make setup-autorestart
```

Follow the prompts to choose your passphrase handling option. After setup, DagKnows will automatically start when your system boots.

---

## Overview

The auto-restart feature uses **systemd** to automatically start DagKnows services after system reboots. This ensures your deployment recovers automatically from:

- System reboots (planned maintenance)
- Power outages
- Kernel updates requiring restart
- System crashes

---

## Quick Setup

```bash
# Run setup (requires sudo)
make setup-autorestart
```

The setup wizard will:
1. Enable Docker to start on boot
2. Ask how you want to handle your GPG passphrase
3. Install systemd service files
4. Enable automatic startup

---

## Passphrase Handling Options

Since DagKnows encrypts your `.env` file with GPG, the system needs a way to decrypt it during startup. You have three options:

### Option 1: Passphrase File (Recommended)

**How it works:**
- Your passphrase is stored in `/root/.dkapp-passphrase`
- The file has root-only access (chmod 600)
- During startup, the system decrypts `.env.gpg` using this passphrase
- After startup, the decrypted `.env` file is deleted

**Security:**
- Passphrase only accessible by root
- Decrypted `.env` exists only briefly during startup
- Recommended for most production deployments

**Setup:**
```
Choose option (1/2/3) [1]: 1
Enter your GPG passphrase (same as used to encrypt .env): ********
```

### Option 2: Unencrypted .env

**How it works:**
- The `.env.gpg` file is decrypted once to create a permanent `.env` file
- No passphrase needed at startup
- Services start directly using the `.env` file

**Security:**
- Environment variables visible in plaintext
- Simpler but less secure
- Use only if physical server security is ensured

**Setup:**
```
Choose option (1/2/3) [1]: 2
Enter your GPG passphrase: ********
```

### Option 3: Manual Start

**How it works:**
- No systemd services are installed
- You manually start DagKnows after each reboot
- Most secure option

**Security:**
- Passphrase never stored on disk
- Requires human intervention after every reboot
- Best for high-security environments

**Setup:**
```
Choose option (1/2/3) [1]: 3
```

After reboot, you must run:
```bash
make updb && make up
```

---

## Systemd Services

Two systemd services are installed:

### dkapp-db.service

**Purpose:** Starts database services (PostgreSQL and Elasticsearch)

**Startup order:**
1. Waits for Docker service
2. Waits for network to be online
3. Runs `dkapp-startup.sh db-docker-compose.yml`

**Configuration:**
- TimeoutStartSec: 300s (5 minutes)
- TimeoutStopSec: 120s (2 minutes)

### dkapp.service

**Purpose:** Starts application services (req-router, taskservice, settings, etc.)

**Startup order:**
1. Waits for Docker service
2. **Waits for dkapp-db.service** (databases must be running)
3. Waits for PostgreSQL to accept connections
4. Waits for Elasticsearch to be healthy
5. Runs `dkapp-startup.sh docker-compose.yml`

**Configuration:**
- TimeoutStartSec: 600s (10 minutes)
- TimeoutStopSec: 120s (2 minutes)

### Startup Flow

```
System Boot
    │
    ▼
Docker Service
    │
    ▼
dkapp-db.service
    │
    ├─► Decrypt .env (if using passphrase file)
    ├─► Start PostgreSQL + Elasticsearch
    ├─► Start database log capture
    └─► Clean up decrypted .env
    │
    ▼
dkapp.service
    │
    ├─► Wait for PostgreSQL ready
    ├─► Wait for Elasticsearch healthy
    ├─► Decrypt .env (if using passphrase file)
    ├─► Apply version overrides (if versioning enabled)
    ├─► Start application services
    ├─► Start application log capture
    └─► Clean up decrypted .env
```

---

## Management Commands

### Check Auto-Restart Status

```bash
make autorestart-status
```

Output shows:
- Whether systemd services are installed
- Whether services are enabled (start on boot)
- Whether services are currently active

### Disable Auto-Restart

```bash
make disable-autorestart
```

This will:
- Stop all containers
- Disable and remove systemd service files
- Reload systemd daemon

### Manual Service Control

You can also use systemctl directly:

```bash
# Start services
sudo systemctl start dkapp-db.service
sudo systemctl start dkapp.service

# Stop services
sudo systemctl stop dkapp.service
sudo systemctl stop dkapp-db.service

# Restart services
sudo systemctl restart dkapp.service

# Check status
sudo systemctl status dkapp.service
sudo systemctl status dkapp-db.service
```

---

## Viewing Logs

### Startup Logs

```bash
# View startup log (created by dkapp-startup.sh)
cat /var/log/dkapp-startup.log

# Or tail for latest entries
tail -50 /var/log/dkapp-startup.log
```

Example startup log:
```
2026-01-15 08:30:01 - Starting DagKnows services using db-docker-compose.yml
2026-01-15 08:30:01 - Auto-restart mode: Using passphrase file for decryption
2026-01-15 08:30:02 - Environment decrypted successfully
2026-01-15 08:30:02 - Ensuring required directories and permissions...
2026-01-15 08:30:03 - Starting containers with docker compose -f db-docker-compose.yml...
2026-01-15 08:30:18 - Waiting for containers to stabilize...
2026-01-15 08:30:33 - Starting background database log capture
2026-01-15 08:30:34 - Database log capture started (PID: 1234)
2026-01-15 08:30:34 - Cleaned up decrypted environment file
2026-01-15 08:30:34 - Startup complete for db-docker-compose.yml
```

### Application Logs

```bash
# Live logs
make logs

# Today's captured logs
make logs-today

# Errors only
make logs-errors
```

### Database Logs

```bash
# Live database logs
make dblogs

# Today's captured database logs
make dblogs-today

# Database errors only
make dblogs-errors
```

### Systemd Service Logs

```bash
# View systemd journal for services
journalctl -u dkapp.service
journalctl -u dkapp-db.service

# Follow logs in real-time
journalctl -u dkapp.service -f
```

---

## Troubleshooting

### Services Not Starting After Reboot

**Check systemd status:**
```bash
sudo systemctl status dkapp-db.service
sudo systemctl status dkapp.service
```

**Check startup log:**
```bash
cat /var/log/dkapp-startup.log
```

**Common issues:**

1. **Passphrase verification failed**
   - Check that `/root/.dkapp-passphrase` contains the correct passphrase
   - Try manually decrypting: `gpg -d .env.gpg`

2. **Docker not running**
   - Ensure Docker is enabled: `sudo systemctl enable docker`
   - Start Docker: `sudo systemctl start docker`

3. **Database health check timeout**
   - Databases may need more time on slow systems
   - Check database logs: `make dblogs`

### Passphrase File Issues

**Verify passphrase file exists and has correct permissions:**
```bash
ls -la /root/.dkapp-passphrase
# Should show: -rw------- 1 root root
```

**Test passphrase manually:**
```bash
gpg --batch --passphrase-file /root/.dkapp-passphrase -d .env.gpg
```

### Service Dependency Issues

**Check service dependencies:**
```bash
systemctl list-dependencies dkapp.service
```

**Verify correct startup order:**
```bash
# dkapp-db should start before dkapp
systemctl show -p After dkapp.service | grep dkapp-db
```

### Re-running Setup

If you need to change your passphrase handling option:

```bash
# Disable current setup
make disable-autorestart

# Run setup again
make setup-autorestart
```

---

## Security Considerations

### Option 1 (Passphrase File)

- File stored at `/root/.dkapp-passphrase` with mode 600
- Only root can read the file
- Decrypted `.env` is deleted immediately after containers start
- **Recommended for most deployments**

### Option 2 (Unencrypted .env)

- `.env` file contains all secrets in plaintext
- Ensure file permissions are 600
- Consider disk encryption for additional protection
- **Use only with physical security measures**

### Option 3 (Manual)

- No secrets stored on disk
- Requires physical/remote access after every reboot
- **Best for high-security environments**

### General Recommendations

1. Use disk encryption (LUKS) for the root filesystem
2. Restrict SSH access to the server
3. Use network firewalls to limit access
4. Regularly rotate credentials
5. Monitor `/var/log/dkapp-startup.log` for anomalies

---

## File Locations

| File | Purpose |
|------|---------|
| `/root/.dkapp-passphrase` | Stored passphrase for auto-decrypt (Option 1) |
| `/etc/systemd/system/dkapp.service` | Application service unit file |
| `/etc/systemd/system/dkapp-db.service` | Database service unit file |
| `/var/log/dkapp-startup.log` | Startup script log |
| `{dkapp}/dkapp-startup.sh` | Startup script executed by systemd |
| `{dkapp}/logs/*.log` | Application log files |
| `{dkapp}/dblogs/*.log` | Database log files |

---

## Command Reference

| Command | Description |
|---------|-------------|
| `make setup-autorestart` | Configure auto-start on boot |
| `make autorestart-status` | Check auto-restart configuration |
| `make disable-autorestart` | Remove auto-restart configuration |
| `make start` | Start all services (uses systemd if configured) |
| `make stop` | Stop all services |
| `make restart` | Restart all services |
| `make logs` | View application logs |
| `make dblogs` | View database logs |
