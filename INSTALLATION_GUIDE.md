# DagKnows Installation Guide

Complete guide for installing, configuring, and managing DagKnows on docker-compose setups.

---

## 📋 Table of Contents
- [Quick Start](#quick-start)
- [What's Automated](#whats-automated)
- [Resume Capability](#resume-capability)
- [Management Commands](#management-commands)
- [Troubleshooting](#troubleshooting)
- [Testing](#testing)
- [Technical Details](#technical-details)

---

## Quick Start

### Prerequisites
- Ubuntu/Debian Linux (16.04+)
- 16 GB RAM minimum
- 50 GB disk space
- Internet connection
- Root/sudo access

### Installation (5-15 Minutes)

```bash
# 1. Clone repository
git clone https://github.com/dagknows/dkapp.git
cd dkapp

# 2. Run installation wizard
python3 install.py

# 3. Follow prompts (details below)

# 4. Access your instance
# Open browser to: https://YOUR_SERVER_IP
```

### What the Wizard Asks

1. **DagKnows URL** - Your public IP or domain (auto-detected)
2. **Database Password** - PostgreSQL password (strong recommended)
3. **Admin Details** - Email, name, password, organization
4. **Mail Config** (optional) - SMTP settings for notifications
5. **OpenAI API** (optional) - For AI features
6. **Encryption Password** - ⚠️ **Use SAME password as admin** (recommended)

**Password Requirements**:
- Minimum 8 characters
- At least 1 uppercase letter (A-Z)
- At least 1 lowercase letter (a-z)
- At least 1 number (0-9)
- At least 1 special character (!@#$%^&*()-_=+)

**Password Tip**: The wizard recommends using the same password for both admin and encryption to simplify management.

---

## What's Automated

### ✅ System automatically handles:
- System package updates (apt update/upgrade)
- Installing Docker, docker-compose, make, gpg
- Docker repository setup
- User added to docker group (uses `sg docker` during install)
- Docker network creation
- Data directories setup (postgres-data, esdata1, elastic_backup)
- Configuration file creation and encryption
- **Sequential image pulling** (avoids ECR rate limits)
- Database services startup (PostgreSQL, Elasticsearch)
- Application services startup (all 9 services)
- Health monitoring

### 🎯 Time Savings
- **Before**: 30-45 minutes (manual, error-prone)
- **After**: 5-15 minutes (automated, guided)
- **Saved**: ~75% reduction

---

## Resume Capability

### Smart State Detection
The installer detects your current state and **resumes automatically**:

| State | Detected | Action |
|-------|----------|--------|
| **Already running** | All services up | Offers to skip or reinstall |
| **Database running** | DB up, app down | Resumes from app startup |
| **Configured only** | .env.gpg exists | Resumes from services |
| **Interrupted config** | .env without .gpg | Offers to use or reconfigure |

### Idempotent Operations
All steps are safe to rerun:
- ✅ System updates skip if recent (< 1 hour)
- ✅ Docker install skips if present
- ✅ Image pull skips if all 9 images present
- ✅ Services skip if already running

### Example: Resume After Interruption

```bash
# First run (interrupted during image pull)
$ python3 install.py
[... installing ...]
^C

# Second run (detects state and resumes)
$ python3 install.py

Existing Installation Detected
✓ Found existing configuration
✓ Database services running

Resume from starting application? (yes/no) [yes]: yes

Resuming...
[... pulls remaining images ...]
[... starts application ...]
✓ Complete!
```

---

## Management Commands

All commands available via Makefile:

### Installation & Setup
```bash
make install      # Run installation wizard
make prepare      # Install Docker manually
make uninstall    # Remove installation (with prompts)
```

### Configuration
```bash
make encrypt      # Encrypt .env file (prompts for password)
make reconfigure  # Update settings without reinstall
```

### Service Management
```bash
make updb         # Start database services
make up           # Start application services
make down         # Stop all services
make restart      # Restart everything
```

### Monitoring
```bash
make logs         # View application logs (Ctrl+C to exit)
make dblogs       # View database logs
make status       # Check system health
```

### Maintenance
```bash
make pull         # Pull latest images (sequential)
make update       # Update to latest version
make backups      # Backup data (to .backups/)
make help         # Show all commands
```

---

## Troubleshooting

### Docker Permission Denied

**Problem**: `permission denied while trying to connect to Docker daemon`

**Solution**: The installer uses `sg docker` during installation. For manual commands afterward:

```bash
# Option 1: Activate docker group in current session
newgrp docker

# Now run commands normally
make logs
make restart

# Option 2: Log out and back in (permanent)

# Option 3: Prefix individual commands
sg docker -c "make logs"
```

**Why**: Group membership doesn't activate in current shell. Must use `newgrp docker` or logout/login.

### Services Won't Start

```bash
# 1. Check Docker is running
sudo systemctl status docker
sudo systemctl start docker

# 2. Check status
make status

# 3. View logs for errors
make dblogs
make logs
```

### Port Already in Use

```bash
# Find what's using ports 80/443
sudo lsof -i :80
sudo lsof -i :443

# Stop conflicting service
# Then: make restart
```

### Forgot Encryption Password

**No recovery possible.** Must reconfigure:

```bash
make down
rm .env.gpg
python3 install.py
```

### Can't Access Web Interface

```bash
# 1. Verify services running
docker ps | grep nginx

# 2. Check firewall
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# 3. Check configuration
make reconfigure
```

### Containers Keep Restarting

Common causes:
- Database not ready (wait 30 seconds)
- Wrong database password (reconfigure)
- Insufficient memory (need 16GB)

Check logs: `make logs`

---

## Testing

### Minimum Test Set (~45 min)

#### Test 1: Fresh Install (10-15 min)
```bash
cd dkapp
python3 install.py
# Use SAME password for admin and encryption
# Verify: docker ps shows 12+ containers
```

#### Test 2: Interrupt & Resume (10 min)
```bash
python3 install.py
# After encryption, press Ctrl+C
python3 install.py
# Should offer to resume
```

#### Test 3: Already Installed (2 min)
```bash
# After successful install
python3 install.py
# Should detect running system, offer to skip
```

#### Test 4: Docker Group (5 min)
```bash
# After install
docker ps  # Will fail
newgrp docker
docker ps  # Works!
```

### Verification Commands

```bash
# Check all services
docker ps | wc -l  # Should show 12+

# Check encrypted config
ls -la .env.gpg

# Test access
curl -k https://localhost

# Full health check
make status

# Verify docker group
groups | grep docker
```

### Common Test Issues

| Issue | Solution |
|-------|----------|
| Permission denied | Run `newgrp docker` |
| Image pull fails | Check internet, retry |
| Services don't start | Check `make dblogs` and `make logs` |
| Port in use | Check `sudo lsof -i :80` |

---

## Technical Details

### Tools Created

1. **install.py** (21KB) - Main installation wizard
   - Automated end-to-end installation
   - Interactive prompts with validation
   - Resume capability
   - Docker group handling with `sg docker`

2. **install.sh** (388B) - Shell wrapper
   - Checks/installs Python 3
   - Runs installation wizard

3. **reconfigure.py** (7.8KB) - Configuration manager
   - Update settings without reinstall
   - Backs up existing config
   - Section-by-section updates

4. **check-status.py** (11KB) - Health checker
   - Verifies all components
   - Clear pass/fail report
   - Actionable error messages

5. **uninstall.sh** (3.6KB) - Safe removal
   - Optional backup
   - Selective component removal
   - Interactive confirmations

### Docker Group Handling

**Challenge**: User added to docker group during install, but group not active in current session.

**Solution**: 
- Uses `sg docker -c "command"` to run Docker commands with proper permissions
- **Never falls back to sudo** - only proper group membership
- Reminds user to run `newgrp docker` after installation

**Permission Check Logic**:
```python
1. Try: docker ps
   ├─ Success? → Use direct docker commands
   └─ Failed? → Use sg docker -c "docker ps"
       └─ Still fails? → Graceful error with instructions
```

### Sequential Image Pulling

**Problem**: Public ECR has rate limits on concurrent unauthenticated pulls.

**Solution**: `make pull` downloads images one-by-one before `make up`:
```
make updb (databases) → wait → make pull (sequential) → make up (application)
```

**Images Pulled** (9 total):
1. wsfe
2. ansi_processing
3. jobsched
4. apigateway
5. conv_mgr
6. settings
7. taskservice
8. req_router
9. dagknows_nuxt

### Password Management

**Recommendation**: Use same password for:
- Admin user password
- GPG encryption password

**Benefits**:
- ✅ Only one password to remember
- ✅ Clearly communicated during install
- ✅ Reduces user error

**Prompts**:
```
⚠ IMPORTANT:
Use the SAME password for both Super User and encryption.

Super User Password (will also be used for encryption): ********

[Later during encryption...]

⚠ USE THE SAME PASSWORD as your Super User password
Enter passphrase: ********
```

### State Detection

```python
def check_installation_state():
    return {
        'env_configured': exists('.env.gpg'),
        'docker_installed': which('docker'),
        'db_running': check_containers(['postgres', 'elasticsearch']),
        'app_running': check_containers(['nginx', 'req-router'])
    }
```

Handles permission gracefully:
- Tries regular `docker ps`
- Falls back to `sg docker -c "docker ps"`
- If both fail, continues without container status

---

## Security Best Practices

### Essential
1. ✅ Use strong passwords (8+ characters minimum, with uppercase, lowercase, numbers, and special characters - enforced by wizard)
2. ✅ Remember encryption password (no recovery!)
3. ✅ Regular backups: `make backups`
4. ✅ Keep system updated: `make update`
5. ✅ Use firewall, limit SSH access

### Files to Protect
- `.env.gpg` - Encrypted configuration
- `.backups/` - Data backups
- Keep backups in secure, separate location

### Encrypted Files
- Configuration encrypted with GPG symmetric encryption
- Temporary `.env` files deleted immediately
- User controls encryption password
- No plaintext passwords in logs

---

## Quick Reference

### File Structure
```
dkapp/
├── install.py           # Installation wizard
├── install.sh           # Shell wrapper  
├── reconfigure.py       # Config updater
├── check-status.py      # Health checker
├── uninstall.sh         # Removal script
├── Makefile            # Management commands
├── docker-compose.yml  # App services (9 containers)
├── db-docker-compose.yml # Databases (2 containers)
├── .env.gpg            # Encrypted configuration
├── postgres-data/      # PostgreSQL data
├── esdata1/           # Elasticsearch data
└── elastic_backup/    # ES backups
```

### After Installation

```bash
# 1. Activate docker group
newgrp docker

# 2. Check status
make status

# 3. View logs
make logs

# 4. Access application
# Browser: https://YOUR_SERVER_IP

# 5. Configure email (if skipped)
make reconfigure

# 6. Set up backups
make backups
```

### Success Criteria

After install, you should be able to:
1. ✓ Run `make status` - all checks pass
2. ✓ Run `docker ps` - see 12+ containers
3. ✓ Access web interface at your URL
4. ✓ Login with admin credentials
5. ✓ View logs: `make logs`

---

## Getting Help

### Diagnosis Steps
1. Check status: `make status`
2. View logs: `make logs` or `make dblogs`
3. Check Docker: `docker ps`
4. Review this guide
5. Search GitHub issues

### Support Resources
- **Documentation**: [README.md](README.md)
- **Issues**: https://github.com/dagknows/dkapp/issues
- **Commands**: `make help`

### Common Questions

**Q: Can I interrupt the installation?**  
A: Yes! The wizard detects state and resumes from where you left off.

**Q: What if I use different passwords?**  
A: Works fine, but you'll need to remember two passwords instead of one.

**Q: How do I update DagKnows?**  
A: Run `make update` then `make restart`

**Q: Can I change configuration after install?**  
A: Yes! Run `make reconfigure`

**Q: Is it safe to run the installer multiple times?**  
A: Yes! It's idempotent and won't break existing installations.

---

## Summary

### What You Get
- ✅ **Fully automated** installation (5-15 minutes)
- ✅ **Resume capability** - interrupt and continue anytime
- ✅ **Smart detection** - skips completed steps
- ✅ **Robust** - handles permissions, network issues gracefully
- ✅ **User-friendly** - colored output, clear messages
- ✅ **Comprehensive tools** - install, configure, monitor, uninstall
- ✅ **Production-ready** - secure, tested, documented

### Key Commands
```bash
python3 install.py   # Install
make reconfigure      # Update config
make status          # Check health
make logs            # View logs
make restart         # Restart services
make backups         # Backup data
make help            # Show all commands
```

---

**Questions?** Run `make help` or check [README.md](README.md)

**Issues?** Run `make status` and check logs

**Ready to install?** Run `python3 install.py`

**Enjoy DagKnows! 🚀**

