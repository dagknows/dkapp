# Installation Resume Capability

The DagKnows installation wizard now has robust resume capabilities that allow you to stop and restart the installation at any point without losing progress.

## 🎯 Key Features

### 1. **State Detection**
The installer automatically detects:
- ✅ Existing encrypted configuration (`.env.gpg`)
- ✅ Unencrypted configuration from interrupted run (`.env`)
- ✅ Docker and Docker Compose installation status
- ✅ Running database containers (PostgreSQL, Elasticsearch)
- ✅ Running application containers (nginx, req-router, etc.)
- ✅ System package update timestamps

### 2. **Smart Skip Logic**
The installer skips completed steps:
- ✅ **System updates** - Skips if updated within last hour
- ✅ **Make installation** - Skips if already present
- ✅ **Docker installation** - Skips if already installed, only ensures group membership
- ✅ **Docker service** - Checks if running before restarting
- ✅ **Image pulling** - Checks if images already present
- ✅ **Configuration** - Offers to keep or reconfigure existing settings

### 3. **Resume Points**
The installer can resume from multiple points:

#### **Point 1: Already Running**
```
Detected: Application services running
Action: Offers to skip installation or reinstall
Message: "System is already running"
```

#### **Point 2: Database Running, App Not Started**
```
Detected: Database services running, app services not
Action: Offers to resume from application startup
Resumes: make pull → make up → completion
```

#### **Point 3: Services Configured but Not Running**
```
Detected: .env.gpg exists, no services running
Action: Offers to resume from service startup
Resumes: make updb → make pull → make up → completion
```

#### **Point 4: Configuration Incomplete**
```
Detected: Unencrypted .env file (interrupted before encryption)
Action: Offers to use existing config or reconfigure
Resumes: From encryption step onward
```

### 4. **Configuration Backup**
When reconfiguring:
- ✅ Automatically backs up existing `.env.gpg`
- ✅ Creates timestamped backup: `.env.gpg.backup.{timestamp}`
- ✅ Allows safe experimentation with settings

## 📋 Interruption Scenarios

### Scenario 1: Ctrl+C During System Update
```
User: Presses Ctrl+C
Next Run: Checks update timestamp, may skip if recent
Resume: Continues from Make installation
```

### Scenario 2: Ctrl+C During Docker Installation
```
User: Presses Ctrl+C during `make prepare`
Next Run: Detects partial Docker installation
Resume: Completes Docker setup, continues to configuration
```

### Scenario 3: Ctrl+C During Configuration
```
User: Presses Ctrl+C while entering passwords
Next Run: No .env.gpg exists
Resume: Starts configuration from scratch
```

### Scenario 4: Ctrl+C After Encryption
```
User: Presses Ctrl+C after creating .env.gpg
Next Run: Detects .env.gpg exists
Options:
  - Resume from service startup
  - Reconfigure (with backup)
  - Skip (if services already running)
```

### Scenario 5: Ctrl+C During Image Pull
```
User: Presses Ctrl+C during `make pull`
Next Run: Detects partial images
Resume: Continues pulling remaining images
```

### Scenario 6: Ctrl+C During Service Startup
```
User: Presses Ctrl+C during `make updb`
Next Run: Checks which services are running
Resume: Starts missing services only
```

### Scenario 7: System Crash/Network Loss
```
System: Crashes or loses network mid-install
Next Run: Detects completed steps
Resume: Picks up from last successful step
```

## 🔧 Technical Implementation

### State Detection Function
```python
def check_installation_state():
    return {
        'env_configured': exists('.env.gpg'),
        'env_unencrypted': exists('.env'),
        'docker_installed': which('docker'),
        'make_installed': which('make'),
        'db_running': check_containers(['postgres', 'elasticsearch']),
        'app_running': check_containers(['nginx', 'req-router'])
    }
```

### Resume Logic
```python
if state['app_running']:
    # Fully installed, offer to skip
    prompt_skip_or_reinstall()
elif state['db_running']:
    # Resume from app startup
    run_make_pull() → run_make_up()
elif state['env_configured']:
    # Resume from service startup
    run_make_updb() → run_make_pull() → run_make_up()
else:
    # Fresh install
    full_installation_flow()
```

## 💡 User Experience

### Fresh Install
```bash
$ ./install.sh

============================================================
            DagKnows Installation Wizard                 
============================================================

This wizard will guide you through...

Do you want to continue? (yes/no): yes

[Proceeds with full installation]
```

### Resume After Interruption
```bash
$ ./install.sh

============================================================
            DagKnows Installation Wizard                 
============================================================

============================================================
           Existing Installation Detected                 
============================================================

✓ Found existing encrypted configuration (.env.gpg)
⚠ Services are not running

Resume from starting services? (yes/no) [yes]: yes

ℹ Resuming installation from service startup...

[Skips completed steps, resumes from services]
```

### Already Running
```bash
$ ./install.sh

============================================================
            DagKnows Installation Wizard                 
============================================================

============================================================
           Existing Installation Detected                 
============================================================

✓ Found existing encrypted configuration (.env.gpg)
✓ Application services are already running!

Your DagKnows installation appears to be complete.

Available actions:
  1. View logs: make logs
  2. Restart services: make restart
  3. Check status: make status
  4. Reconfigure: make reconfigure

Do you want to reinstall anyway? (yes/no) [no]: no

ℹ Installation skipped. System is already running.
```

## 🛡️ Safety Features

### 1. **Confirmation Prompts**
- Always asks before overwriting existing configuration
- Confirms before reinstalling on running system
- Allows user to keep or replace settings

### 2. **Automatic Backups**
- Backs up `.env.gpg` before reconfiguration
- Timestamped backups for easy recovery
- Never overwrites without user consent

### 3. **Non-Destructive Detection**
- All checks are read-only
- No files modified during state detection
- Safe to run multiple times

### 4. **Graceful Degradation**
- Failed steps don't corrupt state
- Can retry individual steps
- Clear error messages with recovery instructions

## 📊 State Transition Diagram

```
START
  ↓
Check State
  ├─ App Running? → Offer Skip/Reinstall
  ├─ DB Running?  → Resume: Pull Images → Start App
  ├─ Config Exists? → Resume: Start DB → Pull → Start App
  └─ Fresh Install → Full Flow
```

## 🚀 Benefits

### For Users:
- ✅ **No wasted time** - Never repeat completed steps
- ✅ **Flexible** - Stop and resume at will
- ✅ **Safe** - Automatic backups, confirmation prompts
- ✅ **Clear** - Always know what's happening
- ✅ **Forgiving** - Easy recovery from interruptions

### For Developers:
- ✅ **Testable** - Can test individual steps
- ✅ **Debuggable** - Clear state at each point
- ✅ **Maintainable** - Modular design
- ✅ **Robust** - Handles edge cases

## 🔍 Testing Scenarios

### Test 1: Full Fresh Install
```bash
./install.sh
# Complete all steps
# Verify: Services running
```

### Test 2: Interrupt During Package Update
```bash
./install.sh
# Press Ctrl+C during apt upgrade
./install.sh
# Verify: Skips or completes package update, continues
```

### Test 3: Interrupt During Configuration
```bash
./install.sh
# Press Ctrl+C during password entry
./install.sh
# Verify: Starts configuration from scratch
```

### Test 4: Interrupt After Configuration
```bash
./install.sh
# Complete configuration, press Ctrl+C before services
./install.sh
# Verify: Offers to resume from service startup
```

### Test 5: Run on Already-Installed System
```bash
./install.sh
# After successful install
./install.sh
# Verify: Detects running services, offers to skip
```

### Test 6: Reconfigure Running System
```bash
./install.sh
# On running system, choose to reconfigure
# Verify: Backs up config, allows reconfiguration
```

## 📝 Best Practices

### For Users:
1. **Let it complete** - Best to run uninterrupted if possible
2. **Note where you stopped** - Helps understand what to expect
3. **Check status** - Run `make status` after resume
4. **Keep backups** - `.env.gpg.backup.*` files are valuable

### For Developers:
1. **Test interruptions** - At every major step
2. **Verify idempotency** - Multiple runs should be safe
3. **Clear messaging** - User should know what's happening
4. **Log state** - For debugging resume issues

## 🔄 Idempotency

All installation steps are idempotent:
- ✅ Running twice produces same result as once
- ✅ No errors from re-running completed steps
- ✅ Safe to run multiple times
- ✅ Detects and skips completed work

## 🎓 Example Session

```bash
# First run - interrupted during image pull
$ ./install.sh
[... system update ...]
[... docker install ...]
[... configuration ...]
[... encryption ...]
[... database startup ...]
[... image pulling ...]
^C

# Second run - resumes from where left off
$ ./install.sh

Existing Installation Detected
✓ Found existing encrypted configuration
✓ Database services are running

Resume from starting application services? (yes/no) [yes]: yes

Resuming installation from application startup...
[... pulls remaining images ...]
[... starts application ...]
✓ Installation Complete!
```

## 🔑 Key Takeaways

1. **Always Safe** - Can interrupt and resume at any point
2. **No Repetition** - Skips completed steps automatically
3. **User Control** - Always confirms before changing things
4. **Clear State** - Always know where you are
5. **Easy Recovery** - Simple to fix interrupted installs

---

**The installation is now robust, resumable, and user-friendly!** 🎉

