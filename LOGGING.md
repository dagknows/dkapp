# DagKnows Logging Guide

This guide explains how logging works in dkapp and how to use it for debugging and monitoring.

## Quick Start

```bash
# Option 1: Smart start (recommended - handles everything)
make start       # Health checks, versioning, and auto log capture

# Option 2: Manual start
make updb        # Start databases first
make up          # Start app + auto-starts background log capture

# View live logs when needed
make logs        # Real-time log stream (Ctrl+C to exit)

# Check captured logs
make logs-today  # View today's logs
make logs-errors # View errors only
```

## Database Logs

Database logs (postgres, elasticsearch) are captured separately from application logs.

```bash
# Start database services (auto-starts DB log capture + waits for healthy)
make updb

# View database errors (includes OOM detection)
make dblogs-errors

# Check today's DB logs
make dblogs-today
```

### Database Log Commands

| Command | Description |
|---------|-------------|
| `make dblogs` | View live DB logs (follow mode) |
| `make dblogs-today` | View today's captured DB logs |
| `make dblogs-errors` | Show errors including OOM/killed |
| `make dblogs-service SERVICE=elasticsearch` | Filter to specific DB |
| `make dblogs-search PATTERN='text'` | Search DB logs |
| `make dblogs-start` | Manually start DB log capture |
| `make dblogs-stop` | Stop DB log capture |
| `make dblogs-status` | Show DB log disk usage |
| `make dblogs-rotate` | Rotate DB logs |

## How It Works

When you run `make up`, two things happen:
1. Application services start in Docker containers
2. Background log capture automatically starts

Logs are captured to `./logs/YYYY-MM-DD.log` (e.g., `./logs/2026-01-09.log`).

All services are logged together chronologically, making it easy to trace issues across services.

## Log Commands

### Viewing Logs

| Command | Description |
|---------|-------------|
| `make logs` | View live logs (last 300 lines + follow) |
| `make logs-today` | View today's captured logs |
| `make logs-errors` | Show only error/exception/fail lines |
| `make logs-service SERVICE=req-router` | Filter to specific service |
| `make logs-search PATTERN='text'` | Search for pattern in logs |

### Managing Log Capture

| Command | Description |
|---------|-------------|
| `make logs-start` | Manually start background capture |
| `make logs-stop` | Stop background capture |
| `make logs-status` | Show log directory size and files |

### Log Maintenance

| Command | Description |
|---------|-------------|
| `make logs-rotate` | Compress logs >3 days, delete >7 days |
| `make logs-clean` | Delete all captured logs (with confirmation) |
| `make logs-cron-install` | Setup daily auto-rotation at midnight |
| `make logs-cron-remove` | Remove auto-rotation cron job |

## Log File Format

Logs are stored in `./logs/` with one file per day:

```
./logs/
  2026-01-09.log      # Today's logs
  2026-01-08.log      # Yesterday's logs
  2026-01-07.log.gz   # Compressed older logs
```

Each log line includes the service name prefix:

```
req-router-1    | 2026-01-09 14:30:00 INFO  Starting request processing
taskservice-1   | 2026-01-09 14:30:00 INFO  Received task query
conv-mgr-1      | 2026-01-09 14:30:00 INFO  Processing conversation
taskservice-1   | 2026-01-09 14:30:01 ERROR Connection timeout to elasticsearch
req-router-1    | 2026-01-09 14:30:01 ERROR Upstream service error
```

## Startup Procedure

### Smart Start (Recommended)

```bash
# Single command handles everything:
# - Health checks for PostgreSQL and Elasticsearch
# - Version management (generates versions.env from manifest)
# - Starts all services
# - Starts background log capture
make start

# Check status
make status
make logs-status
```

### Traditional Startup

```bash
# 1. Start databases (waits for healthy + auto-starts DB log capture)
make updb

# 2. Start application (auto-starts app log capture)
make up

# 3. Check for any DB errors if needed
make dblogs-errors

# 4. View live logs if needed
make logs        # Ctrl+C to exit (capture continues in background)
```

### Stopping Services

```bash
# Stops all services AND log capture processes
make stop

# Or restart everything
make restart
```

### Checking Status

```bash
# Check if services are running
docker compose ps

# Check if log capture is running
make logs-status
make dblogs-status

# View any errors
make logs-errors
```

## Debugging with Logs

### Find Errors

```bash
# Show all errors from captured logs
make logs-errors

# Search for specific error
make logs-search PATTERN='connection refused'
```

### Filter by Service

```bash
# View only req-router logs
make logs-service SERVICE=req-router

# View only taskservice logs
make logs-service SERVICE=taskservice

# Available services:
#   req-router, taskservice, settings, conv-mgr,
#   wsfe, jobsched, apigateway, nginx, dagknows-nuxt, ansi-processing
```

### Search for Patterns

```bash
# Find all elasticsearch-related logs
make logs-search PATTERN='elasticsearch'

# Find specific user activity
make logs-search PATTERN='user@example.com'

# Find specific endpoint calls
make logs-search PATTERN='POST /api/tasks'
```

### Using grep Directly

For more complex searches, use grep on the log files:

```bash
# Find errors around a specific time
grep "14:30" ./logs/2026-01-09.log | grep -i error

# Count errors per service
grep -i error ./logs/2026-01-09.log | cut -d'|' -f1 | sort | uniq -c

# Find last 50 errors
grep -i error ./logs/2026-01-09.log | tail -50

# View context around an error (5 lines before/after)
grep -B5 -A5 "Connection timeout" ./logs/2026-01-09.log
```

## Log Retention Policy

| Age | Action |
|-----|--------|
| 0-3 days | Kept as `.log` (uncompressed) |
| 3-7 days | Compressed to `.log.gz` |
| 7+ days | Deleted |

### Manual Rotation

```bash
make logs-rotate
```

### Automatic Rotation (Recommended)

Set up a cron job to rotate logs daily at midnight:

```bash
make logs-cron-install   # Setup cron job
crontab -l               # Verify installation
make logs-cron-remove    # Remove if needed
```

## Storage Estimates

| Timeframe | Size |
|-----------|------|
| Per day (uncompressed) | 100-500 MB |
| Per day (compressed) | 20-100 MB |
| 7-day retention total | ~700 MB - 1.5 GB |

Check current usage:

```bash
make logs-status
```

## Troubleshooting

### Log capture not running

```bash
# Check if capture is running (uses PID file)
cat ./logs/.capture.pid 2>/dev/null && echo "PID file exists"

# Manually start if needed
make logs-start
```

### Logs not appearing

```bash
# Check if services are running
docker compose ps

# Check log file exists
ls -la ./logs/

# Try viewing live logs
make logs
```

### Disk space issues

```bash
# Check log size
make logs-status

# Force rotation
make logs-rotate

# Or clean all logs
make logs-clean
```

### Multiple log capture processes

```bash
# Stop all capture processes
make logs-stop

# Start fresh
make logs-start
```
